// CHANGE-ID: 20260521_153000_ContentViewJournalTintResolverPass3
// SCOPE: ContentView Pass 3 — Journal tint derivation only. No UI, filtering, routing, backend, navigation, or state ownership changes.
// SEARCH-TOKEN: 20260521_153000_ContentViewJournalTintResolverPass3

import SwiftUI

struct ContentViewJournalTintResolver {
    static func instrumentLabel(for session: Session) -> String? {
        let explicitLabel = (session.value(forKey: "userInstrumentLabel") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitLabel, !explicitLabel.isEmpty {
            return explicitLabel
        }

        let fallbackName = session.instrument?.name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackName, !fallbackName.isEmpty {
            return fallbackName
        }

        return nil
    }

    static func activityLabel(for session: Session) -> String? {
        let explicitLabel = (session.value(forKey: "userActivityLabel") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitLabel, !explicitLabel.isEmpty {
            return explicitLabel
        }

        if let code = session.value(forKey: "activityType") as? Int16 {
            let fallbackLabel = (ActivityType(rawValue: code) ?? .practice).label.trimmingCharacters(in: .whitespacesAndNewlines)
            return fallbackLabel.isEmpty ? nil : fallbackLabel
        }

        return nil
    }

    static func instrumentOwnerID(for session: Session, fallbackUserID: String?) -> String? {
        let ownerID = session.ownerUserID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let ownerID, !ownerID.isEmpty {
            return ownerID
        }
        return fallbackUserID
    }

    static func instrumentCounts(in sessions: [Session]) -> [String: Int] {
        Theme.usageCounts(
            labels: sessions.compactMap {
                Theme.InstrumentTint.normalizedLabel(instrumentLabel(for: $0))
            }
        )
    }

    static func activityCounts(in sessions: [Session]) -> [String: Int] {
        Theme.usageCounts(
            labels: sessions.compactMap {
                Theme.ActivityTint.normalizedLabel(activityLabel(for: $0))
            }
        )
    }

    static func threadLabel(for session: Session) -> String? {
        let raw = ((session.value(forKey: "threadLabel") as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sanitized = ThreadLabelSanitizer.sanitize(raw, maxLength: 32),
              !sanitized.isEmpty else {
            return nil
        }

        return sanitized
    }

    static func threadCounts(in sessions: [Session]) -> [String: Int] {
        Theme.usageCounts(
            labels: sessions.compactMap {
                Theme.ThreadTint.normalizedLabel(threadLabel(for: $0))
            }
        )
    }

    static func resolvedTintSource(
        in sessions: [Session],
        tintMode: Theme.TintMode
    ) -> Theme.ResolvedTintSource {
        Theme.resolvedTintSource(
            tintMode: tintMode,
            instrumentCounts: instrumentCounts(in: sessions),
            activityCounts: activityCounts(in: sessions),
            threadCounts: threadCounts(in: sessions),
            persistAutoSource: false
        )
    }

    static func resolvedTint(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode
    ) -> Theme.ResolvedTint {
        Theme.resolvedTint(
            instrument: instrumentLabel(for: session),
            activity: activityLabel(for: session),
            thread: threadLabel(for: session),
            tintMode: tintMode,
            instrumentCounts: instrumentCounts(in: sessions),
            activityCounts: activityCounts(in: sessions),
            threadCounts: threadCounts(in: sessions),
            persistAutoSource: false
        )
    }

    static func weekCardFillColor(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode,
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color {
        resolvedTint(for: session, in: sessions, tintMode: tintMode).fill(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    static func weekCardStrokeColor(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode,
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color {
        resolvedTint(for: session, in: sessions, tintMode: tintMode).stroke(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            strength: .cardMedium
        )
    }

    static func monthBarFillColor(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode,
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color {
        if resolvedTint(for: session, in: sessions, tintMode: tintMode).accent(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            shouldAssignIfNeeded: false
        ) != nil {
            return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055)
    }

    static func monthBarStrokeColor(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode,
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color {
        if resolvedTint(for: session, in: sessions, tintMode: tintMode).accent(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            shouldAssignIfNeeded: false
        ) != nil {
            return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05)
    }

    static func monthBarAccentColor(
        for session: Session,
        in sessions: [Session],
        tintMode: Theme.TintMode,
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color? {
        resolvedTint(for: session, in: sessions, tintMode: tintMode).accent(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            shouldAssignIfNeeded: false
        )
    }

    static func thoughtThreadTint(
        for session: Session,
        tintMode: Theme.TintMode,
        contextSessions: [Session]
    ) -> Theme.ResolvedTint? {
        guard tintMode == .thread,
              let thread = threadLabel(for: session),
              !thread.isEmpty else {
            return nil
        }

        return Theme.ResolvedTint(
            source: .thread,
            instrumentLabel: nil,
            activityLabel: nil,
            threadLabel: thread,
            threadCounts: threadCounts(in: contextSessions + [session])
        )
    }

    static func thoughtThreadChipFillColor(
        for session: Session,
        tintMode: Theme.TintMode,
        contextSessions: [Session],
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color? {
        thoughtThreadTint(
            for: session,
            tintMode: tintMode,
            contextSessions: contextSessions
        )?.fill(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            strength: .pickerStrong,
            shouldAssignIfNeeded: false
        )
    }

    static func thoughtThreadChipTextColor(
        for session: Session,
        tintMode: Theme.TintMode,
        contextSessions: [Session],
        fallbackUserID: String?,
        colorScheme: ColorScheme
    ) -> Color? {
        thoughtThreadTint(
            for: session,
            tintMode: tintMode,
            contextSessions: contextSessions
        )?.stroke(
            ownerID: instrumentOwnerID(for: session, fallbackUserID: fallbackUserID),
            scheme: colorScheme,
            strength: .pickerStrong,
            shouldAssignIfNeeded: false
        )
    }
}
