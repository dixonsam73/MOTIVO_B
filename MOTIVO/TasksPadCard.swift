import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TasksPadCard: View {
    @Binding var showTasksPad: Bool
    @Binding var taskLines: [TaskLine]
    @Binding var autoTaskTexts: [UUID: String]

    let focusedTaskID: FocusState<UUID?>.Binding
    let tasksAccent: Color

    // Callbacks back into PracticeTimerView for behaviour/persistence
    let onToggleDone: (UUID) -> Void
    let onToggleLineType: (UUID) -> Void
    let onDeleteLine: (UUID) -> Void
    let onClearAll: () -> Void
    let onAddEmptyLine: () -> Void
    let onHandleReturn: (UUID) -> Void
    let onPersistSnapshot: () -> Void
    let onExpand: () -> Void
    let onImportTasks: () -> Void

    @State private var draggedTaskID: UUID? = nil
    @State private var suppressAutoClearForLineID: UUID? = nil
    @State private var ignoreNextTapForLineID: UUID? = nil

    private let dragHandleWidth: CGFloat = 20
    private let deleteIconWidth: CGFloat = 20
    private let dragDeleteSpacing: CGFloat = 16
    private let contextTextLeadingInset: CGFloat = 6

    private var rightControlZoneWidth: CGFloat {
        dragHandleWidth + dragDeleteSpacing + deleteIconWidth
    }

    private var hasAnyTaskLines: Bool {
        !taskLines.isEmpty
    }

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
            VStack(alignment: .leading, spacing: 0) {
                ForEach($taskLines) { $line in
                    taskRow($line)
                        .onDrop(
                            of: [UTType.text],
                            delegate: TaskLineDropDelegate(
                                targetID: line.id,
                                taskLines: $taskLines,
                                draggedTaskID: $draggedTaskID,
                                onPersistSnapshot: onPersistSnapshot
                            )
                        )
                }
            }

            if hasAnyTaskLines {
                HStack(alignment: .center, spacing: 12) {
                    Spacer(minLength: 0)

                    Button(action: {
                        onClearAll()
                    }) {
                        Text("Clear set")
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear task set")
                    .frame(width: rightControlZoneWidth + 96, alignment: .trailing)
                }
                .padding(.top, 0)
            }

            HStack(alignment: .center, spacing: 12) {
                Button(action: { onAddEmptyLine() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add line")
                    }
                    .foregroundStyle(tasksAccent.opacity(0.95))
                }

                Spacer(minLength: 8)

                Button(action: {
                    onImportTasks()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Import task set")
                    }
                    .foregroundStyle(tasksAccent.opacity(0.95))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import task set")
                .frame(width: rightControlZoneWidth + 96, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func taskRow(_ line: Binding<TaskLine>) -> some View {
        HStack(spacing: 6) {
            if line.wrappedValue.type == .task {
                Button {
                    onToggleDone(line.wrappedValue.id)
                } label: {
                    Image(systemName: line.wrappedValue.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tasksAccent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            taskTextArea(line)

            Spacer(minLength: 8)

            HStack(spacing: dragDeleteSpacing) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                    .frame(width: dragHandleWidth, height: 28)
                    .contentShape(Rectangle())
                    .onDrag {
                        draggedTaskID = line.wrappedValue.id
                        return NSItemProvider(object: line.wrappedValue.id.uuidString as NSString)
                    }
                    .accessibilityLabel("Reorder task")

                Button(role: .destructive) {
                    onDeleteLine(line.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                        .frame(width: deleteIconWidth, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: rightControlZoneWidth, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func taskTextArea(_ line: Binding<TaskLine>) -> some View {
        TextField(
            line.wrappedValue.type == .context ? "Context" : "Task",
            text: Binding(
                get: { line.wrappedValue.text },
                set: { newValue in
                    if newValue.contains("\n") {
                        let cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                        line.wrappedValue.text = cleaned
                        onPersistSnapshot()
                        onHandleReturn(line.wrappedValue.id)
                    } else {
                        line.wrappedValue.text = newValue
                        onPersistSnapshot()
                    }
                }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .disableAutocorrection(true)
        .focused(focusedTaskID, equals: line.wrappedValue.id)
        .onTapGesture {
            if ignoreNextTapForLineID == line.wrappedValue.id {
                ignoreNextTapForLineID = nil
                focusedTaskID.wrappedValue = nil
                return
            }
            focusedTaskID.wrappedValue = line.wrappedValue.id
        }
        .onChange(of: focusedTaskID.wrappedValue) { _, newFocus in
            if newFocus == line.wrappedValue.id {
                let shouldSuppressAutoClear = (suppressAutoClearForLineID == line.wrappedValue.id)

                if !shouldSuppressAutoClear,
                   let auto = autoTaskTexts[line.wrappedValue.id],
                   line.wrappedValue.text == auto {
                    line.wrappedValue.text = ""
                }

                suppressAutoClearForLineID = nil
                onPersistSnapshot()
            }
        }
        .font(line.wrappedValue.type == .context ? Theme.Text.body.weight(.medium) : Theme.Text.body)
        .padding(.leading, line.wrappedValue.type == .context ? contextTextLeadingInset : 0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    suppressAutoClearForLineID = line.wrappedValue.id
                    ignoreNextTapForLineID = line.wrappedValue.id
                    focusedTaskID.wrappedValue = nil

                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    onToggleLineType(line.wrappedValue.id)
                    generator.impactOccurred(intensity: 0.7)
                }
        )
    }

    private var collapsedHeader: some View {
        Button(action: {
            showTasksPad = true
            onExpand()
        }) {
            HStack(spacing: 8) {
                Text("Tasks")
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
        .accessibilityLabel("Show tasks")
        .padding(.vertical, 8)
    }
}

private struct TaskLineDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var taskLines: [TaskLine]
    @Binding var draggedTaskID: UUID?
    let onPersistSnapshot: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTaskID,
              draggedTaskID != targetID,
              let fromIndex = taskLines.firstIndex(where: { $0.id == draggedTaskID }),
              let toIndex = taskLines.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        if taskLines[toIndex].id != draggedTaskID {
            withAnimation {
                taskLines.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTaskID = nil
        onPersistSnapshot()
        return true
    }
}
