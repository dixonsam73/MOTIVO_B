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

    // MARK: - Capabilities

    /// Milestone 1
    public var canViewFeed: Bool {
        mode == .connected
    }

    /// Milestone 2
    public var canComment: Bool {
        mode == .connected
    }

    /// Milestone 2
    public var canForwardPost: Bool {
        mode == .connected
    }

    /// Milestone 3
    public var canShareWithFollowers: Bool {
        mode == .connected
    }

    /// Milestone 3
    public var canUseAttachmentPrivacy: Bool {
        mode == .connected
    }

    /// Milestone 3
    public var canUseNotesPrivacy: Bool {
        mode == .connected
    }
}
