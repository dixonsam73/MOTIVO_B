// CHANGE-ID: 20260520_211500_ContentViewRowExtractionPass1
// SCOPE: ContentView RemotePostRowTwin extraction only; moved unchanged from ContentView except file-scope access required for separate compilation.
// SEARCH-TOKEN: 20260520_211500_ContentViewRowExtractionPass1

import SwiftUI
import CoreData
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

struct RemotePostRowTwin: View {
    let post: BackendPost
    let scope: FeedScope
    let viewerUserID: String?
    @Binding var activeUserFilterUserID: String?
    let activeEnsembleMemberUserIDs: Set<String>

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var backendFeedStore: BackendFeedStore = BackendFeedStore.shared

    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false
    @AppStorage("hasSeenSaveHint_v1") private var hasSeenSaveHint: Bool = false
    @State private var showSaveHint: Bool = false
    @State private var saveHintToken = UUID()
    @State private var isRemoteCommentsPresented: Bool = false

    private func favAndExtraCount(from refs: [BackendSessionViewModel.BackendAttachmentRef]) -> (BackendSessionViewModel.BackendAttachmentRef?, Int) {
        guard !refs.isEmpty else { return (nil, 0) }
        // Prefer image > video > audio (to match the calmest visual footprint in the feed).
        let fav = refs.first(where: { $0.kind == .image })
            ?? refs.first(where: { $0.kind == .video })
            ?? refs.first
        return (fav, max(0, refs.count - 1))
    }

    private var cachedAttachmentMeta: RemotePostAttachmentMetaCache.Meta? {
        RemotePostAttachmentMetaCache.shared.get(post.id)
    }

    private var effectiveHasAttachments: Bool {
        // Cache-first: if we've ever seen attachments for this post in this session, keep the lane reserved.
        if let cached = cachedAttachmentMeta, cached.hasAny { return true }
        return !model.attachmentRefs.isEmpty
    }

    private var effectiveFavAttachmentRef: BackendSessionViewModel.BackendAttachmentRef? {
        if !model.attachmentRefs.isEmpty {
            return favAndExtraCount(from: model.attachmentRefs).0
        }
        return cachedAttachmentMeta?.fav
    }

    private var effectiveExtraAttachmentCount: Int {
        if !model.attachmentRefs.isEmpty {
            return favAndExtraCount(from: model.attachmentRefs).1
        }
        return cachedAttachmentMeta?.extraCount ?? 0
    }

    private func updateAttachmentMetaCacheIfNeeded() {
        let refs = model.attachmentRefs
        guard !refs.isEmpty else { return }
        let (fav, extra) = favAndExtraCount(from: refs)
        RemotePostAttachmentMetaCache.shared.set(post.id, .init(fav: fav, extraCount: extra, hasAny: true))
    }

    @ViewBuilder
    private func attachmentLanePlaceholder() -> some View {
        // Reserve the exact same footprint as RemoteAttachmentPreview for non-audio thumbs.
        let size: CGFloat = FEED_IMAGE_VIDEO_THUMB
        RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: FEED_THUMB_CORNER, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.06), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }


    private var viewerIsOwner: Bool {
        guard let viewer = viewerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let owner = post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !viewer.isEmpty, !owner.isEmpty else { return false }
        return viewer == owner
    }

    private var isHeaderFilterActive: Bool {
        guard scope == .all else { return false }
        return isActiveUserFilter(ownerIDNonEmpty, activeUserFilterUserID: activeUserFilterUserID)
            || isActiveEnsembleMember(ownerIDNonEmpty, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs)
    }

    private func toggleHeaderUserFilter(ownerID: String) {
        guard scope == .all else { return }
        if isActiveUserFilter(ownerID, activeUserFilterUserID: activeUserFilterUserID) {
            activeUserFilterUserID = nil
        } else {
            activeUserFilterUserID = ownerID
        }
    }

    private var identityHeaderHighlight: some View {
        Capsule(style: .continuous)
            .fill(isHeaderFilterActive ? Color(uiColor: .systemGray5) : .clear)
    }

    private var ownerIDNonEmpty: String? {
        if let o = post.ownerUserID, !o.isEmpty { return o }
        return viewerIsOwner ? (viewerUserID ?? nil) : nil
    }

    private var resolvedDirectoryAccount: DirectoryAccount? {
        // Resolve reactively from BackendFeedStore so the row updates when directory hydration completes.
        if let ownerRaw = post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ownerRaw.isEmpty {
            if let exact = backendFeedStore.directoryAccountsByUserID[ownerRaw] { return exact }
            let lower = ownerRaw.lowercased()
            if let byLower = backendFeedStore.directoryAccountsByUserID[lower] { return byLower }
        }
        return nil
    }

    private static let thoughtTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    private var model: BackendSessionViewModel {
        BackendSessionViewModel(post: post, currentUserID: (viewerUserID ?? ""))
    }

    private var isThoughtPost: Bool {
        BackendThoughtRules.isThought(post: post, model: model)
    }

    private var thoughtDateTimeLine: String {
        Self.thoughtTimestampFormatter.string(from: timestampDate)
    }

    private var activityName: String {
        if let label = post.activityLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        if let type = post.activityType?.trimmingCharacters(in: .whitespacesAndNewlines),
           !type.isEmpty {
            return type
        }
        return "Practice"
    }

    private var postDescription: String {
        post.activityDetail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var instrumentName: String {
        if let inst = post.instrumentLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !inst.isEmpty {
            return inst
        }
        return "Instrument"
    }

    private var timestampDate: Date {
        FeedRowItem.parseBackendDate(post.sessionTimestamp)
            ?? FeedRowItem.parseBackendDate(post.createdAt)
            ?? Date()
    }

    private var defaultDescription: String {
        "\(dayPart(for: timestampDate)) \(activityName)"
    }

    private var recognizedDefaultDescriptions: [String] {
        let parts = ["Morning", "Afternoon", "Evening", "Late Night"]
        return parts.map { "\($0) \(activityName)" }
    }

    private var isUsingDefaultDescription: Bool {
        let desc = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return false }
        if desc.caseInsensitiveCompare(defaultDescription) == .orderedSame { return true }
        return recognizedDefaultDescriptions.contains { desc.caseInsensitiveCompare($0) == .orderedSame }
    }

    private var feedTitle: String {
        // Mirror SessionActivity.feedTitle(for:) rules for BackendPost.
        let d = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return "\(instrumentName) : \(activityName)" }
        if isUsingDefaultDescription { return d }
        return d
    }

    private var feedSubtitle: String {
        // Mirror SessionActivity.feedSubtitle(for:) rules for BackendPost.
        let (timeStr, dateStr) = timeAndDateStrings(for: timestampDate)
        let d = postDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty {
            return [timeStr, dateStr].joined(separator: ", ")
        }

        let titleAlreadyContainsActivity = feedTitle
            .range(of: activityName, options: [.caseInsensitive, .diacriticInsensitive]) != nil

        if titleAlreadyContainsActivity {
            return [instrumentName, timeStr, dateStr].joined(separator: ", ")
        } else {
            return [instrumentName, activityName, timeStr, dateStr].joined(separator: ", ")
        }
    }

    private var subtitleParts: [String] {
        // Split the existing subtitle by commas, trimming whitespace
        feedSubtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateTimeLine: String? {
        // Expect last two parts to be time then date; produce 'DATE at TIME'
        let parts = subtitleParts
        guard parts.count >= 2 else { return nil }
        let time = parts[parts.count - 2]
        let date = parts[parts.count - 1]
        return "\(date) at \(time)"
    }

    private var instrumentActivityLine: String {
        // Everything except the last two parts (time/date)
        let parts = subtitleParts
        if parts.count <= 2 {
            return parts.dropLast(max(0, parts.count - 2)).joined(separator: ", ")
        } else {
            return parts.dropLast(2).joined(separator: ", ")
        }
    }

    private func dayPart(for date: Date) -> String {
        // Local time components
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour], from: date)
        let hour = comps.hour ?? 0
        switch hour {
        case 0...4: return "Late Night"
        case 5...11: return "Morning"
        case 12...17: return "Afternoon"
        default: return "Evening" // 18...23
        }
    }

    private func timeAndDateStrings(for date: Date) -> (String, String) {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        return (timeFormatter.string(from: date), dateFormatter.string(from: date))
    }

private var extraAttachmentCount: Int {
        let total = model.attachmentRefs.count
        return max(total - 1, 0)
    }

    private var favAttachmentRef: BackendSessionViewModel.BackendAttachmentRef? {
        model.attachmentRefs.first
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                // Identity header (match SessionRow: only when not in Mine)
                if scope != .mine,
                   let owner = ownerIDNonEmpty,
                   !owner.isEmpty {

                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            // Avatar 32pt circle
                            Button(action: { showPeek = true }) {
                            DirectoryAvatarCircle(
                                ownerID: owner,
                                displayName: (resolvedDirectoryAccount?.displayName ?? (viewerIsOwner ? "You" : "User")),
                                directoryAvatarKey: (viewerIsOwner ? auth.backendAvatarKey : resolvedDirectoryAccount?.avatarKey)
                            )
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // Name and optional location on one line
                        let realName: String = {
                            if viewerIsOwner {
                                // Owner precedence:
                                // 1) Local Profile.name (Core Data)
                                // 2) resolvedDirectoryAccount.displayName
                                // 3) "You"
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let p = try? ctx.fetch(req).first,
                                   let nRaw = p.name {
                                    let n = nRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !n.isEmpty { return n }
                                }

                                if let acct = resolvedDirectoryAccount {
                                    let dn = acct.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !dn.isEmpty { return dn }
                                }

                                return "You"
                            }

                            if let acct = resolvedDirectoryAccount {
                                let dn = acct.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !dn.isEmpty { return dn }
                            }

                            return "User"
                        }()
                        let loc: String = {
                            if viewerIsOwner {
                                if let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !canonicalOwner.isEmpty {
                                    let canonicalLocal = ProfileStore.location(for: canonicalOwner).trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !canonicalLocal.isEmpty { return canonicalLocal }
                                }

                                let local = ProfileStore.location(for: owner).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !local.isEmpty { return local }

                                if let acct = resolvedDirectoryAccount,
                                   let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !s.isEmpty {
                                    return s
                                }

                                if let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
                                   !canonicalOwner.isEmpty {
                                    if let acct = backendFeedStore.directoryAccountsByUserID[canonicalOwner],
                                       let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !s.isEmpty {
                                        return s
                                    }

                                    let lower = canonicalOwner.lowercased()
                                    if let acct = backendFeedStore.directoryAccountsByUserID[lower],
                                       let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !s.isEmpty {
                                        return s
                                    }
                                }

                                return ""
                            }
                            if let acct = backendFeedStore.directoryAccountsByUserID[owner],
                               let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            let lower = owner.lowercased()
                            if let acct = backendFeedStore.directoryAccountsByUserID[lower],
                               let s = acct.location?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            return ""
                        }()


                        VStack(alignment: .leading, spacing: 2) {
                            Text(realName)
                                .font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text(loc)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        

                        }
                        .background(
                            identityHeaderHighlight
                                .padding(.trailing, -12)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleHeaderUserFilter(ownerID: owner)
                        }
                        .accessibilityLabel(isHeaderFilterActive ? "Clear user filter" : "Filter feed to this user")

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 0)
                }

                if let dt = dateTimeLine {
                    Text(isThoughtPost ? thoughtDateTimeLine : dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 1)
                        .accessibilityLabel("Date and time")
                        .accessibilityIdentifier("row.datetime")
                }

                if isThoughtPost {
                    if let header = post.thoughtHeader {
                        let splitHeader = splitThoughtLead(header)
                        (
                            Text(splitHeader.lead)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(Color.primary.opacity(0.86))
                            +
                            Text(splitHeader.remainder)
                                .font(.headline.weight(.regular))
                                .foregroundColor(Color.primary.opacity(0.78))
                        )
                        .lineLimit(2)
                        .accessibilityLabel("Thought")
                        .accessibilityIdentifier("row.title")
                    }

                    if let body = post.thoughtBodyPreview {
                        Text(body)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(2)
                            .padding(.top, 3)
                            .accessibilityIdentifier("row.subtitle")
                    }
                } else {
                    // Title only (paperclip removed)
                    Text(feedTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityLabel("Session title")
                        .accessibilityIdentifier("row.title")

                    // Activity subtitle (metadata)
                    if !instrumentActivityLine.isEmpty {
                        Text(instrumentActivityLine)
                            .font(Theme.Text.body)
                            .lineLimit(2)
                            .padding(.top, 3)
                            .accessibilityLabel(instrumentActivityLine)
                            .accessibilityIdentifier("row.subtitle")
                    }
                }

                // Attachment preview (twin placement to SessionRow)
                if effectiveHasAttachments {
                    HStack(alignment: .center, spacing: 8) {
                        if let fav = effectiveFavAttachmentRef {
                            RemoteAttachmentPreview(ref: fav, postID: post.id)
                        } else {
                            attachmentLanePlaceholder()
                        }
                        Spacer()
                    }
                    .padding(.top, 2)

                    interactionRow(postID: post.id, attachmentCount: effectiveExtraAttachmentCount)
                        .padding(.top, 6)
                } else {
                    interactionRow(postID: post.id, attachmentCount: effectiveExtraAttachmentCount)
                        .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, effectiveHasAttachments ? 10 : 6)
.onAppear {
            updateAttachmentMetaCacheIfNeeded()
            // Keep initial saved state in sync for this viewer + post.
            let vid = (viewerUserID ?? "unknown")
            isSavedLocal = FeedInteractionStore.isSaved(post.id, viewerUserID: vid)
        }
        .onChange(of: model.attachmentRefs.count) { _, _ in
            updateAttachmentMetaCacheIfNeeded()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("row.openDetail")
        .sheet(isPresented: $showPeek) {
            let viewer = viewerUserID ?? ""
            let owner = post.ownerUserID ?? ""
            // Invariant: self-peek must never render follow gating in any mode.
            let ownerForPeek = (owner.isEmpty || owner == viewer) ? (viewer.isEmpty ? owner : viewer) : owner

            // CHANGE-ID: 20260211_142500_ContentView_PPV_RemotePeek_InjectDirectoryIdentity
            // SCOPE: Feed remote row ProfilePeekView must receive directory identity (name/location/avatar/instruments) to avoid "User •" fallback; no UI/layout changes.
            let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek]
                    ?? BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek.lowercased()]

            ProfilePeekView(
                ownerID: ownerForPeek,
                directoryDisplayName: acct?.displayName,
                directoryAccountID: acct?.accountID,
                directoryLocation: acct?.location,
                directoryAvatarKey: acct?.avatarKey,
                directoryInstruments: acct?.instruments
            )
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
        }
        .sheet(isPresented: $isRemoteCommentsPresented) {
            let owner = (post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let viewer = (viewerUserID ?? auth.backendUserID ?? auth.currentUserID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !owner.isEmpty, !viewer.isEmpty {
                CommentsView(
                    postID: post.id,
                    ownerUserID: owner,
                    viewerUserID: viewer,
                    ownerDisplayName: resolvedDirectoryAccount?.displayName,
                    placeholderAuthor: "You"
                )
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
            } else {
                EmptyView()
            }
        }

    }


// CHANGE-ID: 20260304_165600_FeedFilter_ThreadParityMenuSize_7c1a
// SCOPE: Feed Filter: keep strict parity; increase selector closed-state size to match prior Picker.menu label
// SEARCH-TOKEN: 20260210_181900_Phase15_Step2_AvatarRenderCache_DIR_AVATAR_VIEW
#if canImport(UIKit)
private struct DirectoryAvatarCircle: View {
    let ownerID: String
    let displayName: String
    let directoryAvatarKey: String?

    @State private var remoteAvatar: UIImage? = nil

    var body: some View {
        let key = directoryAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cacheKey = "avatars|\(key)"

        return Group {
            if let img = ProfileStore.avatarImage(for: ownerID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if !key.isEmpty, let cached = RemoteAvatarImageCache.get(cacheKey) {
                Image(uiImage: cached).resizable().scaledToFill()
            } else if !key.isEmpty, let remoteAvatar {
                Image(uiImage: remoteAvatar).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Text(initials(from: displayName))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .task(id: key) {
            guard !key.isEmpty else {
                remoteAvatar = nil
                return
            }
            if RemoteAvatarImageCache.get(cacheKey) != nil { return }
            if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: key) {
                remoteAvatar = ui
            }
        }
    }

    private func initials(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        let words = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
        let first = words.first?.first.map { String($0).uppercased() } ?? ""
        let last = words.last?.first.map { String($0).uppercased() } ?? ""
        let combo = (first + last)
        return combo.isEmpty ? "U" : combo
    }
}
#endif


private var saveHintView: some View {
    VStack(spacing: 2) {
        Text("Saved for later")
            .font(Theme.Text.meta)
            .foregroundStyle(.primary)
        Text("Use Filter to find saved posts")
            .font(.caption2)
            .foregroundStyle(Theme.Colors.secondaryText)
    }
    .transition(.opacity)
    }

private func presentSaveHint() {
    let token = UUID()
    saveHintToken = token
    withAnimation(.easeInOut(duration: 0.15)) {
        showSaveHint = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        guard saveHintToken == token else { return }
        hideSaveHint()
    }
    }

private func hideSaveHint() {
    withAnimation(.easeInOut(duration: 1.0)) {
        showSaveHint = false
    }
    }

private func interactionRow(postID: UUID, attachmentCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSaveHint {
                saveHintView
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Save (viewer-local)
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let vid = viewerUserID ?? "unknown"
                let newState = FeedInteractionStore.toggleSaved(postID, viewerUserID: vid)
                isSavedLocal = newState
                if !hasSeenSaveHint {
                    presentSaveHint()
                    hasSeenSaveHint = true
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSavedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isSavedLocal ? Color.red.opacity(0.75) : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            // Comment
            Button(action: {
                let owner = (post.ownerUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                let viewer = (viewerUserID ?? auth.backendUserID ?? auth.currentUserID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !owner.isEmpty, !viewer.isEmpty else { return }
                isRemoteCommentsPresented = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: CommentPresenceStore.shared.hasComments(postID: post.id) ? "text.bubble" : "bubble.right")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

       

            Spacer(minLength: 0)

            if attachmentCount > 0 {
                AttachmentCountBadge(count: attachmentCount)
            }
        }
        .padding(.top, -2)
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        }
    }

    private func shareText() -> String {
        // Keep this conservative: title + date only.
        var out: [String] = [feedTitle]
        if let dt = dateTimeLine { out.append(dt) }
        return out.joined(separator: "\n")
    }
}

