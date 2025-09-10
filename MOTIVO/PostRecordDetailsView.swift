//
//  PostRecordDetailsView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct PostRecordDetailsView: View {
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    // Inputs from timer
    let proposedTitle: String
    let startedAt: Date
    let durationSeconds: Int
    let notes: String
    let instrumentName: String
    let onSaved: () -> Void

    // Local form
    @State private var title: String = ""
    @State private var when: Date = Date()
    @State private var isPublic: Bool = false
    @State private var mood: Double = 5
    @State private var effort: Double = 5
    @State private var selectedInstrument: String = ""
    @State private var tagsCSV: String = ""
    @State private var extraNotes: String = ""
    @State private var userEditedTitle: Bool = false

    // Instruments for picker
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    var body: some View {
        NavigationView {
            Form {
                // Title (no header)
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.words)
                    .onChange(of: title) { _, _ in userEditedTitle = true }

                // When & duration (compact, no header)
                DatePicker("Start", selection: $when, displayedComponents: [.date, .hourAndMinute])
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(formatDuration(durationSeconds))
                        .foregroundStyle(.secondary)
                }

                // Instrument (no header)
                Picker("Instrument", selection: $selectedInstrument) {
                    Text("—").tag("")
                    ForEach(instrumentNames, id: \.self) { ins in
                        Text(ins).tag(ins)
                    }
                }
                .onChange(of: selectedInstrument) { old, new in
                    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    let newAuto = trimmed.isEmpty ? "Practice Session" : "\(trimmed) Practice"
                    if !userEditedTitle || title == autoTitleForInstrument(old) || title == proposedTitle {
                        title = newAuto
                        userEditedTitle = false
                    }
                }

                // Privacy & Feel (kept grouped)
                Section(header: Text("Privacy & Feel")) {
                    Toggle("Public", isOn: $isPublic)
                    VStack(alignment: .leading) {
                        HStack { Text("Mood"); Spacer(); Text("\(Int(mood))").foregroundStyle(.secondary) }
                        Slider(value: $mood, in: 0...10, step: 1)
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("Effort"); Spacer(); Text("\(Int(effort))").foregroundStyle(.secondary) }
                        Slider(value: $effort, in: 0...10, step: 1)
                    }
                }

                // Tags (no header)
                TextField("Tags (comma-separated: e.g. scales, repertoire)", text: $tagsCSV)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                // Notes (no header)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $extraNotes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Review & Save")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear { primeForm() }
        }
    }

    // MARK: - Derived
    private var instrumentNames: [String] {
        instruments
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func autoTitleForInstrument(_ instrument: String?) -> String {
        let ins = (instrument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ins.isEmpty ? "Practice Session" : "\(ins) Practice"
    }

    // MARK: - Actions
    private func primeForm() {
        title = proposedTitle
        when = startedAt
        selectedInstrument = instrumentName
        extraNotes = notes

        let fr: NSFetchRequest<Profile> = Profile.fetchRequest()
        fr.fetchLimit = 1
        if let p = try? ctx.fetch(fr).first {
            isPublic = p.defaultPrivacy
        } else {
            isPublic = false
        }
        userEditedTitle = false
    }

    private func save() {
        let s = Session(context: ctx)
        s.id = UUID()
        s.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.notes = extraNotes
        s.timestamp = when
        s.isPublic = isPublic
        s.mood = Int16(min(max(Int(mood), 0), 10))
        s.effort = Int16(min(max(Int(effort), 0), 10))
        s.instrument = selectedInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        s.durationSeconds = Int64(max(0, durationSeconds))

        do {
            let tags = try TagCanonicalizer.upsertCSV(in: ctx, csv: tagsCSV)
            for t in tags { s.addToTags(t) }
        } catch { }

        do {
            try ctx.save()
            onSaved()
            dismiss()
        } catch {
            // Minimal handling
        }
    }
}

// MARK: - Helpers
private func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    if s == 0 { return "\(m)m" }
    return String(format: "%dm %02ds", m, s)
}
