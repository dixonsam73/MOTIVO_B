//
//  FollowStore+Backend.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-FollowStoreExt-ce22
//  SCOPE: v7.12C — additive helpers for backend preview logging
//
//  This file adds non-invasive helpers to FollowStore. No behaviour changes.
//

import Foundation

extension FollowStore {
    var backendEnv: BackendEnvironment { BackendEnvironment.shared }

    @MainActor
    func _backendPreviewLog(_ action: String, meta: [String: String] = [:]) {
        Task { @MainActor in
            if backendEnv.isPreview {
                await BackendDiagnostics.shared.simulatedCall("FollowStore.\(action)", meta: meta)
            }
        }
    }
}
