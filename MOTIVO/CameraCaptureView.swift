//
//  CameraCaptureView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 12/09/2025.
//

import SwiftUI
import UIKit
import AVFoundation

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.presentationMode) var presentationMode
    var onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onImageCaptured = { image in
            onImageCaptured(image)
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }
        vc.onCancel = {
            DispatchQueue.main.async {
                presentationMode.wrappedValue.dismiss()
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

// MARK: - Custom Camera Controller
final class CameraViewController: UIViewController {
    // Public callbacks
    var onImageCaptured: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    // Capture components
    private let session = AVCaptureSession()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()

    // UI
    private let previewView = PreviewView()
    private let shutterButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let modeLabel = PaddedLabel()

    private var isSessionRunning = false
    private var currentPosition: AVCaptureDevice.Position = .front
    private var flashMode: AVCaptureDevice.FlashMode = .off

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureUI() {
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false

        // Shutter button
        shutterButton.setImage(circleImage(diameter: 72, ring: true), for: .normal)
        shutterButton.tintColor = .white
        shutterButton.accessibilityLabel = "Shutter"
        shutterButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)

        // Close (cancel)
        closeButton.setImage(symbol("xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        // Flip camera
        flipButton.setImage(symbol("arrow.triangle.2.circlepath.camera"), for: .normal)
        flipButton.tintColor = .white
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)

        // Flash toggle
        flashButton.setImage(symbol("bolt.slash.fill"), for: .normal)
        flashButton.tintColor = .white
        flashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)

        // Mode label (to mimic PHOTO pill without heavy UI)
        modeLabel.text = "PHOTO"
        modeLabel.textColor = .systemYellow
        modeLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        modeLabel.textAlignment = .center
        modeLabel.backgroundColor = UIColor(white: 0, alpha: 0.6)
        modeLabel.layer.cornerRadius = 16
        modeLabel.layer.masksToBounds = true
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.setContentHuggingPriority(.required, for: .vertical)
        modeLabel.setContentHuggingPriority(.required, for: .horizontal)
        modeLabel.textInsets = UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)

        for button in [shutterButton, closeButton, flipButton, flashButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(button)
        }
        view.addSubview(modeLabel)

        // Layout with safe areas so controls are fully visible
        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Shutter centered at bottom
            shutterButton.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            shutterButton.widthAnchor.constraint(equalToConstant: 88),
            shutterButton.heightAnchor.constraint(equalTo: shutterButton.widthAnchor),

            // Close at bottom-left
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 56),
            closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),

            // Flip at bottom-right
            flipButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            flipButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: 56),
            flipButton.heightAnchor.constraint(equalTo: flipButton.widthAnchor),

            // Flash at top-right
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            flashButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalTo: flashButton.widthAnchor),

            // Mode label above shutter
            modeLabel.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            modeLabel.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16)
        ])
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        do {
            let device = try bestDevice(position: currentPosition)
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
        } catch {
            print("Camera input error: \(error)")
        }

        // Output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        session.commitConfiguration()
        previewView.session = session
    }

    private func startSessionIfNeeded() {
        guard !isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
            self.isSessionRunning = true
        }
    }

    private func stopSession() {
        guard isSessionRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
            self.isSessionRunning = false
        }
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        if let device = videoDeviceInput?.device, device.hasFlash {
            settings.flashMode = self.flashMode
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() { onCancel?() }

    @objc private func flipCamera() {
        currentPosition = (currentPosition == .front) ? .back : .front
        session.beginConfiguration()
        // Remove existing input
        if let currentInput = videoDeviceInput { session.removeInput(currentInput) }
        // Add new input
        do {
            let device = try bestDevice(position: currentPosition)
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                videoDeviceInput = input
            }
        } catch {
            print("Flip camera error: \(error)")
        }
        session.commitConfiguration()
    }

    @objc private func toggleFlash() {
        flashMode = (flashMode == .off) ? .on : .off
        let name = (flashMode == .on) ? "bolt.fill" : "bolt.slash.fill"
        flashButton.setImage(symbol(name), for: .normal)
    }

    private func bestDevice(position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        if let fallback = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            return fallback
        }
        throw NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "No camera available"])
    }

    private func symbol(_ name: String) -> UIImage? {
        if let img = UIImage(systemName: name) { return img }
        return nil
    }

    private func circleImage(diameter: CGFloat, ring: Bool) -> UIImage? {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.clear.setFill()
            ctx.fill(rect)
            let path = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            UIColor.white.setStroke()
            path.lineWidth = ring ? 6 : 0
            path.stroke()
            let inner = UIBezierPath(ovalIn: rect.insetBy(dx: 14, dy: 14))
            UIColor.white.withAlphaComponent(0.9).setFill()
            inner.fill()
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Capture error: \(error)")
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        onImageCaptured?(image)
    }
}

// MARK: - PreviewView
private final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set { videoPreviewLayer.session = newValue }
    }
}

// MARK: - Padded label helper
final class PaddedLabel: UILabel {
    private struct AssociatedKeys { static var insetsKey: UInt8 = 0 }

    public var textInsets: UIEdgeInsets {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.insetsKey) as? NSValue)?.uiEdgeInsetsValue ?? .zero
        }
        set {
            let value = NSValue(uiEdgeInsets: newValue)
            objc_setAssociatedObject(self, &AssociatedKeys.insetsKey, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        let insetW = textInsets.left + textInsets.right
        let insetH = textInsets.top + textInsets.bottom
        return CGSize(width: size.width + insetW, height: size.height + insetH)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}
