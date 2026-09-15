import SwiftUI

/// Shared editing behaviour for task-pad and saved-set lines.
struct TaskLineTextField: View {
    let title: String
    @Binding var text: String
    let id: UUID
    let focusedLineID: FocusState<UUID?>.Binding
    var axis: Axis? = nil
    let onSubmit: () -> Void
    let onShowActions: () -> Void

    @State private var selection: TextSelection?

    private var isEditing: Bool { focusedLineID.wrappedValue == id }

    var body: some View {
        TextField(title, text: $text, selection: $selection, axis: axis)
            .textFieldStyle(.plain)
            .disableAutocorrection(true)
            .textInputAutocapitalization(.sentences)
            .tint(Theme.Colors.accent)
            .submitLabel(.done)
            .focused(focusedLineID, equals: id)
            .onSubmit(onSubmit)
            .onChange(of: isEditing) { _, editing in
                guard editing else {
                    selection = nil
                    return
                }
                // Set the initial caret after native focus has been established.
                // Subsequent taps and selections belong entirely to the text field.
                DispatchQueue.main.async {
                    guard isEditing else { return }
                    selection = TextSelection(insertionPoint: text.endIndex)
                }
            }
            .allowsHitTesting(isEditing)
            .accessibilityAction { focusedLineID.wrappedValue = id }
            .overlay {
                if !isEditing {
                    // Keep line actions out of the native text-selection gestures.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .exclusively(before: TapGesture())
                                .onEnded { gesture in
                                    switch gesture {
                                    case .first:
                                        onShowActions()
                                    case .second:
                                        focusedLineID.wrappedValue = id
                                    }
                                }
                        )
                        .accessibilityHidden(true)
                }
            }
    }
}
