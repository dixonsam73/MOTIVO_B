//
//  BackendDiagnostics.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-BackendDiagnostics-f91e
//  SCOPE: v7.12C — simulated call logging
//

import Foundation

public final class BackendDiagnostics {
    public static let shared = BackendDiagnostics()
    private init() {}

    @MainActor
    public func simulatedCall(_ name: String, meta: [String: String] = [:]) async {
        // Small artificial delay to mimic an async hop (kept tiny for UX safety).
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        let mode = currentBackendMode()
        if mode == .backendPreview {
            let metaString = meta.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            print("🌐 [Simulated API] \(name) \(metaString)")
        } else {
            // In local simulation mode, remain quiet to avoid console noise.
        }
    }
}
