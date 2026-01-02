import SwiftUI

// Read-only detail view for a BackendSessionViewModel.
// - No CoreData imports
// - Minimal styling with Motivo Theme tokens where available
public struct BackendSessionDetailView: View {
    public let model: BackendSessionViewModel

    // Local shims to avoid hard dependencies on Theme while keeping visual consistency.
    // If Theme provides spacing/tokens, prefer those via optional accessors; otherwise use system defaults.
    private var spacingS: CGFloat { 8 }
    private var spacingM: CGFloat { 12 }
    private var spacingL: CGFloat { 16 }
    
    public init(model: BackendSessionViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacingL) {
                // Card surface container
                Group {
                    VStack(alignment: .leading, spacing: spacingM) {
                        titleRow
                        metaRow
                    }
                    .padding(spacingL)
                    .background(cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Notes section
                section(header: Text("Notes")) {
                    if let notes = model.notes, notes.isEmpty == false {
                        Text(notes)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No notes.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Attachments section
                section(header: Text("Attachments")) {
                    if model.attachmentURLs.isEmpty {
                        Text("No attachments.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: spacingS) {
                            ForEach(model.attachmentURLs, id: \.self) { url in
                                HStack(spacing: spacingS) {
                                    Image(systemName: "paperclip")
                                        .foregroundStyle(.secondary)
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(spacingL)
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.activityLabel)
                .font(.headline) // Use Theme text style if available; fallback to .headline
                .foregroundStyle(.primary)
            Spacer()
            Text(model.createdAtRaw ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: spacingS) {
            Text(model.ownerUserID)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(model.id.uuidString)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // Generic section builder with a header to mimic Theme section headers while staying dependency-free.
    @ViewBuilder
    private func section<Content: View>(header: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacingM) {
            header
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: spacingM) {
                content()
            }
            .padding(spacingL)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // Card-like surface using system materials to approximate Motivo cardSurface.
    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .background(.clear)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        }
    }
}

#Preview("Backend Session Detail") {
    // Inline JSON representing a BackendPost. Adjust keys to match BackendPost's Decodable mapping.
    let json = """
    {
      "id": "11111111-2222-3333-4444-555555555555",
      "createdAt": "2025-12-31 23:59",
      "ownerUserID": "user_123"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    // If BackendPost uses snake_case or different date strategies, configure decoder here.
    // decoder.keyDecodingStrategy = .convertFromSnakeCase

    let post = try! decoder.decode(BackendPost.self, from: json)
    let model = BackendSessionViewModel(post: post, currentUserID: "user_123")

    return BackendSessionDetailView(model: model)
}
