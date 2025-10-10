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
    @State private var localIsPrivate: Bool = false
    @State private var cachedURL: URL? = nil
    var onDelete: ((URL) -> Void)? = nil
    var onFavourite: ((URL) -> Void)? = nil
    var isFavourite: ((URL) -> Bool)? = nil
    var onTogglePrivacy: ((URL) -> Void)? = nil
    var isPrivate: ((URL) -> Bool)? = nil

    private func currentURL() -> URL? {
        imageURLs.indices.contains(currentIndex) ? imageURLs[currentIndex] : nil
    }

    init(imageURLs: [URL], startIndex: Int, themeBackground: Color = Color(.systemBackground), onDelete: ((URL) -> Void)? = nil, onFavourite: ((URL) -> Void)? = nil, isFavourite: ((URL) -> Bool)? = nil, onTogglePrivacy: ((URL) -> Void)? = nil, isPrivate: ((URL) -> Bool)? = nil) {
        self.imageURLs = imageURLs
        self._startIndex = State(initialValue: startIndex)
        self._currentIndex = State(initialValue: startIndex)
        self.themeBackground = themeBackground
        self.onDelete = onDelete
        self.onFavourite = onFavourite
        self.isFavourite = isFavourite
        self.onTogglePrivacy = onTogglePrivacy
        self.isPrivate = isPrivate
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
                    if let url = currentURL() {
                        cachedURL = url
                        localIsPrivate = isPrivate?(url) ?? false
                    }
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
                    if let url = currentURL() {
                        cachedURL = url
                        localIsPrivate = isPrivate?(url) ?? false
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
                        let isFav = (imageURLs.indices.contains(currentIndex)
                                     ? (isFavourite?(imageURLs[currentIndex]) ?? false)
                                     : false)
                        let isPriv = localIsPrivate

                        Button {
                            if imageURLs.indices.contains(currentIndex) {
                                onFavourite?(imageURLs[currentIndex])
                            }
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isFav ? "Unfavourite attachment" : "Favourite attachment")

                        Button {
                            if let url = currentURL() {
                                // Optimistic UI update – no rebuild, no flash
                                localIsPrivate.toggle()
                                onTogglePrivacy?(url)
                            }
                        } label: {
                            Image(systemName: isPriv ? "eye.slash" : "eye")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPriv ? "Make attachment visible to others" : "Hide attachment from others")

                        Button {
                            if imageURLs.indices.contains(currentIndex) {
                                let url = imageURLs[currentIndex]
                                onDelete?(url) // app-only delete provided by presenter
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 17, weight: .semibold))
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete attachment")

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
            Task(priority: .background) {
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
    @State private var loadTask: Task<Void, Never>? = nil

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
            // Track the load task so we can cancel on disappear/reuse
            loadTask = Task { await loadIfNeeded() }
            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .background(background)
        .ignoresSafeArea()
    }

    @MainActor
    private func setImage(_ image: UIImage?) {
        self.uiImage = image
    }

    private func loadIfNeeded() async {
        if Task.isCancelled { return }
        if uiImage != nil || isLoading { return }
        isLoading = true
        let key = url as NSURL
        if let cached = _ImageCache.shared.cache.object(forKey: key) {
            await setImage(cached)
            if Task.isCancelled { return }
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
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
