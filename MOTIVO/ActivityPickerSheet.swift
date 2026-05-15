// CHANGE-ID: 20260515_111500_ActivityPickerInlineCreate
// SCOPE: Add lightweight inline New Activity creation control to ActivityPickerSheet; persist/select via supplied parent closure. No unrelated picker redesign.
// SEARCH-TOKEN: 20260515_111500_ActivityPickerInlineCreate

import SwiftUI

struct ActivityPickerSheet: View {
    @Binding var activityChoice: String
    @Binding var showActivitySheet: Bool

    let choices: [String]
    let displayName: (String) -> String
    let applyChoice: (String) -> Void
    let resetTasks: () -> Void
    let createActivityChoice: (String) -> String?

    @State private var tempChoice: String = ""
    @State private var isAddingNewActivity: Bool = false
    @State private var newActivityName: String = ""
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Activity", selection: $tempChoice) {
                    ForEach(choices, id: \.self) { choice in
                        Text(displayName(choice)).tag(choice)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .top)

                Divider()
                    .opacity(0.45)

                VStack(spacing: Theme.Spacing.xs) {
                    if isAddingNewActivity {
                        HStack(spacing: Theme.Spacing.s) {
                            TextField("New activity", text: $newActivityName)
                                .font(Theme.Text.body)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    addNewActivity()
                                }

                            Button("Add") {
                                addNewActivity()
                            }
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.accent)
                            .disabled(newActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Button {
                            isAddingNewActivity = true
                        } label: {
                            HStack {
                                Text("+ New activity")
                                    .font(Theme.Text.body)
                                    .foregroundStyle(Theme.Colors.accent)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, Theme.Spacing.s)
            .background(Theme.Colors.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Seed the temporary selection from the current committed activity
                tempChoice = activityChoice
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Commit temp selection to real activity
                        activityChoice = tempChoice
                        applyChoice(tempChoice)
                        resetTasks()
                        showActivitySheet = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Discard temp selection and just dismiss
                        showActivitySheet = false
                    }
                }
            }
        }
    }

    private func addNewActivity() {
        guard let choice = createActivityChoice(newActivityName) else { return }

        tempChoice = choice
        activityChoice = choice
        applyChoice(choice)
        resetTasks()
        newActivityName = ""
        isAddingNewActivity = false
        showActivitySheet = false
    }
}
