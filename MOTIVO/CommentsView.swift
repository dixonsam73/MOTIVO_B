// CHANGE-ID: 20260214_153800_8H_CommentsOwnerSendDefault
// SCOPE: Enable owner composer send in connected comments by defaulting to Respond-to-commenters when commenters exist; no identity wiring.

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
    @State private var tappedMention: String? = nil
    
    @State private var replyTargetUserID: String? = nil
    @State private var replyTargetDisplayName: String? = nil
    
    @State private var isRespondToCommentersMode: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var scheme
    
    private let mode: CommentsViewMode
    private let placeholderAuthor: String
    
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
    private func relativeTimestamp(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let tzAwareNow = now
        let tzAwareDate = date
        
        // Today / Yesterday using calendar semantics (DST-safe)
        if calendar.isDateInToday(tzAwareDate) {
            let tf = DateFormatter()
            tf.locale = Locale.autoupdatingCurrent
            tf.timeZone = TimeZone.autoupdatingCurrent
            tf.dateFormat = "HH:mm"
            return "Today at \(tf.string(from: tzAwareDate))"
        }
        if calendar.isDateInYesterday(tzAwareDate) {
            return "Yesterday"
        }
        
        // Compare day boundaries to avoid 24h-delta pitfalls (DST/clock changes)
        let startOfNow = calendar.startOfDay(for: tzAwareNow)
        let startOfDate = calendar.startOfDay(for: tzAwareDate)
        guard let dayDiff = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day else {
            let df = DateFormatter()
            df.locale = Locale.autoupdatingCurrent
            df.timeZone = TimeZone.autoupdatingCurrent
            df.dateFormat = "d MMM yyyy"
            return df.string(from: tzAwareDate)
        }
        
        if dayDiff < 7 {
            return "\(dayDiff) days ago"
        }
        if dayDiff < 30 {
            let weeks = max(1, dayDiff / 7)
            return weeks == 1 ? "A week ago" : "\(weeks) weeks ago"
        }
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = TimeZone.autoupdatingCurrent
        df.dateFormat = "d MMM yyyy"
        return df.string(from: tzAwareDate)
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
                    .padding(.horizontal, Theme.Spacing.m)
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
                .task {
                    if case .connectedPost(let pid, let ownerUserID, let viewerUserID, _) = mode {
                        await backendStore.refresh(postID: pid)
                        // Owner default: if there are any commenters, default the composer to "Respond to commenters".
                        await MainActor.run {
                            let ownerLower = ownerUserID.lowercased()
                            let viewerLower = viewerUserID.lowercased()
                            if ownerLower == viewerLower {
                                let commenterIDs = Set(backendStore.comments.map { $0.authorUserID.lowercased() })
                                    .subtracting([ownerLower])
                                isRespondToCommentersMode = !commenterIDs.isEmpty
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
            
            return AnyView(
                List {
                ForEach(comments) { comment in
                    commentRowLocal(comment: comment, ownerID: ownerID, viewerID: viewerID, sessionID: sid)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.m)
            .accessibilitySortPriority(1)
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
            
            return AnyView(
                List {
                ForEach(rows) { row in
                    commentRowBackend(row: row, postID: pid, ownerUserID: ownerUserID, viewerUserID: viewerUserID)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1)
            )
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.m)
            .accessibilitySortPriority(1)
            )
        }
    }
    
    
    private func commentRowLocal(comment: Comment, ownerID: String?, viewerID: String?, sessionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            
            HStack(alignment: .center, spacing: 8) {
                // Avatar (32pt circle) — try to use current user's avatar when author is "You"; else show initials
                Group {
#if canImport(UIKit)
                    if comment.authorName == "You", let ui = ProfileStore.avatarImage(for: (try? PersistenceController.shared.currentUserID) ?? nil) {
                        Image(uiImage: ui).resizable().scaledToFill()
                    } else {
                        let initials: String = {
                            let name = comment.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let parts = name.split(separator: " ")
                            if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
                            let first = parts.first?.first.map { String($0).uppercased() } ?? "U"
                            let last = parts.last?.first.map { String($0).uppercased() } ?? ""
                            return (first + last).isEmpty ? "U" : (first + last)
                        }()
                        ZStack {
                            Circle().fill(Color.gray.opacity(0.2))
                            Text(initials)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
#else
                    ZStack {
                        Circle().fill(Color.gray.opacity(0.2))
                        Text("U").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    }
#endif
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
                
                // Name and inline timestamp on one line
                HStack(spacing: 6) {
                    let displayName: String = {
                        if comment.authorName == "You" {
#if canImport(CoreData)
                            let ctx = PersistenceController.shared.container.viewContext
                            let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                            req.fetchLimit = 1
                            if let profile = try? ctx.fetch(req).first, let n = profile.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                return n
                            }
#endif
                            return "You"
                        } else {
                            return comment.authorName
                        }
                    }()
                    Text(displayName)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Color.primary.opacity(0.9))
                    Text("•")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(relativeTimestamp(from: comment.timestamp))
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                    
                    let authorID = store.authorUserID(for: comment.id)
                    let ownerIDForUI = ownerID ?? ""
                    let viewerIDForUI = viewerID ?? ""
                    let isViewerOwner = (!ownerIDForUI.isEmpty && ownerIDForUI == viewerIDForUI)
                    let isAuthorOwner = (authorID == ownerIDForUI)
                    
                    if isViewerOwner, let authorID, !authorID.isEmpty, !isAuthorOwner {
                        Button {
                            isRespondToCommentersMode = false
                            replyTargetUserID = authorID
                            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            replyTargetDisplayName = (name == "You") ? "Commenter" : name
                        } label: {
                            Text("· Reply")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reply to commenter")
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            Text(comment.text)
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            
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
    
    private func commentRowBackend(row: BackendPostComment, postID: UUID, ownerUserID: String, viewerUserID: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            
            HStack(alignment: .center, spacing: 8) {
                // Avatar placeholder (32pt circle). Identity surfaces are minimal in v1.
                let initials: String = {
                    let name = backendDisplayName(for: row, ownerUserID: ownerUserID, viewerUserID: viewerUserID)
                    let parts = name.split(separator: " ")
                    if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
                    let first = parts.first?.first.map { String($0).uppercased() } ?? "U"
                    let last = parts.last?.first.map { String($0).uppercased() } ?? ""
                    return (first + last).isEmpty ? "U" : (first + last)
                }()
                ZStack {
                    Circle().fill(Color.gray.opacity(0.2))
                    Text(initials)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.Colors.cardStroke(scheme), lineWidth: 1))
                
                HStack(spacing: 6) {
                    let displayName = backendDisplayName(for: row, ownerUserID: ownerUserID, viewerUserID: viewerUserID)
                    Text(displayName)
                        .font(Theme.Text.meta)
                        .foregroundStyle(Color.primary.opacity(0.9))
                    Text("•")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(relativeTimestamp(from: row.createdAt))
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                    
                    let isViewerOwner = (viewerUserID == ownerUserID)
                    let isAuthorOwner = (row.authorUserID.lowercased() == ownerUserID.lowercased())
                    
                    if isViewerOwner, !row.authorUserID.isEmpty, !isAuthorOwner {
                        Button {
                            isRespondToCommentersMode = false
                            replyTargetUserID = row.authorUserID.lowercased()
                            replyTargetDisplayName = "Commenter"
                        } label: {
                            Text("· Reply")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reply to commenter")
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            Text(row.body)
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            
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
            let canDelete = (!viewerUserID.isEmpty && (viewerUserID == ownerUserID || viewerUserID == row.authorUserID.lowercased()))
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
    private var composer: some View {
        VStack(spacing: 0) {
            let ownerID = ownerUserIDForSession()
            let viewerID = viewerUserID()
            let isOwner = (ownerID != nil && viewerID != nil && ownerID == viewerID)
            
            if isOwner, let ownerID {
                let recipients = respondToCommentersRecipientIDs(ownerUserID: ownerID)
                let recipientCount = recipients.count
                
                // Owner-only 8H-D control: respond to all commenters (fan-out private replies)
                if recipientCount > 0 {
                    HStack(spacing: Theme.Spacing.s) {
                        Button {
                            // Enter/exit fan-out mode. Entering clears single-target reply.
                            if isRespondToCommentersMode {
                                isRespondToCommentersMode = false
                            } else {
                                clearReplyTarget()
                                isRespondToCommentersMode = true
                            }
                        } label: {
                            Text("Respond to commenters")
                                .font(Theme.Text.meta)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Respond to commenters")
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, Theme.Spacing.s)
                    
                    if isRespondToCommentersMode {
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
            // 8H-C single-target reply banner (suppressed while in fan-out mode)
            if !isRespondToCommentersMode, isOwner, let targetID = replyTargetUserID, !targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Replying to \(replyTargetDisplayName ?? "commenter")")
                        .font(Theme.Text.meta)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    
                    Spacer(minLength: 0)
                    
                    Button {
                        clearReplyTarget()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear reply target")
                }
                .padding(.bottom, Theme.Spacing.s)
            }
            
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
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
                    clearReplyTarget()
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
                    clearReplyTarget()
                }
            } else {
                store.add(sessionID: sid, authorUserID: viewerID, authorName: placeholderAuthor, text: trimmed, recipientUserID: ownerID)
                draft = ""
            }
            
        case .connectedPost(let pid, _, _, _):
            if viewerID == ownerID {
                if isRespondToCommentersMode {
                    Task {
                        _ = await backendStore.respondToCommenters(postID: pid, body: trimmed)
                        draft = ""
                        isRespondToCommentersMode = false
                        clearReplyTarget()
                    }
                } else {
                    let target = (replyTargetUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !target.isEmpty else { return }
                    Task {
                        _ = await backendStore.replyToCommenter(postID: pid, recipientUserID: target, body: trimmed)
                        draft = ""
                        clearReplyTarget()
                    }
                }
            } else {
                Task {
                    _ = await backendStore.addComment(postID: pid, body: trimmed)
                    draft = ""
                }
            }
        }
    }
    
    #Preview("Comments") {
        CommentsView(sessionID: UUID())
    }
}
