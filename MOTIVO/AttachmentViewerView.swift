import SwiftUI

private final class _ImageCache {
    static let shared = _ImageCache()
    let cache = NSCache<NSURL, UIImage>()
    private init() {}
}

struct AttachmentViewerView: View {
    let imageURLs: [URL]
    @State var startIndex: Int
    var themeBackground: Color = Color(.systemBackground) // dynamic light/dark

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var isPagerInteractable = false
    @State private var pendingDragTranslation: CGFloat = 0
    @State private var hasCommittedOnce: Bool = false

    init(imageURLs: [URL], startIndex: Int, themeBackground: Color = Color(.systemBackground)) {
        self.imageURLs = imageURLs
        self._startIndex = State(initialValue: startIndex)
        self._currentIndex = State(initialValue: startIndex)
        self.themeBackground = themeBackground
    }

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()

            GeometryReader { proxy in
                TabView(selection: $currentIndex) {
                    ForEach(imageURLs.indices, id: \.self) { i in
                        URLImageView(url: imageURLs[i], background: themeBackground)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .background(Color.clear)
                            .clipped()
                            .tag(i)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height) // <-- key
                .contentShape(Rectangle()) // full-area swipe target
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .indexViewStyle(.page(backgroundDisplayMode: .automatic))
                .allowsHitTesting(isPagerInteractable)
                .onChange(of: currentIndex) { oldValue, newValue in
                    guard !imageURLs.isEmpty else {
                        currentIndex = 0
                        return
                    }
                    let upper = imageURLs.count - 1
                    let clamped = min(max(newValue, 0), upper)
                    if clamped != newValue {
                        currentIndex = clamped
                        return
                    }
                    DispatchQueue.main.async {
                        if currentIndex == clamped {
                            currentIndex = clamped
                        }
                        hasCommittedOnce = true
                    }
                    prefetchNeighbors(around: clamped)
                }
                .onAppear {
                    let idx: Int
                    if imageURLs.isEmpty {
                        idx = 0
                    } else {
                        let upper = imageURLs.count - 1
                        idx = min(max(startIndex, 0), upper)
                    }
                    currentIndex = idx
                    DispatchQueue.main.async { currentIndex = idx }
                    prefetchNeighbors(around: idx)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        currentIndex = idx
                        isPagerInteractable = true
                    }
                }
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
    
    private func prefetchNeighbors(around index: Int) {
        guard !imageURLs.isEmpty else { return }
        let neighbors = [index - 1, index, index + 1].filter { imageURLs.indices.contains($0) }
        for i in neighbors {
            let url = imageURLs[i] as NSURL
            if _ImageCache.shared.cache.object(forKey: url) != nil { continue }
            Task.detached {
                if let data = try? Data(contentsOf: url as URL),
                   let img = UIImage(data: data) {
                    _ImageCache.shared.cache.setObject(img, forKey: url)
                }
            }
        }
    }
}

// MARK: - Async URL Image Loader (no blocking on main)
private struct URLImageView: View {
    let url: URL
    var background: Color = Color(.systemBackground)
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
        .background(background)
        .ignoresSafeArea()
    }

    @MainActor
    private func setImage(_ image: UIImage?) {
        self.uiImage = image
    }

    private func loadIfNeeded() async {
        if uiImage != nil || isLoading { return }
        isLoading = true
        let key = url as NSURL
        if let cached = _ImageCache.shared.cache.object(forKey: key) {
            await setImage(cached)
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                await setImage(img)
                _ImageCache.shared.cache.setObject(img, forKey: key)
            } else {
                await setImage(UIImage(systemName: "photo"))
            }
        } catch {
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
