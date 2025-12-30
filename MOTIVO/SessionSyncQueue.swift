//
//  SessionSyncQueue.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-SessionSyncQueue-a9e1-fix2
//  SCOPE: v7.12D — Deferred local publish queue (no networking)
//  CHANGE-ID: 20251230-SessionSyncQueue-6A-wire-preview-upload
//  SCOPE: v7.12D — Step 6A minimal real-call wiring (preview only)
//  CHANGE-ID: 20251230_210900-SessionSyncQueue-NSLogFlush
//  SCOPE: Step 7 — Ensure flush path is visible in Xcode console and always attempts upload in Backend Preview
//

import Foundation

@MainActor
public final class SessionSyncQueue: ObservableObject {
    public static let shared = SessionSyncQueue()

    public struct Item: Codable, Identifiable, Equatable {
        public let id: UUID          // postID
        public let createdAt: Date
        public var attempts: Int
        public var lastError: String?

        public init(id: UUID, createdAt: Date = .init(), attempts: Int = 0, lastError: String? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.attempts = attempts
            self.lastError = lastError
        }
    }

    @Published public private(set) var items: [Item] = []
    private let fileURL: URL

    private init() {
        self.fileURL = SessionSyncQueue.makeFileURL()
        self.items = (try? Self.load(from: fileURL)) ?? []
    }

    // MARK: - Public API

    public func enqueue(postID: UUID) {
        guard items.contains(where: { $0.id == postID }) == false else { return }
        items.append(Item(id: postID))
        persist()
        BackendLogger.notice("Queue enqueue • postID=\(postID.uuidString) • total=\(items.count)")
    }

    public func dequeue(postID: UUID) {
        items.removeAll { $0.id == postID }
        persist()
        BackendLogger.notice("Queue dequeue • postID=\(postID.uuidString) • total=\(items.count)")
    }

    public func clear() {
        items.removeAll()
        persist()
        BackendLogger.notice("Queue cleared")
    }

    /// Flush now. In Backend Preview: prints simulated upload logs and drains on success.
    /// In Local Simulation: logs and keeps items to reflect "waiting to publish".
    public func flushNow() async {
        let mode = BackendEnvironment.shared.mode
        NSLog("[SessionSyncQueue] flushNow requested • mode=%@ • queued=%d", String(describing: mode), items.count)
        BackendLogger.notice("Flush requested • mode=\(String(describing: mode)) • queued=\(items.count)")

        if mode == .backendPreview {
            for item in items {
                let result = await BackendEnvironment.shared.publish.uploadPost(item.id)
                switch result {
                case .success:
                    NSLog("[SessionSyncQueue] upload success • postID=%@", item.id.uuidString)
                    BackendLogger.notice("Preview upload success • postID=\(item.id.uuidString)")
                    self.dequeue(postID: item.id)
                case .failure(let error):
                    NSLog("[SessionSyncQueue] upload failed • postID=%@ • error=%@", item.id.uuidString, error.localizedDescription)
                    BackendLogger.notice("Preview upload failed • postID=\(item.id.uuidString) • error=\(error.localizedDescription)")
                    // Preserve semantics: failures remain queued; no retries/timers added here.
                }
            }
            NSLog("[SessionSyncQueue] flushNow completed • remaining=%d", items.count)
            BackendLogger.notice("Flush completed • remaining=\(items.count)")
        } else {
            NSLog("[SessionSyncQueue] flushNow skipped (local-simulation) • remaining=%d", items.count)
            BackendLogger.notice("Flush skipped (local-simulation) • remaining=\(items.count)")
        }
    }


    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            BackendLogger.notice("Queue persist error • \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) throws -> [Item] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Item].self, from: data)
    }

    private static func makeFileURL() -> URL {
        let fm = FileManager.default
        let dir = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MOTIVO", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SessionSyncQueue_v1.json")
    }
}
