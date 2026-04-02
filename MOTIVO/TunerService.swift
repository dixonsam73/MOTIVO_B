//
//  TunerService.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 02/04/2026.
//

import Foundation
import AVFoundation
import AudioKit
import AudioKitEX
import SoundpipeAudioKit

final class TunerService: ObservableObject {

    // MARK: - Published Output

    @Published private(set) var state: TunerDisplayState = .listening

    // MARK: - AudioKit

    private var engine: AudioEngine?
    private var pitchTap: PitchTap?
    private var mutedInput: Fader?
    private var analysisMixer: Mixer?

    // MARK: - Mapping

    private let mapper = TunerMapper()

    // MARK: - State

    private var isRunning = false

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        mapper.reset()
        state = .listening

        teardownAudioGraph()
        setupAudioSession()
        setupPitchDetection()

        guard let engine else {
            print("⚠️ TunerService failed to create audio engine")
            isRunning = false
            return
        }

        do {
            try engine.start()
        } catch {
            print("⚠️ TunerService failed to start engine: \(error)")
            teardownAudioGraph()
            deactivateAudioSession()
            restorePlaybackFriendlySession()
            isRunning = false
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        teardownAudioGraph()
        deactivateAudioSession()
        restorePlaybackFriendlySession()

        DispatchQueue.main.async {
            self.state = .listening
        }
    }

    // MARK: - Setup

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker]
            )
            try session.setPreferredInput(nil)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ TunerService audio session error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ TunerService audio session deactivation error: \(error)")
        }
    }

    private func restorePlaybackFriendlySession() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ TunerService playback session restore error: \(error)")
        }
    }

    private func setupPitchDetection() {
        let engine = AudioEngine()
        self.engine = engine

        guard let input = engine.input else {
            print("⚠️ TunerService: no audio input available")
            return
        }

        let analysisMixer = Mixer(input)
        let mutedInput = Fader(analysisMixer, gain: 0)

        self.analysisMixer = analysisMixer
        self.mutedInput = mutedInput
        engine.output = mutedInput

        let pitchTap = PitchTap(input) { [weak self] frequencies, amplitudes in
            guard let self else { return }
            guard
                let frequency = frequencies.first,
                let amplitude = amplitudes.first
            else { return }

            let newState = self.mapper.process(
                frequency: Double(frequency),
                amplitude: Double(amplitude)
            )

            DispatchQueue.main.async {
                self.state = newState
            }
        }

        self.pitchTap = pitchTap
        pitchTap.start()
    }

    private func teardownAudioGraph() {
        pitchTap?.stop()
        pitchTap = nil

        engine?.stop()
        engine?.output = nil
        engine = nil

        mutedInput = nil
        analysisMixer = nil
    }
}
