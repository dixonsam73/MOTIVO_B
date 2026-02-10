// CHANGE-ID: 20260210_190200_Phase15_Step3B_AvatarEditor
// SCOPE: Phase 15 Step 3B — AvatarEditorView: export JPEG (sRGB) with size hygiene + Clear control; output jpegData+preview; no layout redesign.
// SEARCH-TOKEN: 20260210_190200_Phase15_Step3B_AvatarEditor

import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

private enum TopButtonsUI {
    static let size: CGFloat = 40
    static let fillOpacityLight: CGFloat = 0.96
    static let fillOpacityDark: CGFloat = 0.88
}

fileprivate struct InitialsCircleView: View {
    let initials: String
    let diameter: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(UIColor.secondarySystemFill))
            Text(initials)
                .font(.system(size: max(12, diameter * 0.32), weight: .bold))
                .minimumScaleFactor(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Avatar placeholder: \(initials)")
    }
}

public struct AvatarEditorView: View {
    public init(
        image: UIImage?,
        placeholderInitials: String? = nil,
        onSave: @escaping (Data, UIImage) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onReplaceOriginal: ((UIImage) -> Void)? = nil
    ) {
        self._workingImage = State(initialValue: image)
        self.placeholderInitials = placeholderInitials
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onReplaceOriginal = onReplaceOriginal
    }
    
    @State private var workingImage: UIImage?
    @State private var exportErrorMessage: String? = nil
    
    // Zoom & pan state
    @State private var baseScale: CGFloat = 1.0
    @GestureState private var pinch: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    // Layout tracking
    @State private var editorDiameter: CGFloat = 280
    @Environment(\.colorScheme) private var colorScheme
    private let placeholderInitials: String?

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 3.0
    
    #if canImport(PhotosUI)
    @State private var showPhotoPicker = false
    @State private var item: PhotosPickerItem?
    #endif

    @State private var showCamera = false
    
    private let onSave: (Data, UIImage) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void
    private let onReplaceOriginal: ((UIImage) -> Void)?
    
    public var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width, proxy.size.height, 280)
                    
                    let effectiveScale = min(max(baseScale * pinch, minScale), maxScale)
                    let effectiveOffset = CGSize(
                        width: offset.width + dragTranslation.width,
                        height: offset.height + dragTranslation.height
                    )
                    
                    ZStack {
                        if let image = workingImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .scaleEffect(effectiveScale)
                                .offset(effectiveOffset)
                                .frame(width: diameter, height: diameter)
                                .clipShape(Circle())
                                .contentShape(Circle())
                                .gesture(
                                    SimultaneousGesture(
                                        MagnificationGesture()
                                            .updating($pinch) { value, state, _ in
                                                state = value
                                            }
                                            .onEnded { value in
                                                baseScale = min(max(baseScale * value, minScale), maxScale)
                                            },
                                        DragGesture()
                                            .updating($dragTranslation) { value, state, _ in
                                                state = value.translation
                                            }
                                            .onEnded { value in
                                                offset = CGSize(
                                                    width: offset.width + value.translation.width,
                                                    height: offset.height + value.translation.height
                                                )
                                            }
                                    )
                                )
                        } else {
                            if let initials = placeholderInitials, !initials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                InitialsCircleView(initials: initials, diameter: diameter)
                            } else {
                                Circle()
                                    .fill(Color(UIColor.secondarySystemFill))
                                    .frame(width: diameter, height: diameter)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(.secondary)
                                            .padding(diameter * 0.3)
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: proxy.size) { newSize in
                        let diameter = min(newSize.width, newSize.height, 280)
                        editorDiameter = diameter
                    }
                }
                .frame(height: 320)
                if let msg = exportErrorMessage {
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.s)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .safeAreaInset(edge: .top) {
                HStack {
                    Button(action: onCancel) {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                                .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")

                    Spacer()

                    HStack(spacing: Theme.Spacing.l) {
                        Button { showCamera = true } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                Image(systemName: "camera")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Take photo with camera")

                        #if canImport(PhotosUI)
                        Button { showPhotoPicker = true } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose photo from library")
                        #endif

                        

                        Button {
                            // Clear the current avatar (revert to initials)
                            onDelete()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                Image(systemName: "trash")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(workingImage == nil)
                        .opacity(workingImage == nil ? 0.35 : 1.0)
                        .accessibilityLabel("Clear avatar")
Button {
                            guard let image = workingImage else { return }
                            let effectiveScale = min(max(baseScale, minScale), maxScale)
                            let cropped = renderCroppedCircle(
                                from: image,
                                outputSize: 512,
                                editorDiameter: editorDiameter,
                                scale: effectiveScale,
                                offset: offset
                            )

                            // Data hygiene: JPEG sRGB, target ≤100 KB, hard cap 200 KB.
                            guard let jpegData = AvatarJPEGExporter.makeJPEGData(
                                from: cropped,
                                targetBytes: 100_000,
                                hardCapBytes: 200_000
                            ) else {
                                exportErrorMessage = "Couldn’t export this photo as a small JPEG. Please try a different image."
                                return
                            }

                            if jpegData.count > 200_000 {
                                exportErrorMessage = "That photo is still too large after compression. Please choose a different image."
                                return
                            }

                            exportErrorMessage = nil
                            onSave(jpegData, cropped)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.thinMaterial)
                                    .opacity(colorScheme == .dark ? TopButtonsUI.fillOpacityDark : TopButtonsUI.fillOpacityLight)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.15), radius: 2, y: 1)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            .frame(width: TopButtonsUI.size, height: TopButtonsUI.size)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Save avatar photo")
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
             }
            #if canImport(PhotosUI)
            .photosPicker(isPresented: $showPhotoPicker, selection: $item, matching: .images)
            .task(id: item) {
                guard let item = item else { return }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    workingImage = uiImage
                    baseScale = 1.0
                    offset = .zero
                    onReplaceOriginal?(uiImage)
                }
            }
            #endif
            #if canImport(UIKit)
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    workingImage = image
                    baseScale = 1.0
                    offset = .zero
                    onReplaceOriginal?(image)
                }
            }
            #endif
            .appBackground()
            .background(Theme.Colors.background(colorScheme).ignoresSafeArea())
        }
    }
    
    private func renderCroppedCircle(
        from image: UIImage,
        outputSize: CGFloat,
        editorDiameter: CGFloat,
        scale: CGFloat,
        offset: CGSize
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize))
        return renderer.image { context in
            let ctx = context.cgContext

            // Clip to a full-size circle
            let circleRect = CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
            ctx.addEllipse(in: circleRect)
            ctx.clip()

            let imageSize = image.size

            // Base aspect-fill scale to fit the image within the editorDiameter square
            let scaleX = editorDiameter / imageSize.width
            let scaleY = editorDiameter / imageSize.height
            let aspectFillScale = max(scaleX, scaleY)

            // Total scale applied in the preview
            let totalScale = aspectFillScale * scale

            // In editor coordinates, the image is drawn centered in a editorDiameter x editorDiameter square
            let scaledImageSize = CGSize(width: imageSize.width * totalScale, height: imageSize.height * totalScale)
            let editorOrigin = CGPoint(
                x: (editorDiameter - scaledImageSize.width) / 2 + offset.width,
                y: (editorDiameter - scaledImageSize.height) / 2 + offset.height
            )

            // Convert editor coordinates to output coordinates
            let outputFactor = outputSize / editorDiameter
            let outputOrigin = CGPoint(x: editorOrigin.x * outputFactor, y: editorOrigin.y * outputFactor)
            let outputSizeRect = CGSize(width: scaledImageSize.width * outputFactor, height: scaledImageSize.height * outputFactor)

            let drawRect = CGRect(origin: outputOrigin, size: outputSizeRect)
            ctx.interpolationQuality = .high
            image.draw(in: drawRect)
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}


// MARK: - Avatar export hygiene

enum AvatarJPEGExporter {
    /// Export JPEG data in sRGB, attempting to hit targetBytes and never exceeding hardCapBytes if possible.
    static func makeJPEGData(from image: UIImage, targetBytes: Int, hardCapBytes: Int) -> Data? {
        let srgb = forceSRGB(image)
        // Try a descending quality ladder.
        let qualities: [CGFloat] = [0.85, 0.75, 0.65, 0.55, 0.45, 0.38, 0.32, 0.28]
        var best: Data?

        for q in qualities {
            guard let data = srgb.jpegData(compressionQuality: q) else { continue }
            best = data
            if data.count <= targetBytes { return data }
            if data.count <= hardCapBytes {
                // Keep searching for closer-to-target but this is acceptable.
                // Continue to see if we can hit target without exceeding cap.
                continue
            }
        }

        // If we never got under hard cap, return the smallest we managed.
        return best
    }

    private static func forceSRGB(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width
        let height = cg.height

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let out = ctx.makeImage() else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }
}
