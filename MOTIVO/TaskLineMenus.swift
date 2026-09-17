import SwiftUI

/// The two existing line types, exposed without adding a new stored model.
struct TaskLineAddButton: View {
    let accent: Color
    let onAddTask: () -> Void
    let onAddContext: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false
    @State private var pendingContext: Bool?

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text("+")
                Text("Add line")
            }
            .foregroundStyle(accent.opacity(0.95))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add line")
        .accessibilityHint("Choose an item or a heading or note")
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                TaskLineMenuItem(title: "Item", subtitle: "An item to tick off", symbol: "checkmark.circle") {
                    pendingContext = false
                    isPresented = false
                }
                Divider()
                TaskLineMenuItem(title: "Heading or note", subtitle: "Organise items or add instructions", symbol: "text.alignleft") {
                    pendingContext = true
                    isPresented = false
                }
            }
            .padding(.horizontal, 16)
            .frame(width: 280)
            .fixedSize(horizontal: false, vertical: true)
            .presentationBackground(Theme.Colors.surface(colorScheme))
            .presentationCompactAdaptation(.popover)
            .onDisappear {
                // Insert/focus after dismissal so the popover does not take keyboard focus back.
                guard let context = pendingContext else { return }
                pendingContext = nil
                if context { onAddContext() } else { onAddTask() }
            }
        }
    }
}

struct TaskLineActionsButton: View {
    @Binding var isPresented: Bool
    let text: String
    let isContext: Bool
    let onOpen: () -> Void
    let onConvert: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDeletion: Bool?

    private var conversionTitle: String {
        isContext ? "Make item" : "Make heading or note"
    }

    var body: some View {
        Button {
            onOpen()
            isPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.9))
                .frame(width: 20, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actions for \(text.isEmpty ? "empty line" : text)")
        .accessibilityValue(isContext ? "Heading or note" : "Item")
        .accessibilityAction(named: Text(conversionTitle), onConvert)
        .accessibilityAction(named: Text("Delete line"), onDelete)
        .popover(isPresented: $isPresented) {
            VStack(spacing: 0) {
                TaskLineMenuItem(title: conversionTitle, symbol: isContext ? "checkmark.circle" : "text.alignleft") {
                    pendingDeletion = false
                    isPresented = false
                }
                Divider()
                TaskLineMenuItem(title: "Delete line", symbol: "trash") {
                    pendingDeletion = true
                    isPresented = false
                }
            }
            .padding(.horizontal, 16)
            .frame(width: 280)
            .fixedSize(horizontal: false, vertical: true)
            .presentationBackground(Theme.Colors.surface(colorScheme))
            .presentationCompactAdaptation(.popover)
            .onDisappear {
                guard let deletion = pendingDeletion else { return }
                pendingDeletion = nil
                if deletion { onDelete() } else { onConvert() }
            }
        }
    }
}

private struct TaskLineMenuItem: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.Text.body).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(Theme.Text.meta).foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
