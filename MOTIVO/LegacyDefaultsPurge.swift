//
//  LegacyDefaultsPurge.swift
//  MOTIVO
//
//  Created by ChatGPT on 2025-11-03.
//  CHANGE-ID: 20251103_094600-legacy-defaults-purge-v1
//  SCOPE: One-time purge of legacy large UserDefaults keys for staged media blobs.
//  Notes:
//  - This file is intentionally standalone and has ZERO dependencies on PracticeTimerView.
//  - It safely removes any old keys that might store large media bytes in UserDefaults to
//    prevent CFPreferences/NSUserDefaults 4 MB warnings on fresh runs.
//

import Foundation

/// Purges legacy large UserDefaults values that were used to stage media (audio/video/images)
/// directly in preferences. This avoids the CFPreferences 4 MB limit warning seen on first save
/// after a fresh run. Safe to call multiple times; it will no-op after the first successful run.
enum LegacyDefaultsPurge {
    private static let sentinelKey = "LegacyDefaultsPurge_V1_Completed"
    private static let explicitLegacyKeys: [String] = [
        // Known/likely historical keys used by PracticeTimerView for staged media blobs.
        "PracticeTimer.stagedAudio",
        "PracticeTimer.stagedVideo",
        "PracticeTimer.stagedImages"
    ]

    /// Run once (idempotent). Removes explicit legacy keys and any other keys that match
    /// "PracticeTimer.staged*" just in case earlier variants exist.
    static func runOnce() {
        let d = UserDefaults.standard
        if d.bool(forKey: sentinelKey) { return }

        // Remove explicit keys if present
        for key in explicitLegacyKeys {
            if d.object(forKey: key) != nil {
                d.removeObject(forKey: key)
            }
        }

        // Defensive sweep: remove any keys that look like PracticeTimer staged blobs
        let dict = d.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("PracticeTimer.staged") {
            d.removeObject(forKey: key)
        }

        // Mark complete so we don't repeat work
        d.set(true, forKey: sentinelKey)
        d.synchronize()
    }
}
