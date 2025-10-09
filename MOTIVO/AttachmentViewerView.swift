import SwiftUI

struct AttachmentViewerView: View {
    let imageURLs: [URL]
    @State var startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0

    init(imageURLs: [URL], startIndex: Int) {
        self.imageURLs = imageURLs
        self._startIndex = State(initialValue: startIndex)
        self._currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(imageURLs.indices, id: \.self) { i in
                    URLImageView(url: imageURLs[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onAppear {
                currentIndex = startIndex.clamped(to: 0...(imageURLs.count - 1))
            }

            // Top controls
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())

                    Spacer()

                    if imageURLs.indices.contains(currentIndex) {
                        ShareLink(item: imageURLs[currentIndex]) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }
            .zIndex(2) // ensure buttons are above the pager
            .allowsHitTesting(true)
        }
    }
}

// MARK: - Async URL Image Loader (no blocking on main)
private struct URLImageView: View {
    let url: URL
    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadIfNeeded()
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    @MainActor
    private func setImage(_ image: UIImage?) {
        self.uiImage = image
    }

    private func loadIfNeeded() async {
        if uiImage != nil || isLoading { return }
        isLoading = true
        // Load off the main thread
        let data: Data? = await withCheckedContinuation { cont in
            Task.detached {
                let d = try? Data(contentsOf: url)
                cont.resume(returning: d)
            }
        }
        if let data, let img = UIImage(data: data) {
            await setImage(img)
        } else {
            // neutral placeholder if missing/unreadable
            await setImage(UIImage(systemName: "photo"))
        }
        isLoading = false
    }
}

// MARK: - Helpers
private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
