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
    @Published public private(set) var mode: AppMode

    public init(mode: AppMode = .solo) {
        self.mode = mode
        Self.applyBackendRuntimeMode(for: mode)
    }

    func applyActivation(auth: AuthManager, isEntitled: Bool, reason: String = "-") {
        let resolved = Self.resolvedActivationMode(auth: auth, isEntitled: isEntitled)

        // TEMPORARY — C-38 diagnosis. Remove with ActivationTrace.swift.
        // Reads only; the resolve above is untouched.
        ActivationTrace.gates(
            reason: reason,
            backendConfigured: BackendConfig.isConfigured,
            isEntitled: isEntitled,
            isSignedIn: auth.isSignedIn,
            hasToken: auth.hasSupabaseAccessToken,
            hasBackendUserID: !(auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            resolved: String(describing: resolved),
            previous: String(describing: self.mode)
        )

        applyMode(resolved)
    }

    func applyMode(_ mode: AppMode) {
        Self.applyBackendRuntimeMode(for: mode)
        guard self.mode != mode else { return }
        self.mode = mode
    }

    private static func applyBackendRuntimeMode(for mode: AppMode) {
        switch mode {
        case .solo:
            setBackendMode(.localSimulation)
        case .connected:
            setBackendMode(.backendConnected)
        }
        BackendConfig.apply()
    }

    static func resolvedActivationMode(auth: AuthManager, isEntitled: Bool) -> AppMode {
        #if DEBUG
        switch DebugAppExperienceOverride.current {
        case .automatic:
            return ProductionAppModeActivation.resolve(auth: auth, isEntitled: isEntitled)
        case .forceSolo:
            return .solo
        case .forceConnected:
            return .connected
        }
        #else
        return ProductionAppModeActivation.resolve(auth: auth, isEntitled: isEntitled)
        #endif
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

    /// Connected Attachment Sharing — native iOS sharing remains available in both modes.
    public var canShareAttachmentsWithConnected: Bool {
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

    /// Milestone 4
    public var canShowConnectedAccountManagement: Bool {
        mode == .connected
    }
}


// MARK: - Production Activation

@MainActor
enum ProductionAppModeActivation {
    static func resolve(auth: AuthManager, isEntitled: Bool) -> AppMode {
        guard BackendConfig.isConfigured else { return .solo }
        guard isEntitled else { return .solo }
        guard auth.isSignedIn else { return .solo }
        guard auth.hasSupabaseAccessToken else { return .solo }

        let backendID = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !backendID.isEmpty else { return .solo }

        return .connected
    }
}

#if DEBUG
public enum DebugAppExperienceOverride: String, CaseIterable, Identifiable {
    case automatic
    case forceSolo
    case forceConnected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .forceSolo:
            return "Force Études"
        case .forceConnected:
            return "Force Études Connected"
        }
    }

    static let defaultsKey = "Debug.appExperienceOverride_v1"

    static var current: DebugAppExperienceOverride {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let value = DebugAppExperienceOverride(rawValue: raw) else {
                return .automatic
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}
#endif
