// CHANGE-ID: 20260308_195800_MultiDeviceBootstrap_ProfileStore
// SCOPE: Multi-device bootstrap hardening — add best-effort backend-to-local hydration for missing display name, location, and instruments on fresh second-device sign-in. No avatar/UI/logic changes beyond hydration helper.
// SEARCH-TOKEN: 20260308_195800_MultiDeviceBootstrap_ProfileStore

// CHANGE-ID: 20260120_124800_Phase12C_ProfileStore_PerUserLookup
// SCOPE: Phase 12C — per-backend-user lookup settings + account_id storage; legacy allowDiscovery_v1 adopted as initial default.
// SEARCH-TOKEN: 20260120_124800_Phase12C_ProfileStore_PerUserLookup

// CHANGE-ID: 20260303_162500_DeleteAccountV2_Stage5_ProfileStoreWipe_FIX
// SCOPE: Delete Account v2 Stage 5 — fix syntax + add ProfileStore.wipeLocalIdentityForFactoryReset to purge profile.* UserDefaults keys and delete Application Support/Profiles avatar files. No other behavior changes.
// SEARCH-TOKEN: 20260303_162500_DeleteAccountV2Stage5_ProfileStoreWipe_FIX

import Foundation
import CoreData
#if canImport(UIKit)
import UIKit
#endif

/// Lightweight local profile helper for identity MVP (single name, avatar, location).
/// - Storage:
///   - Name: Provided by Core Data Profile (source of truth) — not stored here.
///   - Location: UserDefaults per user.
///   - Avatar (original): JPEG file in Application Support/Profiles/{userID}-original.jpg
///   - Avatar (derived/display): PNG file in Application Support/Profiles/{userID}-avatar.png (square, typically 256–512 px)
/// P5-I / C-34 R2 (B1) — PURE. Whether this device's copy of the owner's own
/// avatar should follow the backend. **The backend avatar and version are
/// authoritative for the Connected profile when this device has no unsynced
/// local avatar change.**
///
/// On FIRST SIGHT (nothing applied yet) an absent backend avatar cannot be told
/// apart from one never uploaded, so it is only recorded — a local copy is
/// removed only when the version CHANGES after one was already applied.
///
/// C-192, second pass (2026-11-11). With one shared profile a device also
/// PUBLISHES what the private sync brings it, so a changed backend version is
/// usually an echo: this device's own publication, or another of the owner's
/// devices publishing the picture the journal already delivered here. Reading
/// an echo back would re-encode the image and send it through iCloud as a new
/// edit, which the next Connected device would publish again. The first pass
/// stopped that by never reading back while sync was on, which also hid a
/// real change made on a Connected device whose sync is off. Now:
///
///  1. a device records the version its OWN publication produced, so it never
///     reads that back (`AccountDirectoryService.updateSelfAvatarKey`);
///  2. only a version NEWER than the recorded one is followed (both are the
///     server's clock), so a row read before this device's own publication
///     cannot undo it;
///  3. a newer version showing the SAME PICTURE this device holds is an echo:
///     recorded, nothing written (`samePicture`);
///  4. a different picture, or a removal, is a real change. With sync on it is
///     applied only once it has STOOD for `settleInterval`, because a sibling
///     can publish an older state for a moment (a photo change that reaches it
///     as a removal and then the image, C-194; a retried older upload), and
///     applying that would send the removal or the old picture to every device.
enum OwnAvatarSync {
    enum Action: Equatable { case none, recordOnly, refresh, remove }

    static func normalized(_ version: String?) -> String {
        (version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `avatar_version` is the server's `now()` as PostgREST prints it,
    /// "2026-11-11T19:41:42.302262+00:00", with a fraction of 0 to 6 digits.
    static func date(ofVersion version: String) -> Date? {
        let v = normalized(version)
        guard !v.isEmpty else { return nil }
        var base = v
        var fraction = 0.0
        if let dot = v.firstIndex(of: ".") {
            let after = v[v.index(after: dot)...]
            let digits = after.prefix { $0.isNumber }
            fraction = Double("0." + digits) ?? 0
            base = String(v[..<dot]) + String(after.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: base)?.addingTimeInterval(fraction)
    }

    /// Both values are server stamps. A version is only ever stamped, never
    /// unset, so an empty one cannot follow a set one. Values that are not
    /// timestamps (never seen from the server) fall back to "different is newer".
    static func isNewer(_ incoming: String, than last: String) -> Bool {
        if incoming == last || incoming.isEmpty { return false }
        if last.isEmpty { return true }
        if let a = date(ofVersion: incoming), let b = date(ofVersion: last) { return a > b }
        return true
    }

    static func decide(lastApplied: String?,
                       backendVersion: String?,
                       backendHasAvatar: Bool,
                       hasPendingLocalChange: Bool) -> Action {
        if hasPendingLocalChange { return .none }
        let incoming = normalized(backendVersion)
        guard let last = lastApplied else { return backendHasAvatar ? .refresh : .recordOnly }
        guard isNewer(incoming, than: last) else { return .none }
        return backendHasAvatar ? .refresh : .remove
    }

    // MARK: A real change must stand before a sync-on device applies it

    static let settleInterval: TimeInterval = 120

    /// The backend version this device is waiting on, and when it first saw it.
    struct Seen: Equatable { var version: String; var at: Date }

    /// PURE. A version seen for the first time starts the wait; the same
    /// version still standing `interval` later has settled. A clock set back
    /// starts the wait again.
    static func settle(seen: Seen?, version: String, now: Date,
                       interval: TimeInterval = settleInterval) -> (settled: Bool, seen: Seen) {
        guard let seen, seen.version == version, now >= seen.at else {
            return (false, Seen(version: version, at: now))
        }
        return (now.timeIntervalSince(seen.at) >= interval, seen)
    }

    #if canImport(UIKit)
    // MARK: The same picture, whatever the encoding

    /// A 32 x 32 RGBA rendering: small enough that JPEG loss and a PNG
    /// re-encode disappear, large enough that two photos never look alike.
    ///
    /// Drawn at 256 x 256 and averaged down here in 8 x 8 blocks. Drawing
    /// straight to 32 x 32 lets the system pick the reduction, and it reduces a
    /// JPEG while decoding it and a PNG afterwards: measured, the SAME pixels
    /// stored as JPEG and as PNG came out 7 apart (of 255), more than two
    /// similar photos might.
    static func thumbnail(of image: UIImage, side: Int = 32) -> [UInt8]? {
        let block = 8
        let full = side * block
        var large = [UInt8](repeating: 0, count: full * full * 4)
        let drawn: Bool = large.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: full, height: full, bitsPerComponent: 8,
                                          bytesPerRow: full * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: full, height: full))
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: 0, y: 0, width: full, height: full))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return nil }
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                var sum = [0, 0, 0]
                for dy in 0..<block {
                    let row = ((y * block + dy) * full + x * block) * 4
                    for dx in 0..<block {
                        let i = row + dx * 4
                        sum[0] += Int(large[i]); sum[1] += Int(large[i + 1]); sum[2] += Int(large[i + 2])
                    }
                }
                let o = (y * side + x) * 4
                for c in 0..<3 { pixels[o + c] = UInt8(sum[c] / (block * block)) }
            }
        }
        return pixels
    }

    /// Mean absolute difference per colour channel, 0 to 255. Measured in the
    /// tests: a JPEG round trip of the same picture is under 2; different
    /// pictures are far above the tolerance.
    static func pictureDistance(_ a: UIImage, _ b: UIImage) -> Double? {
        guard let x = thumbnail(of: a), let y = thumbnail(of: b), x.count == y.count else { return nil }
        var total = 0
        var count = 0
        for i in stride(from: 0, to: x.count, by: 4) {
            for c in 0..<3 { total += abs(Int(x[i + c]) - Int(y[i + c])); count += 1 }
        }
        return count == 0 ? nil : Double(total) / Double(count)
    }

    static let samePictureTolerance = 6.0

    static func samePicture(_ a: UIImage, _ b: UIImage) -> Bool {
        guard let distance = pictureDistance(a, b) else { return false }
        return distance <= samePictureTolerance
    }

    /// The same measure against a thumbnail kept from a photo that no longer
    /// exists (`ProfileStore.removedAvatarThumbnail`).
    static func samePicture(thumbnail x: [UInt8], _ image: UIImage) -> Bool {
        guard let y = thumbnail(of: image), x.count == y.count, !x.isEmpty else { return false }
        var total = 0
        var count = 0
        for i in stride(from: 0, to: x.count, by: 4) {
            for c in 0..<3 { total += abs(Int(x[i + c]) - Int(y[i + c])); count += 1 }
        }
        return Double(total) / Double(count) <= samePictureTolerance
    }
    #endif
}

/// PURE. Whether a waiting REMOVAL may be published to the Connected profile.
///
/// Third pass (2026-11-12). A removal removes one picture. The private sync can
/// carry a removal that is already out of date (a photo change that travels as
/// a removal and then the image, C-194, with the image arriving minutes or
/// hours later), and by the time this device publishes it another of the
/// owner's devices may have published the NEW photo. Publishing the removal
/// then deletes that photo from the profile; its holder reads the removal
/// back, applies it and sends it to every device, and the photo is gone for
/// good. So a removal is published only when the profile still shows the
/// picture this device removed. Anything else on the profile is a photo this
/// removal is not about: it is withdrawn, and the photo comes to this device
/// instead. In doubt the photo is kept; a removal can be made again, a lost
/// photo cannot.
enum AvatarRemovalGuard {
    enum Decision: Equatable { case publish, alreadyRemoved, yieldToBackend }

    /// `backendShowsTheRemovedPicture` is nil when this device kept no record of
    /// the picture it removed.
    static func decide(backendHasAvatar: Bool, backendShowsTheRemovedPicture: Bool?) -> Decision {
        guard backendHasAvatar else { return .alreadyRemoved }
        return backendShowsTheRemovedPicture == true ? .publish : .yieldToBackend
    }
}

#if canImport(UIKit)
/// What the backend shows for the owner's avatar, as a promotion needs it
/// before publishing a removal. Tests supply one; the app reads the row and
/// downloads the image.
struct AvatarBackendProbe {
    var rowExists: Bool
    var avatarKey: String?
    var avatarVersion: String?
    var image: UIImage?
}
#endif

struct ProfileStore {
    #if DEBUG
    /// Test-only: runs immediately before a backend read-back writes or removes
    /// the local avatar, so a test can land an iCloud import in that window.
    nonisolated(unsafe) static var testHookBeforeBackendAvatarWrite: (() -> Void)?
    #endif

    // MARK: - Keys
    private static let localProfileStorageID = "__local_etudes_profile__"
    private static func profileStorageID(for userID: String?) -> String {
        let trimmed = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? localProfileStorageID : trimmed
    }
    private static func locationKey(for userID: String) -> String { "profile.\(userID).location" }
    private static let localAvatarSyncStateKey = "profile.__local_etudes_profile__.avatarSyncState_v1"

    // MARK: - Local Avatar Sync State
    // THE MARKER LIVES IN A FILE (third pass, 2026-11-12). It was a UserDefaults
    // value. Writing UserDefaults posts its change notification before the
    // write returns, and the sync engine observes that notification on the
    // main queue, so a marking made on the sync's thread WAITED FOR THE MAIN
    // THREAD while holding the avatar lock; the main thread deadlocked the
    // moment it asked for that lock. Found by the overlap test for the
    // read-back, in the test host, with the engine's observer installed; the
    // same wait exists in the app whenever sync is on. A file write posts
    // nothing. The file holds "upload", "delete" or "none"; when it has never
    // been written, the value an older build left in UserDefaults is read.
    private static func avatarMarkerFileURL() -> URL? {
        baseProfilesDir()?.appendingPathComponent("__avatar_sync_state", isDirectory: false)
    }

    private static func storedAvatarMarker() -> String? {
        if let url = avatarMarkerFileURL(), let data = try? Data(contentsOf: url) {
            let text = String(decoding: data, as: UTF8.self)
            return text == "upload" || text == "delete" ? text : nil
        }
        let legacy = UserDefaults.standard.string(forKey: localAvatarSyncStateKey)
        return legacy == "upload" || legacy == "delete" ? legacy : nil
    }

    private static func storeAvatarMarker(_ state: String?) {
        guard let url = avatarMarkerFileURL() else { return }
        try? Data((state ?? "none").utf8).write(to: url, options: .atomic)
    }

    static func hasPendingLocalAvatarUpload() -> Bool { storedAvatarMarker() == "upload" }

    static func hasPendingLocalAvatarDeletion() -> Bool { storedAvatarMarker() == "delete" }

    static func hasPendingLocalAvatarSync() -> Bool {
        hasPendingLocalAvatarUpload() || hasPendingLocalAvatarDeletion()
    }

    static func clearPendingLocalAvatarSync() {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        storeAvatarMarker(nil)
    }

    // C-192: the marker is one value, and a photo change can arrive as a
    // removal followed by the new image while the removal is still being
    // published. Each marking gets a number; a promotion clears the marker
    // only if it is still the marking it started from, so the later one is
    // not lost. In memory only: the marker itself survives a relaunch.
    //
    // ONE LOCK FOR ALL OF IT (second pass, 2026-11-11). The number and the
    // stored value used to change in two steps, so a clear could pass its
    // check, a new marking could land, and the clear could then remove it. The
    // lock now covers a marking (number and value together), the checked
    // clear (check and removal together), the sync's own writers (files and
    // marking together) and the promotion's local delete. Recursive because
    // the writers mark from inside it.
    private static let avatarMarkerLock = NSRecursiveLock()
    nonisolated(unsafe) private static var avatarMarkerCount = 0
    #if DEBUG
    /// Test-only: runs inside the checked clear, after the check has passed and
    /// before the removal, so a test can try to mark in exactly that window.
    nonisolated(unsafe) static var testHookInsideCheckedAvatarClear: (() -> Void)?
    #endif

    static var pendingLocalAvatarGeneration: Int {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        return avatarMarkerCount
    }

    /// The marker and its number, read together.
    static func pendingLocalAvatarSnapshot() -> (state: String?, generation: Int) {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        return (storedAvatarMarker(), avatarMarkerCount)
    }

    private static func setPendingLocalAvatar(_ state: String) {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        avatarMarkerCount += 1
        storeAvatarMarker(state)
    }

    /// Clears the marker unless the avatar was marked again since `generation`.
    @discardableResult
    static func clearPendingLocalAvatarSync(ifUnchangedSince generation: Int) -> Bool {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        guard avatarMarkerCount == generation else { return false }
        #if DEBUG
        testHookInsideCheckedAvatarClear?()
        #endif
        storeAvatarMarker(nil)
        return true
    }

    // MARK: - P5-I / C-34 R2 — the backend avatar version this device last applied

    private static func ownAvatarAppliedVersionKey(for userID: String) -> String {
        "profile.\(userID).ownAvatarAppliedVersion_v1"
    }

    /// The owner's `avatar_version` this device last took from the backend, or
    /// nil if it has never applied one. A record, not a pending flag.
    static func ownAvatarAppliedVersion(for userID: String) -> String? {
        UserDefaults.standard.string(forKey: ownAvatarAppliedVersionKey(for: userID))
    }

    static func setOwnAvatarAppliedVersion(_ version: String, for userID: String) {
        UserDefaults.standard.set(version, forKey: ownAvatarAppliedVersionKey(for: userID))
    }

    /// A publication by this device: the version it produced is the one this
    /// device holds. Never moves the record backwards.
    static func noteOwnAvatarPublished(version: String?, for userID: String?) {
        guard let uid = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !uid.isEmpty else { return }
        let incoming = OwnAvatarSync.normalized(version)
        guard !incoming.isEmpty else { return }
        if let last = ownAvatarAppliedVersion(for: uid), !OwnAvatarSync.isNewer(incoming, than: last) { return }
        setOwnAvatarAppliedVersion(incoming, for: uid)
    }

    // The backend change a sync-on device is waiting on (`OwnAvatarSync.settle`).
    private static func ownAvatarSeenVersionKey(for userID: String) -> String { "profile.\(userID).ownAvatarSeenVersion_v1" }
    private static func ownAvatarSeenAtKey(for userID: String) -> String { "profile.\(userID).ownAvatarSeenAt_v1" }

    static func ownAvatarBackendChangeSeen(for userID: String) -> OwnAvatarSync.Seen? {
        guard let version = UserDefaults.standard.string(forKey: ownAvatarSeenVersionKey(for: userID)),
              let at = UserDefaults.standard.object(forKey: ownAvatarSeenAtKey(for: userID)) as? Double else { return nil }
        return OwnAvatarSync.Seen(version: version, at: Date(timeIntervalSince1970: at))
    }

    static func setOwnAvatarBackendChangeSeen(_ seen: OwnAvatarSync.Seen?, for userID: String) {
        if let seen {
            UserDefaults.standard.set(seen.version, forKey: ownAvatarSeenVersionKey(for: userID))
            UserDefaults.standard.set(seen.at.timeIntervalSince1970, forKey: ownAvatarSeenAtKey(for: userID))
        } else {
            UserDefaults.standard.removeObject(forKey: ownAvatarSeenVersionKey(for: userID))
            UserDefaults.standard.removeObject(forKey: ownAvatarSeenAtKey(for: userID))
        }
    }

    private static func markPendingLocalAvatarUploadIfNeeded(for userID: String?) {
        if profileStorageID(for: userID) == localProfileStorageID {
            setPendingLocalAvatar("upload")
        }
    }

    private static func markPendingLocalAvatarDeletionIfNeeded(for userID: String?) {
        if profileStorageID(for: userID) == localProfileStorageID {
            setPendingLocalAvatar("delete")
        }
    }

    // MARK: - Phase 12C (Per-backend-user Lookup Keys)
    private static let legacyAllowDiscoveryKey = "allowDiscovery_v1"
    private static func discoveryModeKey(for backendUserID: String) -> String { "profile.\(backendUserID).discoveryMode_v1" }
    /// **LEGACY.** The user-facing handle is removed; nothing reads or writes
    /// this value any more. The key is kept solely so `purge` still clears what
    /// an upgraded device is carrying — deleting the helper would strand it.
    private static func accountIDKey(for backendUserID: String) -> String { "profile.\(backendUserID).account_id_v1" }

    // MARK: - Phase 12C (Per-backend-user Lookup Settings)
    /// Per-backend-user lookup mode (int raw value).
    /// Backward-compat: if per-user value missing, we adopt the legacy device-level allowDiscovery_v1 as the initial default.
    static func discoveryModeRaw(for backendUserID: String?) -> Int {
        guard let bid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return 0 }
        let key = discoveryModeKey(for: bid)
        if let v = UserDefaults.standard.object(forKey: key) as? Int { return v }
        if let legacy = UserDefaults.standard.object(forKey: legacyAllowDiscoveryKey) as? Int {
            UserDefaults.standard.set(legacy, forKey: key)
            return legacy
        }
        return 1
    }

    static func setDiscoveryModeRaw(_ raw: Int, for backendUserID: String?) {
        guard let bid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return }
        UserDefaults.standard.set(raw, forKey: discoveryModeKey(for: bid))
    }

    // MARK: - Public API (Location)
    static func location(for userID: String?) -> String {
        let uid = profileStorageID(for: userID)
        return UserDefaults.standard.string(forKey: locationKey(for: uid)) ?? ""
    }
    /// C-36 — the location a profile PRESENTS for `userID`.
    ///
    /// Identical to `location(for:)` whenever the scoped key exists, including an
    /// explicit "" (a deliberate clear). ONLY when the scoped key has never been
    /// written — a first Connected join, before any writer has run — it presents
    /// the local Études location instead of a blank, because a blank presented
    /// in `ProfileView` is synced to the directory as NULL. Persists nothing.
    static func presentedLocation(for userID: String?) -> String {
        let uid = profileStorageID(for: userID)
        guard UserDefaults.standard.object(forKey: locationKey(for: uid)) != nil else {
            return location(for: nil)
        }
        return location(for: userID)
    }

    static func setLocation(_ value: String, for userID: String?) {
        let uid = profileStorageID(for: userID)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Stage H: a changed value is a profile edit; the same value written
        // again (every Profile blur and close rewrites it) is not.
        let previous = UserDefaults.standard.string(forKey: locationKey(for: uid))
        UserDefaults.standard.set(trimmed, forKey: locationKey(for: uid))
        if previous != trimmed { JournalProfileMirror.locationChanged() }
    }

    /// C-193 — a location the person committed, or one the private sync
    /// applied. Études has ONE profile: the value goes under the identity's key
    /// and is also the local Études location.
    ///
    /// Writing only the identity's key left the local key holding the older
    /// value, and `locationForBackgroundPublish` prefers the local key: the next
    /// background publish (after any validated request) put the old value back
    /// and published it. Seen 2026-11-11: "Alpha Two" became "Alpha" and "Gamma"
    /// became "Delta" within seconds. A cleared location came back the same way.
    static func commitLocation(_ value: String, for userID: String?) {
        setLocation(value, for: userID)
        if profileStorageID(for: userID) != localProfileStorageID { setLocation(value, for: nil) }
    }

    /// The location the background snapshot publish sends for `userID`.
    ///
    /// The local Études location wins when it holds a value, and is adopted
    /// under the identity's key: that is how a location edited while signed out
    /// reaches the Connected profile at the next sign-in. It is only safe
    /// because every writer with an identity present writes BOTH keys
    /// (`commitLocation`), so the local key is never the older one.
    static func locationForBackgroundPublish(for userID: String) -> String {
        let local = location(for: nil).trimmingCharacters(in: .whitespacesAndNewlines)
        let scoped = location(for: userID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !local.isEmpty else { return scoped }
        if local != scoped { setLocation(local, for: userID) }
        return local
    }

    /// C-27 — at sign-out the local Études profile keeps the location the signed-in
    /// profile PRESENTED, which is what `ProfileView` preserves when it is mounted.
    ///
    /// Reads through `presentedLocation`, so an identity whose scoped key was never
    /// written leaves the local value alone, and an explicit "" (a deliberate clear)
    /// carries like any other value. Deletes nothing: the scoped key survives, so
    /// signing back in still restores it.
    static func carryPresentedLocationToLocal(from backendUserID: String?) {
        let uid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !uid.isEmpty else { return }
        setLocation(presentedLocation(for: uid), for: nil)
    }

    // MARK: - Paths
    private static func baseProfilesDir() -> URL? {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base?.appendingPathComponent("Profiles", isDirectory: true)
        if let dir, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func avatarOriginalURL(for userID: String?) -> URL? {
        let uid = profileStorageID(for: userID)
        return baseProfilesDir()?.appendingPathComponent("\(uid)-original.jpg", conformingTo: .jpeg)
    }

    static func avatarDerivedURL(for userID: String?) -> URL? {
        let uid = profileStorageID(for: userID)
        return baseProfilesDir()?.appendingPathComponent("\(uid)-avatar.png", conformingTo: .png)
    }

    static func avatarURL(for userID: String?) -> URL? {
        // Compatibility: legacy calls refer to the derived (display) avatar
        return avatarDerivedURL(for: userID)
    }




    // MARK: - Multi-Device Bootstrap Hydration

    /// Best-effort hydration of missing local identity fields from canonical backend directory state.
    /// Fills only missing local values; does not destructively replace existing local data.
    @MainActor
    static func hydrateMissingLocalIdentity(
        displayName: String?,
        location: String?,
        instruments: [String]?,
        for backendUserID: String?,
        in moc: NSManagedObjectContext
    ) {
        guard let bid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return }

        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let canonicalInstruments = canonicalInstrumentNames(from: instruments)

        var didChange = false

        moc.performAndWait {
            let profile = fetchOrCreateProfile(in: moc)

            if let profile {
                let localName = (profile.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if localName.isEmpty, !trimmedDisplayName.isEmpty {
                    profile.name = trimmedDisplayName
                    didChange = true
                }
            }

            let localLocation = Self.location(for: bid).trimmingCharacters(in: .whitespacesAndNewlines)
            if localLocation.isEmpty, !trimmedLocation.isEmpty {
                Self.setLocation(trimmedLocation, for: bid)
            }

            if let profile, !canonicalInstruments.isEmpty {
                let fetch: NSFetchRequest<Instrument> = Instrument.fetchRequest()
                fetch.predicate = NSPredicate(format: "profile == %@", profile)
                let existing = (try? moc.fetch(fetch)) ?? []
                let existingNorms = Set(existing.compactMap { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })

                for name in canonicalInstruments where !existingNorms.contains(name.lowercased()) {
                    let inst = Instrument(context: moc)
                    inst.id = UUID()
                    inst.name = name
                    inst.profile = profile
                    didChange = true

                    do {
                        let norm = name
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()

                        let fr: NSFetchRequest<UserInstrument> = UserInstrument.fetchRequest()
                        fr.fetchLimit = 1
                        fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                            NSPredicate(format: "ownerUserID == %@", bid),
                            NSPredicate(format: "normalizedName == %@", norm)
                        ])

                        if let existing = try moc.fetch(fr).first {
                            if existing.coreInstrument != inst {
                                existing.coreInstrument = inst
                            }

                            if existing.isVisibleOnProfile != true {
                                existing.isVisibleOnProfile = true
                            }
                        } else {
                            let ui = UserInstrument(context: moc)
                            ui.id = UUID()
                            ui.ownerUserID = bid
                            ui.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            ui.normalizedName = norm
                            ui.isVisibleOnProfile = true
                            ui.displayOrder = 0
                            ui.coreInstrument = inst
                        }

                    } catch {
                        NSLog("[ProfileStore] Multi-device bootstrap mirror failed for instrument %@: %@", name, String(describing: error))
                    }
                }
            }

            if didChange, moc.hasChanges {
                do {
                    try moc.save()
                } catch {
                    NSLog("[ProfileStore] Multi-device bootstrap save failed: %@", String(describing: error))
                }
            }
        }
    }

    private static func fetchOrCreateProfile(in moc: NSManagedObjectContext) -> Profile? {
        let fetch: NSFetchRequest<Profile> = Profile.fetchRequest()
        fetch.fetchLimit = 1
        if let existing = try? moc.fetch(fetch).first { return existing }

        let profile = Profile(context: moc)
        profile.id = UUID()
        profile.name = ""
        profile.primaryInstrument = ""
        return profile
    }

    private static func canonicalInstrumentNames(from instruments: [String]?) -> [String] {
        guard let instruments else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for raw in instruments {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(trimmed)
        }
        return out
    }

    // MARK: - Delete Account v2 (Local Factory Reset)

    /// Wipes local profile identity artifacts for a factory reset.
    /// - Removes per-user `profile.*` UserDefaults keys (location, discovery mode, account id).
    /// - Removes legacy device-level allowDiscovery_v1.
    /// - Deletes on-disk avatar artifacts under Application Support/Profiles and clears in-memory cache.
    /// Best-effort and safe to call multiple times.
    static func wipeLocalIdentityForFactoryReset(backendUserID: String?) {
        let defaults = UserDefaults.standard

        if let uid = backendUserID, !uid.isEmpty {
            defaults.removeObject(forKey: locationKey(for: uid))
            defaults.removeObject(forKey: discoveryModeKey(for: uid))
            // Legacy handle key: unread since the handle was removed, still purged.
            defaults.removeObject(forKey: accountIDKey(for: uid))
        } else {
            // If caller cannot provide a user id, purge any per-user profile.* keys.
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("profile.") {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: legacyAllowDiscoveryKey)

        #if canImport(UIKit)
        cache.removeAllObjects()
        #endif

        let fm = FileManager.default
        if let dir = baseProfilesDir(), fm.fileExists(atPath: dir.path) {
            do {
                try fm.removeItem(at: dir)
            } catch {
                NSLog("[ProfileStore] wipeLocalIdentityForFactoryReset — failed to remove Profiles dir: \(error)")
            }
        }
    }

    #if canImport(UIKit)
    private static let cache = NSCache<NSString, UIImage>()

    static func avatarImage(for userID: String?) -> UIImage? {
        // Derived/display image
        guard let url = avatarDerivedURL(for: userID) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: url.path), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    static func avatarOriginalImage(for userID: String?) -> UIImage? {
        guard let url = avatarOriginalURL(for: userID) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: url.path), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Save original (full) image as JPEG (quality 0.9). No downscale here; editor manages framing and export.
    static func saveAvatarOriginal(_ image: UIImage, for userID: String?) {
        guard let url = avatarOriginalURL(for: userID) else { return }
        let fm = FileManager.default
        if let dir = url.deletingLastPathComponent() as URL?, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: url, options: .atomic)
        cache.setObject(image, forKey: url.path as NSString)
    }

    /// Save derived/display avatar as PNG. Downscale to max 256 px on the longer side for UI use.
    static func saveAvatarDerived(_ image: UIImage, for userID: String?) {
        saveAvatarDerived(image, for: userID, markPendingLocalSync: true)
    }

    /// Save derived/display avatar without creating a pending Solo→Connected upload marker.
    /// Used when hydrating local caches from an already-authoritative Connected backend avatar.
    static func saveAvatarDerivedFromConnectedHydration(_ image: UIImage, for userID: String?) {
        saveAvatarDerived(image, for: userID, markPendingLocalSync: false)
    }

    private static func saveAvatarDerived(_ image: UIImage, for userID: String?, markPendingLocalSync: Bool) {
        guard let url = avatarDerivedURL(for: userID) else { return }
        let fm = FileManager.default
        if let dir = url.deletingLastPathComponent() as URL?, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let down = downscale(image, maxSide: 256)
        guard let data = down.pngData() else { return }
        try? data.write(to: url, options: .atomic)
        cache.setObject(down, forKey: url.path as NSString)
        if markPendingLocalSync {
            markPendingLocalAvatarUploadIfNeeded(for: userID)
        }
        JournalProfileMirror.avatarChanged()
    }

    // MARK: - Stage H: the private-sync writers
    //
    // An avatar received from the other device is written byte for byte (a
    // re-encode would change its hash and the two devices would send it back
    // and forth) and clocked with the sender's file time.
    //
    // C-192 (policy, 2026-11-11): Études has one shared profile, so both
    // writers SET the pending marker. A device holding a Connected identity
    // then publishes the image (or the removal) to that owner's Connected
    // profile through the existing promotion; a Solo device publishes nothing
    // and keeps the marker, exactly as for an avatar chosen in Solo, until it
    // joins. Before this the writers set no marker and an imported avatar
    // never reached the Connected profile while an imported location did.

    @discardableResult
    static func writeSyncedAvatar(pngData: Data, for userID: String?, modifiedAt: Date) -> Bool {
        guard let image = UIImage(data: pngData) else { return false }
        // Files and marking together, so a promotion's local delete cannot fall between them.
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        var ok = true
        for scope in Set([profileStorageID(for: userID), localProfileStorageID]) {
            guard let derived = avatarDerivedURL(for: scope), let original = avatarOriginalURL(for: scope) else { ok = false; continue }
            let fm = FileManager.default
            if !fm.fileExists(atPath: derived.deletingLastPathComponent().path) {
                try? fm.createDirectory(at: derived.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            do {
                try pngData.write(to: derived, options: .atomic)
                try fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: derived.path)
            } catch { ok = false; continue }
            cache.setObject(image, forKey: derived.path as NSString)
            if let jpeg = image.jpegData(compressionQuality: 0.9) {
                try? jpeg.write(to: original, options: .atomic)
                cache.setObject(image, forKey: original.path as NSString)
            }
        }
        if ok { setPendingLocalAvatar("upload") }
        return ok
    }

    /// Both scopes, and the removal is marked for the Connected profile.
    static func removeSyncedAvatar(for userID: String?) {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        deleteAvatarFiles(for: userID)
        deleteAvatarFiles(for: nil)
        setPendingLocalAvatar("delete")
    }

    /// The promotion of a pending removal drops the identity's copy. Only if
    /// the avatar has not been marked again since the promotion started: an
    /// image the sync wrote meanwhile is not this removal's to delete.
    static func deleteAvatarForPendingDeletion(for userID: String?, ifUnchangedSince generation: Int) -> Bool {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        guard avatarMarkerCount == generation else { return false }
        deleteAvatarFiles(for: userID)
        return true
    }

    /// True when the identity's avatar file and the local Études one are the
    /// same bytes (what a sync import leaves). The promotion then uploads
    /// without rewriting the identity's copy: a rewrite re-encodes the PNG,
    /// which the private sync would send to the other devices as a new image.
    static func avatarScopesHoldTheSameFile(for userID: String?) -> Bool {
        guard profileStorageID(for: userID) != localProfileStorageID,
              let scoped = avatarDerivedURL(for: userID), let local = avatarDerivedURL(for: nil),
              let a = try? Data(contentsOf: scoped), let b = try? Data(contentsOf: local) else { return false }
        return a == b
    }

    /// Backwards-compatibility: treat this as saving the derived/display avatar.
    static func saveAvatarImage(_ image: UIImage, for userID: String?) {
        saveAvatarDerived(image, for: userID)
    }

    static func deleteAvatar(for userID: String?) {
        deleteAvatarFiles(for: userID)
        markPendingLocalAvatarDeletionIfNeeded(for: userID)
    }

    // MARK: The picture last removed (for `AvatarRemovalGuard`)

    private static func removedAvatarThumbnailURL() -> URL? {
        baseProfilesDir()?.appendingPathComponent("__last_removed_avatar.thumb", isDirectory: false)
    }

    /// A 32 x 32 rendering of the photo this device last removed, kept so a
    /// waiting removal can be checked against what the profile shows.
    static func removedAvatarThumbnail() -> [UInt8]? {
        guard let url = removedAvatarThumbnailURL(), let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return [UInt8](data)
    }

    private static func keepThumbnailOfAvatarAboutToBeRemoved(at url: URL) {
        guard let image = UIImage(contentsOfFile: url.path), let pixels = OwnAvatarSync.thumbnail(of: image),
              let target = removedAvatarThumbnailURL() else { return }
        try? Data(pixels).write(to: target, options: .atomic)
    }

    private static func deleteAvatarFiles(for userID: String?, removalClock: Date? = nil) {
        let fm = FileManager.default
        var removed = false
        if let url = avatarOriginalURL(for: userID) {
            if fm.fileExists(atPath: url.path) { removed = true }
            try? fm.removeItem(at: url)
            cache.removeObject(forKey: url.path as NSString)
        }
        if let url = avatarDerivedURL(for: userID) {
            if fm.fileExists(atPath: url.path) {
                removed = true
                keepThumbnailOfAvatarAboutToBeRemoved(at: url)
            }
            try? fm.removeItem(at: url)
            cache.removeObject(forKey: url.path as NSString)
        }
        // C-192: removing nothing is not a removal. Publishing a removal the
        // sync applied calls this for files already gone; telling the sync
        // "removed now" would give this device a newer clock than the photo
        // that follows the removal, and it would delete that photo everywhere.
        if removed { JournalProfileMirror.avatarRemoved(at: removalClock) }
    }

    /// The ONE place a backend avatar becomes the local copy. It writes the
    /// connected scope (only if absent unless `replacingExisting`) and always the
    /// local Études scope, and never sets a pending upload — the image is already
    /// backend-authoritative.
    static func seedAvatarFromConnected(_ image: UIImage, for userID: String?, replacingExisting: Bool) {
        if replacingExisting || avatarImage(for: userID) == nil {
            saveAvatarDerived(image, for: userID, markPendingLocalSync: false)
        }
        if replacingExisting || avatarOriginalImage(for: userID) == nil {
            saveAvatarOriginal(image, for: userID)
        }
        saveAvatarDerived(image, for: nil, markPendingLocalSync: false)
        saveAvatarOriginal(image, for: nil)
    }

    // MARK: A change read back from the Connected profile (third pass, 2026-11-12)
    //
    // Two rules, both about the private sync.
    //
    // ATOMIC. The read-back decides on the main actor; an iCloud import writes
    // on the sync's thread. The check ("nothing has marked the avatar since
    // this read-back began, and nothing is waiting") and the write happen here
    // under the lock the sync's writers take, so an import can land before
    // (the read-back then stands down) or after (the import is the later
    // write), never between.
    //
    // NEVER "NOW". A change read back used to enter the journal clocked at the
    // moment this device applied it, which outranked anything the journal had
    // not delivered yet: a replacement photo chosen ten minutes earlier and
    // arriving late lost to the removal this device had just applied, on every
    // device, for good. With sync on the change is clocked a millisecond after
    // the state it displaces (the photo this device held, or the removal the
    // journal holds), so it displaces exactly that and loses to anything newer.

    private static func modificationDate(of url: URL?) -> Date? {
        guard let url, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }

    private static func nothingHasMarkedTheAvatar(since generation: Int) -> Bool {
        avatarMarkerCount == generation && storedAvatarMarker() == nil
    }

    /// Writes the backend's picture as this device's avatar, both scopes.
    /// False, and nothing written, if the avatar was marked since `generation`.
    static func applyAvatarFromBackend(_ image: UIImage, for userID: String?, ifUnchangedSince generation: Int,
                                       journalIsOn: Bool) -> Bool {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        guard nothingHasMarkedTheAvatar(since: generation) else { return false }
        #if DEBUG
        testHookBeforeBackendAvatarWrite?()
        #endif
        let displaced = modificationDate(of: avatarDerivedURL(for: userID)) ?? JournalProfileMirror.removalClock?()
        seedAvatarFromConnected(image, for: userID, replacingExisting: true)
        if journalIsOn, let displaced {
            let clock = displaced.addingTimeInterval(0.001)
            for url in [avatarDerivedURL(for: userID), avatarDerivedURL(for: nil)].compactMap({ $0 }) {
                try? FileManager.default.setAttributes([.modificationDate: clock], ofItemAtPath: url.path)
            }
            JournalProfileMirror.avatarChanged()
        }
        return true
    }

    /// Removes this device's avatar because the backend's was removed, both
    /// scopes. False, and nothing removed, if the avatar was marked since `generation`.
    static func removeAvatarFromBackend(for userID: String?, ifUnchangedSince generation: Int, journalIsOn: Bool) -> Bool {
        avatarMarkerLock.lock(); defer { avatarMarkerLock.unlock() }
        guard nothingHasMarkedTheAvatar(since: generation) else { return false }
        #if DEBUG
        testHookBeforeBackendAvatarWrite?()
        #endif
        let clock = journalIsOn ? modificationDate(of: avatarDerivedURL(for: userID))?.addingTimeInterval(0.001) : nil
        deleteAvatarFiles(for: userID, removalClock: clock)
        deleteAvatarFiles(for: nil, removalClock: clock)
        return true
    }

    private static func downscale(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let size = img.size
        guard size.width > 0 && size.height > 0 else { return img }
        let scale = min(maxSide / max(size.width, size.height), 1.0)
        if scale >= 1.0 { return img }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
    #else
    static func avatarImage(for userID: String?) -> Any? { return nil }
    static func avatarOriginalImage(for userID: String?) -> Any? { return nil }
    static func saveAvatarOriginal(_ image: Any, for userID: String?) { }
    static func saveAvatarDerived(_ image: Any, for userID: String?) { }
    static func saveAvatarDerivedFromConnectedHydration(_ image: Any, for userID: String?) { }
    static func saveAvatarImage(_ image: Any, for userID: String?) { }
    static func deleteAvatar(for userID: String?) { }
    static func hasPendingLocalAvatarUpload() -> Bool { false }
    static func hasPendingLocalAvatarDeletion() -> Bool { false }
    static func hasPendingLocalAvatarSync() -> Bool { false }
    static func clearPendingLocalAvatarSync() { }
    #endif
}
