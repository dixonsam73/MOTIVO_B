//
//  Moderation.swift
//  MOTIVO
//
//  App Review Guideline 1.2: filter objectionable content, report it, block
//  abusive users, and publish a contact address.
//
//  Deliberately small. Blocking is local to this device: it removes the follow
//  in both directions (posts are only readable by approved followers, so that
//  alone cuts off the blocked person's access), then hides their requests,
//  comments, posts and sends here. Reports are emails to support, so Samuel is
//  notified without any backend change.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Moderation {
    static let supportEmail = "support@etudes.app"

    static func normalizedID(_ id: String?) -> String {
        (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Block list

/// Blocked accounts on this device, keyed by backend user id, with the display
/// name at the time of blocking so the Blocked list can show who it is.
/// Stored in UserDefaults, so it is backed up with the device and removed by
/// Erase All (the factory reset wipes the whole defaults domain).
@MainActor
final class BlockList: ObservableObject {
    static let shared = BlockList()

    private static let storageKey = "Moderation.blockedAccounts.v1"
    private static let unconfirmedKey = "Moderation.blockUnconfirmed.v1"
    private let defaults: UserDefaults
    private let sever: (String) async -> Bool

    @Published private(set) var blocked: [String: String] = [:]
    /// C-104. Blocked here, but the server has not yet confirmed that both follow
    /// rows are gone, so the person may still see shared sessions. Retried from
    /// the Blocked list and whenever People opens.
    @Published private(set) var unconfirmed: Set<String> = []

    init(defaults: UserDefaults = .standard,
         sever: @escaping (String) async -> Bool = { await FollowStore.shared.severRelationships(with: $0) }) {
        self.defaults = defaults
        self.sever = sever
        reloadFromDefaults()
    }

    func isBlocked(_ userID: String?) -> Bool {
        let id = Moderation.normalizedID(userID)
        return !id.isEmpty && blocked[id] != nil
    }

    func isUnconfirmed(_ userID: String?) -> Bool {
        unconfirmed.contains(Moderation.normalizedID(userID))
    }

    /// Records the block, then removes every follow relationship with the
    /// person. Returns false if the server did not confirm the removal.
    @discardableResult
    func block(_ userID: String, displayName: String?) async -> Bool {
        let id = Moderation.normalizedID(userID)
        guard !id.isEmpty else { return false }
        let name = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        blocked[id] = name.isEmpty ? "Blocked account" : name
        unconfirmed.insert(id)
        save()
        return await confirmRemoval(of: id)
    }

    /// Retries removing the follow rows for a blocked account.
    @discardableResult
    func confirmRemoval(of userID: String) async -> Bool {
        let id = Moderation.normalizedID(userID)
        guard blocked[id] != nil else { return true }
        let ok = await sever(id)
        if ok || blocked[id] == nil { unconfirmed.remove(id) }
        save()
        return ok
    }

    func retryUnconfirmed() async {
        for id in unconfirmed.sorted() {
            await confirmRemoval(of: id)
        }
    }

    func unblock(_ userID: String) {
        let id = Moderation.normalizedID(userID)
        guard blocked.removeValue(forKey: id) != nil else { return }
        unconfirmed.remove(id)
        save()
    }

    /// Called after Erase All has wiped the defaults domain.
    func reloadFromDefaults() {
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        if stored != blocked { blocked = stored }
        let pending = Set(defaults.stringArray(forKey: Self.unconfirmedKey) ?? [])
        if pending != unconfirmed { unconfirmed = pending }
    }

    private func save() {
        defaults.set(blocked, forKey: Self.storageKey)
        defaults.set(Array(unconfirmed).sorted(), forKey: Self.unconfirmedKey)
    }
}

// MARK: - Content filter

/// Refuses a small list of slurs and strong profanity in text that will be
/// shared with other people. It never touches private text.
enum SharedTextFilter {
    /// Whole words only, so ordinary words that contain these letters pass.
    static let blockedWords: Set<String> = [
        "cunt", "cunts", "twat", "twats", "wanker", "wankers",
        "cocksucker", "cocksuckers", "whore", "whores", "slut", "sluts",
        "nigger", "niggers", "nigga", "niggas", "faggot", "faggots", "fag", "fags",
        "kike", "kikes", "spic", "spics", "chink", "chinks", "wetback", "wetbacks",
        "tranny", "trannies",
    ]

    /// Any word starting with one of these roots (fuck, fucking, fucker…).
    static let blockedRoots: [String] = ["fuck", "motherfuck"]

    static func isAllowed(_ text: String) -> Bool {
        words(in: text).allSatisfy { word in
            !blockedWords.contains(word) && !blockedRoots.contains(where: { word.hasPrefix($0) })
        }
    }

    static func areAllowed(_ texts: [String?]) -> Bool {
        texts.allSatisfy { isAllowed($0 ?? "") }
    }

    /// C-105. A save is refused only when the text will actually be shared:
    /// Connected sharing is available AND Share is on. Solo saves, including
    /// edits of sessions that were shared before, are never filtered.
    static func refusesSave(sharingAvailable: Bool, isShared: Bool, texts: [String?]) -> Bool {
        sharingAvailable && isShared && !areAllowed(texts)
    }

    static let refusalMessage =
        "This contains language that can’t be shared with other members. Edit it, or turn off Share to keep it private."

    private static let leet: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "@": "a", "$": "s",
    ]

    private static func words(in text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let mapped = String(folded.map { leet[$0] ?? $0 })
        return mapped
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }
}

// MARK: - Reports

struct ModerationReport {
    enum Kind: String {
        case post = "Post"
        case comment = "Comment"
        case account = "Account"
    }

    let kind: Kind
    let reportedUserID: String
    let reportedDisplayName: String?
    let reporterUserID: String?
    var postID: UUID? = nil
    var commentID: UUID? = nil
    var excerpt: String? = nil

    var subject: String { "Report: \(kind.rawValue)" }

    var body: String {
        var lines = [
            "Please tell us what's wrong (optional):",
            "",
            "",
            "---",
            "Reported: \(kind.rawValue)",
            "Account: \(reportedDisplayName ?? "Unknown") (\(Moderation.normalizedID(reportedUserID)))",
        ]
        if let postID { lines.append("Post: \(postID.uuidString.lowercased())") }
        if let commentID { lines.append("Comment: \(commentID.uuidString.lowercased())") }
        if let excerpt, !excerpt.isEmpty { lines.append("Text: \(String(excerpt.prefix(300)))") }
        lines.append("Reported by: \(Moderation.normalizedID(reporterUserID))")
        return lines.joined(separator: "\n")
    }

    var mailtoURL: URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Moderation.supportEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return c.url
    }
}

enum ModerationMail {
    /// Opens the default mail app. Returns false when there is none, so the
    /// caller can show the address instead.
    @MainActor
    static func open(_ url: URL?) async -> Bool {
        #if canImport(UIKit)
        guard let url else { return false }
        return await UIApplication.shared.open(url)
        #else
        return false
        #endif
    }

    static var supportURL: URL? { URL(string: "mailto:\(Moderation.supportEmail)") }

    static let noMailMessage =
        "No mail app is set up on this device. Please email \(Moderation.supportEmail) — the address has been copied."

    static func copySupportAddress() {
        #if canImport(UIKit)
        UIPasteboard.general.string = Moderation.supportEmail
        #endif
    }
}

// MARK: - Shared UI

/// Adds the Report/Block confirmation and failure alerts to a view. Callers set
/// `pendingBlock` to ask for confirmation, and call `report(_:)` to send.
@MainActor
final class ModerationActions: ObservableObject {
    struct PendingBlock: Identifiable {
        let userID: String
        let displayName: String?
        var id: String { userID }
    }

    @Published var pendingBlock: PendingBlock? = nil
    @Published var message: String? = nil
    @Published var messageTitle: String = "Report"
    /// C-104. Set when the server did not confirm the follow removal.
    @Published var unfinishedBlock: PendingBlock? = nil

    func report(_ report: ModerationReport) {
        Task {
            if !(await ModerationMail.open(report.mailtoURL)) {
                ModerationMail.copySupportAddress()
                messageTitle = "Report"
                message = ModerationMail.noMailMessage
            }
        }
    }

    func confirmBlock(userID: String, displayName: String?) {
        pendingBlock = PendingBlock(userID: userID, displayName: displayName)
    }

    /// Blocks and waits for the server. Returns true only when access is
    /// confirmed revoked; otherwise offers a retry.
    func block(_ pending: PendingBlock) async -> Bool {
        let ok = await BlockList.shared.block(pending.userID, displayName: pending.displayName)
        if !ok { unfinishedBlock = pending }
        return ok
    }

    func retryBlock(_ pending: PendingBlock) async -> Bool {
        let ok = await BlockList.shared.confirmRemoval(of: pending.userID)
        if !ok { unfinishedBlock = pending }
        return ok
    }

    static let unfinishedBlockMessage =
        "They’re blocked on this device, but we couldn’t remove them from your followers, so they may still see your shared sessions. Check your connection and try again. You can also retry from People → Blocked."
}

struct ModerationAlerts: ViewModifier {
    @ObservedObject var actions: ModerationActions
    var onBlocked: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                blockTitle,
                isPresented: Binding(get: { actions.pendingBlock != nil },
                                     set: { if !$0 { actions.pendingBlock = nil } }),
                titleVisibility: .visible,
                presenting: actions.pendingBlock
            ) { pending in
                Button("Block", role: .destructive) {
                    actions.pendingBlock = nil
                    Task {
                        if await actions.block(pending) { onBlocked?() }
                    }
                }
                Button("Cancel", role: .cancel) { actions.pendingBlock = nil }
            } message: { _ in
                Text("They won’t be able to see your shared sessions, and you won’t see their posts, comments or requests. They aren’t notified. You can unblock them in People.")
            }
            .alert("Block Not Finished",
                   isPresented: Binding(get: { actions.unfinishedBlock != nil },
                                        set: { if !$0 { actions.unfinishedBlock = nil } }),
                   presenting: actions.unfinishedBlock) { pending in
                Button("Try Again") {
                    actions.unfinishedBlock = nil
                    Task {
                        if await actions.retryBlock(pending) { onBlocked?() }
                    }
                }
                Button("Not Now", role: .cancel) { actions.unfinishedBlock = nil }
            } message: { _ in
                Text(ModerationActions.unfinishedBlockMessage)
            }
            .alert(actions.messageTitle, isPresented: Binding(get: { actions.message != nil },
                                                  set: { if !$0 { actions.message = nil } })) {
                Button("OK", role: .cancel) { actions.message = nil }
            } message: {
                Text(actions.message ?? "")
            }
    }

    private var blockTitle: String {
        let name = (actions.pendingBlock?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Block this account?" : "Block \(name)?"
    }
}

extension View {
    func moderationAlerts(_ actions: ModerationActions, onBlocked: (() -> Void)? = nil) -> some View {
        modifier(ModerationAlerts(actions: actions, onBlocked: onBlocked))
    }
}
