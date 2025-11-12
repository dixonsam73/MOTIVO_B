//
//  SyncQueueSection.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-SyncQueueSection-d2f7
//  SCOPE: v7.12D — Debug panel section for SessionSyncQueue
//

import SwiftUI

public struct SyncQueueSection: View {
    @ObservedObject private var queue = SessionSyncQueue.shared
    @State private var isFlushing = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish Queue").font(.headline)

            HStack {
                Text("Queued: \(queue.items.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isFlushing ? "Flushing…" : "Flush Now") {
                    Task { @MainActor in
                        isFlushing = true
                        defer { isFlushing = false }
                        await queue.flushNow()
                    }
                }
                .disabled(isFlushing || queue.items.isEmpty)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}
