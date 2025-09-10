//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    /// Pass a Session to edit; leave nil to create new
    var session: Session?

    // MARK: - State (form fields)
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var when: Date = Date()
    @State private var isPublic: Bool = false
    @State private var mood: Double = 5
    @State private var effort: Double = 5
    @State private var instrumentName: String = ""
    @State private var tagsCSV: String = ""

    // Duration entry: minutes + seconds (text fields + ± buttons)
    @State private var durMinutes: String = "0"
    @State private var durSeconds: String = "0"

    // Track whether user overrode auto-title
    @State private var userEditedTitle: Bool = false

    init(session: Session? = nil) {
        self.session = session
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("When")) {
                    DatePicker("Date & time", selection: $when, displayedComponents: [.date, .hourAndMinute])
                }

                Section(header: Text("Instrument")) {
                    TextField("Instrument", text: $instrumentName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: instrumentName) { _, _ in
                            applyAutoTitleIfNeeded()
                        }
                }

                Section(header: Text("Title")) {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .onChange(of: title) { _, _ in userEditedTitle = true }
                }

                Section(header: Text("Duration")) {
                    DurationEditor(
                        minutes: $durMinutes,
                        seconds: $durSeconds,
                        incMin: { adjustMinutes(+1) },
                        decMin: { adjustMinutes(-1) },
                        incSec: { adjustSeconds(+1) },
                        decSec: { adjustSeconds(-1) }
                    )
                }

                Section(header: Text("Privacy & Feel")) {
                    Toggle("Public", isOn: $isPublic)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Mood")
                            Spacer()
                            Text("\(Int(mood))").foregroundStyle(.secondary)
                        }
                        Slider(value: $mood, in: 0...10, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Effort")
                            Spacer()
                            Text("\(Int(effort))").foregroundStyle(.secondary)
                        }
                        Slider(value: $effort, in: 0...10, step: 1)
                    }
                }

                Section(header: Text("Tags")) {
                    TextField("Comma-separated (e.g. scales, repertoire)", text: $tagsCSV)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle(session == nil ? "New Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(totalDurationSeconds == 0)
                }
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    // MARK: - Derived
    private var totalDurationSeconds: Int {
        let mins = Int(durMinutes.filter(\.isNumber)) ?? 0
        let rawSecs = Int(durSeconds.filter(\.isNumber)) ?? 0
        let secs = min(max(rawSecs, 0), 59) // clamp 0...59
        let clampedMins = max(mins, 0)
        return clampedMins * 60 + secs
    }

    // MARK: - Actions
    private func loadIfEditing() {
        if let s = session {
            // Editing existing
            title = s.title ?? ""
            notes = s.notes ?? ""
            when = s.timestamp ?? Date()
            isPublic = s.isPublic
            mood = Double(s.mood)
            effort = Double(s.effort)
            instrumentName = s.instrument ?? ""

            let secs = max(0, Int(s.durationSeconds))
            durMinutes = String(secs / 60)
            durSeconds = String(secs % 60)

            tagsCSV = ((s.tags as? Set<Tag>) ?? [])
                .compactMap { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")
        } else {
            // Creating new
            applyAutoTitleIfNeeded()
            durMinutes = "0"
            durSeconds = "0"

            // NEW: Pull default privacy from Profile.defaultPrivacy (Boolean)
            let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
            fr.fetchLimit = 1
            if let p = try? ctx.fetch(fr).first {
                isPublic = p.defaultPrivacy
            } else {
                isPublic = false // fallback if no profile exists yet
            }
        }
    }

    private func applyAutoTitleIfNeeded() {
        guard !userEditedTitle else { return }
        let trimmed = instrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Practice Session" : "\(trimmed) Practice"
    }

    // MARK: - Duration adjustments (+ / -)
    private func adjustMinutes(_ delta: Int) {
        var m = Int(durMinutes.filter(\.isNumber)) ?? 0
        m = max(0, m + delta)
        durMinutes = String(m)
    }

    private func adjustSeconds(_ delta: Int) {
        var m = Int(durMinutes.filter(\.isNumber)) ?? 0
        var s = Int(durSeconds.filter(\.isNumber)) ?? 0
        s += delta

        if s >= 60 {
            m += s / 60
            s = s % 60
        } else if s < 0 {
            let borrow = (abs(s) + 59) / 60
            if m >= borrow {
                m -= borrow
                s += borrow * 60
            } else {
                m = 0
                s = 0
            }
        }

        durMinutes = String(max(0, m))
        durSeconds = String(max(0, min(59, s)))
    }

    private func save() {
        let isEditing = (session != nil)
        let s: Session = session ?? Session(context: ctx)
        if s.id == nil { s.id = UUID() }

        s.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.notes = notes
        s.timestamp = when
        s.isPublic = isPublic
        s.mood = Int16(min(max(Int(mood), 0), 10))
        s.effort = Int16(min(max(Int(effort), 0), 10))
        s.instrument = instrumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        s.durationSeconds = Int64(totalDurationSeconds)

        // Upsert tags from CSV (case-insensitive)
        do {
            let tags = try TagCanonicalizer.upsertCSV(in: ctx, csv: tagsCSV)
            s.removeFromTags((s.tags) ?? NSSet()) // clear existing
            for t in tags { s.addToTags(t) }
        } catch {
            // If tag upsert fails, still attempt to save the session.
        }

        do {
            try ctx.save()
            dismiss()
        } catch {
            if !isEditing { ctx.delete(s) } // rollback create failure
        }
    }
}

// MARK: - DurationEditor subview (text fields + +/- buttons)
private struct DurationEditor: View {
    @Binding var minutes: String
    @Binding var seconds: String

    let incMin: () -> Void
    let decMin: () -> Void
    let incSec: () -> Void
    let decSec: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Minutes row
            HStack(spacing: 8) {
                TextField("0", text: $minutes)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 52)
                    .onChange(of: minutes) { _, new in
                        sanitizeMinutes(new)
                    }
                Text("min").foregroundStyle(.secondary)
                StepButton(system: "minus.circle.fill", action: decMin)
                StepButton(system: "plus.circle.fill", action: incMin)
            }

            // Seconds row
            HStack(spacing: 8) {
                TextField("0", text: $seconds)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 52)
                    .onChange(of: seconds) { _, new in
                        sanitizeSeconds(new)
                    }
                Text("sec").foregroundStyle(.secondary)
                StepButton(system: "minus.circle.fill", action: decSec)
                StepButton(system: "plus.circle.fill", action: incSec)
            }
        }
    }

    private func sanitizeMinutes(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value { minutes = digits }
        if digits.count > 5 { minutes = String(digits.prefix(5)) }
    }

    private func sanitizeSeconds(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value { seconds = digits }
        if let n = Int(digits), n > 59 { seconds = "59" }
        if digits.count > 2 { seconds = String(digits.prefix(2)) }
    }
}

private struct StepButton: View {
    let system: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 32, minHeight: 32)
        .contentShape(Rectangle())
    }
}
