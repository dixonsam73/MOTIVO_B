//
//  TimerStagedVideo.swift
//  MOTIVO
//
//  C-84 — a Practice Timer video is staged by FILE, not by bytes.
//
//  A capped in-app recording is ~560 MB. Holding it as `Data` meant every
//  restore read the whole file into memory, and a relaunch that restored it
//  could crash the same way that killed it. The bytes live in `StagingStore`;
//  the timer keeps only where they are. They are read once, at the hand-off
//  to post-record details — existing behaviour, outside the relaunch loss.
//

import Foundation

struct TimerStagedVideo: Identifiable, Equatable {
    /// The `StagingStore` ref id — staging is given this id, so it never changes.
    let id: UUID
    /// The staged file. Before `StagingStore.saveNew` completes this is the
    /// recorder's output; afterwards it is the staging file.
    var fileURL: URL
}
