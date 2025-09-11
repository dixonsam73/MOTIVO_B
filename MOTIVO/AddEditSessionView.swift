//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Close-first, then save
    @Binding var isPresented: Bool

    var session: Session? = nil

    @State private var instrument: Instrument?
    @State private var title = ""
    @State private var timestamp = Date()
    @State private var durationSeconds = 0
    @State private var isPublic = true
    @State private var mood = 5
    @State private var effort = 5
    @State private var tagsText = ""
    @State private var notes = ""

    @State private var showStartPicker = false
    @State private var showDurationPicker = false
    @State private var tempDate = Date()
    @State private var tempHours = 0
    @State private var tempMinutes = 0

    @State private var isSaving = false
    @State private var isTitleEdited = false
    @State private var initialAutoTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Instrument", selection: $instrument) {
                        ForEach(fetchInstruments(), id: \.self) { inst in
                            Text(inst.name ?? "").tag(inst as Instrument?)
                        }
                    }
                }
                Section {
                    TextField("Title", text: $title)
                        .onChange(of: title) { _, newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != initialAutoTitle {
                                isTitleEdited = true
                            }
                        }
                }
                Section {
                    Button {
                        tempDate = timestamp
                        showStartPicker = true
                    } label: {
                        HStack { Text("Start Time"); Spacer(); Text(formattedDate(timestamp)).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button {
                        (tempHours, tempMinutes) = secondsToHM(durationSeconds)
                        showDurationPicker = true
                    } label: {
                        HStack { Text("Duration"); Spacer(); Text(formattedDuration(durationSeconds)).foregroundStyle(.secondary) }
                    }
                    if durationSeconds == 0 {
                        Text("Duration must be greater than 0").font(.footnote).foregroundColor(.red)
                    }
                }
                Section { Toggle("Public", isOn: $isPublic) }
                Section("Mood & Effort") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Mood"); Spacer(); Text("\(mood)").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { Double(mood) }, set: { mood = Int($0.rounded()) }), in: 0...10, step: 1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("Effort"); Spacer(); Text("\(effort)").foregroundStyle(.secondary) }
                        Slider(value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 0...10, step: 1)
                    }
                }
                Section { TextField("Tags (comma-separated)", text: $tagsText) }

                // Notes with placeholder
                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Notes")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle(session == nil ? "New Session" : "Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !isSaving else { return }
                        isSaving = true
                        // 1) Close immediately
                        isPresented = false
                        // 2) Save on next tick (after the sheet is gone)
                        DispatchQueue.main.async {
                            saveToCoreData()
                        }
                    } label: { Text("Save") }
                    .disabled(isSaving || durationSeconds == 0 || instrument == nil)
                }
            }
            .sheet(isPresented: $showStartPicker) {
                NavigationStack {
                    VStack {
                        DatePicker("", selection: $tempDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                        Spacer()
                    }
                    .navigationTitle("Start Time")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showStartPicker = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { timestamp = tempDate; showStartPicker = false } }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showDurationPicker) {
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
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { durationSeconds = (tempHours * 3600) + (tempMinutes * 60); showDurationPicker = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear { loadSession() }
            .onChange(of: instrument) { _, _ in
                guard !isTitleEdited else { return }
                let auto = defaultTitle(); title = auto; initialAutoTitle = auto
            }
        }
    }

    private func loadSession() {
        if let s = session {
            instrument = s.instrument
            title = s.title ?? ""
            timestamp = s.timestamp ?? Date()
            durationSeconds = Int(s.durationSeconds)
            isPublic = s.isPublic
            mood = Int(s.mood); effort = Int(s.effort)
            tagsText = ((s.tags as? Set<Tag>) ?? [])
                .compactMap { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .joined(separator: ", ")
            notes = s.notes ?? ""
            let auto = defaultTitle(for: s.instrument)
            initialAutoTitle = auto
            isTitleEdited = !(title.isEmpty || title == auto)
            if title.isEmpty { title = auto }
        } else {
            let auto = defaultTitle()
            title = auto; initialAutoTitle = auto; isTitleEdited = false
        }
    }

    private func saveToCoreData() {
        let s = session ?? Session(context: viewContext)
        s.instrument = instrument
        s.title = title.isEmpty ? defaultTitle() : title
        s.timestamp = timestamp
        s.durationSeconds = Int64(durationSeconds)
        s.isPublic = isPublic
        s.mood = Int16(mood)
        s.effort = Int16(effort)
        s.notes = notes

        let tagNames = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        s.tags = NSSet(array: upsertTags(tagNames))

        do { try viewContext.save() } catch { print("Error saving session: \(error)") }
    }

    // Helpers
    private func defaultTitle(for inst: Instrument? = nil) -> String {
        if let name = (inst ?? instrument)?.name, !name.isEmpty { return "\(name) Practice" }
        return "Practice"
    }
    private func fetchInstruments() -> [Instrument] {
        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return (try? viewContext.fetch(req)) ?? []
    }
    private func upsertTags(_ names: [String]) -> [Tag] {
        var results: [Tag] = []
        for name in names {
            let req: NSFetchRequest<Tag> = Tag.fetchRequest()
            req.predicate = NSPredicate(format: "name ==[c] %@", name)
            if let existing = (try? viewContext.fetch(req))?.first { results.append(existing) }
            else { let t = Tag(context: viewContext); t.name = name; results.append(t) }
        }
        return results
    }
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.doesRelativeDateFormatting = true; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    private func formattedDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private func secondsToHM(_ seconds: Int) -> (Int, Int) {
        let h = seconds / 3600; let m = (seconds % 3600) / 60; return (h, m)
    }
}
