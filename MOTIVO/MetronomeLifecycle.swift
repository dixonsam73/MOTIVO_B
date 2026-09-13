import Foundation

enum MetronomeFailure: Equatable, Sendable {
    case resources, setup, start, interrupted, routeChanged, mediaReset, stoppedAudio
    var explanation: String {
        switch self {
        case .resources: return "The click sounds could not be loaded."
        case .setup, .start: return "Audio could not be started."
        case .interrupted: return "Audio was interrupted. Try again when it is available."
        case .routeChanged: return "The audio output changed. Try again to reconnect."
        case .mediaReset: return "Audio needs to reconnect."
        case .stoppedAudio: return "Audio stopped. Try again to reconnect."
        }
    }
}
enum MetronomeAvailability: Equatable, Sendable {
    case stopped, starting, running, unavailable(MetronomeFailure)
}

/// Run identity prevents a queued route/engine event from invalidating a newer explicit restart.
struct MetronomeLifecycle {
    private(set) var token: UUID?
    private(set) var availability: MetronomeAvailability = .stopped
    mutating func begin() -> UUID {
        let value = UUID()
        token = value
        availability = .starting
        return value
    }
    mutating func started(_ value: UUID, audioRunning: Bool) -> Bool {
        guard token == value, availability == .starting else { return false }
        availability = audioRunning ? .running : .unavailable(.start)
        return audioRunning
    }
    @discardableResult mutating func fail(_ failure: MetronomeFailure, token value: UUID) -> Bool {
        guard token == value else { return false }
        switch availability {
        case .starting, .running: availability = .unavailable(failure); return true
        case .stopped, .unavailable: return false
        }
    }
    mutating func stop() { token = nil; availability = .stopped }
}
