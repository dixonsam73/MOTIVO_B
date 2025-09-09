//
//  AddEditSessionView.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 09/09/2025.
//

import SwiftUI
import CoreData

struct AddEditSessionView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    // If nil = creating; if non-nil = editing this session
    let session: Session?

    // Fetches (string-key to avoid keypath inference issues)
    @FetchRequest(
        entity: Instrument.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var instruments: FetchedResults<Instrument>

    @FetchRequest(entity: Profile.entity(), sortDescriptors: [])
    private var profiles: FetchedResults<Profile>

    // Form state
    @State private var selectedInstrument: String = ""     // NEW
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var when: Date = Date()
    @State private var durationSeconds: Int = 0
    @State private var isPublic: Bool = true
    @State private var mood: Double = 5
    @State private var effort: Double = 5
    @State private var tagsInput: String = "" // comma-separated
    @State private var didAutoSetTitle: Bool = true        // NEW

    @State private var showingInstruments = false          // NEW

    // MARK: - Init overloads for backwards compatibility
    init() { self.session = nil }                    // ContentView calls this for “Add manually”
    init(session: Session) { self.session = session } // Detail view will use this for Edit

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Instrument + manage (affects default title)
                Section("Instrument") {
                    HStack {
                        Picker("Instrument", selection: $selectedInstrument) {
                            ForEach(instrumentList(), id: \.self) { inst in
                                Text(inst).tag(inst)
                            }
                        }
                        Button {
                            showingInstruments = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel("Manage Instruments")
                    }
                    .onChange(of: selectedInstrument) { _, newValue in
                        // Only auto-update title if the user hasn't customized it
                        if didAutoSetTitle {
                            title = defaultTitle(for: newValue)
                        }
                    }
                }

                // MARK: Session basics
                Section("Session") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                        .onChange(of: title) { _, newValue in
                            let def = defaultTitle(for: selectedInstrument)
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            didAutoSetTitle = (trimmed.isEmpty || trimmed == def)
                        }

                    DatePicker("When", selection: $when, displayedComponents: [.date, .hourAndMinute])

                    DurationEditor(seconds: $durationSeconds)

                    Toggle("Public", isOn: $isPublic)
                }

                Section("How it felt") {
                    sliderRow("Mood", value: $mood)
                    sliderRow("Effort", value: $effort)
                }

                Section("Tags") {
                    TextField("Add tags (comma-separated)", text: $tagsInput)
                    Text("Example: scales, tone, repertoire")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextField("What did you work on?", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle(session == nil ? "Add Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(durationSeconds <= 0 && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingInstruments) {
                InstrumentListView()
                    .environment(\.managedObjectContext, moc)
            }
            .onAppear { seedForm() }
        }
    }

    // MARK: - Derived data

    private func instrumentList() -> [String] {
        // Prefer Instrument entities; fallback to profile primary; else "Practice"
        var names: [String] = instruments.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
        names = names.filter { !$0.isEmpty }
        if names.isEmpty {
            let primary = profiles.first?.primaryInstrument?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return primary.isEmpty ? ["Practice"] : [primary]
        }
        return names
    }

    private func defaultTitle(for instrument: String) -> String {
        let inst = instrument.trimmingCharacters(in: .whitespacesAndNewlines)
        return (inst.isEmpty || inst.lowercased() == "practice") ? "Practice Session" : "\(inst) Practice"
    }

    // MARK: - Actions

    private func seedForm() {
        // Choose instrument first (affects title default)
        let list = instrumentList()
        selectedInstrument = list.first ?? "Practice"

        if let s = session {
            // Existing session → load values
            title = (s.title ?? "")
            notes = (s.notes ?? "")
            when = s.timestamp ?? Date()
            durationSeconds = max(0, Int(s.durationSeconds))
            isPublic = s.isPublic
            mood = Double(s.mood)
            effort = Double(s.effort)

            if let set = s.tags as? Set<Tag> {
                let names = set
                    .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .sorted()
                tagsInput = names.joined(separator: ", ")
            } else {
                tagsInput = ""
            }

            // If the stored title matches the default, keep auto-title behavior ON
            let def = defaultTitle(for: selectedInstrument)
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            didAutoSetTitle = (trimmed.isEmpty || trimmed == def)
            if trimmed.isEmpty { title = def }
        } else {
            // New session defaults
            let def = defaultTitle(for: selectedInstrument)
            title = def
            notes = ""
            when = Date()
            durationSeconds = 0
            isPublic = true
            mood = 5
            effort = 5
            tagsInput = ""
            didAutoSetTitle = true
        }
    }

    private func save() {
        let s: Session = session ?? Session(context: moc)
        if s.id == nil { s.id = UUID() }

        // Title (respect user override; otherwise default from instrument)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = trimmedTitle.isEmpty ? defaultTitle(for: selectedInstrument) : trimmedTitle

        s.notes = notes
        s.timestamp = when
        s.durationSeconds = Int64(max(0, durationSeconds))
        s.isPublic = isPublic
        s.mood = Int16(clamp(mood, 0, 10))
        s.effort = Int16(clamp(effort, 0, 10))

        // Upsert tags
        let names = tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var newTagObjects: [Tag] = []
        for name in names {
            if let existing = fetchTag(named: name) {
                newTagObjects.append(existing)
            } else {
                let t = Tag(context: moc)
                t.id = UUID()
                t.name = name
                newTagObjects.append(t)
            }
        }
        s.tags = NSSet(array: newTagObjects)

        try? moc.save()
        dismiss()
    }

    private func fetchTag(named: String) -> Tag? {
        let req: NSFetchRequest<Tag> = Tag.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "name ==[c] %@", named)
        return try? moc.fetch(req).first
    }

    private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }

    // MARK: - Tiny UI bits

    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: 0...10, step: 1)
            Text("\(Int(value.wrappedValue))").frame(width: 28, alignment: .trailing)
        }
    }
}

// Simple editor: minutes & seconds with normalization to total seconds
private struct DurationEditor: View {
    @Binding var seconds: Int
    @State private var minutesPart: Int = 0
    @State private var secondsPart: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Duration")
                Spacer()
                Text(formatted(seconds))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Stepper(value: $minutesPart, in: 0...599) {
                    Text("\(minutesPart) min")
                }
                Stepper(value: $secondsPart, in: 0...59) {
                    Text("\(secondsPart) sec")
                }
            }
        }
        .onAppear {
            minutesPart = seconds / 60
            secondsPart = seconds % 60
        }
        .onChange(of: minutesPart) { _, _ in
            seconds = minutesPart * 60 + secondsPart
        }
        .onChange(of: secondsPart) { _, _ in
            seconds = minutesPart * 60 + secondsPart
        }
    }

    private func formatted(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
