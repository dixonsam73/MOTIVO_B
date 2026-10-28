//
//  SyncRecoveryView.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  The person's view of what sync displaced (stage J): one card per conflict
//  with the value that lost, Copy, and Restore where the app can apply it as
//  a new edit. Not a version history.
//

#if SYNCTEST
import SwiftUI

struct SyncRecoveryView: View {
    @State private var entries: [JournalSyncConflict] = []
    @State private var notice: String?

    private var store: JournalSyncStateStore? { JournalSyncCoordinator.shared.store }

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("Nothing has been displaced. When the same entry is edited on two devices before they sync, the later edit is kept and the other appears here.")
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
                                Text(entry.displaced[key] ?? "").font(.body).textSelection(.enabled)
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
        let side = entry.winner == "server" ? "the other device's edit was kept" : (entry.winner == "local" ? "this device's edit was kept" : "merged")
        return "\(f.string(from: entry.at)) · \(side)"
    }
}
#endif
