//
// CHANGE-ID: 20260305_071025_TPV_RemoveRedundantDone_SetInline_9b7f9f1a
// SCOPE: Visual-only — remove redundant top-right Done control (match ILV/ALV pattern) by moving commit action inline next to TextField. No logic/behaviour changes.
//
// PREVIOUS CHANGE-IDs:
// - 20260304_081250_Threads_S2_ThreadPickerView_Skeleton
// - 20260304_131900_Threads_S6F_ThreadPickerView_Options_FixIsSelected
//

import SwiftUI

struct ThreadPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var selectedThread: String?

    private let title: String
    private let recentThreads: [String]
    private let maxLength: Int

    @State private var draftText: String = ""

    init(
        selectedThread: Binding<String?>,
        title: String = "Thread",
        recentThreads: [String] = [],
        maxLength: Int = 32
    ) {
        self._selectedThread = selectedThread
        self.title = title
        self.recentThreads = recentThreads
        self.maxLength = maxLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Set Thread").sectionHeader()) {
                    HStack(spacing: Theme.Spacing.m) {
                        TextField("Type a thread name", text: $draftText)
                            .font(Theme.Text.body)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)

                        Button {
                            let sanitized = sanitize(draftText, maxLength: maxLength)
                            selectedThread = sanitized
                            dismiss()
                        } label: {
                            Text("Set")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(isEffectivelyEmpty(draftText))
                    }
                }

                if !recentThreads.isEmpty {
                    Section(header: Text("Threads").sectionHeader()) {
                        ForEach(recentThreads, id: \.self) { thread in
                            Button {
                                applySelection(thread)
                            } label: {
                                HStack(spacing: Theme.Spacing.m) {
                                    Text(thread)
                                        .font(Theme.Text.body)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                    if isSelected(thread) {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if selectedThread != nil {
                    Section {
                        Button {
                            selectedThread = nil
                            dismiss()
                        } label: {
                            Text("Clear thread")
                                .font(Theme.Text.body)
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.Text.pageTitle)
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close thread picker")
                }
                            }
            .onAppear {
                // Initialize the draft text from current selection (if any).
                draftText = selectedThread ?? ""
            }
            .appBackground()
        }
    }

    private func applySelection(_ thread: String) {
        selectedThread = sanitize(thread, maxLength: maxLength)
        dismiss()
    }

    private func isEffectivelyEmpty(_ raw: String) -> Bool {
        sanitize(raw, maxLength: maxLength) == nil
    }

    private func isSelected(_ thread: String) -> Bool {
        guard let a = sanitize(thread, maxLength: maxLength)?.lowercased() else { return false }
        guard let b = sanitize(selectedThread ?? "", maxLength: maxLength)?.lowercased() else { return false }
        return a == b
    }

    /// Trims, collapses internal whitespace, enforces max length, and returns nil for empty.
    private func sanitize(_ raw: String, maxLength: Int) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Collapse consecutive whitespace into a single space.
        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else { return nil }

        if collapsed.count <= maxLength {
            return collapsed
        } else {
            let idx = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
            return String(collapsed[..<idx])
        }
    }
}
