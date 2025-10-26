import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Lightweight local profile helper for identity MVP (single name, avatar, location).
/// - Storage:
///   - Name: Provided by Core Data Profile (source of truth) — not stored here.
///   - Location: UserDefaults per user.
///   - Avatar: JPEG file in Application Support/Profiles/{userID}.jpg (downscaled to max 256 px, quality 0.8).
struct ProfileStore {
    // MARK: - Keys
    private static func locationKey(for userID: String) -> String { "profile.\(userID).location" }

    // MARK: - Public API (Location)
    static func location(for userID: String?) -> String {
        guard let uid = userID, !uid.isEmpty else { return "" }
        return UserDefaults.standard.string(forKey: locationKey(for: uid)) ?? ""
    }
    static func setLocation(_ value: String, for userID: String?) {
        guard let uid = userID, !uid.isEmpty else { return }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: locationKey(for: uid))
    }

    // MARK: - Public API (Avatar)
    static func avatarURL(for userID: String?) -> URL? {
        guard let uid = userID, !uid.isEmpty else { return nil }
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
        let dir = base?.appendingPathComponent("Profiles", isDirectory: true)
        if let dir, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir?.appendingPathComponent("\(uid).jpg", conformingTo: .jpeg)
    }

    #if canImport(UIKit)
    private static let cache = NSCache<NSString, UIImage>()

    static func avatarImage(for userID: String?) -> UIImage? {
        guard let url = avatarURL(for: userID) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: url.path), let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Save avatar image downscaled to max 256 px and JPEG(0.8)
    static func saveAvatarImage(_ image: UIImage, for userID: String?) {
        guard let url = avatarURL(for: userID) else { return }
        let fm = FileManager.default
        if let dir = url.deletingLastPathComponent() as URL?, !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let down = downscale(image, maxSide: 256)
        guard let data = down.jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: url, options: .atomic)
        cache.setObject(down, forKey: url.path as NSString)
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
    static func saveAvatarImage(_ image: Any, for userID: String?) { }
    #endif
}
