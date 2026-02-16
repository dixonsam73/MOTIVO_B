//
//  SessionActivityType.swift
//  MOTIVO
//
//  Centralized core activity enum shared across the app.
//
import Foundation

public enum SessionActivityType: Int16, CaseIterable, Identifiable {
    case practice = 0, rehearsal = 1, recording = 2, lesson = 3, performance = 4, writing = 5

    public var id: Int16 { rawValue }

    public var label: String {
        switch self {
        case .practice:    return "Practice"
        case .rehearsal:   return "Rehearsal"
        case .recording:   return "Recording"
        case .lesson:      return "Lesson"
        case .performance: return "Performance"
        case .writing:     return "Writing"
        }
    }

    public static func from(_ raw: Int16?) -> SessionActivityType {
        SessionActivityType(rawValue: raw ?? 0) ?? .practice
    }
}
