//
//  FeedInteractionStore+Backend.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-FeedInteractionStoreExt-9b77
//  SCOPE: v7.12C — additive helpers for backend preview logging
//
//  This file adds non-invasive helpers to FeedInteractionStore. No behaviour changes.
//

import Foundation

extension FeedInteractionStore {
    var backendEnv: BackendEnvironment { BackendEnvironment.shared }

    @MainActor
    func _backendPreviewLog(_ action: String, meta: [String: String] = [:]) {
        Task { @MainActor in
            if backendEnv.isPreview {
                await BackendDiagnostics.shared.simulatedCall("FeedInteractionStore.\(action)", meta: meta)
            }
        }
    }
}
