//
//  PracticeTimerDiagnostics.swift
//  MOTIVO
//
//  C-84 — outcome logging for Practice Timer restore and video playback setup,
//  readable on device (`privacy: .public`). Durations, counts and sizes only:
//  no ids, names or paths.
//

import Foundation
import os

enum PracticeTimerDiagnostics {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MOTIVO", category: "PracticeTimer")

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// Memory this process can still allocate before the system would
    /// terminate it, in MB. A restore that loaded staged video would lower it
    /// by the video's size.
    static func headroomMB() -> Int {
        Int(os_proc_available_memory() / 1_048_576)
    }
}
