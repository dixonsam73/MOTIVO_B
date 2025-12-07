import SwiftUI

struct ActivityPickerSheet: View {
    @Binding var activityChoice: String
    @Binding var showActivitySheet: Bool

    let choices: [String]
    let displayName: (String) -> String
    let applyChoice: (String) -> Void
    let resetTasks: () -> Void

    @State private var tempChoice: String = ""

    var body: some View {
        NavigationView {
            VStack {
                Picker("Activity", selection: $tempChoice) {
                    ForEach(choices, id: \.self) { choice in
                        Text(displayName(choice)).tag(choice)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
            .navigationTitle("Activity")
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
}
