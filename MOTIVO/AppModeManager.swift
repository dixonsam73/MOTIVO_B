import Foundation
import SwiftUI

public enum AppMode: String, CaseIterable {
    case solo
    case connected

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

    /// Milestone 1:
    /// Connected-only capability used by ContentView to determine
    /// whether feed-related UI should be available.
    public var canViewFeed: Bool {
        mode == .connected
    }
}
