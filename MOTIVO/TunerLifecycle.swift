import Foundation

enum TunerFailure: Equatable, Sendable {
    case inputUnavailable, engineStart, interrupted, routeChanged, mediaReset

    var explanation: String {
        switch self {
        case .inputUnavailable: return "No microphone input is available."
        case .engineStart: return "The microphone could not be started."
        case .interrupted: return "Audio was interrupted. Try again when it is available."
        case .routeChanged: return "The audio input changed. Try again to use the current input."
        case .mediaReset: return "Audio needs to reconnect."
        }
    }
}

enum TunerAvailability: Equatable, Sendable {
    case stopped, requestingPermission, starting, listening, permissionDenied
    case unavailable(TunerFailure)
}

/// Pure run-token/phase policy. Late permission, audio and observer callbacks cannot revive a run.
struct TunerLifecycle {
    private(set) var token: UUID?
    private(set) var availability: TunerAvailability = .stopped

    mutating func begin(needsPermission: Bool) -> UUID {
        let value = UUID()
        token = value
        availability = needsPermission ? .requestingPermission : .starting
        return value
    }

    mutating func resolvePermission(granted: Bool, token value: UUID) -> Bool {
        guard token == value,
              availability == .requestingPermission || availability == .starting else { return false }
        availability = granted ? .starting : .permissionDenied
        return granted
    }

    mutating func started(token value: UUID) -> Bool {
        guard token == value, availability == .starting else { return false }
        availability = .listening
        return true
    }

    func acceptsOutput(token value: UUID) -> Bool {
        token == value && availability == .listening
    }

    mutating func fail(_ failure: TunerFailure, token value: UUID) {
        guard token == value else { return }
        availability = .unavailable(failure)
    }

    mutating func stop() {
        token = nil
        availability = .stopped
    }
}
