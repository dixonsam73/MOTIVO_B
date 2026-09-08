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

    func applyActivation(auth: AuthManager, isEntitled: Bool) {
        applyMode(Self.resolvedActivationMode(auth: auth, isEntitled: isEntitled))
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
    /// Connected requires BOTH an entitlement and an identity. Keeping the two
    /// terms visibly separate is deliberate: the identity half is
    /// `auth.hasConnectedIdentity`, which account deletion consumes on its own,
    /// without the entitlement (C-35). One definition, so the deletion gate and
    /// the mode resolver cannot drift apart.
    ///
    /// P5-G/D1 adds the age-eligibility term, and its POSITION is deliberate:
    /// it sits BEFORE the entitlement term so that when both hold, the age
    /// reason is the operative one. A withheld member must never be routed into
    /// purchase copy — buying a subscription cannot resolve age eligibility.
    ///
    /// **THIS DOES NOT GATE ACCOUNT DELETION.** Deletion is gated on
    /// `auth.hasConnectedIdentity` at `ProfileView.performDeleteAccount`, never
    /// on `AppMode`, precisely because C-35 was sprung twice. A withheld member
    /// keeps the full delete route without re-subscribing.
    static func resolve(auth: AuthManager, isEntitled: Bool) -> AppMode {
        guard BackendConfig.isConfigured else { return .solo }
        guard !auth.ageEligibilityWithheld else { return .solo }
        guard isEntitled else { return .solo }
        guard auth.hasConnectedIdentity else { return .solo }
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
