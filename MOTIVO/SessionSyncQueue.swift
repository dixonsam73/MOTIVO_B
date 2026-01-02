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

    public struct PostPublishPayload: Codable, Identifiable {
      public let id: UUID            // == postID
      public let sessionID: UUID?
      public let sessionTimestamp: Date?
      public let title: String?
      public let durationSeconds: Int?
      public let activityType: String?
      public let activityDetail: String?
      public let instrumentLabel: String?
      public let mood: Int?
      public let effort: Int?

      public init(id: UUID, sessionID: UUID?, sessionTimestamp: Date?, title: String?, durationSeconds: Int?, activityType: String?, activityDetail: String?, instrumentLabel: String?, mood: Int?, effort: Int?) {
          self.id = id
          self.sessionID = sessionID
          self.sessionTimestamp = sessionTimestamp
          self.title = title
          self.durationSeconds = durationSeconds
          self.activityType = activityType
          self.activityDetail = activityDetail
          self.instrumentLabel = instrumentLabel
          self.mood = mood
          self.effort = effort
      }
    }

    @Published public private(set) var items: [PostPublishPayload] = []
    private let fileURL: URL

    private init() {
        self.fileURL = SessionSyncQueue.makeFileURL()
        self.items = (try? Self.load(from: fileURL)) ?? []
    }

    // MARK: - Public API

    public func enqueue(_ payload: PostPublishPayload) {
        guard items.contains(where: { $0.id == payload.id }) == false else { return }
        items.append(payload)
        persist()
        BackendLogger.notice("Queue enqueue • postID=\(payload.id.uuidString) • total=\(items.count)")
    }

    public func enqueue(postID: UUID) {
        guard items.contains(where: { $0.id == postID }) == false else { return }
        let payload = PostPublishPayload(id: postID, sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil, activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil)
        enqueue(payload)
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
            for payload in items {
                let result = await BackendEnvironment.shared.publish.uploadPost(payload)
                switch result {
                case .success:
                    NSLog("[SessionSyncQueue] upload success • postID=%@", payload.id.uuidString)
                    BackendLogger.notice("Preview upload success • postID=\(payload.id.uuidString)")
                    self.dequeue(postID: payload.id)
                case .failure(let error):
                    NSLog("[SessionSyncQueue] upload failed • postID=%@ • error=%@", payload.id.uuidString, error.localizedDescription)
                    BackendLogger.notice("Preview upload failed • postID=\(payload.id.uuidString) • error=\(error.localizedDescription)")
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

    private static func load(from url: URL) throws -> [PostPublishPayload] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        if let new = try? decoder.decode([PostPublishPayload].self, from: data) {
            return new
        }
        if let old = try? decoder.decode([UUID].self, from: data) {
            return old.map { uuid in
                PostPublishPayload(id: uuid, sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil, activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil)
            }
        }
        // If neither format matches, propagate a decoding error
        return try decoder.decode([PostPublishPayload].self, from: data)
    }

    private static func makeFileURL() -> URL {
        let fm = FileManager.default
        let dir = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MOTIVO", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SessionSyncQueue_v1.json")
    }
}

