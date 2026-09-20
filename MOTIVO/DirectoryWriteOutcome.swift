//
//  DirectoryWriteOutcome.swift
//  MOTIVO
//
//  PHASE 6 · C-70 — WHAT A DIRECTORY WRITE ACTUALLY ESTABLISHED.
//
//  **THE DEFECT THIS EXISTS TO CORRECT.** The directory writer returned
//  `Result<Void, Error>`, so "it did not throw" was the only thing a caller
//  could learn — and `Prefer: return=minimal` meant the server sent nothing
//  back. A write affecting ZERO rows is a 2xx with an empty body, which is
//  byte-identical to one that changed the row. `ProfileView` then latched that
//  outcome into `lastDirectorySyncFingerprint`, whose whole purpose is to skip
//  the next identical attempt, and `upsertSelfRowOnce` merged the values it had
//  SENT into the shared identity cache and the feed store.
//
//  So a write that changed nothing could be recorded as done, never retried,
//  and published into the identity other surfaces render from. **`Void` is what
//  allowed "it did not throw" to mean "it saved".**
//
//  This module is the vocabulary that replaces it, and the evidence rule:
//    * IDENTITY is a hard gate — a receipt for another row is never applied;
//    * VALUES are compared against the payload ACTUALLY SERIALISED, after
//      sanitisation, and only for the keys it actually carried;
//    * a mismatch is reported as NOT EVIDENCED and never as a diagnosis. A
//      trigger, server-side canonicalisation and malformed evidence are all
//      equally consistent with it, so naming a cause would be inventing one.
//
//  Pure and transport-free so it can be tested directly.
//

import Foundation

// MARK: - What kind of write this is

/// Writes are not interchangeable, and stale-intent suppression depends on the
/// difference: a full-profile edit may supersede an earlier one, but a
/// handle-only generation must never be discarded by either.
public enum DirectoryWriteKind: Equatable, Sendable {
    /// The member editing name / account id / location / instruments.
    case profileEdit
    /// Account-ID auto-generation. Sends `account_id` and nothing else.
    case generation
    /// The first INSERT for an identity that has no row. Still gated.
    case creation
}

// MARK: - The row the server sent back

/// One `account_directory` row exactly as the server returned it.
///
/// **Key PRESENCE is recorded separately from the value**, because the two
/// answer different questions. Every key here is named in the request's
/// `select=`, so a key that is absent from the response is malformed evidence —
/// which is not the same observation as a key that is present and null.
public struct DirectoryWriteReceipt: Decodable, Equatable, Sendable {
    public let userID: String
    public let displayName: String?
    public let displayNamePresent: Bool
    public let accountID: String?
    public let accountIDPresent: Bool
    public let location: String?
    public let locationPresent: Bool
    public let instruments: [String]?
    public let instrumentsPresent: Bool

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case accountID = "account_id"
        case location = "location"
        case instruments = "instruments"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `user_id` is the identity gate and is required outright: a receipt
        // that cannot say which row it describes is not evidence about any row.
        userID = try c.decode(String.self, forKey: .userID).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        displayNamePresent = c.contains(.displayName)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        accountIDPresent = c.contains(.accountID)
        accountID = try c.decodeIfPresent(String.self, forKey: .accountID)
        locationPresent = c.contains(.location)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        instrumentsPresent = c.contains(.instruments)
        instruments = try c.decodeIfPresent([String].self, forKey: .instruments)
    }

    /// True when every column named in `DirectoryWriteEvidence.selectedColumns`
    /// is present in the response — `user_id` is required by the decoder itself.
    public var hasAllSelectedColumns: Bool {
        displayNamePresent && accountIDPresent && locationPresent && instrumentsPresent
    }

    /// Direct construction, for tests and for transport-free use.
    public init(userID: String,
                displayName: String?, displayNamePresent: Bool,
                accountID: String?, accountIDPresent: Bool,
                location: String?, locationPresent: Bool,
                instruments: [String]?, instrumentsPresent: Bool) {
        self.userID = userID.lowercased()
        self.displayName = displayName
        self.displayNamePresent = displayNamePresent
        self.accountID = accountID
        self.accountIDPresent = accountIDPresent
        self.location = location
        self.locationPresent = locationPresent
        self.instruments = instruments
        self.instrumentsPresent = instrumentsPresent
    }
}

// MARK: - The outcome

/// What one directory write established. Every case that is not `.applied`
/// means the same thing to the caller: **do not report saved, do not latch, do
/// not merge.** They are kept distinct because they are distinct observations.
public enum DirectoryWriteOutcome {
    /// The server returned this owner's row and every value actually sent is
    /// evidenced in it.
    case applied(DirectoryWriteReceipt)
    /// The server returned this owner's row and at least one sent value is not
    /// evidenced in it. **A neutral observation, not a diagnosis.**
    case notEvidenced(DirectoryWriteReceipt)
    /// 2xx, zero rows. The write matched nothing. NOT success.
    case noRowMatched
    /// A policy or privilege refusal (403 + SQLSTATE 42501). Establishes that
    /// the write was refused, and NOTHING about why.
    case refusedByPolicy
    /// 23505 with the server naming the `account_id` unique constraint.
    case accountIDTaken
    /// 23505 with the server naming the primary key. Not a handle collision.
    case rowConflict
    /// The request was sent and its outcome is UNKNOWN. Never retried
    /// automatically: a blind replay could duplicate a server effect.
    case ambiguous(Error)
    /// The bound identity changed, so the request was not sent, not retried, or
    /// its result must not be applied.
    case supersededIdentity
    /// A newer, strictly-superseding edit was submitted before this one
    /// dispatched. Nothing was sent. The caller resolves — it never hangs.
    case superseded
    case failed(Error)

    /// The one case a caller may treat as saved.
    public var isApplied: Bool {
        if case .applied = self { return true }
        return false
    }
}

// MARK: - Evidence

public enum DirectoryWriteEvidence {

    /// The columns every directory write asks the server to return.
    ///
    /// **One definition, used both to BUILD the `select=` and to REQUIRE the
    /// keys in the response.** Two lists would drift, and the drift would be
    /// invisible: a column dropped from the request but still required would
    /// fail every write, and one required but not requested would never arrive.
    public static let selectedColumns = ["user_id", "display_name", "account_id", "location", "instruments"]

    public static var selectList: String { selectedColumns.joined(separator: ",") }

    /// One expectation derived from the serialised payload.
    public enum Field: Equatable {
        case displayName(String)
        case accountID(String)
        case location(String)
        case locationNull
        case instruments([String])
    }

    /// Derive what the response must show FROM THE DICTIONARY THAT WAS
    /// SERIALISED — not from the caller's arguments.
    ///
    /// This is the whole reason the writer builds one dictionary and hands that
    /// same dictionary here: an expectation derived from the caller's inputs
    /// could disagree with what sanitisation actually produced, and the two
    /// would drift silently. `user_id` is deliberately NOT an expectation —
    /// identity is gated separately and more strictly.
    public static func expectation(from payload: [String: Any]) -> [Field] {
        var fields: [Field] = []
        if let v = payload["display_name"] as? String { fields.append(.displayName(v)) }
        if let v = payload["account_id"] as? String { fields.append(.accountID(v)) }
        if payload["location"] is NSNull {
            fields.append(.locationNull)
        } else if let v = payload["location"] as? String {
            fields.append(.location(v))
        }
        if let v = payload["instruments"] as? [String] { fields.append(.instruments(v)) }
        return fields
    }

    /// Is every sent value evidenced in the returned row?
    ///
    /// A key the payload did not carry asserts nothing and is not compared —
    /// `upsertSelfRow` deliberately omits a blank or invalid handle so an
    /// existing one is preserved, and comparing an omitted key would fail a
    /// write that behaved exactly as designed.
    public static func matches(_ expectation: [Field], _ receipt: DirectoryWriteReceipt) -> Bool {
        for field in expectation {
            switch field {
            case .displayName(let v):
                guard receipt.displayNamePresent, receipt.displayName == v else { return false }
            case .accountID(let v):
                guard receipt.accountIDPresent, receipt.accountID == v else { return false }
            case .location(let v):
                guard receipt.locationPresent, receipt.location == v else { return false }
            case .locationNull:
                // Present and null. A MISSING key is malformed evidence, not a null.
                guard receipt.locationPresent, receipt.location == nil else { return false }
            case .instruments(let v):
                guard receipt.instrumentsPresent, receipt.instruments == v else { return false }
            }
        }
        return true
    }

    /// Either the one row this owner's write returned, or the outcome that
    /// settles it without one.
    public enum Resolution {
        case row(DirectoryWriteReceipt)
        case settled(DirectoryWriteOutcome)
    }

    /// Decode a PostgREST representation array into exactly one row belonging to
    /// `owner`, or say why not.
    ///
    /// Row count is evidence in its own right: zero means the write matched
    /// nothing, and more than one means something is wrong with the request —
    /// taking `.first` is how a wrong row gets adopted.
    public static func resolve(data: Data, owner: String) -> Resolution {
        let expectedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows: [DirectoryWriteReceipt]
        do {
            rows = try JSONDecoder().decode([DirectoryWriteReceipt].self, from: data)
        } catch {
            return .settled(.failed(error))
        }
        guard !rows.isEmpty else { return .settled(.noRowMatched) }
        guard rows.count == 1 else {
            return .settled(.failed(NSError(domain: "DirectoryWrite", code: 2,
                                   userInfo: [NSLocalizedDescriptionKey: "expected one row, got \(rows.count)"])))
        }
        let row = rows[0]
        guard row.userID == expectedOwner else {
            // A receipt for somebody else's row is never applied, whatever it says.
            return .settled(.failed(NSError(domain: "DirectoryWrite", code: 3,
                                   userInfo: [NSLocalizedDescriptionKey: "receipt owner mismatch"])))
        }
        // EVERY SELECTED COLUMN MUST BE PRESENT, whether or not the payload sent
        // it. Value equality is checked against the fields actually sent, but
        // PRESENCE is structural: the caches consume all four columns from the
        // receipt, so a missing key would read as nil and CLEAR a cached value
        // the write never targeted. A handle-only generation receipt without
        // `location` would wipe the cached location — a defect with no failing
        // request anywhere to point at.
        guard row.hasAllSelectedColumns else {
            return .settled(.failed(NSError(domain: "DirectoryWrite", code: 4,
                                   userInfo: [NSLocalizedDescriptionKey: "receipt is missing selected columns"])))
        }
        return .row(row)
    }

    // MARK: - Classifying a failure

    /// True only when the SERVER named the `account_id` unique constraint.
    ///
    /// **A bare 23505 is NOT enough.** `account_directory` carries two unique
    /// constraints — `account_directory_account_id_key` on `account_id` and
    /// `account_directory_pkey` on `user_id` — and both raise 23505. Asserting a
    /// handle collision from the code alone would blame the Account ID for a
    /// primary-key conflict, which is the exact defect C-70(a) exists to
    /// prevent: attribute a failure to a field only when the server attributed
    /// it there.
    public static func namesAccountIDConstraint(_ body: String) -> Bool {
        body.contains("account_directory_account_id_key") || body.contains("Key (account_id)")
    }

    /// True only when the server named the primary key.
    public static func namesPrimaryKey(_ body: String) -> Bool {
        body.contains("account_directory_pkey") || body.contains("Key (user_id)")
    }

    /// Map a transport/HTTP failure to an outcome.
    public static func classify(_ error: Error) -> DirectoryWriteOutcome {
        if error is TransportIdentityError { return .supersededIdentity }
        if error is CancellationError { return .supersededIdentity }
        guard let net = error as? NetworkManager.NetworkError else { return .failed(error) }
        switch net {
        case .httpError(let status, let body):
            let text = body ?? ""
            if status == 403, text.contains("42501") { return .refusedByPolicy }
            if status == 409 || text.contains("23505") {
                if namesAccountIDConstraint(text) { return .accountIDTaken }
                if namesPrimaryKey(text) { return .rowConflict }
                return .failed(error)
            }
            return .failed(error)
        case .transportError:
            // Sent, outcome unknown. Never replayed automatically.
            return .ambiguous(error)
        default:
            return .failed(error)
        }
    }
}
