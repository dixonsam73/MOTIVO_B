// TasksPadCard.swift
// Extracted from PracticeTimerView as part of refactor step 4 (tasks pad only).
// View-only wrapper for the Notes / Tasks pad. All state and persistence stay in PracticeTimerView.

import SwiftUI

struct TasksPadCard: View {
    @Binding var showTasksPad: Bool
    @Binding var taskLines: [PracticeTimerView.TaskLine]
    @Binding var autoTaskTexts: [UUID: String]

    let focusedTaskID: FocusState<UUID?>.Binding
    let tasksAccent: Color

    // Callbacks back into PracticeTimerView for behaviour/persistence
    let onToggleDone: (UUID) -> Void
    let onDeleteLine: (UUID) -> Void
    let onClearAll: () -> Void
    let onAddEmptyLine: () -> Void
    let onHandleReturn: (UUID) -> Void
    let onPersistSnapshot: () -> Void
    let onExpand: () -> Void

    var body: some View {
        Group {
            if showTasksPad {
                expandedPad
            } else {
                collapsedHeader
            }
        }
    }

    @ViewBuilder
    private var expandedPad: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Centered header to align with rest of page
            HStack(alignment: .firstTextBaseline) {
                Text("Notes / Tasks")
                    .sectionHeader()

                Spacer(minLength: 0)

                // Discrete "Clear all" – wipes pad, no auto-refill
                Button(action: {
                    onClearAll()
                }) {
                    Text("Clear all")
                        .font(Theme.Text.body)
                        .foregroundStyle(tasksAccent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear all tasks")

                // Chevron-up to collapse
                Button(action: {
                    showTasksPad = false
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide notes and tasks")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach($taskLines) { $line in
                HStack(spacing: 8) {
                    Button {
                        onToggleDone(line.id)
                    } label: {
                        Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tasksAccent)
                    }

                    TextField(
                        "Task",
                        text: Binding(
                            get: { line.text },
                            set: { newValue in
                                if newValue.contains("\n") {
                                    // Strip newline characters and treat as "return"
                                    let cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                                    line.text = cleaned
                                    onHandleReturn(line.id)
                                } else {
                                    line.text = newValue
                                    onPersistSnapshot()
                                }
                            }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .focused(focusedTaskID, equals: line.id)
                    .onTapGesture {
                        focusedTaskID.wrappedValue = line.id
                    }
                    .onChange(of: focusedTaskID.wrappedValue) { _, newFocus in
                        if newFocus == line.id {
                            // If current equals auto text, clear to start fresh
                            if let auto = autoTaskTexts[line.id], line.text == auto {
                                line.text = ""
                            }
                            onPersistSnapshot()
                        }
                    }

                    Spacer(minLength: 8)

                    Button(role: .destructive) {
                        onDeleteLine(line.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: { onAddEmptyLine() }) {
                HStack {
                    Image(systemName: "plus")
                    Text("Add line")
                }
                .foregroundStyle(tasksAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var collapsedHeader: some View {
        Button(action: {
            showTasksPad = true
            onExpand()
        }) {
            HStack(spacing: 8) {
                Text("Notes / Tasks")
                    .sectionHeader()

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show notes and tasks")
        .padding(.vertical, 8)
    }
}
