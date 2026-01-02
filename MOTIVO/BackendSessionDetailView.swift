import SwiftUI

// Read-only detail view for a BackendSessionViewModel.
// - No CoreData imports
// - Minimal styling with Motivo Theme tokens where available
public struct BackendSessionDetailView: View {
    public let model: BackendSessionViewModel

    // Local shims to avoid hard dependencies on Theme while keeping visual consistency.
    private var spacingS: CGFloat { 8 }
    private var spacingM: CGFloat { 12 }
    private var spacingL: CGFloat { 16 }

    public init(model: BackendSessionViewModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacingL) {
                titleRow

                section(header: Text("Metadata")) {
                    VStack(alignment: .leading, spacing: spacingS) {
                        // Activity / instrument
                        labeledLine(label: "Activity", value: model.activityLabel)
                        labeledLine(label: "Instrument", value: model.instrumentLabel ?? "—")

                        // Ownership
                        labeledLine(label: "Owner", value: model.ownerUserID.isEmpty ? "—" : model.ownerUserID)
                        labeledLine(label: "Is mine", value: model.isMine ? "true" : "false")

                        // Timestamps
                        labeledLine(label: "Session time", value: model.sessionTimestampRaw ?? "—")
                        labeledLine(label: "Created", value: model.createdAtRaw ?? "—")
                        labeledLine(label: "Updated", value: model.updatedAtRaw ?? "—")
                    }
                }

                // Notes section (placeholder until backend provides it)
                section(header: Text("Notes")) {
                    if let notes = model.notes, !notes.isEmpty {
                        Text(notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("No notes.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Attachments section (8G will wire read-only URLs)
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
                                        .font(.footnote)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, spacingM)
            .padding(.vertical, spacingL)
        }
        .navigationTitle("Backend Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.activityLabel)
                .font(.headline)
                .foregroundStyle(.primary)

            if let instrument = model.instrumentLabel, !instrument.isEmpty {
                Text("•")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(instrument)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Prefer sessionTimestamp in the header when available; fall back to createdAt.
            Text(model.sessionTimestampRaw ?? model.createdAtRaw ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(header: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacingS) {
            header
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: spacingS) {
                content()
            }
            .padding(spacingM)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func labeledLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: spacingS) {
            Text(label + ":")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }
}

#if DEBUG
#Preview("BackendSessionDetailView") {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "owner_user_id": "user_123",
      "session_id": "00000000-0000-0000-0000-000000000002",
      "session_timestamp": "2025-12-31 23:58",
      "created_at": "2025-12-31 23:59",
      "updated_at": "2026-01-01 00:01",
      "is_public": true,
      "activity_label": "Practice",
      "instrument_label": "Bass"
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    let post = try! decoder.decode(BackendPost.self, from: json)
    let model = BackendSessionViewModel(post: post, currentUserID: "user_123")
    return NavigationStack { BackendSessionDetailView(model: model) }
}
#endif
