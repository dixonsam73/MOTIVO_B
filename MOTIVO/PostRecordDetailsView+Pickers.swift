// CHANGE-ID: 20260605_184500_PRDV_PickerExtract
// SCOPE: PostRecordDetailsView — picker sheet/view-builder extraction only. No UI or logic changes.
// SEARCH-TOKEN: 20260605_184500_PRDV_PickerExtract

import SwiftUI
import CoreData

extension PostRecordDetailsView {
    var instrumentPicker: some View {
        VStack(spacing: 16) {
            Text("Instrument")
                .font(.headline)

            VStack(spacing: 0) {
                Button {
                    instrument = nil
                    showInstrumentPicker = false
                } label: {
                    pickerSheetRow(
                        title: "Select instrument…",
                        isSelected: instrument == nil
                    )
                }
                .buttonStyle(.plain)

                if instruments.isEmpty == false {
                    Divider()
                }

                ForEach(instruments, id: \.self) { inst in
                    Button {
                        instrument = inst
                        showInstrumentPicker = false
                    } label: {
                        pickerSheetRow(
                            title: inst.name ?? "Instrument",
                            isSelected: instrument == inst
                        )
                    }
                    .buttonStyle(.plain)

                    if inst != instruments.last {
                        Divider()
                    }
                }
            }
            .cardSurface()

            Spacer(minLength: 0)
        }
        .padding()
        .appBackground()
    }

    var activityPickerPinned: some View {
        VStack(spacing: 16) {
            Text("Activity")
                .font(.headline)

            VStack(spacing: 0) {
                let choices = activityChoicesPinned()
                ForEach(choices, id: \.self) { choice in
                    Button {
                        activityChoice = choice

                        if choice.hasPrefix("core:") {
                            if let raw = Int(choice.split(separator: ":").last ?? "0") {
                                tempActivity = SessionActivityType(rawValue: Int16(raw)) ?? .practice
                                activity = tempActivity
                            } else {
                                tempActivity = .practice
                                activity = .practice
                            }
                            selectedCustomName = ""
                        } else if choice.hasPrefix("custom:") {
                            let name = String(choice.dropFirst("custom:".count))
                            tempActivity = .practice
                            activity = .practice
                            selectedCustomName = name
                        }

                        showActivityPicker = false
                        maybeUpdateActivityDetailFromDefaults()
                        refreshAutoTitleIfNeeded()
                    } label: {
                        pickerSheetRow(
                            title: activityDisplayName(for: choice),
                            isSelected: choice == activityChoice
                        )
                    }
                    .buttonStyle(.plain)

                    if choice != choices.last {
                        Divider()
                    }
                }
            }
            .cardSurface()

            Spacer(minLength: 0)
        }
        .padding()
        .appBackground()
        .onAppear { syncActivityChoiceFromState() }
    }

    func pickerSheetRow(title: String, isSelected: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: isSelected ? "checkmark" : "circle")
                .font(.body)
                .foregroundStyle(
                    isSelected
                    ? AnyShapeStyle(.primary)
                    : AnyShapeStyle(Theme.Colors.secondaryText)
                )
                .frame(width: 24)

            Text(title)
                .font(Theme.Text.body)
                .foregroundStyle(
                    isSelected
                    ? AnyShapeStyle(.primary)
                    : AnyShapeStyle(Theme.Colors.secondaryText)
                )

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    var startPicker: some View {
        NavigationStack {
            VStack {
                DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel).labelsHidden()
                Spacer()
            }
            .navigationTitle("Start Time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showStartPicker = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { timestamp = tempDate; showStartPicker = false; maybeUpdateActivityDetailFromDefaults() } }
            }
        }
        .presentationDetents([.medium])
    }

    var durationPicker: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("Hours", selection: $tempHours) { ForEach(0..<24, id: \.self) { Text("\($0) h").tag($0) } }.pickerStyle(.wheel)
                    Picker("Minutes", selection: $tempMinutes) { ForEach(0..<60, id: \.self) { Text("\($0) m").tag($0) } }.pickerStyle(.wheel)
                }
                Spacer()
            }
            .navigationTitle("Duration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDurationPicker = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { durationSeconds = (tempHours * 3600) + (tempMinutes * 60); showDurationPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    func activityDisplayName(for choice: String) -> String {
        if choice.hasPrefix("core:") {
            if let raw = Int(choice.split(separator: ":").last ?? "0"),
               let t = SessionActivityType(rawValue: Int16(raw)) {
                return t.label
            }
            return SessionActivityType.practice.label
        } else if choice.hasPrefix("custom:") {
            return String(choice.dropFirst("custom:".count))
        }
        return SessionActivityType.practice.label
    }

    func activityChoicesPinned() -> [String] {
        let core: [String] = SessionActivityType.allCases.map { "core:\($0.rawValue)" }
        let customs: [String] = userActivities.compactMap { ua in
            let n = (ua.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? nil : "custom:\(n)"
        }
        let primary = normalizedPrimary()
        var result: [String] = []
        if let p = primary { result.append(p) }
        for c in core where !result.contains(c) { result.append(c) }
        for cu in customs where !result.contains(cu) { result.append(cu) }
        return result
    }

    func syncActivityChoiceFromState() {
        if selectedCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            activityChoice = "core:\(activity.rawValue)"
        } else {
            activityChoice = "custom:\(selectedCustomName)"
        }
    }
}
