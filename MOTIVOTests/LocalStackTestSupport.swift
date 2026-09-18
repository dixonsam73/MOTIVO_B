//
//  LocalStackTestSupport.swift
//  MOTIVOTests
//
//  C-100. SHARED SETUP FOR TESTS THAT MUST EXERCISE A REAL BACKEND.
//
//  Two defects made local-stack results untrustworthy:
//   1. Tests used `auth.users` identities that nothing created; a local reset
//      removed them and the suites failed at seeding.
//   2. The host app's launch activation could overwrite the backend mode after
//      setUp, so a backend call resolved to the SIMULATED service and returned
//      success without a request (measured by call stack; see UnitTestHost).
//
//  So a test using this support:
//   - creates its own disposable identities, and verifies they exist;
//   - FAILS in setUp, with a named reason, unless it is really wired to the
//     intended backend (mode, configuration, base URL and the resolved HTTP
//     services), instead of letting a simulated success count as evidence;
//   - FAILS in tearDown if the host app's activation wrote the mode during it.
//  A local stack that is not running still SKIPS, as before.
//

import XCTest
@testable import Etudes

enum LocalStackRequirementError: Error, CustomStringConvertible {
    case unmet(String)
    var description: String {
        switch self { case .unmet(let why): return "C-100 setup requirement not met: \(why)" }
    }
}

@MainActor
enum LocalStackSupport {
    static let baseURLString = "http://127.0.0.1:54321"

    /// The Supabase CLI's local demo service-role key (the same value the local
    /// suites already carry). It authenticates to the loopback stack only.
    private static let serviceKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0."
        + "EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

    static func isReachable() -> Bool {
        var r = URLRequest(url: URL(string: baseURLString + "/auth/v1/health")!)
        r.timeoutInterval = 3
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return ok
    }

    /// Creates each identity through the local auth admin API with an explicit
    /// id, idempotently, and verifies it exists afterwards. Measured: the API
    /// accepts an explicit id and answers a repeat with 422 `email_exists`, so
    /// existence is confirmed by id rather than inferred from that status.
    static func ensureIdentities(_ uids: [String]) async throws {
        for uid in uids {
            if try await identityExists(uid) { continue }
            let body: [String: Any] = ["id": uid, "email": "c100-\(uid.suffix(12))@local.invalid", "email_confirm": true]
            let (code, data) = await admin("auth/v1/admin/users", "POST", body)
            guard try await identityExists(uid) else {
                throw LocalStackRequirementError.unmet(
                    "identity \(uid) could not be created (HTTP \(code): \(String(data: data, encoding: .utf8) ?? ""))")
            }
        }
    }

    private static func identityExists(_ uid: String) async throws -> Bool {
        let (code, _) = await admin("auth/v1/admin/users/\(uid)", "GET", nil)
        switch code {
        case 200: return true
        case 404: return false
        default: throw LocalStackRequirementError.unmet("could not read identity \(uid) (HTTP \(code))")
        }
    }

    private static func admin(_ path: String, _ method: String, _ body: [String: Any]?) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(serviceKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + serviceKey, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }

    /// The test is wired to the REAL backend it claims to verify, or it fails now.
    static func requireRealBackend(baseURL: String = baseURLString) throws {
        guard UnitTestHost.isActive else {
            throw LocalStackRequirementError.unmet("UnitTestHost.isActive is false inside the test process, so the host app's launch activation is not suppressed")
        }
        guard BackendEnvironment.shared.mode == .backendConnected else {
            throw LocalStackRequirementError.unmet("backend mode is \(BackendEnvironment.shared.mode), not backendConnected")
        }
        guard BackendConfig.isConfigured, BackendConfig.apiBaseURL?.absoluteString == baseURL else {
            throw LocalStackRequirementError.unmet("BackendConfig is not configured for \(baseURL) (found \(BackendConfig.apiBaseURL?.absoluteString ?? "nil"))")
        }
        guard NetworkManager.shared.baseURL?.absoluteString == baseURL else {
            throw LocalStackRequirementError.unmet("NetworkManager base URL is \(NetworkManager.shared.baseURL?.absoluteString ?? "nil"), not \(baseURL)")
        }
        guard BackendEnvironment.shared.publish is HTTPBackendPublishService else {
            throw LocalStackRequirementError.unmet("publish service resolves to \(type(of: BackendEnvironment.shared.publish)), not HTTPBackendPublishService")
        }
        guard BackendEnvironment.shared.follow is HTTPBackendFollowService else {
            throw LocalStackRequirementError.unmet("follow service resolves to \(type(of: BackendEnvironment.shared.follow)), not HTTPBackendFollowService")
        }
    }
}

/// C-100. Fails the test if the HOST APP's launch activation writes the backend
/// mode while it runs. A write is attributed to the host app only when its call
/// stack carries a `MOTIVOApp` frame — the measured writer — so a test's OWN
/// deliberate mode changes (e.g. switching to backendPreview) are not flagged.
/// C-100 — WHICH FRAMES MEAN "THE HOST APP WROTE THIS".
///
/// The sentinel exists to catch the host app's launch activation writing the
/// backend mode during a test — measured on 2026-09-14 as
/// `MOTIVOApp.handleMembershipState` → `AppModeManager.applyActivation` →
/// `setBackendMode`, from a closure in `MOTIVOApp.body`. Those are `MOTIVOApp`
/// CODE frames, and they still attribute.
///
/// **What no longer attributes: the app's SwiftUI `@main` entry point, and only
/// that frame.** It sits at the bottom of EVERY main-thread stack in a hosted
/// test process — measured 2026-09-18 in a probe (frame 64 of 68) and in a
/// crash report's thread 0 — so matching it attributed any write whose
/// notification the main run loop delivered, whoever made the write. That is
/// the probable cause of the unexplained failure in the 2c full run.
///
/// The exclusion is the EXACT symbol as `Thread.callStackSymbols` prints it,
/// not a substring: any other `MOTIVOApp` frame, and any line that cannot be
/// parsed, still attributes — the rule fails towards reporting.
enum HostActivationAttribution {
    static let entryPointSymbol = "$s6Etudes9MOTIVOAppV5$mainyyFZ"

    /// The symbol field of a `callStackSymbols` line:
    /// `<index> <image> <address> <symbol> + <offset>`.
    static func symbol(of frame: String) -> String? {
        let fields = frame.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return nil }
        return String(fields[3])
    }

    static func attributingFrames(_ stack: [String]) -> [String] {
        stack.filter { $0.contains("MOTIVOApp") && symbol(of: $0) != entryPointSymbol }
    }
}

final class AppActivationWriteSentinel: NSObject {
    private let lock = NSLock()
    private var hostWrites: [String] = []
    private var observing = false

    func start() {
        guard !observing else { return }
        UserDefaults.standard.addObserver(self, forKeyPath: BackendKeys.modeKey, options: [.new], context: nil)
        observing = true
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let stack = Thread.callStackSymbols
        // C-100 CORRECTION (2026-09-18): the app's `@main` entry frame no longer
        // counts. See `HostActivationAttribution`.
        let attributing = HostActivationAttribution.attributingFrames(stack)
        guard !attributing.isEmpty else { return }
        let value = (change?[.newKey] as? String) ?? "<nil>"
        // The FULL stack is kept: the earlier 30-frame record cut off the very
        // frame that had to be explained. Reported through `XCTFail` in
        // `assertNoHostActivationWrites` only — never an XCTContext activity,
        // which aborts the process when created off the main thread.
        let report = "wrote \(value) (mainThread=\(Thread.isMainThread)):\n"
            + "ATTRIBUTING FRAMES:\n" + attributing.joined(separator: "\n")
            + "\nFULL STACK (\(stack.count) frames):\n" + stack.joined(separator: "\n")
        lock.lock()
        hostWrites.append(report)
        lock.unlock()
    }

    /// Call first thing in tearDown.
    func assertNoHostActivationWrites(file: StaticString = #filePath, line: UInt = #line) {
        if observing {
            UserDefaults.standard.removeObserver(self, forKeyPath: BackendKeys.modeKey)
            observing = false
        }
        lock.lock(); let writes = hostWrites; lock.unlock()
        if !writes.isEmpty {
            XCTFail("C-100: the host app's launch activation wrote the backend mode during this test, so its backend result is not evidence:\n"
                    + writes.joined(separator: "\n\n"), file: file, line: line)
        }
    }

    deinit {
        if observing { UserDefaults.standard.removeObserver(self, forKeyPath: BackendKeys.modeKey) }
    }
}

/// C-100. The gate must be active where the tests run, or every guarantee above
/// is inert.
final class LocalStackTestSupportTests: XCTestCase {
    func testUnitTestHostGateIsActiveInsideTheTestProcess() {
        XCTAssertTrue(UnitTestHost.isActive,
                      "XCTestConfigurationFilePath is absent, so MOTIVOApp's launch activation would still run in the test host")
    }
}
