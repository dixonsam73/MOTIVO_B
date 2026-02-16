// CHANGE-ID: 20260215_221500_CommentsView_InitialAutoScroll_ConnectedPaddingFix
// SCOPE: CommentsView — restore List-era horizontal insets for CONNECTED comments path after ScrollView/LazyVStack migration. UI-only; no logic/backend changes.
// SEARCH-TOKEN: 20260215_221500_CommentsView_InitialAutoScroll_ConnectedPaddingFix

// CHANGE-ID: 20260215_220800_CommentsView_InitialAutoScrollToBottom_SpacingFix3
// SCOPE: Restore List-equivalent outer + inner horizontal padding for comment card when using ScrollView+LazyVStack (UI-only).
// SEARCH-TOKEN: 20260215_215900_CommentsView_InitialAutoScrollToBottom_SpacingFix2
// SEARCH-TOKEN: 20260215_213000_CommentsView_InitialAutoScrollToBottom

// CHANGE-ID: 20260215_202000_CommentsUI_PlaceholderFix_SyntaxRepair
// SCOPE: Fix bad paste that left stray placeholder-return code at top level causing cascading compile errors; placeholder logic unchanged (fan-out wording only when recipientCount>1 && fan-out mode).
// SEARCH-TOKEN: 20260215_202000_CommentsUI_PlaceholderFix_SyntaxRepair

// CHANGE-ID: 20260215_200500_CommentsUI_CalmConditionalControls
// SCOPE: Comments UI calm-down: hide 'Respond to all commenters' when only one commenter; remove helper explanation line; show fan-out 'Sending privately…' chip only in fan-out; auto-exit fan-out if recipient count drops to 1. UI-only; no backend/schema/RPC changes.
// SEARCH-TOKEN: 20260215_200500_CommentsUI_CalmConditionalControls

// CHANGE-ID: 20260215_101500_CommentsUI_OwnerFollowUp_TargetSelector
// SCOPE: Comments UI-only: owner can always send targeted follow-up replies via calm target selector above composer; rename fan-out control to "Respond to all commenters" (+ helper text). No backend/schema/RPC changes.
// SEARCH-TOKEN: 20260215_101500_CommentsUI_OwnerFollowUp_TargetSelector

// CHANGE-ID: 20260215_174800_CommentsView_KeyboardDismissOnSend_Fix
// SCOPE: CommentsView keyboard retract-on-send + ensure latest message visible (ScrollViewReader bottom anchor). UI-only; no store/backend/schema changes.
// SEARCH-TOKEN: 20260215_174800_CommentsView_KeyboardDismissOnSend_Fix

// CHANGE-ID: 20260215_110254_UnreadComments_PeoplePlus
// SCOPE: CommentsView: when viewing connected post comments as owner, mark post comments as viewed (clears People '+'). No UI changes.
// SEARCH-TOKEN: 20260215_110254_UnreadComments_PeoplePlus

// CHANGE-ID: 20260215_102000_CommentsView_CalmUI_Polish_TuneDateAndTime
// SCOPE: CommentsView Calm UI Polish — remove location line; calmer date/time labels; UI-only
// SEARCH-TOKEN: 20260215_102000_CommentsView_CalmUI_Polish_TuneDateAndTime

import SwiftUI
import CoreData

public enum CommentsViewMode: Equatable {
    case localSession(sessionID: UUID)
    case connectedPost(postID: UUID, ownerUserID: String, viewerUserID: String, ownerDisplayName: String?)
}

public struct CommentsView: View {
    @ObservedObject private var store = CommentsStore.shared
    @StateObject private var backendStore: BackendCommentsStore
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool
    @State private var scrollToBottomNonce: Int = 0
    
    // Deterministic first-open scroll: keyed by current mode (postID/sessionID) so reopening a different thread re-scrolls.
    @State private var initialAutoScrollKey: String? = nil
    @State private var didInitialAutoScroll: Bool = false
    @State private var userHasManuallyScrolled: Bool = false
    @State private var tappedMention: String? = nil
    
    @State private var replyTargetUserID: String? = nil
    @State private var replyTargetDisplayName: String? = nil
    @State private var isTargetPickerPresented: Bool = false
    @State private var isRespondToCommentersMode: Bool = false

    // UI-only: read-through identity cache for comment rows (displayName/location/avatarKey). Never shows raw IDs.
    @State private var directoryAccounts: [String: DirectoryAccount] = [:]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var scheme
    
    private let mode: CommentsViewMode
    private let placeholderAuthor: String
    private static let bottomAnchorID = "comments_bottom_anchor"
    
    private var sessionID: UUID? {
        if case .localSession(let sid) = mode { return sid }
        return nil
    }
    
    private var postID: UUID? {
        if case .connectedPost(let pid, _, _, _) = mode { return pid }
        return nil
    }
    
    private var connectedOwnerUserID: String? {
        if case .connectedPost(_, let owner, _, _) = mode { return owner }
        return nil
    }
    
    private var connectedViewerUserID: String? {
        if case .connectedPost(_, _, let viewer, _) = mode { return viewer }
        return nil
    }
    
    private var connectedOwnerDisplayName: String? {
        if case .connectedPost(_, _, _, let name) = mode { return name }
        return nil
    }
    
    

    // MARK: - Deterministic auto-scroll

    private func autoScrollKey() -> String {
        switch mode {
        case .localSession(let sid):
            return "local_\(sid.uuidString)"
        case .connectedPost(let pid, _, _, _):
            return "connected_\(pid.uuidString)"
        }
    }

    private func resetAutoScrollStateIfNeeded() {
        let key = autoScrollKey()
        if initialAutoScrollKey != key {
            initialAutoScrollKey = key
            didInitialAutoScroll = false
            userHasManuallyScrolled = false
        }
    }

    private func scheduleScrollToBottom(_ proxy: ScrollViewProxy) {
        let perform: () -> Void = {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }

        DispatchQueue.main.async(execute: perform)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: perform)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: perform)
    }

    private func maybePerformInitialAutoScroll(proxy: ScrollViewProxy, contentCount: Int) {
        resetAutoScrollStateIfNeeded()
        guard !userHasManuallyScrolled else { return }
        guard contentCount > 0 else { return }
        guard !didInitialAutoScroll else { return }
        didInitialAutoScroll = true
        scheduleScrollToBottom(proxy)
    }

    public init(sessionID: UUID, placeholderAuthor: String = "You") {
        self.mode = .localSession(sessionID: sessionID)
        self.placeholderAuthor = placeholderAuthor
        _backendStore = StateObject(wrappedValue: BackendCommentsStore())
    }
    
    public init(postID: UUID, ownerUserID: String, viewerUserID: String, ownerDisplayName: String? = nil, placeholderAuthor: String = "You") {
        self.mode = .connectedPost(postID: postID, ownerUserID: ownerUserID.lowercased(), viewerUserID: viewerUserID.lowercased(), ownerDisplayName: ownerDisplayName)
        self.placeholderAuthor = placeholderAuthor
        _backendStore = StateObject(wrappedValue: BackendCommentsStore())
    }
    
    private func clearReplyTarget() {
        replyTargetUserID = nil
        replyTargetDisplayName = nil
    }
    
    
    // MARK: - 8H-D helper (owner fan-out recipients)
    private func respondToCommentersRecipientIDs(ownerUserID: String) -> [String] {
        // Connected mode: distinct commenter author ids (non-owner) present in the current fetched snapshot.
        if postID != nil {
            let owner = ownerUserID.lowercased()
            let ids = backendStore.comments.compactMap { row -> String? in
                let a = row.authorUserID.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !a.isEmpty, a != owner else { return nil }
                return a
            }
            return Array(Set(ids)).sorted()
        }
        
        // Local mode: distinct non-owner authors who have commented.
        guard let sid = sessionID else { return [] }
        let all = store.comments(for: sid)
        let ids: [String] = all.compactMap { c in
            let author = (store.authorUserID(for: c.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if author.isEmpty { return nil }
            if author == ownerUserID.lowercased() { return nil }
            return author
        }
        return Array(Set(ids)).sorted()
    }

    // MARK: - Owner reply targeting (UI-only)
    private struct CommenterTarget: Identifiable, Equatable {
        let userID: String
        let lastActivity: Date
        var id: String { userID }
    }

    private func commenterTargetsForPicker(ownerUserID: String) -> [CommenterTarget] {
        let owner = ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let _ = postID {
            // Connected: derive from backend snapshot.
            var latestByAuthor: [String: Date] = [:]
            for row in backendStore.comments {
                let a = row.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !a.isEmpty, a != owner else { continue }
                let t = row.createdAt
                if let existing = latestByAuthor[a] {
                    if t > existing { latestByAuthor[a] = t }
                } else {
                    latestByAuthor[a] = t
                }
            }
            return latestByAuthor
                .map { CommenterTarget(userID: $0.key, lastActivity: $0.value) }
                .sorted(by: { $0.lastActivity > $1.lastActivity })
        }

        // Local: derive from local comments.
        guard let sid = sessionID else { return [] }
        let all = store.comments(for: sid)
        var latestByAuthor: [String: Date] = [:]
        for c in all {
            let a = (store.authorUserID(for: c.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !a.isEmpty, a != owner else { continue }
            let t = c.timestamp
            if let existing = latestByAuthor[a] {
                if t > existing { latestByAuthor[a] = t }
            } else {
                latestByAuthor[a] = t
            }
        }
        return latestByAuthor
            .map { CommenterTarget(userID: $0.key, lastActivity: $0.value) }
            .sorted(by: { $0.lastActivity > $1.lastActivity })
    }

    private func ensureDefaultReplyTargetIfNeeded(ownerUserID: String) {
        // Owner-only: ensure we always have a valid target when there are commenters.
        let targets = commenterTargetsForPicker(ownerUserID: ownerUserID)
        guard !targets.isEmpty else {
            replyTargetUserID = nil
            replyTargetDisplayName = nil
            return
        }

        let existing = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !existing.isEmpty, targets.contains(where: { $0.userID == existing }) {
            // Keep existing selection; refresh display name if we can.
            replyTargetDisplayName = nil
            return
        }

        // Default: most recent commenter.
        let chosen = targets[0].userID
        replyTargetUserID = chosen
        replyTargetDisplayName = nil
    }

    private func displayNameForUserID(_ userIDLowercased: String) -> String {
        let key = userIDLowercased.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let acct = directoryAccounts[key] {
            let n = acct.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty { return n }
        }
        return "User"
    }


    private func composerPlaceholderText(ownerID: String?, viewerID: String?) -> String {
        let trimmedOwner = (ownerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedViewer = (viewerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isOwnerViewer = !trimmedOwner.isEmpty && trimmedOwner == trimmedViewer

        if isOwnerViewer {
            let recipientCount: Int = {
                guard let ownerID else { return 0 }
                return respondToCommentersRecipientIDs(ownerUserID: ownerID).count
            }()

            // Only show fan-out wording when fan-out is actually meaningful/available.
            if recipientCount > 1 && isRespondToCommentersMode {
                return "Respond to all commenters…"
            }

            let id = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = (replyTargetDisplayName ?? displayNameForUserID(id)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return "Reply to \(name)…" }

            // If there are no commenters to target yet, keep the placeholder generic/calm.
            if recipientCount == 0 { return "Add a comment…" }
            return "Reply…"
        }

        return "Add a comment…"
    }



    // MARK: - Mentions tokenization & helpers
    private struct MentionSpan: Identifiable {
        let id = UUID()
        let text: String
        let isMention: Bool
    }
    
    private func tokenizeMentions(_ s: String) -> [MentionSpan] {
        // Regex: (?<!\w)@[A-Za-z0-9_\.]+
        // Keep allocation-light: if no matches, return single non-mention span
        let pattern = "(?<!\\w)@[A-Za-z0-9_\\.]+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [MentionSpan(text: s, isMention: false)]
        }
        let ns = s as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: s, options: [], range: fullRange)
        if matches.isEmpty {
            return [MentionSpan(text: s, isMention: false)]
        }
        var spans: [MentionSpan] = []
        var cursor = 0
        for m in matches {
            let range = m.range
            if range.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                if !before.isEmpty { spans.append(MentionSpan(text: before, isMention: false)) }
            }
            let handle = ns.substring(with: range)
            spans.append(MentionSpan(text: handle, isMention: true))
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(from: cursor)
            if !tail.isEmpty { spans.append(MentionSpan(text: tail, isMention: false)) }
        }
        return spans
    }
    
    private func mentions(in s: String) -> [String] {
        tokenizeMentions(s).filter { $0.isMention }.map { $0.text }
    }
    
    private func accessibleLabel(for s: String) -> String {
        // Keep existing text as the accessible label
        return s
    }
    
    // MARK: - Header title (match feed title used in ContentView)
    private func headerTitleForSession() -> String {
        if postID != nil { return "Comments" }
        
        guard let sid = sessionID else { return "Comments" }
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Session> = Session.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
        guard let session = try? ctx.fetch(req).first else { return "Comments" }
        let title = (session.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Comments" : title
    }
    
    // MARK: - 8H-B identity helpers (viewer + owner)
    
    private func ownerUserIDForSession() -> String? {
        if let owner = connectedOwnerUserID, !owner.isEmpty { return owner }
        
        // Local-only path: derive owner ID from Core Data session.
        guard let sid = sessionID else { return nil }
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Session> = Session.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
        return (try? ctx.fetch(req).first?.ownerUserID)?.lowercased()
    }
    
    private func viewerUserID() -> String? {
        if let viewer = connectedViewerUserID, !viewer.isEmpty { return viewer }
        
        // Local-only path: use current user ID.
#if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override.trimmingCharacters(in: .whitespacesAndNewlines)
        }
#endif
        return PersistenceController.shared.currentUserID
    }
    
    // MARK: - Header subtitle (owner name • session date)
    private func headerSubtitleForSession() -> String? {
        // Connected mode: keep subtitle minimal (privacy-first).
        if postID != nil { return nil }
        
        guard let sid = sessionID else { return nil }
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<Session> = Session.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
        guard let session = try? ctx.fetch(req).first else { return nil }
        let date = session.timestamp ?? Date()
        return formatDate(date)
    }
    
    private func formatDate(_ date: Date) -> String {
        // CHANGE-ID: 20260214_115100_fix_formatDate
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: date)
    }
    
    
    // MARK: - Header likes count
    private func headerLikesCount() -> Int {
        // Use the stable session id directly
        if let sid = sessionID { return FeedInteractionStore.likeCount(sid) }
        return 0
    }
    
    @ViewBuilder
    private func mentionStyledText(_ s: String, onTap: @escaping (String) -> Void) -> some View {
        // Render inline mentions with accent text and a subtle rounded background for better contrast in dark mode
        let spans = tokenizeMentions(s)
        // Use a flow-like HStack; preserves reading order and line wrapping via Text concatenation fragments
        // We'll assemble using AttributedString-like pieces by combining Texts inside a single Text view where possible.
        // To keep background on mentions only, we compose via HStack with baseline alignment.
        // Note: This keeps accessibility label as the original string.
        let _ = spans // silence if unused in preview
        VStack(alignment: .leading, spacing: 0) {
            // Use a text-building approach that keeps wrapping, by interleaving Texts.
            // SwiftUI doesn't support background per-substring within a single Text without AttributedString styling,
            // so we approximate using a wrapping container with alignment guides.
            // For simplicity and reliability across iOS versions, we join into a multi-Text Group.
            Group {
                // Render as multiple Text views; SwiftUI will wrap them inline when placed in a Text container.
                // Since Text doesn't host children, we use a wrapping container with alignment to allow line wraps.
                // A simple approach: convert spans to a single Text by concatenation, but apply background only to mentions using overlay.
                spans.reduce(Text("")) { acc, span in
                    let base = Text(span.text)
                    if span.isMention {
                        let mentionText = base
                            .foregroundStyle(Theme.Colors.accent)
                            .fontWeight(.semibold)
                        // Add thin spaces around mention to create breathing room without breaking Text concatenation type
                        let padded = Text("\u{2009}") + mentionText + Text("\u{2009}")
                        return acc + padded
                    } else {
                        return acc + base.foregroundStyle(Color.primary.opacity(0.9))
                    }
                }
            }
            .font(Theme.Text.body)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(accessibleLabel(for: s))
    }
    
    // MARK: - Relative time formatting
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateFormat = "d MMM"
        return f
    }()


    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current; f.timeZone = .current
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    // MARK: - Calm date/time formatting (UI-only)
    static func calmDateLabel(from date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if (2...6).contains(days) { return "\(days) days ago" }
        if (7...29).contains(days) { return "\(max(1, days / 7)) weeks ago" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
        return sameYear ? dayMonthFormatter.string(from: date) : dayMonthYearFormatter.string(from: date)
    }

    private static let time24Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current; f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f
    }()
    static func calmTimeLabel(from date: Date) -> String { time24Formatter.string(from: date) }

    private static func authorDayKey(authorID: String, date: Date) -> String {
        "\(authorID)|\(Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970))"
    }

    private static func relativeTimestamp(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current

        // Variant A:
        // - Same day as now → time only (no "Today")
        // - Different day → "d MMM" + time
        if calendar.isDate(date, inSameDayAs: now) {
            return timeOnlyFormatter.string(from: date)
        } else {
            let d = dayMonthFormatter.string(from: date)
            let t = timeOnlyFormatter.string(from: date)
            return "\(d) \(t)"
        }
    }
    
    public var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headerTitleForSession())
                                .font(Theme.Text.sectionHeader)
                            if let sub = headerSubtitleForSession() {
                                Text(sub)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Spacing.m)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .alert(tappedMention ?? "", isPresented: Binding(get: { tappedMention != nil }, set: { if !$0 { tappedMention = nil } })) {
                    Button("OK", role: .cancel) { tappedMention = nil }
                } message: {
                    Text("Mention tapped. Future: open profile or start reply with \(tappedMention ?? "")")
                }
                .appBackground()
                .onAppear {
                    let ownerID = ownerUserIDForSession()
                    let viewerID = viewerUserID()
                    if let ownerID, let viewerID, ownerID == viewerID {
                        ensureDefaultReplyTargetIfNeeded(ownerUserID: ownerID)
                    }
                }
                .task {
                    if case .connectedPost(let pid, let ownerUserID, let viewerUserID, _) = mode {
                        await backendStore.refresh(postID: pid)
                        // Calm unread presence: opening comments clears unread state for THIS viewer (owner or commenter).
                        await UnreadCommentsStore.shared.markViewed(postID: pid)

                        // Owner default: if there are any commenters, default the composer to "Respond to all commenters".
                        await MainActor.run {
                            let ownerLower = ownerUserID.lowercased()
                            let viewerLower = viewerUserID.lowercased()
                            if ownerLower == viewerLower {
                                let commenterIDs = Set(backendStore.comments.map { $0.authorUserID.lowercased() })
                                    .subtracting([ownerLower])
                                isRespondToCommentersMode = !commenterIDs.isEmpty
                                ensureDefaultReplyTargetIfNeeded(ownerUserID: ownerUserID)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
        }
        .appBackground()
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            list.padding(.top, Theme.Spacing.m)
            composer
                .background(Theme.Colors.background(scheme))
        }
        .background(Theme.Colors.background(scheme))
    }
    
    private var list: AnyView {
        switch mode {
        case .localSession(let sid):
            let ownerID = ownerUserIDForSession()
            let viewerID = viewerUserID()
            let commentsRaw = store.visibleComments(for: sid, viewerUserID: viewerID, ownerUserID: ownerID)
            let sorted = commentsRaw.sorted { $0.timestamp < $1.timestamp }
            
            let isOwnerViewer: Bool = {
                guard let ownerID, let viewerID else { return false }
                return ownerID == viewerID
            }()
            
            let comments: [Comment] = {
                if isOwnerViewer, let ownerID {
                    return collapseOwnerFanOutDuplicates(sorted, ownerUserID: ownerID)
                } else {
                    return sorted
                }
            }()
            
                        let replyEligibleCommentIDs: Set<UUID> = {
                guard isOwnerViewer, let ownerID, let viewerID else { return [] }
                guard ownerID == viewerID else { return [] }
                return eligibleReplyCommentIDsLocal(comments, ownerUserID: ownerID)
            }()

            let authorDayCounts: [String: Int] = comments.reduce(into: [:]) { acc, c in
                let a = (store.authorUserID(for: c.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !a.isEmpty { acc[CommentsView.authorDayKey(authorID: a, date: c.timestamp), default: 0] += 1 }
            }

return AnyView(
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(comments.enumerated()), id: \.element.id) { idx, comment in
                    let authorID = (store.authorUserID(for: comment.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let prevAuthorID: String = {
                        guard idx > 0 else { return "" }
                        let prev = comments[idx - 1]
                        return (store.authorUserID(for: prev.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }()
                    let nextAuthorID: String = {
                        guard idx + 1 < comments.count else { return "" }
                        let next = comments[idx + 1]
                        return (store.authorUserID(for: next.id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }()
                    let isStartOfRun = authorID.isEmpty ? true : (prevAuthorID != authorID)
                    let isEndOfRun = authorID.isEmpty ? true : (nextAuthorID != authorID)
                    let prevTimestamp = idx > 0 ? comments[idx - 1].timestamp : nil
                    commentRowLocal(
                        comment: comment,
                        ownerID: ownerID,
                        viewerID: viewerID,
                        sessionID: sid,
                        isStartOfAuthorRun: isStartOfRun,
                        isEndOfAuthorRun: isEndOfRun,
                        prevTimestamp: prevTimestamp,
                        authorDayCounts: authorDayCounts,
                        replyEligibleCommentIDs: replyEligibleCommentIDs
                    )
                }
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in userHasManuallyScrolled = true })
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .onAppear {
                maybePerformInitialAutoScroll(proxy: proxy, contentCount: comments.count)
            }
            .onChange(of: comments.count) { newCount in
                maybePerformInitialAutoScroll(proxy: proxy, contentCount: newCount)
            }
            .task(id: directoryKey(for: comments.compactMap { store.authorUserID(for: $0.id) } + [ownerID ?? "", viewerID ?? ""])) {
                await hydrateDirectoryIfNeeded(userIDs: comments.compactMap { store.authorUserID(for: $0.id) } + [ownerID ?? "", viewerID ?? ""])
            }
            .onChange(of: scrollToBottomNonce) { _ in
                scheduleScrollToBottom(proxy)
            }
            .accessibilitySortPriority(1)
                }
            )
            
        case .connectedPost(let pid, let ownerUserID, let viewerUserID, _):
            let sorted = backendStore.comments.sorted(by: { $0.createdAt < $1.createdAt })
            let isOwnerViewer = (viewerUserID == ownerUserID)
            let rows: [BackendPostComment] = {
                if isOwnerViewer {
                    return collapseOwnerFanOutDuplicatesBackend(sorted, ownerUserID: ownerUserID)
                } else {
                    return sorted
                }
            }()
            
                        let replyEligibleCommentIDs: Set<UUID> = {
                guard isOwnerViewer else { return [] }
                return eligibleReplyCommentIDsBackend(rows, ownerUserID: ownerUserID)
            }()

            let authorDayCounts: [String: Int] = rows.reduce(into: [:]) { acc, r in
                let a = r.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !a.isEmpty { acc[CommentsView.authorDayKey(authorID: a, date: r.createdAt), default: 0] += 1 }
            }

return AnyView(
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    let authorID = row.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let prevAuthorID: String = {
                        guard idx > 0 else { return "" }
                        return rows[idx - 1].authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }()
                    let nextAuthorID: String = {
                        guard idx + 1 < rows.count else { return "" }
                        return rows[idx + 1].authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }()
                    let isStartOfRun = authorID.isEmpty ? true : (prevAuthorID != authorID)
                    let isEndOfRun = authorID.isEmpty ? true : (nextAuthorID != authorID)
                    let prevTimestamp = idx > 0 ? rows[idx - 1].createdAt : nil
                    commentRowBackend(
                        row: row,
                        postID: pid,
                        ownerUserID: ownerUserID,
                        viewerUserID: viewerUserID,
                        isStartOfAuthorRun: isStartOfRun,
                        isEndOfAuthorRun: isEndOfRun,
                        prevTimestamp: prevTimestamp,
                        authorDayCounts: authorDayCounts,
                        replyEligibleCommentIDs: replyEligibleCommentIDs
                    )
                }
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
                        }
                        .padding(.horizontal, Theme.Spacing.l)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in userHasManuallyScrolled = true })
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .onAppear {
                maybePerformInitialAutoScroll(proxy: proxy, contentCount: rows.count)
            }
            .onChange(of: rows.count) { newCount in
                maybePerformInitialAutoScroll(proxy: proxy, contentCount: newCount)
            }
            .task(id: directoryKey(for: rows.map { $0.authorUserID } + [ownerUserID, viewerUserID])) {
                await hydrateDirectoryIfNeeded(userIDs: rows.map { $0.authorUserID } + [ownerUserID, viewerUserID])
            }
            .onChange(of: scrollToBottomNonce) { _ in
                scheduleScrollToBottom(proxy)
            }
            .accessibilitySortPriority(1)
                }
            )
        }
    }
    
    
    
    // MARK: - Directory identity hydration (UI-only)

    private func normalizedUserID(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        return s
    }

    private func directoryKey(for userIDs: [String]) -> String {
        let norm = userIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(norm)).sorted().joined(separator: ",")
    }

    private func hydrateDirectoryIfNeeded(userIDs: [String]) async {
        let ids = Array(Set(userIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return }

        let result = await AccountDirectoryService.shared.resolveAccounts(userIDs: ids, forceRefresh: false)
        switch result {
        case .success(let map):
            // Merge into local state (fail-closed: keep existing on error).
            var merged = directoryAccounts
            for (k, v) in map {
                let nk = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !nk.isEmpty { merged[nk] = v }
            }
            directoryAccounts = merged
        case .failure:
            break
        }
    }

    private func directoryAccount(for userID: String?) -> DirectoryAccount? {
        guard let id = normalizedUserID(userID) else { return nil }
        return directoryAccounts[id]
    }

    private func safeDisplayName(_ s: String?) -> String {
        let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "User" : trimmed
    }

    private func safeLocation(_ s: String?) -> String {
        let trimmed = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed
    }

    // MARK: - Comment identity header (People row parity; no navigation; fail-closed)

    private struct CommentIdentityHeader: View {
        let authorUserID: String?
        let viewerUserID: String?
        let fallbackDisplayName: String
        let directoryAccount: DirectoryAccount?
        let timestamp: Date
        let showsReplyAction: Bool
        let onReply: (() -> Void)?

        @Environment(\.colorScheme) private var scheme

        @State private var remoteAvatarImage: UIImage?

        private func initials(from name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "U" }
            let words = trimmed
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            if words.isEmpty { return "U" }
            if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
            let first = words.first?.first.map { String($0).uppercased() } ?? ""
            let last = words.last?.first.map { String($0).uppercased() } ?? ""
            let combo = first + last
            return combo.isEmpty ? "U" : combo
        }

        private var normalizedAuthorID: String? {
            let s = (authorUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return s.isEmpty ? nil : s
        }

        private var normalizedViewerID: String? {
            let s = (viewerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return s.isEmpty ? nil : s
        }

        private var isViewerAuthor: Bool {
            guard let a = normalizedAuthorID, let v = normalizedViewerID else { return false }
            return a == v
        }

        private var resolvedDisplayName: String {
            let nameFromDirectory = directoryAccount?.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = nameFromDirectory, !n.isEmpty { return n }
            let fallback = fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallback.isEmpty ? "User" : fallback
        }

        private var primaryLabel: String {
            // Spec: if author == viewer, label as "You" but still show identity if available.
            return isViewerAuthor ? "You" : resolvedDisplayName
        }

        private var secondaryLabel: String {
            // Combine optional identity + location on one calm line.
            let loc = (directoryAccount?.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var parts: [String] = []
            if isViewerAuthor {
                let n = resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty, n.lowercased() != "you" { parts.append(n) }
            }
            if !loc.isEmpty { parts.append(loc) }
            return parts.joined(separator: " • ")
        }

        private var avatarKey: String? {
            let k = (directoryAccount?.avatarKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return k.isEmpty ? nil : k
        }

        private var avatarFallbackNameForInitials: String {
            if isViewerAuthor {
                let n = resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return n.isEmpty ? "User" : n
            }
            let n = primaryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "User" : n
        }

        @ViewBuilder
        private var avatar: some View {
#if canImport(UIKit)
            if let id = normalizedAuthorID, let ui = ProfileStore.avatarImage(for: id) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
            } else if let remote = remoteAvatarImage {
                Image(uiImage: remote)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
            } else {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(initials(from: avatarFallbackNameForInitials))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    )
                    .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
                    .task(id: avatarKey ?? "") {
                        guard let key = avatarKey else {
                            if remoteAvatarImage != nil { remoteAvatarImage = nil }
                            return
                        }
                        let img = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: key)
                        if Task.isCancelled { return }
                        remoteAvatarImage = img
                    }
            }
#else
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Text("U")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                )
                .overlay(Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5))
#endif
        }

        var body: some View {
            HStack(spacing: Theme.Spacing.m) {
                avatar

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(primaryLabel)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary)

                        Spacer(minLength: 0)

                        HStack(spacing: 6) {
                            Text(CommentsView.calmDateLabel(from: timestamp))
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.58))

                            if showsReplyAction {
                                Button(action: { onReply?() }) {
                                    Text("Reply")
                                        .font(Theme.Text.meta)
                                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Reply to commenter")
                            }
                        }
                    }
                }
            }
        }
    }



    private struct CommenterPickerRow: View {
        @Environment(\.colorScheme) private var scheme
        let userID: String
        let displayName: String
        let directoryAccount: DirectoryAccount?

        private var avatarKey: String? {
            let k = (directoryAccount?.avatarKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return k.isEmpty ? nil : k
        }

        private var fallbackName: String {
            let n = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "User" : n
        }

        var body: some View {
            HStack(spacing: Theme.Spacing.m) {
#if canImport(UIKit)
                let id = userID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let ui = ProfileStore.avatarImage(for: id) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
                } else {
                    initialsAvatar(fallbackName)
                }
#else
                initialsAvatar(fallbackName)
#endif

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(displayName.isEmpty ? "User" : displayName)
                        .font(Theme.Text.body)
                        .foregroundStyle(Color.primary)

                    if let loc = directoryAccount?.location, !loc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(loc)
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Spacing.xs)
        }

        @ViewBuilder
        private func initialsAvatar(_ name: String) -> some View {
            let initials = initialsForName(name)
            ZStack {
                Circle()
                    .fill(Theme.Colors.stroke(scheme).opacity(0.25))
                    .frame(width: 36, height: 36)
                Text(initials)
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
            }
            .overlay(Circle().stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
        }

        private func initialsForName(_ n: String) -> String {
            let parts = n
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .map(String.init)
            let first = parts.first?.first.map(String.init) ?? "U"
            let last = parts.dropFirst().first?.first.map(String.init) ?? ""
            let combo = (first + last).uppercased()
            return combo.isEmpty ? "U" : combo
        }
    }

struct CommentContinuationMetaRow: View {
        let timestamp: Date
        let showsReplyAction: Bool
        let onReply: (() -> Void)?

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(spacing: 6) {
                Spacer(minLength: 0)

                Text(CommentsView.relativeTimestamp(from: timestamp))
                    .font(Theme.Text.meta)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))

                if showsReplyAction, let onReply {
                    Button(action: onReply) {
                        Text("Reply")
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }


    private func commentRowLocal(comment: Comment, ownerID: String?, viewerID: String?, sessionID: UUID, isStartOfAuthorRun: Bool, isEndOfAuthorRun: Bool, prevTimestamp: Date?, authorDayCounts: [String: Int], replyEligibleCommentIDs: Set<UUID>) -> some View {
        let authorID = store.authorUserID(for: comment.id)
        let isViewerOwner: Bool = {
            let o = (ownerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let v = (viewerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !o.isEmpty, !v.isEmpty else { return false }
            return o == v
        }()
        let isAuthorOwner: Bool = {
            let a = (authorID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let o = (ownerID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !a.isEmpty, !o.isEmpty else { return false }
            return a == o
        }()

        // Fallback name (never shows raw IDs).
        let fallbackName: String = {
            if comment.authorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "User"
            }
            // Local store may still label viewer as "You".
            return comment.authorName
        }()

        let dir = directoryAccount(for: authorID)

        let showsReplyAction: Bool = {
            guard isViewerOwner else { return false }
            guard let authorID else { return false }
            let a = authorID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !a.isEmpty else { return false }
            guard !isAuthorOwner else { return false }
            // UI-only: only show reply for the most recent *unanswered* commenter message (per commenter).
            return replyEligibleCommentIDs.contains(comment.id)
        }()

        let onReply: (() -> Void)? = showsReplyAction ? {
            guard let authorID, !authorID.isEmpty else { return }
            isRespondToCommentersMode = false
            replyTargetUserID = authorID.lowercased()

            // UI-only: target label should be calm and never leak IDs.
            let name = (dir?.displayName ?? fallbackName).trimmingCharacters(in: .whitespacesAndNewlines)
            replyTargetDisplayName = name.isEmpty || name.lowercased() == "you" ? "Commenter" : name
        } : nil

        return VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            if isStartOfAuthorRun {
                CommentIdentityHeader(
                    authorUserID: authorID,
                    viewerUserID: viewerID,
                    fallbackDisplayName: fallbackName,
                    directoryAccount: dir,
                    timestamp: comment.timestamp,
                    showsReplyAction: showsReplyAction,
                    onReply: onReply
                )

                Text(comment.text)
                    .padding(.top, 2)
                    .font(.body)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // No ID header: move timestamp to the same line as the comment text (Variant A format).
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(comment.text)
                        .font(.body)
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(CommentsView.relativeTimestamp(from: comment.timestamp))
                            .font(Theme.Text.meta)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                            .lineLimit(1)

                        if showsReplyAction {
                            Button(action: { onReply?() }) {
                                Text("Reply")
                                    .font(Theme.Text.meta)
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .layoutPriority(0)
                }
                .padding(.top, 2)
            }

            let _handles = mentions(in: comment.text)
            if !_handles.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(_handles, id: \.self) { handle in
                        Button(action: { tappedMention = handle }) {
                            Text(handle)
                                .font(.footnote)
                                .foregroundStyle(Color.primary).fontWeight(.bold)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Theme.Colors.surface(scheme).opacity(0.35), in: Capsule())
                        }
                        .accessibilityLabel("Mention \(handle)")
                    }
                    Spacer(minLength: 0)
                }
                .accessibilitySortPriority(1)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Comment")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if store.canDelete(commentID: comment.id, viewerUserID: viewerID, ownerUserID: ownerID) {
                Button {
                    store.delete(commentID: comment.id, in: sessionID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.Colors.secondaryText.opacity(0.28))
                .accessibilityLabel("Delete comment")
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.m, bottom: 0, trailing: Theme.Spacing.m))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }


private func commentRowBackend(row: BackendPostComment, postID: UUID, ownerUserID: String, viewerUserID: String, isStartOfAuthorRun: Bool, isEndOfAuthorRun: Bool, prevTimestamp: Date?, authorDayCounts: [String: Int], replyEligibleCommentIDs: Set<UUID>) -> some View {
        let authorID = row.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isViewerOwner = (viewerUserID.lowercased() == ownerUserID.lowercased())
        let isAuthorOwner = (!authorID.isEmpty && authorID == ownerUserID.lowercased())

        let dir = directoryAccount(for: authorID)
        let fallbackName = backendDisplayName(for: row, ownerUserID: ownerUserID, viewerUserID: viewerUserID)

        let showsReplyAction: Bool = {
            guard isViewerOwner else { return false }
            guard !authorID.isEmpty else { return false }
            guard !isAuthorOwner else { return false }
            // UI-only: only show reply for the most recent *unanswered* commenter message (per commenter).
            return replyEligibleCommentIDs.contains(row.id)
        }()

        let onReply: (() -> Void)? = showsReplyAction ? {
            guard !authorID.isEmpty else { return }
            isRespondToCommentersMode = false
            replyTargetUserID = authorID
            let name = (dir?.displayName ?? fallbackName).trimmingCharacters(in: .whitespacesAndNewlines)
            replyTargetDisplayName = name.isEmpty || name.lowercased() == "you" ? "Commenter" : name
        } : nil

        return VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            if isStartOfAuthorRun {
                CommentIdentityHeader(
                    authorUserID: authorID,
                    viewerUserID: viewerUserID,
                    fallbackDisplayName: fallbackName,
                    directoryAccount: dir,
                    timestamp: row.createdAt,
                    showsReplyAction: showsReplyAction,
                    onReply: onReply
                )

                Text(row.body)
                    .padding(.top, 2)
                    .font(.body)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(row.body)
                        .font(.body)
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    let showInlineTime = {
                        guard !authorID.isEmpty, let prevTimestamp else { return false }
                        let cal = Calendar.current
                        guard cal.isDate(prevTimestamp, inSameDayAs: row.createdAt) else { return false }
                        if abs(row.createdAt.timeIntervalSince(prevTimestamp)) < 60 { return false }
                        let key = CommentsView.authorDayKey(authorID: authorID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), date: row.createdAt)
                        return (authorDayCounts[key] ?? 0) >= 2
                    }()
                    HStack(spacing: 6) {
                        if showInlineTime {
                            Text(CommentsView.calmTimeLabel(from: row.createdAt))
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                                .lineLimit(1)
                        }
                        if showsReplyAction {
                            Button(action: { onReply?() }) {
                                Text("Reply")
                                    .font(Theme.Text.meta)
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .layoutPriority(0)
                }
                .padding(.top, 2)
            }

            let _handles = mentions(in: row.body)
            if !_handles.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(_handles, id: \.self) { handle in
                        Button(action: { tappedMention = handle }) {
                            Text(handle)
                                .font(.footnote)
                                .foregroundStyle(Color.primary).fontWeight(.bold)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                                .background(Theme.Colors.surface(scheme).opacity(0.35), in: Capsule())
                        }
                        .accessibilityLabel("Mention \(handle)")
                    }
                    Spacer(minLength: 0)
                }
                .accessibilitySortPriority(1)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Comment")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Delete allowed if viewer is owner or author (enforced by RLS; fail-closed UI).
            let canDelete = (!viewerUserID.isEmpty && (viewerUserID == ownerUserID || viewerUserID == authorID))
            if canDelete {
                Button {
                    Task {
                        _ = await backendStore.deleteComment(commentID: row.id, postID: postID)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.Colors.secondaryText.opacity(0.28))
                .accessibilityLabel("Delete comment")
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.m, bottom: 0, trailing: Theme.Spacing.m))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }



private func backendDisplayName(for row: BackendPostComment, ownerUserID: String, viewerUserID: String) -> String {
        let author = row.authorUserID.lowercased()
        if author == viewerUserID.lowercased() { return "You" }
        if author == ownerUserID.lowercased() {
            let n = (connectedOwnerDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "Owner" : n
        }
        return "Commenter"
    }
    
    private func collapseOwnerFanOutDuplicatesBackend(_ comments: [BackendPostComment], ownerUserID: String) -> [BackendPostComment] {
        var result: [BackendPostComment] = []
        var lastKept: BackendPostComment? = nil
        
        for c in comments {
            let authorID = c.authorUserID.lowercased()
            if authorID == ownerUserID.lowercased(), let last = lastKept {
                let lastAuthorID = last.authorUserID.lowercased()
                if lastAuthorID == ownerUserID.lowercased(),
                   last.body == c.body,
                   abs(last.createdAt.timeIntervalSince(c.createdAt)) < 1 {
                    continue
                }
            }
            
            result.append(c)
            lastKept = c
        }
        
        return result
    }


    // MARK: - Reply eligibility (UI-only)
    // Show Reply only for the most recent *unanswered* commenter message (per commenter).
    // "Unanswered" means: latest commenter → owner message timestamp is later than latest owner → commenter reply.
    private func eligibleReplyCommentIDsLocal(_ comments: [Comment], ownerUserID: String) -> Set<UUID> {
        let owner = ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !owner.isEmpty else { return [] }

        // We do NOT have recipientUserID on local Comment, so we infer "answered" using
        // list order: a commenter is considered answered iff the next message after their
        // most recent comment is authored by the owner.
        //
        // This preserves your intended UX without adding any schema / store fields.

        // 1) Find the last comment index per non-owner author.
        var lastIndexByAuthor: [String: Int] = [:]
        for (idx, c) in comments.enumerated() {
            let author = (store.authorUserID(for: c.id) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !author.isEmpty else { continue }
            guard author != owner else { continue } // only commenters
            lastIndexByAuthor[author] = idx
        }

        // 2) For each commenter, eligible reply = most recent comment AND not answered.
        var eligible: Set<UUID> = []

        for (author, lastIdx) in lastIndexByAuthor {
            let nextIdx = lastIdx + 1

            // If there's a next message and it's from the owner, we consider this commenter answered.
            var answered = false
            if nextIdx < comments.count {
                let nextAuthor = (store.authorUserID(for: comments[nextIdx].id) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                answered = (nextAuthor == owner)
            }

            if !answered {
                eligible.insert(comments[lastIdx].id)
            }
        }

        return eligible
    }

    private func eligibleReplyCommentIDsBackend(_ rows: [BackendPostComment], ownerUserID: String) -> Set<UUID> {
        let owner = ownerUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !owner.isEmpty else { return [] }

        var latestIncoming: [String: (id: UUID, ts: Date)] = [:] // commenter -> latest comment to owner
        var latestOwnerReply: [String: Date] = [:] // commenter -> latest owner reply to commenter

        for r in rows {
            let author = r.authorUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let recipient = r.recipientUserID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !author.isEmpty else { continue }

            if author == owner {
                guard !recipient.isEmpty, recipient != owner else { continue }
                let ts = r.createdAt
                if let existing = latestOwnerReply[recipient] {
                    if ts > existing { latestOwnerReply[recipient] = ts }
                } else {
                    latestOwnerReply[recipient] = ts
                }
            } else {
                guard recipient == owner else { continue }
                let ts = r.createdAt
                if let existing = latestIncoming[author] {
                    if ts > existing.ts { latestIncoming[author] = (r.id, ts) }
                } else {
                    latestIncoming[author] = (r.id, ts)
                }
            }
        }

        var eligible: Set<UUID> = []
        for (commenter, incoming) in latestIncoming {
            let lastReply = latestOwnerReply[commenter] ?? .distantPast
            if incoming.ts > lastReply {
                eligible.insert(incoming.id)
            }
        }
        return eligible
    }
    private var composer: some View {
        VStack(spacing: 0) {
            let ownerID = ownerUserIDForSession()
            let viewerID = viewerUserID()
            let isOwner = (ownerID != nil && viewerID != nil && ownerID == viewerID)
            
            if isOwner, let ownerID {
                let recipients = respondToCommentersRecipientIDs(ownerUserID: ownerID)
                let recipientCount = recipients.count
                

                // Keep UI calm: if only one commenter remains, fan-out is not a meaningful state.
                // Ensure we exit fan-out mode if the recipient set collapses.
                Color.clear
                    .frame(width: 0, height: 0)
                    .onChange(of: recipientCount) { _, newValue in
                        if newValue <= 1 {
                            isRespondToCommentersMode = false
                        }
                    }
                // Owner-only 8H-D control: respond to all commenters (fan-out private replies)
                if recipientCount > 1 {
                    HStack(spacing: Theme.Spacing.s) {
                        Button {
                            // Enter/exit fan-out mode (fan-out remains multiple independent private replies).
                            if isRespondToCommentersMode {
                                isRespondToCommentersMode = false
                            } else {
                                isRespondToCommentersMode = true
                            }
                        } label: {
                            Text("Respond to all commenters")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Respond to all commenters")
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, Theme.Spacing.s)

                    if isRespondToCommentersMode && recipientCount > 1 {
                        HStack(spacing: Theme.Spacing.s) {
                            Text("Sending privately to \(recipientCount) commenter\(recipientCount == 1 ? "" : "s")")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            
                            Spacer(minLength: 0)
                            
                            Button {
                                isRespondToCommentersMode = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel respond to commenters")
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .fill(Theme.Colors.surface(scheme).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .stroke(Theme.Colors.cardStroke(scheme).opacity(0.6), lineWidth: 1)
                        )
                        .padding(.bottom, Theme.Spacing.s)
                    }
                }
                
                
            }

            // Owner-only: targeted reply selector (replaces unanswered-only gating; no row-level reply buttons).
            if isOwner, let ownerID, !isRespondToCommentersMode {
                let targets = commenterTargetsForPicker(ownerUserID: ownerID)
                if !targets.isEmpty {
                    let selectedID = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let selectedName = (replyTargetDisplayName ?? displayNameForUserID(selectedID)).trimmingCharacters(in: .whitespacesAndNewlines)

                    Button {
                        if targets.count > 1 {
                            isTargetPickerPresented = true
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.s) {
                            Text("Reply to: \(selectedName.isEmpty ? "User" : selectedName)")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))

                            if targets.count > 1 {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, Theme.Spacing.s)
                }
            }


            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField(composerPlaceholderText(ownerID: ownerID, viewerID: viewerID), text: $draft, axis: .vertical)
                    .focused($composerFocused)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Add a comment")
                    .onSubmit(send)
                
                Button(action: send) {
                    let ownerID = ownerUserIDForSession()
                    let viewerID = viewerUserID()
                    let isOwner = (ownerID != nil && viewerID != nil && ownerID == viewerID)
                    
                    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasTarget = !(replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let recipientCount = (isOwner && ownerID != nil) ? respondToCommentersRecipientIDs(ownerUserID: ownerID!).count : 0
                    let hasRecipients = recipientCount > 0
                    let isEnabled = isOwner ? (hasText && (isRespondToCommentersMode ? hasRecipients : hasTarget)) : hasText
                    
                    if isEnabled {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Theme.Colors.accent.opacity((scheme == .dark) ? 0.22 : 0.18))
                                .frame(width: 32, height: 32)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(Color.primary).fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                .disabled({
                    let ownerID = ownerUserIDForSession()
                    let viewerID = viewerUserID()
                    let isOwner = (ownerID != nil && viewerID != nil && ownerID == viewerID)
                    
                    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let hasTarget = !(replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let recipientCount = (isOwner && ownerID != nil) ? respondToCommentersRecipientIDs(ownerUserID: ownerID!).count : 0
                    let hasRecipients = recipientCount > 0
                    return isOwner ? !(hasText && (isRespondToCommentersMode ? hasRecipients : hasTarget)) : !hasText
                }())
                .accessibilityLabel("Send comment")
            }
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            let ownerID = ownerUserIDForSession() ?? ""
            let targets = commenterTargetsForPicker(ownerUserID: ownerID)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        isTargetPickerPresented = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                            .frame(width: 44, height: 44, alignment: .center)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Text("Reply to")
                        .font(Theme.Text.sectionHeader)
                        .kerning(0.2)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))

                    Spacer(minLength: 0)

                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.s)

                List {
                    ForEach(targets) { t in
                        Button {
                            replyTargetUserID = t.userID
                            replyTargetDisplayName = nil
                            isTargetPickerPresented = false
                        } label: {
                            CommenterPickerRow(
                                userID: t.userID,
                                displayName: displayNameForUserID(t.userID),
                                directoryAccount: directoryAccounts[t.userID]
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m, bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .appBackground()
        }

        .cardSurface(padding: Theme.Spacing.m)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilitySortPriority(0) // After list
    }
    
    
    
    // 8H-D polish: collapse owner fan-out duplicates for display only (owner view).
    // Underlying comments remain separate per-recipient for privacy; we only dedupe rendering for the owner.
    private func collapseOwnerFanOutDuplicates(_ comments: [Comment], ownerUserID: String) -> [Comment] {
        var result: [Comment] = []
        var lastKept: Comment? = nil
        
        for c in comments {
            // Only consider owner-authored comments for collapse.
            let authorID = store.authorUserID(for: c.id)
            if authorID == ownerUserID, let last = lastKept {
                let lastAuthorID = store.authorUserID(for: last.id)
                if lastAuthorID == ownerUserID,
                   last.text == c.text,
                   abs(last.timestamp.timeIntervalSince(c.timestamp)) < 1 {
                    // Likely a fan-out duplicate: same owner text created in the same second → skip rendering.
                    continue
                }
            }
            
            result.append(c)
            lastKept = c
        }
        return result
    }
    
    private func handleSuccessfulSend() {
        composerFocused = false
        scrollToBottomNonce &+= 1
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let ownerID = ownerUserIDForSession()
        let viewerID = viewerUserID()
        guard let ownerID, let viewerID else { return }
        
        switch mode {
        case .localSession(let sid):
            if viewerID == ownerID {
                if isRespondToCommentersMode {
                    let recipients = respondToCommentersRecipientIDs(ownerUserID: ownerID)
                    guard !recipients.isEmpty else { return }
                    
                    for rid in recipients {
                        store.add(
                            sessionID: sid,
                            authorUserID: viewerID,
                            authorName: placeholderAuthor,
                            text: trimmed,
                            recipientUserID: rid
                        )
                    }
                    
                    draft = ""
                                isRespondToCommentersMode = false
                    CommentPresenceStore.shared.set(postID: sid, hasComments: true)
                                handleSuccessfulSend()
                } else {
                    let target = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !target.isEmpty else { return }
                    
                    store.add(
                        sessionID: sid,
                        authorUserID: viewerID,
                        authorName: placeholderAuthor,
                        text: trimmed,
                        recipientUserID: target
                    )
                    
                    draft = ""
                    CommentPresenceStore.shared.set(postID: sid, hasComments: true)
                                handleSuccessfulSend()
                }
            } else {
                store.add(sessionID: sid, authorUserID: viewerID, authorName: placeholderAuthor, text: trimmed, recipientUserID: ownerID)
                draft = ""
                CommentPresenceStore.shared.set(postID: sid, hasComments: true)
                                handleSuccessfulSend()
            }
            
        case .connectedPost(let pid, _, _, _):
            if viewerID == ownerID {
                if isRespondToCommentersMode {
                    Task {
                        let result = await backendStore.respondToCommenters(postID: pid, body: trimmed)
                        switch result {
                        case .success:
                            await MainActor.run {
                                draft = ""
                                isRespondToCommentersMode = false
                                CommentPresenceStore.shared.set(postID: pid, hasComments: true)
                                handleSuccessfulSend()
                            }
                        case .failure:
                            break
                        }
                    }
                } else {
                    let target = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !target.isEmpty else { return }
                    Task {
                        let result = await backendStore.replyToCommenter(postID: pid, recipientUserID: target, body: trimmed)
                        switch result {
                        case .success:
                            await MainActor.run {
                                draft = ""
                                CommentPresenceStore.shared.set(postID: pid, hasComments: true)
                                handleSuccessfulSend()
                            }
                        case .failure:
                            break
                        }
                    }
                }
            } else {
                Task {
                    let result = await backendStore.addComment(postID: pid, body: trimmed)
                    switch result {
                    case .success:
                        await MainActor.run {
                            draft = ""
                            CommentPresenceStore.shared.set(postID: pid, hasComments: true)
                            handleSuccessfulSend()
                        }
                    case .failure:
                        break
                    }
                }
            }
        }
    }
    
    #Preview("Comments") {
        CommentsView(sessionID: UUID())
    }
}
