import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

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
        onSave: @escaping (UIImage) -> Void,
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
    
    // Zoom & pan state
    @State private var baseScale: CGFloat = 1.0
    @GestureState private var pinch: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    // Layout tracking
    @State private var editorDiameter: CGFloat = 280
    private let placeholderInitials: String?

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 3.0
    
    #if canImport(PhotosUI)
    @State private var showPhotoPicker = false
    @State private var item: PhotosPickerItem?
    #endif
    
    private let onSave: (UIImage) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void
    private let onReplaceOriginal: ((UIImage) -> Void)?
    
    public var body: some View {
        NavigationStack {
            VStack {
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
                Spacer()
            }
            .navigationTitle("Edit Avatar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", action: onCancel)
                        .accessibilityLabel("Cancel avatar editing")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Overflow menu with Replace Photo and Delete
                    Menu {
                        #if canImport(PhotosUI)
                        Button("Replace Photo") { showPhotoPicker = true }
                        #endif
                        Button("Delete", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                            .accessibilityLabel("More options")
                    }

                    // Primary Save action remains as a button
                    Button("Save") {
                        guard let image = workingImage else { return }
                        let effectiveScale = min(max(baseScale, minScale), maxScale)
                        let cropped = renderCroppedCircle(
                            from: image,
                            outputSize: 512,
                            editorDiameter: editorDiameter,
                            scale: effectiveScale,
                            offset: offset
                        )
                        onSave(cropped)
                    }
                    .accessibilityLabel("Save avatar photo")
                    .bold()
                }
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

