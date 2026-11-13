//
//  SyncRecoveryView.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  The person's view of what sync displaced (stage J): one card per conflict
//  with the value that lost, Copy, and Restore where the app can apply it as
//  a new edit. Not a version history.
//

import SwiftUI

struct SyncRecoveryView: View {
    @State private var entries: [JournalSyncConflict] = []
    @State private var notice: String?

    private var store: JournalSyncStateStore? { JournalSyncCoordinator.shared.store }

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("Nothing has been displaced. When the same entry differs on two devices, one version is kept in the journal (the later edit, or iCloud's when that cannot be told) and the other appears here, with Restore. An entry that was deleted on another device before this one first synced is kept here too.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(entries) { entry in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.subject.isEmpty ? entry.recordType : entry.subject).font(.headline)
                        Text(describeWhen(entry)).font(.caption).foregroundStyle(.secondary)
                        if let restore = entry.restore, restore.hasPrefix("avatar:"),
                           let image = UIImage(contentsOfFile: String(restore.dropFirst("avatar:".count))) {
                            Image(uiImage: image).resizable().scaledToFit().frame(width: 96, height: 96).clipShape(Circle())
                        }
                        ForEach(entry.displaced.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                                // An empty value is a cleared one: the losing edit removed the text.
                                if (entry.displaced[key] ?? "").isEmpty { Text("Cleared").font(.body).italic().foregroundStyle(.secondary) }
                                else { Text(entry.displaced[key] ?? "").font(.body).textSelection(.enabled) }
                            }
                        }
                        HStack {
                            if entry.hasRecoverableText {
                                Button("Copy") {
                                    UIPasteboard.general.string = JournalRecovery.copyText(of: entry)
                                    notice = "Copied"
                                }
                            }
                            if entry.restore != nil {
                                Button("Restore") {
                                    guard let store else { return }
                                    switch JournalRecovery.restore(entry, store: store) {
                                    case .restored(let text): notice = text
                                    case .failed(let text): notice = text
                                    }
                                    reload()
                                }
                            }
                            Spacer()
                            Button("Dismiss", role: .destructive) {
                                guard let store else { return }
                                JournalRecovery.dismiss(entry, store: store)
                                reload()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Displaced by sync")
        .onAppear(perform: reload)
        .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        }
    }

    private func reload() {
        guard let store else { entries = []; return }
        entries = JournalRecovery.entries(store: store)
    }

    private func describeWhen(_ entry: JournalSyncConflict) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        let side: String
        switch entry.winner {
        case "server": side = "the other device's version was kept"
        case "local": side = "this device's version was kept"
        case "deleted": side = "deleted on another device; this device's copy is kept here"
        default: side = "merged"
        }
        return "\(f.string(from: entry.at)) · \(side)"
    }
}
