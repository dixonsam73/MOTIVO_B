// CHANGE-ID: 20260522_150900_MRRC_PermissionRecovery
// SCOPE: MediaRecorderRowCard — replace silent video camera/microphone permission failures with local recovery alerts + Settings route. No UI/logic changes outside permission recovery.
// SEARCH-TOKEN: 20260522_150900_MRRC_PermissionRecovery

import SwiftUI
import AVFoundation
import AVKit

struct MediaRecorderRowCard: View {
    @Binding var showAudioRecorder: Bool
    @Binding var showCamera: Bool
    @Binding var showVideoRecorder: Bool
    @Binding var droneIsOn: Bool

    @State private var isAudioRecorderRecording = false
    @State private var showCameraDeniedAlert = false
    @State private var showMicrophoneDeniedAlert = false

    let recorderIcon: Color
    let droneEngine: DroneEngine
    let stopAttachmentPlayback: () -> Void
    let ensureCameraAuthorized: (@escaping () -> Void) -> Void
    var isTunerOpen: Bool = false

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

    private var audioTriggerOpacity: Double {
        isTunerOpen ? 0.45 : 1.0
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    if showAudioRecorder {
                        // Close the recorder panel when already visible
                        showAudioRecorder = false
                    } else {
                        guard !isTunerOpen else { return }
                        stopAttachmentPlayback()

                        let micPerm = AVAudioSession.sharedInstance().recordPermission

                        switch micPerm {
                        case .granted:
                            showAudioRecorder = true

                        case .undetermined:
                            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                                DispatchQueue.main.async {
                                    if granted {
                                        showAudioRecorder = true
                                    } else {
                                        showMicrophoneDeniedAlert = true
                                    }
                                }
                            }

                        case .denied:
                            showMicrophoneDeniedAlert = true

                        @unknown default:
                            showMicrophoneDeniedAlert = true
                        }
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
                    Capsule(style: .continuous)
                        .fill(audioTriggerFillColor)
                )
                .clipShape(Capsule(style: .continuous))
                .opacity(audioTriggerOpacity)
                .animation(.none, value: showAudioRecorder)
                .transaction { txn in
                    txn.disablesAnimations = true
                }
                .accessibilityLabel("Record audio")
                .accessibilityHint(
                    isTunerOpen
                    ? "Unavailable while tuner is open."
                    : "Opens the audio recorder for this session."
                )

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
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
                                        showMicrophoneDeniedAlert = true
                                    }
                                }
                            }
                        case .denied:
                            showMicrophoneDeniedAlert = true
                        @unknown default:
                            showMicrophoneDeniedAlert = true
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
                                    showCameraDeniedAlert = true
                                }
                            }
                        }
                    case .denied, .restricted:
                        showCameraDeniedAlert = true
                    @unknown default:
                        showCameraDeniedAlert = true
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
        .onChange(of: showAudioRecorder) { _, isShown in
            if !isShown {
                isAudioRecorderRecording = false
            }
        }
        .alert(
            "Camera access denied",
            isPresented: $showCameraDeniedAlert
        ) {
            Button("OK", role: .cancel) {}

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Enable camera access in Settings to capture media.")
        }
        .alert(
            "Microphone access denied",
            isPresented: $showMicrophoneDeniedAlert
        ) {
            Button("OK", role: .cancel) {}

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("Enable microphone access in Settings to record audio or video.")
        }
    }
}
