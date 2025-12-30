// CHANGE-ID: 20251230_200530-BackendDiagnostics-PreviewToHTTP
// SCOPE: Step 7 — Log simulated calls only when BackendEnvironment is in simulated preview

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
        if BackendEnvironment.shared.isPreview {
            let metaString = meta.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            print("🌐 [Simulated API] \(name) \(metaString)")
        } else {
            // In local simulation mode, remain quiet to avoid console noise.
        }
    }
}
