//
//  TimerStateRecovery.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 10/09/2025.
//

import Foundation
import Combine
import SwiftUI

/// Persist + restore timer state across app kills/crashes/backgrounding.
/// Drop-in helper; keeps your existing PracticeTimerView logic intact.
/// Integration notes at bottom of this file.
enum TimerMode: String, Codable {
    case idle
    case running
    case paused
}

struct TimerSnapshot: Codable {
    var mode: TimerMode
    /// When the current run segment started (only meaningful for `.running`)
    var startedAt: Date?
    /// Accumulated elapsed seconds *before* the current run segment.
    var accumulated: Int
    /// Last write timestamp (for sanity checks / drift)
    var savedAt: Date

    static let empty = TimerSnapshot(mode: .idle, startedAt: nil, accumulated: 0, savedAt: Date())
}

final class TimerStateRecovery: ObservableObject {
    static let shared = TimerStateRecovery()

    // MARK: - Storage
    private let ud = UserDefaults.standard
    private let key = "Motivo.TimerState.v1"

    @Published private(set) var snapshot: TimerSnapshot = .empty

    private init() {
        load()
    }

    // MARK: - Public API

    /// Call when user taps Start. Resets `startedAt` and keeps any existing accumulated if resuming.
    func start(resumeFrom accumulated: Int = 0, at date: Date = Date()) {
        snapshot = TimerSnapshot(mode: .running, startedAt: date, accumulated: accumulated, savedAt: date)
        save()
    }

    /// Call when user taps Pause. Freezes elapsed into accumulated.
    func pause(at date: Date = Date()) {
        guard snapshot.mode == .running, let began = snapshot.startedAt else { return }
        let run = max(0, Int(date.timeIntervalSince(began)))
        snapshot = TimerSnapshot(mode: .paused, startedAt: nil, accumulated: snapshot.accumulated + run, savedAt: date)
        save()
    }

    /// Call when user taps Resume from paused.
    func resume(at date: Date = Date()) {
        guard snapshot.mode == .paused else { return }
        snapshot = TimerSnapshot(mode: .running, startedAt: date, accumulated: snapshot.accumulated, savedAt: date)
        save()
    }

    /// Call when user taps Finish OR discards the timer.
    func clear() {
        snapshot = .empty
        ud.removeObject(forKey: key)
    }

    /// Total elapsed seconds at this instant (accumulated + current segment if running).
    func elapsedSeconds(now: Date = Date()) -> Int {
        switch snapshot.mode {
        case .idle:   return 0
        case .paused: return max(0, snapshot.accumulated)
        case .running:
            let seg = max(0, Int(now.timeIntervalSince(snapshot.startedAt ?? now)))
            return max(0, snapshot.accumulated + seg)
        }
    }

    // MARK: - App lifecycle helpers

    /// Call on scenePhase changes to autosave when moving to background/inactive.
    func scenePhaseDidChange(_ phase: ScenePhase, now: Date = Date()) {
        switch phase {
        case .active:
            // No-op (load already occurred in init/onAppear)
            break
        case .inactive, .background:
            // Evaluate current elapsed (suppresses unused-value warning while keeping semantics)
            _ = elapsedSeconds(now: now)

            switch snapshot.mode {
            case .idle:
                break
            case .paused:
                snapshot.savedAt = now
                save()
            case .running:
                // Seal the current segment into accumulated and continue from `now` to avoid drift.
                let began = snapshot.startedAt ?? now
                let seg = max(0, Int(now.timeIntervalSince(began)))
                snapshot.accumulated += seg
                snapshot.startedAt = now
                snapshot.savedAt = now
                save()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = ud.data(forKey: key) else {
            snapshot = .empty
            return
        }
        do {
            let snap = try JSONDecoder().decode(TimerSnapshot.self, from: data)
            snapshot = snap
        } catch {
            // Corrupt payload; reset safely
            snapshot = .empty
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(snapshot)
            ud.set(data, forKey: key)
        } catch {
            // Best-effort persistence; timer UX should keep working regardless.
        }
    }
}

// MARK: - Integration Notes (keep in comments; no previews)

/*
 In PracticeTimerView:

 1) Hold a reference:
    @StateObject private var recovery = TimerStateRecovery.shared

 2) On appear, optionally adopt recovered state:
    .onAppear {
        let recovered = recovery.snapshot
        switch recovered.mode {
        case .idle:
            // start fresh UI
            break
        case .paused:
            // reflect accumulated = recovery.elapsedSeconds()
            // state = .paused, set displayed elapsed accordingly
            break
        case .running:
            // state = .running
            // displayed elapsed = recovery.elapsedSeconds()
            break
        }
    }

 3) Wire user actions:
    - Start:  recovery.start(resumeFrom: currentAccumulated)
    - Pause:  recovery.pause()
    - Resume: recovery.resume()
    - Finish: recovery.clear()   (after you’ve saved a Session)

 4) Track scene phase to autosave/roll-over segments:
    @Environment(\.scenePhase) var scenePhase
    .onChange(of: scenePhase) { _, newPhase in
        recovery.scenePhaseDidChange(newPhase)
    }

 5) To render elapsed “clock-true”:
    - Continue your existing Timer.publish/DisplayLink.
    - For the displayed value, prefer `recovery.elapsedSeconds(now: Date())`
      combined with your formatter, so UI and persistence stay aligned.

 This helper intentionally avoids any dependency on your Session model to keep it reusable.
*/
