//
//  UnitTestHost.swift
//  MOTIVO
//
//  C-100. WHETHER THIS PROCESS IS A HOSTED UNIT-TEST RUN.
//
//  The unit-test target is hosted by the app, so `MOTIVOApp` launches inside the
//  test process. Measured 2026-09-14 by call stack: its launch-time StoreKit
//  membership read resolved not-entitled 0.227 s after the first test's setUp and
//  wrote the backend mode back to local simulation
//  (`handleMembershipState` → `AppModeManager.applyActivation` →
//  `setBackendMode(.localSimulation)`), so a local-stack test silently ran
//  against the simulated backend and reported success.
//
//  SCOPE IS DELIBERATELY NARROW. True ONLY in a Debug build AND only when XCTest
//  has configured this process as a test host. It is always false in Release,
//  and false in every ordinary Debug launch. `MOTIVOApp` consults it to skip its
//  own launch activation; nothing else does, so `AppModeManager`, StoreKit code
//  and any test that drives activation directly behave exactly as before.
//

import Foundation

enum UnitTestHost {
    static let isActive: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }()
}
