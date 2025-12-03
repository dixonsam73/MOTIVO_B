// PracticeTimerView+AudioPlayback.swift
// Extracted audio playback & interruption handling from PracticeTimerView.
// No UI or behavioural changes.

import SwiftUI
import AVFoundation

extension PracticeTimerView {

    func togglePlay(_ id: UUID) {
        // Stop drone before any audio attachment playback
        if droneIsOn {
            droneEngine.stop()
            droneIsOn = false
        }

        if showAudioRecorder {
            return
        }
        if currentlyPlayingID == id {
            // Toggle play/pause for the same item and keep the selection so the icon flips reliably
            if let p = audioPlayer {
                if p.isPlaying {
                    p.pause()
                    isAudioPlaying = false
                    // Keep currentlyPlayingID so UI shows the item as selected (pause icon becomes play on next render)
                    // No change needed to currentlyPlayingID here
                } else {
                    // Attempt to resume
                    p.play()
                    isAudioPlaying = p.isPlaying
                    if !p.isPlaying {
                        // Resume failed; clear selection to avoid stuck icon
                        currentlyPlayingID = nil
                        isAudioPlaying = false
                    }
                }
            } else {
                // Player is nil; clear selection so the button becomes actionable again
                currentlyPlayingID = nil
                isAudioPlaying = false
            }
            return
        }

        // Stop any existing playback first (single-player policy)
        if audioPlayer?.isPlaying == true || currentlyPlayingID != nil {
            audioPlayer?.stop()
            audioPlayer = nil
            currentlyPlayingID = nil
            isAudioPlaying = false
        }

        guard let item = stagedAudio.first(where: { $0.id == id }) else { return }
        do {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(id.uuidString)
                .appendingPathExtension("m4a")
            try? item.data.write(to: tmp, options: .atomic)

            audioPlayer = try AVAudioPlayer(contentsOf: tmp)
            let delegate = AudioPlayerDelegateBridge(onFinish: {
                DispatchQueue.main.async {
                    if currentlyPlayingID == id {
                        currentlyPlayingID = nil
                        isAudioPlaying = false
                    }
                }
            })
            audioPlayer?.delegate = delegate
            audioPlayerDelegate = delegate // retain delegate so callbacks fire
            installAudioObserversIfNeeded()
            audioPlayer?.play()
            isAudioPlaying = (audioPlayer?.isPlaying == true)
            currentlyPlayingID = id
        } catch {
            print("Playback error: \(error)")
        }
    }

    func deleteAudio(_ id: UUID) {
        if currentlyPlayingID == id {
            audioPlayer?.stop()
            audioPlayer = nil
            currentlyPlayingID = nil
            isAudioPlaying = false
        }

        // Remove surrogate temp file best-effort
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(id.uuidString)
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: tmp)

        stagedAudio.removeAll { $0.id == id }
        audioTitles.removeValue(forKey: id)
        audioAutoTitles.removeValue(forKey: id)
        audioDurations.removeValue(forKey: id)
        persistStagedAttachments()

        // Mirror delete to staging store
        if let ref = StagingStore.list().first(where: { $0.id == id }) {
            StagingStore.remove(ref)
        }
        // Clear audio metadata in StagingStore for this id
        StagingStore.updateAudioMetadata(id: id, title: "", autoTitle: "", duration: nil)
    }

   func stopAttachmentPlayback() {
        if audioPlayer?.isPlaying == true {
            audioPlayer?.stop()
        }
        audioPlayer = nil
        isAudioPlaying = false
        currentlyPlayingID = nil
    }

   func installAudioObserversIfNeeded() {
        guard !audioObserversInstalled else { return }

        let nc = NotificationCenter.default
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            handleTimerAudioInterruption(note)
        }
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            handleTimerAudioRouteChange(note)
        }

        #if canImport(UIKit)
        nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
                // do not clear currentlyPlayingID so UI shows paused state
            }
        }

        nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            if wasPlayingBeforeInterruption_timer, audioPlayer != nil {
                audioPlayer?.play()
                isAudioPlaying = true
            } else if audioPlayer == nil {
                // Player deallocated or invalid — reset UI so the button toggles work
                currentlyPlayingID = nil
                isAudioPlaying = false
            }
            wasPlayingBeforeInterruption_timer = false
        }
        #endif

        audioObserversInstalled = true
    }

    func removeAudioObserversIfNeeded() {
        guard audioObserversInstalled else { return }

        let nc = NotificationCenter.default
        nc.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        nc.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)

        #if canImport(UIKit)
        nc.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        nc.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif

        audioObserversInstalled = false
    }

    func handleTimerAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
                // Keep currentlyPlayingID set so UI shows paused state
            }
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume),
               wasPlayingBeforeInterruption_timer,
               audioPlayer != nil {
                // Try to resume playback
                audioPlayer?.play()
                isAudioPlaying = true
            } else {
                // If we can't resume, clear stuck UI by resetting currentlyPlayingID
                wasPlayingBeforeInterruption_timer = false
                if audioPlayer == nil || audioPlayer?.url == nil {
                    currentlyPlayingID = nil
                    isAudioPlaying = false
                }
            }
            wasPlayingBeforeInterruption_timer = false
        @unknown default:
            break
        }
    }

  func handleTimerAudioRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            if audioPlayer?.isPlaying == true {
                wasPlayingBeforeInterruption_timer = true
                audioPlayer?.pause()
                isAudioPlaying = false
            }
        default:
            break
        }

        // If the route change invalidated the player, clear UI selection to prevent a stuck button
        if audioPlayer == nil {
            currentlyPlayingID = nil
            isAudioPlaying = false
        }
    }
}

/// Simple bridge so AVAudioPlayer delegate keeps a Swift closure alive.
final class AudioPlayerDelegateBridge: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

