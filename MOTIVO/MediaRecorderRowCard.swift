// MediaRecorderRowCard.swift
// Extracted from PracticeTimerView as part of refactor step 2.
// Visual/interaction row for audio, photo, and video recorders.
// No logic moves; all state/behaviour stays in PracticeTimerView.

import SwiftUI
import AVFoundation
import AVKit

struct MediaRecorderRowCard: View {
    @Binding var showAudioRecorder: Bool
    @Binding var showCamera: Bool
    @Binding var showVideoRecorder: Bool
    @Binding var droneIsOn: Bool

    let recorderIcon: Color
    let droneEngine: DroneEngine
    let stopAttachmentPlayback: () -> Void
    let ensureCameraAuthorized: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: 12) {
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
                        .foregroundStyle(recorderIcon)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.bordered)
                .background(
                    // Always-present overlay sized to the same rect as the button; only fill color changes
                    Capsule(style: .continuous)
                        .fill(showAudioRecorder ? Theme.Colors.primaryAction.opacity(0.18) : Color.clear)
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

                    // Stop drone before opening video recorder
                    droneEngine.stop()
                    droneIsOn = false

                    showVideoRecorder = true
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
        .frame(maxWidth: .infinity, alignment: .center)
        
    }
}

