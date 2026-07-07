//
//  AppModeManager.swift
//  MOTIVO
//
//  Milestone 0: Études / Études Connected architectural foundation.
//

import Foundation
import Combine

public enum AppMode: String, CaseIterable, Identifiable {
    case solo
    case connected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .solo:
            return "Études"
        case .connected:
            return "Études Connected"
        }
    }
}

@MainActor
public final class AppModeManager: ObservableObject {
    @Published public var mode: AppMode

    public init(mode: AppMode = .solo) {
        self.mode = mode
    }
}
