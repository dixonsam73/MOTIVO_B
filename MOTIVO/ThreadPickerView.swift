//
// CHANGE-ID: 20260304_081250_Threads_S2_ThreadPickerView_Skeleton
// SCOPE: Add standalone ThreadPickerView (compile-only skeleton; not wired yet).
//
// NOTE: This file intentionally avoids dependencies on Theme/Auth/CoreData so it can compile
// in isolation for Stage 2. Wiring + recents sourcing happens in later stages.
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
        NavigationView {
            List {
                Section {
                    TextField("Type a thread name", text: $draftText)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                }

                if !recentThreads.isEmpty {
                    Section("Recent") {
                        ForEach(recentThreads, id: \.self) { thread in
                            Button {
                                applySelection(thread)
                            } label: {
                                Text(thread)
                            }
                        }
                    }
                }

                if selectedThread != nil {
                    Section {
                        Button(role: .destructive) {
                            selectedThread = nil
                            dismiss()
                        } label: {
                            Text("Clear thread")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let sanitized = sanitize(draftText, maxLength: maxLength)
                        selectedThread = sanitized
                        dismiss()
                    }
                    .disabled(isEffectivelyEmpty(draftText))
                }
            }
            .onAppear {
                // Initialize the draft text from current selection (if any).
                draftText = selectedThread ?? ""
            }
        }
    }

    private func applySelection(_ thread: String) {
        selectedThread = sanitize(thread, maxLength: maxLength)
        dismiss()
    }

    private func isEffectivelyEmpty(_ raw: String) -> Bool {
        sanitize(raw, maxLength: maxLength) == nil
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
