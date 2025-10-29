import SwiftUI

public struct CommentsView: View {
    @ObservedObject private var store = CommentsStore.shared
    @State private var draft: String = ""
    @State private var tappedMention: String? = nil
    @Environment(\.dismiss) private var dismiss

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

    @ViewBuilder
    private func mentionStyledText(_ s: String, onTap: @escaping (String) -> Void) -> some View {
        // Compose visual text with accent style for mentions using concatenation
        let spans = tokenizeMentions(s)
        let concatenated: Text = spans.reduce(Text("")) { acc, span in
            let part = Text(span.text)
                .font(.body)
                .foregroundStyle(span.isMention ? Color.accentColor : Color.primary)
                .underline(span.isMention, pattern: .solid, color: .clear)
            return acc + part
        }
        concatenated
            .accessibilityLabel(accessibleLabel(for: s))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Comments")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .alert(tappedMention ?? "", isPresented: Binding(get: { tappedMention != nil }, set: { if !$0 { tappedMention = nil } })) {
                    Button("OK", role: .cancel) { tappedMention = nil }
                } message: {
                    Text("Mention tapped. Future: open profile or start reply with \(tappedMention ?? "")")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            list
            composer
                .background(.bar)
        }
    }

    private var list: some View {
        let comments = store.comments(for: sessionID)
        return List {
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.authorName)
                        .font(.headline)
                        .accessibilityLabel("Comment author")

                    // Mention-styled text (visual highlighting only)
                    mentionStyledText(comment.text) { _ in }
                        .fixedSize(horizontal: false, vertical: true)

                    // Optional mention chips line for tappable actions
                    let _handles = mentions(in: comment.text)
                    if !_handles.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(_handles, id: \.self) { handle in
                                Button(action: { tappedMention = handle }) {
                                    Text(handle)
                                        .font(.footnote)
                                        .foregroundStyle(.tint)
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                        .background(.secondary.opacity(0.12), in: Capsule())
                                }
                                .accessibilityLabel("Mention \(handle)")
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilitySortPriority(1)
                    }

                    Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Comment time")
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.delete(commentID: comment.id, in: sessionID)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete comment")
                }
            }
        }
        .listStyle(.plain)
        .accessibilitySortPriority(1) // Ensure list is visited before composer
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Add a comment")
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send comment")
        }
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
