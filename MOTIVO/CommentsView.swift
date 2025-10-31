// CHANGE-ID: v710H-CommentsPolish-20251029-0001
// SCOPE: CommentsView visual polish (wrappers only) — align with Theme.swift
import SwiftUI
import CoreData

public struct CommentsView: View {
    @ObservedObject private var store = CommentsStore.shared
    @State private var draft: String = ""
    @State private var tappedMention: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    private let sessionID: UUID
    private let placeholderAuthor: String

    public init(sessionID: UUID, placeholderAuthor: String = "You") {
        self.sessionID = sessionID
        self.placeholderAuthor = placeholderAuthor
    }

    // MARK: - Mentions tokenization & helpers
    private struct MentionSpan: Identifiable {
        let id = UUID()
        let text: String
        let isMention: Bool
    }

    private func tokenizeMentions(_ s: String) -> [MentionSpan] {
        // Regex: (?<!\\w)@[A-Za-z0-9_\\.]+
        // Keep allocation-light: if no matches, return single non-mention span
        let pattern = "(?<!\\\\w)@[A-Za-z0-9_\\\\.]+"
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
        // Fetch Session by id and derive feed title; fallback to "Comments"
        let req: NSFetchRequest<Session> = Session.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        if let session = try? viewContext.fetch(req).first {
            return SessionActivity.feedTitle(for: session)
        }
        return "Comments"
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
                        .font(.body)
                    if span.isMention {
                        let mentionText = base
                            .foregroundStyle(Theme.Colors.accent)
                        // Add thin spaces around mention to create breathing room without breaking Text concatenation type
                        let padded = Text("\u{2009}") + mentionText + Text("\u{2009}")
                        return acc + padded
                    } else {
                        return acc + base.foregroundStyle(Color.primary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityLabel(accessibleLabel(for: s))
    }

    // MARK: - Relative time formatting
    private func relativeTimestamp(from date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)

        // Day difference (whole days)
        guard let dayDiff = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day else {
            // Fallback — default to full date
            let df = DateFormatter()
            df.dateFormat = "d MMM yyyy"
            return df.string(from: date)
        }

        if dayDiff == 0 {
            // Today → show "Today at HH:mm"
            let tf = DateFormatter()
            tf.dateFormat = "HH:mm"
            return "Today at \(tf.string(from: date))"
        }
        if dayDiff == 1 {
            return "Yesterday"
        }
        if dayDiff < 7 {
            return "\(dayDiff) days ago"
        }
        if dayDiff < 30 {
            // Weeks (rounded down)
            let weeks = max(1, dayDiff / 7)
            return weeks == 1 ? "A week ago" : "\(weeks) weeks ago"
        }
        // 30+ days → absolute date like "14 Sep 2025"
        let df = DateFormatter()
        df.dateFormat = "d MMM yyyy"
        return df.string(from: date)
    }

    public var body: some View {
        NavigationStack {
            content
                .safeAreaInset(edge: .top) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(headerTitleForSession())
                            .sectionHeader()
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
                .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            list.padding(.top, Theme.Spacing.m)
            composer
                .background(.bar)
        }
    }

    private var list: some View {
        let commentsRaw = store.comments(for: sessionID)
        let comments = commentsRaw.sorted { $0.timestamp < $1.timestamp }
        return List {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {

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
                            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))

                            // Name and inline timestamp on one line
                            HStack(spacing: 6) {
                                let displayName: String = {
                                    if comment.authorName == "You" {
                                        // Lookup real name from Profile entity
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
                                Text(displayName).font(.subheadline.weight(.semibold))
                                Text("•").foregroundStyle(Theme.Colors.secondaryText)
                                Text(relativeTimestamp(from: comment.timestamp))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 2)
                        .accessibilityLabel("Comment author")

                        // Mention-styled text (visual highlighting only)
                        mentionStyledText(comment.text) { _ in }
                            .fixedSize(horizontal: false, vertical: true)

                        // Optional mention chips line for tappable actions
                        let _handles = mentions(in: comment.text)
                        if !_handles.isEmpty {
                            HStack(spacing: Theme.Spacing.s) {
                                ForEach(_handles, id: \.self) { handle in
                                    Button(action: { tappedMention = handle }) {
                                        Text(handle)
                                            .font(.footnote)
                                            .foregroundStyle(Theme.Colors.accent)
                                            .padding(.vertical, 2)
                                            .padding(.horizontal, 6)
                                            .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
                                    }
                                    .accessibilityLabel("Mention \(handle)")
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilitySortPriority(1)
                        }

//                        Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
//                            .font(.footnote)
//                            .foregroundStyle(Theme.Colors.secondaryText)
//                            .accessibilityLabel("Comment time")
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityElement(children: .combine)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(commentID: comment.id, in: sessionID)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityLabel("Delete comment")
                    }
                    // Spacer between comments (no visible divider)
                    Rectangle().fill(Color.clear).frame(height: Theme.Spacing.m)
                }
            }
            .cardSurface(padding: Theme.Spacing.l)
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .accessibilitySortPriority(1) // Ensure list is visited before composer
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField("Add a comment…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Add a comment")
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send comment")
            }
        }
        .cardSurface(padding: Theme.Spacing.m)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .accessibilitySortPriority(0) // After list
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(sessionID: sessionID, authorName: placeholderAuthor, text: trimmed)
        draft = ""
    }
}

#Preview("Comments") {
    CommentsView(sessionID: UUID())
}

