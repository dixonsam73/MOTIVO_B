import SwiftUI

public struct CommentsView: View {
    @ObservedObject private var store = CommentsStore.shared
    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    private let sessionID: UUID
    private let placeholderAuthor: String

    public init(sessionID: UUID, placeholderAuthor: String = "You") {
        self.sessionID = sessionID
        self.placeholderAuthor = placeholderAuthor
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
                    Text(comment.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
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
