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
    let onAddEmptyLine: (TaskLineType) -> Void
    let onHandleReturn: (UUID) -> Void
    let onPersistSnapshot: () -> Void
    let onMarkTaskSetDirty: (Bool) -> Void
    let saveListButtonTitle: String
    let isSaveListDisabled: Bool
    let onSaveList: () -> Void
    let onExpand: () -> Void
    let onImportTasks: () -> Void

    @State private var draggedTaskID: UUID? = nil
    @State private var actionsLineID: UUID? = nil

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
                                onPersistSnapshot: onPersistSnapshot,
                                onMarkTaskSetDirty: onMarkTaskSetDirty
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
                    .accessibilityLabel("Clear list")
                    .frame(width: rightControlZoneWidth + 96, alignment: .trailing)
                }
                .padding(.top, 0)
            }

            HStack(alignment: .center, spacing: 12) {
                TaskLineAddButton(
                    accent: tasksAccent,
                    onAddTask: { onAddEmptyLine(.task) },
                    onAddContext: { onAddEmptyLine(.context) }
                )

                Spacer(minLength: 8)

                Button(action: { onSaveList() }) {
                    Text(saveListButtonTitle)
                        .foregroundStyle(
                            isSaveListDisabled
                            ? Theme.Colors.secondaryText.opacity(0.72)
                            : tasksAccent.opacity(0.95)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isSaveListDisabled)
                .accessibilityLabel(saveListButtonTitle)

                Spacer(minLength: 8)

                Button(action: {
                    onImportTasks()
                }) {
                    HStack(spacing: 4) {
                        Text("+")
                        Text("Import list")
                    }
                    .foregroundStyle(tasksAccent.opacity(0.95))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import list")
                .frame(width: rightControlZoneWidth + 96, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .onChange(of: taskLines.map(\.id)) { _, newIDs in
            guard let focusedID = focusedTaskID.wrappedValue else { return }
            guard newIDs.contains(focusedID) == false else { return }

            focusedTaskID.wrappedValue = nil
            actionsLineID = nil
        }
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
                    .accessibilityLabel("Reorder item")

                TaskLineActionsButton(
                    isPresented: Binding(
                        get: { actionsLineID == line.wrappedValue.id },
                        set: { actionsLineID = $0 ? line.wrappedValue.id : nil }
                    ),
                    text: line.wrappedValue.text,
                    isContext: line.wrappedValue.type == .context,
                    onOpen: { focusedTaskID.wrappedValue = nil },
                    onConvert: {
                        focusedTaskID.wrappedValue = nil
                        onToggleLineType(line.wrappedValue.id)
                    },
                    onDelete: {
                        focusedTaskID.wrappedValue = nil
                        onDeleteLine(line.wrappedValue.id)
                    }
                )
            }
            .frame(width: rightControlZoneWidth, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func taskTextArea(_ line: Binding<TaskLine>) -> some View {
        TaskLineTextField(
            title: line.wrappedValue.type == .context ? "Heading or note" : "Item",
            text: Binding(
                get: { line.wrappedValue.text },
                set: { newValue in
                    if newValue.contains("\n") {
                        let cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                        line.wrappedValue.text = cleaned
                        onMarkTaskSetDirty(false)
                        onPersistSnapshot()
                        onHandleReturn(line.wrappedValue.id)
                    } else {
                        line.wrappedValue.text = newValue
                        onMarkTaskSetDirty(false)
                        onPersistSnapshot()
                    }
                }
            ),
            id: line.wrappedValue.id,
            focusedLineID: focusedTaskID,
            axis: .vertical,
            onSubmit: { onHandleReturn(line.wrappedValue.id) },
            onShowActions: {
                focusedTaskID.wrappedValue = nil
                actionsLineID = line.wrappedValue.id
            }
        )
        .font(line.wrappedValue.type == .context ? Theme.Text.body.weight(.medium) : Theme.Text.body)
        .padding(.leading, line.wrappedValue.type == .context ? contextTextLeadingInset : 0)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityLabel(line.wrappedValue.type == .context ? "Heading or note" : "Item")
        .accessibilityAction(named: Text(line.wrappedValue.type == .context ? "Make item" : "Make heading or note")) {
            focusedTaskID.wrappedValue = nil
            onToggleLineType(line.wrappedValue.id)
        }
        .accessibilityAction(named: Text("Delete line")) {
            focusedTaskID.wrappedValue = nil
            onDeleteLine(line.wrappedValue.id)
        }
    }

    private var collapsedHeader: some View {
        Button(action: {
            showTasksPad = true
            onExpand()
        }) {
            HStack(spacing: 8) {
                Text("Lists")
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
        .accessibilityLabel("Show list")
        .padding(.vertical, 8)
    }
}

private struct TaskLineDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var taskLines: [TaskLine]
    @Binding var draggedTaskID: UUID?
    let onPersistSnapshot: () -> Void
    let onMarkTaskSetDirty: (Bool) -> Void

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
        onMarkTaskSetDirty(false)
        onPersistSnapshot()
        return true
    }
}
