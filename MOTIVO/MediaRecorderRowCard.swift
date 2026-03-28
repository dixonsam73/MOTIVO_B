// CHANGE-ID: 20260328_023900_stage5_recorder_live_trigger_alignment_fix
// SCOPE: Visual-only — align audio recorder trigger with established neutral / warm-open / green-live state language, including green trigger while actively recording; no logic or layout changes.
// SEARCH-TOKEN: 20260328_023900_stage5_recorder_live_trigger_alignment_fix


// CHANGE-ID: 20260104_103646-mrrc-densityDemoteA
// SCOPE: Visual-only — slightly reduce MediaRecorderRowCard vertical density to demote it vs TimerCard (Option A)

// MediaRecorderRowCard.swift
// Extracted from PracticeTimerView as part of refactor step 2.
// Visual/interaction row for audio, photo, and video recorders.
// No logic moves; all state/behaviour stays in PracticeTimerView.
//
// CHANGE-ID: 20251214-VIDPERM-GATE-001
// SCOPE: Gate “Record video” launch on camera + microphone permissions (one-file, button-action only).

import SwiftUI
import AVFoundation
import AVKit

struct MediaRecorderRowCard: View {
    @Binding var showAudioRecorder: Bool
    @Binding var showCamera: Bool
    @Binding var showVideoRecorder: Bool
    @Binding var droneIsOn: Bool

    @State private var isAudioRecorderRecording = false

    let recorderIcon: Color
    let droneEngine: DroneEngine
    let stopAttachmentPlayback: () -> Void
    let ensureCameraAuthorized: (@escaping () -> Void) -> Void

    private let tasksAccent = Color(red: 0.66, green: 0.58, blue: 0.46)
    private let tasksAccentIcon = Color(red: 0.44, green: 0.37, blue: 0.29)

    private var audioTriggerIconColor: Color {
        if showAudioRecorder && isAudioRecorderRecording {
            return Theme.Colors.primaryAction
        }
        if showAudioRecorder {
            return tasksAccentIcon
        }
        return recorderIcon
    }

    private var audioTriggerFillColor: Color {
        if showAudioRecorder && isAudioRecorderRecording {
            return Theme.Colors.primaryAction.opacity(0.18)
        }
        if showAudioRecorder {
            return tasksAccent.opacity(0.26)
        }
        return .clear
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    if showAudioRecorder {
                        // Close the recorder panel when already visible
                        showAudioRecorder = false
                    } else {
                        stopAttachmentPlayback()
                        showAudioRecorder = true
                    }
                } label: {
                    Image(systemName: "mic.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(audioTriggerIconColor)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .background(
                    // Always-present overlay sized to the same rect as the button; only fill color changes
                    Capsule(style: .continuous)
                        .fill(audioTriggerFillColor)
                )
                .clipShape(Capsule(style: .continuous))
                .animation(.none, value: showAudioRecorder)
                .transaction { txn in
                    txn.disablesAnimations = true
                }
                .accessibilityLabel("Record audio")
                .accessibilityHint("Opens the audio recorder for this session.")

                // New: Take Photo button (camera) inserted between mic and video
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        // Stop drone before opening camera
                        droneEngine.stop()
                        droneIsOn = false

                        ensureCameraAuthorized { showCamera = true }
                    } label: {
                        Image(systemName: "camera.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(recorderIcon)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Take photo")
                    .accessibilityHint("Opens the camera to capture a still photo for this session.")
                }

                Button {
                    stopAttachmentPlayback()

                    func presentVideoRecorder() {
                        // Stop drone before opening video recorder (only once we're actually presenting)
                        droneEngine.stop()
                        droneIsOn = false
                        showVideoRecorder = true
                    }

                    func checkMicrophoneThenPresent() {
                        let micPerm = AVAudioSession.sharedInstance().recordPermission
                        switch micPerm {
                        case .granted:
                            presentVideoRecorder()
                        case .undetermined:
                            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                                DispatchQueue.main.async {
                                    if granted {
                                        presentVideoRecorder()
                                    } else {
                                        // denied: do nothing (per scope)
                                    }
                                }
                            }
                        case .denied:
                            // denied: do nothing (per scope)
                            break
                        @unknown default:
                            break
                        }
                    }

                    let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    switch camStatus {
                    case .authorized:
                        checkMicrophoneThenPresent()
                    case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    checkMicrophoneThenPresent()
                                } else {
                                    // denied: do nothing (per scope)
                                }
                            }
                        }
                    case .denied, .restricted:
                        // denied/restricted: do nothing (per scope)
                        break
                    @unknown default:
                        break
                    }
                } label: {
                    Image(systemName: "video.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(recorderIcon)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Record video")
                .accessibilityHint("Opens the video recorder for this session.")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("etudesAudioRecorderRecordingStateDidChange"))) { notification in
            guard let isRecording = notification.object as? Bool else { return }
            isAudioRecorderRecording = isRecording
        }
        .onChange(of: showAudioRecorder) { isShown in
            if !isShown {
                isAudioRecorderRecording = false
            }
        }
    }
}
