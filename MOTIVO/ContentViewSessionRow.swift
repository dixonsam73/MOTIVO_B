// CHANGE-ID: 20260520_211500_ContentViewRowExtractionPass1
// SCOPE: ContentView SessionRow extraction only; moved unchanged from ContentView except file-scope access required for separate compilation.
// SEARCH-TOKEN: 20260520_211500_ContentViewRowExtractionPass1

import SwiftUI
import CryptoKit
import CoreData
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Photos)
import Photos
#endif

struct SessionRow: View {
    enum JournalStyle {
        case standard
        case monthCompact
        case yearCompact
    }

    private struct JournalNotesPreviewLine: Hashable {
        let text: String
        let isBullet: Bool
    }

    @ObservedObject var session: Session
    let scope: FeedScope
    let journalStyle: JournalStyle
    let yearCompactHorizontalPadding: CGFloat

    @Binding var selectedThread: String?
    @Binding var activeUserFilterUserID: String?
    let activeEnsembleMemberUserIDs: Set<String>
    @Binding var filtersExpanded: Bool

    @Environment(\.managedObjectContext) private var ctx
    @EnvironmentObject private var auth: AuthManager

    // Force refresh when any Attachment belonging to this session changes (e.g., isThumbnail toggled in Add/Edit)
    @State private var _refreshTick: Int = 0

    //@State private var showDetailFromComment: Bool = false // replaced per instructions
    @State private var isCommentsPresented: Bool = false
    @State private var showPeek: Bool = false
    @State private var isSavedLocal: Bool = false
    @AppStorage("hasSeenSaveHint_v1") private var hasSeenSaveHint: Bool = false
    @State private var showSaveHint: Bool = false
    @State private var saveHintToken = UUID()
    @State private var isShareSheetPresented: Bool = false
    @State private var isSharing: Bool = false
    @State private var errorLine: String? = nil

    #if canImport(UIKit)
    @State private var remoteAvatar: UIImage? = nil
    #endif
    @State private var likeCountLocal: Int = 0
    @State private var commentCountLocal: Int = 0
    @ObservedObject private var commentsStore = CommentsStore.shared
    @ObservedObject private var commentPresence = CommentPresenceStore.shared

    init(
        session: Session,
        scope: FeedScope,
        selectedThread: Binding<String?>,
        activeUserFilterUserID: Binding<String?>,
        activeEnsembleMemberUserIDs: Set<String>,
        filtersExpanded: Binding<Bool>,
        journalStyle: JournalStyle = .standard,
        yearCompactHorizontalPadding: CGFloat = 12
    ) {
        self._session = ObservedObject(initialValue: session)
        self.scope = scope
        self.journalStyle = journalStyle
        self.yearCompactHorizontalPadding = yearCompactHorizontalPadding
        self._selectedThread = selectedThread
        self._activeUserFilterUserID = activeUserFilterUserID
        self.activeEnsembleMemberUserIDs = activeEnsembleMemberUserIDs
        self._filtersExpanded = filtersExpanded
    }

    private var feedTitle: String { SessionActivity.feedTitle(for: session) }
    private var feedSubtitle: String { SessionActivity.feedSubtitle(for: session) }

    private var subtitleParts: [String] {
        // Split the existing subtitle by commas, trimming whitespace
        feedSubtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateTimeLine: String? {
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return "\(Self.sessionRowDateFormatter.string(from: date)) at \(Self.sessionRowTimeFormatter.string(from: date))"
    }

    private var instrumentActivityLine: String {
        // Everything except the last two parts (time/date)
        let parts = subtitleParts
        if parts.count <= 2 {
            return parts.dropLast(max(0, parts.count - 2)).joined(separator: ", ")
        } else {
            return parts.dropLast(2).joined(separator: ", ")
        }
    }

    private var journalThreadLabel: String? {
        ThreadLabelSanitizer.sanitize(session.threadLabel ?? "", maxLength: 32)
    }

    private var journalDateText: String? {
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return Self.sessionRowDateFormatter.string(from: date)
    }

    private var journalTimeText: String? {
        guard let date = session.value(forKey: "timestamp") as? Date else { return nil }
        return Self.sessionRowTimeFormatter.string(from: date)
    }

    private var journalDurationText: String? {
        let attrs = session.entity.attributesByName
        let seconds: Int?
        if attrs["durationSeconds"] != nil, let n = session.value(forKey: "durationSeconds") as? NSNumber {
            seconds = n.intValue
        } else if attrs["durationMinutes"] != nil, let n = session.value(forKey: "durationMinutes") as? NSNumber {
            seconds = n.intValue * 60
        } else if attrs["duration"] != nil, let n = session.value(forKey: "duration") as? NSNumber {
            seconds = n.intValue * 60
        } else if attrs["lengthMinutes"] != nil, let n = session.value(forKey: "lengthMinutes") as? NSNumber {
            seconds = n.intValue * 60
        } else {
            seconds = nil
        }

        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private var journalMetadataLine: String {
        let editorialTimestamp: String? = {
            guard let date = journalDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !date.isEmpty,
                  let time = journalTimeText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !time.isEmpty else {
                return nil
            }

            return "\(date) at \(time)"
        }()

        return [
            journalThreadLabel,
            instrumentActivityLine.isEmpty ? nil : instrumentActivityLine,
            editorialTimestamp
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var journalMetadataTailLine: String {
        let editorialTimestamp: String? = {
            guard let date = journalDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !date.isEmpty,
                  let time = journalTimeText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !time.isEmpty else {
                return nil
            }

            return "\(date) at \(time)"
        }()

        return [
            instrumentActivityLine.isEmpty ? nil : instrumentActivityLine,
            editorialTimestamp
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var yearCompactInstrumentOnlyLine: String {
        subtitleParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var yearCompactMetadataLine: String {
        let instrumentText = yearCompactInstrumentOnlyLine.isEmpty ? nil : yearCompactInstrumentOnlyLine
        let fallbackInstrumentActivityText = instrumentActivityLine.isEmpty ? nil : instrumentActivityLine

        return [
            journalThreadLabel,
            journalThreadLabel == nil ? fallbackInstrumentActivityText : instrumentText,
            journalDateText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var yearCompactMetadataTailLine: String {
        let instrumentText = yearCompactInstrumentOnlyLine.isEmpty ? nil : yearCompactInstrumentOnlyLine
        let fallbackInstrumentActivityText = instrumentActivityLine.isEmpty ? nil : instrumentActivityLine

        return [
            journalThreadLabel == nil ? fallbackInstrumentActivityText : instrumentText,
            journalDateText,
            journalDurationText
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private var journalNotesPreviewLines: [JournalNotesPreviewLine] {
        let trimmed = (session.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let bulletChars = CharacterSet(charactersIn: "•◦▪▫●○■□-–—*·")

        func stripBulletPrefix(from line: String) -> String {
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            while let scalar = value.unicodeScalars.first, bulletChars.contains(scalar) {
                value = String(value.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return value
        }

        func isBulletLine(_ line: String) -> Bool {
            guard let scalar = line.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else {
                return false
            }
            return bulletChars.contains(scalar)
        }

        let rawLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var parsed: [JournalNotesPreviewLine] = []
        var index = 0

        while index < rawLines.count {
            let line = rawLines[index]
            let cleaned = stripBulletPrefix(from: line)
            guard !cleaned.isEmpty else {
                index += 1
                continue
            }

            if !isBulletLine(line) {
                var nextIndex = index + 1
                var foundBulletBlock = false
                while nextIndex < rawLines.count {
                    let candidate = rawLines[nextIndex]
                    if isBulletLine(candidate) {
                        foundBulletBlock = true
                        nextIndex += 1
                    } else {
                        break
                    }
                }

                if foundBulletBlock {
                    parsed.append(JournalNotesPreviewLine(text: cleaned, isBullet: false))
                    index = nextIndex
                    continue
                }

                parsed.append(JournalNotesPreviewLine(text: cleaned, isBullet: false))
                index += 1
                continue
            }

            parsed.append(JournalNotesPreviewLine(text: cleaned, isBullet: true))
            index += 1
        }

        return Array(parsed.prefix(3))
    }

    private var notesPreviewAccessibilityText: String? {
        let summary = journalNotesPreviewLines
            .map { $0.text }
            .joined(separator: ". ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return summary.isEmpty ? nil : summary
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append(feedTitle)
        let meta: String
        if scope == .mine {
            meta = isYearCompactJournalRow ? yearCompactMetadataLine : journalMetadataLine
        } else {
            meta = instrumentActivityLine
        }
        if !meta.isEmpty {
            parts.append(meta)
        }
        if scope != .mine, let dt = dateTimeLine {
            parts.append(dt)
        }
        if scope == .mine, journalStyle == .standard, let notesPreviewAccessibilityText {
            parts.append(notesPreviewAccessibilityText)
        }
        return parts.joined(separator: ". ")
    }

    private var isMonthCompactJournalRow: Bool {
        scope == .mine && journalStyle == .monthCompact
    }

    private var isYearCompactJournalRow: Bool {
        scope == .mine && journalStyle == .yearCompact
    }

    private var isCompactJournalRow: Bool {
        isMonthCompactJournalRow || isYearCompactJournalRow
    }

    private var showsJournalNotesPreview: Bool {
        scope == .mine && journalStyle == .standard
    }

    private var showsJournalAttachmentPreview: Bool {
        scope != .mine || journalStyle == .standard
    }

    private static let sessionRowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f
    }()

    private static let sessionRowTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    private var sessionUUID: UUID? { session.value(forKey: "id") as? UUID }
    private var isPrivatePost: Bool { session.isPublic == false }

    private var sessionIDForComments: UUID? {
        if let real = sessionUUID { return real }
        let uri = session.objectID.uriRepresentation().absoluteString
        return stableUUID(from: uri)
    }

    private var commentsCount: Int {
        guard let id = sessionIDForComments else { return 0 }
        return commentsStore.comments(for: id).count
    }

    var hasComments: Bool {
        guard let id = sessionIDForComments else { return false }
        if auth.isConnected {
            return CommentPresenceStore.shared.hasComments(postID: id)
        }
        return commentsCount > 0
    }

    /// Effective viewer ID, respecting DEBUG override, then Auth, then PersistenceController.
    private var viewerUserID: String? {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
           !override.isEmpty {
            return override
        }
        #endif

        // Local sessions are keyed by the Apple (local) user ID, not the Supabase UUID.
        // Using backendUserID here causes SessionRow to treat the owner as a non-owner in connected mode.
        if let authID = auth.currentUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authID.isEmpty {
            return authID
        }

        // Fallback (mirrors legacy behavior when AuthManager hasn't populated currentUserID yet)
        return PersistenceController.shared.currentUserID
    }

    private func stableUUID(from string: String) -> UUID {
        // Deterministic UUID v5-like using SHA256 first 16 bytes
        let digest = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(digest)
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }

    private var attachments: [Attachment] {
        (session.attachments as? Set<Attachment>).map { Array($0) } ?? []
    }

    // Attachments included with the post (non-private). The feed thumbnail must come from this set.
    private var includedAttachments: [Attachment] {
        attachments.filter { !isPrivate($0) }
    }

    private var favoriteAttachment: Attachment? {
        pickFavoriteAttachment(from: includedAttachments)
    }

    // Visible attachments for the current viewer (owner sees all; others see non-private only)
    private var visibleAttachments: [Attachment] {
        if viewerIsOwner { return attachments }
        return attachments.filter { !isPrivate($0) }
    }

    private var extraAttachmentCount: Int {
        let total = visibleAttachments.count
        return max(total - 1, 0)
    }

    private var viewerIsOwner: Bool {
        // Compare session.ownerUserID to the effective viewer ID, if available
        guard let viewer = viewerUserID, let owner = session.ownerUserID else { return false }
        return viewer == owner
    }

    private var activeHeaderFilterOwnerID: String? {
        let owner = (session.ownerUserID ?? (viewerIsOwner ? viewerUserID : nil))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let owner, !owner.isEmpty else { return nil }
        return owner
    }

    private var isHeaderFilterActive: Bool {
        guard scope == .all else { return false }
        return isActiveUserFilter(activeHeaderFilterOwnerID, activeUserFilterUserID: activeUserFilterUserID)
            || isActiveEnsembleMember(activeHeaderFilterOwnerID, activeEnsembleMemberUserIDs: activeEnsembleMemberUserIDs)
    }

    private func toggleHeaderUserFilter(ownerID: String) {
        guard scope == .all else { return }
        if isActiveUserFilter(ownerID, activeUserFilterUserID: activeUserFilterUserID) {
            activeUserFilterUserID = nil
        } else {
            activeUserFilterUserID = ownerID
        }
    }

    private var identityHeaderHighlight: some View {
        Capsule(style: .continuous)
            .fill(isHeaderFilterActive ? Color(uiColor: .systemGray5) : .clear)
    }

    private func isPrivate(_ att: Attachment) -> Bool {
        let id = att.value(forKey: "id") as? UUID
        // Resolve a stable URL if possible
        let url = attachmentFileURL(att)
        return AttachmentPrivacy.isPrivate(id: id, url: url)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: isYearCompactJournalRow ? 2 : (isMonthCompactJournalRow ? 3 : 6)) {
                // Identity header
                if scope != .mine,
                   let ownerIDNonEmpty = activeHeaderFilterOwnerID,
                   !ownerIDNonEmpty.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            // Avatar 32pt circle
                            Button(action: { showPeek = true }) {
                            Group {
                                #if canImport(UIKit)
                                let ownerAvatarKey = viewerIsOwner ? (auth.backendAvatarKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : ""
                                let ownerAvatarCacheKey = "avatars|\(ownerAvatarKey)"

                                if let img = ProfileStore.avatarImage(for: ownerIDNonEmpty) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else if viewerIsOwner, !ownerAvatarKey.isEmpty, let cached = RemoteAvatarImageCache.get(ownerAvatarCacheKey) {
                                    Image(uiImage: cached)
                                        .resizable()
                                        .scaledToFill()
                                } else if viewerIsOwner, !ownerAvatarKey.isEmpty, let remoteAvatar {
                                    Image(uiImage: remoteAvatar)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    // If viewer is owner, derive initials from Profile.name; else show a neutral 'U'
                                    let initials: String = {
                                        if viewerIsOwner {
                                            let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                            req.fetchLimit = 1
                                            if let ctx = session.managedObjectContext,
                                               let p = try? ctx.fetch(req).first,
                                               let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                let words = n.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    .components(separatedBy: .whitespacesAndNewlines)
                                                    .filter { !$0.isEmpty }
                                                if words.count == 1 { return String(words[0].prefix(1)).uppercased() }
                                                let first = words.first?.first.map { String($0).uppercased() } ?? ""
                                                let last = words.last?.first.map { String($0).uppercased() } ?? ""
                                                let combo = (first + last)
                                                return combo.isEmpty ? "Y" : combo
                                            }
                                            return "Y"
                                        } else {
                                            return "U"
                                        }
                                    }()
                                    ZStack {
                                        Circle().fill(Color.gray.opacity(0.2))
                                        Text(initials)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(Theme.Colors.secondaryText)
                                    }
                                    .task(id: ownerAvatarKey) {
                                        guard viewerIsOwner, !ownerAvatarKey.isEmpty else {
                                            remoteAvatar = nil
                                            return
                                        }
                                        if RemoteAvatarImageCache.get(ownerAvatarCacheKey) != nil { return }
                                        if let ui = await RemoteAvatarPipeline.fetchAvatarImageIfNeeded(avatarKey: ownerAvatarKey) {
                                            remoteAvatar = ui
                                        }
                                    }
                                }
                                #else
                                ZStack {
                                    Circle().fill(Color.gray.opacity(0.2))
                                    Text("U").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                                }
                                #endif
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(.black.opacity(0.06), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // Name and optional location on one line
                        let realName: String = {
                            // Source of truth: Core Data Profile.name for current device's user only.
                            // For other users (future), fallback to a neutral label.
                            if viewerIsOwner {
                                let req: NSFetchRequest<Profile> = Profile.fetchRequest()
                                req.fetchLimit = 1
                                if let ctx = session.managedObjectContext,
                                   let p = try? ctx.fetch(req).first,
                                   let n = p.name, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    return n
                                }
                                return "You"
                            } else {
                                return "User"
                            }
                        }()

                        let loc: String = {
                            if viewerIsOwner {
                                let local = ProfileStore.location(for: ownerIDNonEmpty).trimmingCharacters(in: .whitespacesAndNewlines)
                                if !local.isEmpty { return local }

                                let canonicalOwner = auth.backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if !canonicalOwner.isEmpty {
                                    if let acct = BackendFeedStore.shared.directoryAccountsByUserID[canonicalOwner],
                                       let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                        return s
                                    }
                                    let lower = canonicalOwner.lowercased()
                                    if let acct = BackendFeedStore.shared.directoryAccountsByUserID[lower],
                                       let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                        return s
                                    }
                                }
                                return ""
                            }
                            if let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerIDNonEmpty],
                               let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            let lower = ownerIDNonEmpty.lowercased()
                            if let acct = BackendFeedStore.shared.directoryAccountsByUserID[lower],
                               let s = acct.location?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty {
                                return s
                            }
                            return ""
                        }()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(realName)
                                .font(.subheadline.weight(.semibold))
                            if !loc.isEmpty {
                                Text(loc)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        

                        }
                        .background(
                            identityHeaderHighlight
                                .padding(.trailing, -12)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleHeaderUserFilter(ownerID: ownerIDNonEmpty)
                        }
                        .accessibilityLabel(isHeaderFilterActive ? "Clear user filter" : "Filter feed to this user")

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 0) // tighter feed identity-to-title spacing
                }

                if scope != .mine, let dt = dateTimeLine {
                    Text(dt)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .padding(.bottom, 1)
                        .accessibilityLabel("Date and time")
                        .accessibilityIdentifier("row.datetime")
                }

                if scope != .mine && session.isThought {
                    if let header = session.thoughtHeader {
                        let splitHeader = splitThoughtLead(header)
                        (
                            Text(splitHeader.lead)
                                .font(Theme.Text.body.weight(.semibold))
                                .foregroundColor(Color.primary.opacity(0.86))
                            +
                            Text(splitHeader.remainder)
                                .font(Theme.Text.body)
                                .foregroundColor(Color.primary.opacity(0.78))
                        )
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("row.title")
                    }

                    if let body = session.thoughtBodyPreview {
                        Text(body)
                            .font(Theme.Text.body)
                            .foregroundStyle(Theme.Colors.secondaryText.opacity(0.88))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 1)
                            .accessibilityIdentifier("row.subtitle")
                    }

                    if let fav = favoriteAttachment {
                        HStack(alignment: .center, spacing: 8) {
                            SingleAttachmentPreview(attachment: fav)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 6)

                        if let sid = sessionUUID {
                            interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                                .padding(.top, 6)
                        }
                    } else if let sid = sessionUUID {
                        interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                            .padding(.top, 6)
                    }
                } else {
                    // Title only (paperclip removed)
                    Text(feedTitle)
                        .font(isYearCompactJournalRow ? .subheadline.weight(.semibold) : (isMonthCompactJournalRow ? .subheadline.weight(.medium) : .headline))
                        .lineLimit(isYearCompactJournalRow ? 1 : 2)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("row.title")

                    if scope == .mine {
                        let metaLine = isYearCompactJournalRow ? yearCompactMetadataLine : journalMetadataLine
                        let thread = journalThreadLabel
                        let tailLine = isYearCompactJournalRow ? yearCompactMetadataTailLine : journalMetadataTailLine

                        if let thread, !thread.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    if selectedThread == thread {
                                        selectedThread = nil
                                    } else {
                                        selectedThread = thread
                                    }
                                } label: {
                                    ThreadMetaPill(title: thread, isSelected: selectedThread == thread, font: .caption, verticalPadding: 1)
                                }
                                .buttonStyle(.plain)

                                if !tailLine.isEmpty {
                                    Text(tailLine)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .padding(.top, isYearCompactJournalRow ? 0 : (isMonthCompactJournalRow ? 1 : 1))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Session metadata")
                            .accessibilityIdentifier("row.subtitle")
                        } else if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.secondaryText.opacity(0.72))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.top, isYearCompactJournalRow ? 0 : (isMonthCompactJournalRow ? 1 : 2))
                                .accessibilityLabel("Session metadata")
                                .accessibilityIdentifier("row.subtitle")
                        }

                        if showsJournalNotesPreview, !journalNotesPreviewLines.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(journalNotesPreviewLines.enumerated()), id: \.offset) { _, line in
                                    Text(line.isBullet ? "• \(line.text)" : line.text)
                                        .font(Theme.Text.body)
                                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.96))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            .padding(.top, metaLine.isEmpty ? 4 : 6)
                            .accessibilityLabel("Notes preview")
                            .accessibilityIdentifier("row.notesPreview")
                        }
                    } else {
                        // Instrument / Activity subtitle (metadata) — Thread pill when present (local-only)
                        let metaLine = instrumentActivityLine
                        let thread = journalThreadLabel

                        if let thread, !thread.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Button {
                                    if selectedThread == thread {
                                        selectedThread = nil
                                    } else {
                                        selectedThread = thread
                                    }
                                } label: {
                                    ThreadMetaPill(title: thread, isSelected: selectedThread == thread)
                                }
                                .buttonStyle(.plain)

                                if !metaLine.isEmpty {
                                    Text("·")
                                        .font(Theme.Text.body)

                                    Text(metaLine)
                                        .font(Theme.Text.body)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.top, 3)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Instrument and activity")
                            .accessibilityIdentifier("row.subtitle")
                        } else if !metaLine.isEmpty {
                            Text(metaLine)
                                .font(Theme.Text.body)
                                .lineLimit(2)
                                .padding(.top, 3)
                                .accessibilityLabel("Instrument and activity")
                                .accessibilityIdentifier("row.subtitle")
                        }
                    }

                    if showsJournalAttachmentPreview, let fav = favoriteAttachment {
                        // If viewer isn't the owner, hide preview when favorite is private
                        if viewerIsOwner || !isPrivate(fav) {
                            HStack(alignment: .center, spacing: 8) {
                                SingleAttachmentPreview(attachment: fav)
                                    .scaleEffect(scope == .mine ? 0.92 : 1.0, anchor: .leading)
                                    .opacity(scope == .mine ? 0.96 : 1.0)
                                Spacer()
                            }
                            .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 3 : 5) : 2)
                        }
                        // Interaction row (Like · Comment · Share) — placed directly under thumbnail when present
                        if let sid = sessionUUID {
                            interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                                .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 4 : 7) : 6)
                        }
                    }
                    // Fallback: if there is no thumbnail, place the interaction row below the subtitle
                    else if !isYearCompactJournalRow, let sid = sessionUUID {
                        interactionRow(sessionID: sid, attachmentCount: extraAttachmentCount)
                            .padding(.top, scope == .mine ? (isMonthCompactJournalRow ? 4 : 7) : 6)
                    }
                }
            }
        }
                .padding(.horizontal, isYearCompactJournalRow ? yearCompactHorizontalPadding : 0)
        .padding(.vertical,
            isYearCompactJournalRow ? 1 :
            (isMonthCompactJournalRow ? 3 :
                (scope == .mine ? (!attachments.isEmpty ? 9 : 7) : (!attachments.isEmpty ? 10 : 6)))
        )
        .id(_refreshTick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("row.openDetail")
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { note in
            guard let updates = note.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
            if updates.contains(where: { ($0 as? Attachment)?.session == self.session }) {
                _refreshTick &+= 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            _refreshTick &+= 1
        }
        .task(id: sessionUUID) {
            if let sid = sessionUUID {
                if let vid = viewerUserID {
                isSavedLocal = FeedInteractionStore.isSaved(sid, viewerUserID: vid)
            } else {
                isSavedLocal = false
            }
                // 8H-A: no counts
                commentCountLocal = FeedInteractionStore.commentCount(sid)
            }
        }
        .onReceive(commentsStore.objectWillChange) { _ in
            // Update only when we can resolve a stable comments ID
            if let sid = sessionIDForComments {
                commentCountLocal = commentsStore.comments(for: sid).count
            }
        }
        .sheet(isPresented: $isCommentsPresented) {
            if auth.isConnected, let postID = sessionUUID {
                let raw = (auth.backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let viewerBackendID = raw.isEmpty ? nil : raw.lowercased()
                if let viewerBackendID {
                    CommentsView(
                        postID: postID,
                        ownerUserID: viewerBackendID,
                        viewerUserID: viewerBackendID,
                        ownerDisplayName: auth.displayName,
                        placeholderAuthor: "You"
                    )
                } else {
                    Text("Comments unavailable for this item.").padding()
                }
            } else if let id = sessionIDForComments {
                CommentsView(sessionID: id, placeholderAuthor: "You")
            } else {
                Text("Comments unavailable for this item.").padding()
            }
        }
        .sheet(isPresented: $showPeek) {
            let viewer = viewerUserID ?? ""
            let owner = session.ownerUserID ?? ""
            // Invariant: self-peek must never render follow gating in any mode.
            let ownerForPeek = (owner.isEmpty || owner == viewer) ? (viewer.isEmpty ? owner : viewer) : owner

            let acct = BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek]
                    ?? BackendFeedStore.shared.directoryAccountsByUserID[ownerForPeek.lowercased()]

            ProfilePeekView(
                ownerID: ownerForPeek,
                directoryDisplayName: acct?.displayName,
                directoryAccountID: acct?.accountID,
                directoryLocation: acct?.location,
                directoryAvatarKey: acct?.avatarKey,
                directoryInstruments: acct?.instruments
            )
                .environment(\.managedObjectContext, ctx)
                .environmentObject(auth)
        }
    }


    private var saveHintView: some View {
        VStack(spacing: 2) {
            Text("Saved for later")
                .font(Theme.Text.meta)
                .foregroundStyle(.primary)
            Text("Use Filter to find saved posts")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .transition(.opacity)
    }

    private func presentSaveHint() {
        let token = UUID()
        saveHintToken = token
        withAnimation(.easeInOut(duration: 0.15)) {
            showSaveHint = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            guard saveHintToken == token else { return }
            hideSaveHint()
        }
    }

    private func hideSaveHint() {
        withAnimation(.easeInOut(duration: 1.0)) {
            showSaveHint = false
        }
    }

    @ViewBuilder
    private func interactionRow(sessionID: UUID, attachmentCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSaveHint {
                saveHintView
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
            // Like
            Button(action: {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                let vid = viewerUserID ?? "unknown"
                let newState = FeedInteractionStore.toggleSaved(sessionID, viewerUserID: vid)
                isSavedLocal = newState
                if !hasSeenSaveHint {
                    presentSaveHint()
                    hasSeenSaveHint = true
                }
                // 8H-A: no counts

            }) {
                HStack(spacing: 6) {
                    Image(systemName: isSavedLocal ? "heart.fill" : "heart")
                        .foregroundStyle(isSavedLocal ? Color.red.opacity(0.75) : Theme.Colors.secondaryText)
                }
                .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSavedLocal ? "Unsave" : "Save")

            if scope != .mine {
                // Comment (opens comments sheet)
                Button(action: {
                    // 9D.2: gate comment entry points based on backend follow state (until comments are server-backed)
                    if sessionIDForComments != nil {
                        if viewerIsOwner {
                            isCommentsPresented = true
                        } else if let owner = session.ownerUserID, FollowStore.shared.isFollowing(owner) {
                            isCommentsPresented = true
                        } else {
                            // Fail closed: do nothing.
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: hasComments ? "text.bubble" : "bubble.right")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .font(.system(size: 18, weight: .semibold))

                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comments")

                // Share (owner-only)
                if viewerIsOwner {
                    Button(action: {
                        isShareSheetPresented = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        .contentShape(Rectangle())
                        .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
            }

            Spacer(minLength: 0)

            if attachmentCount > 0 {
                AttachmentCountBadge(count: attachmentCount)
            }
        }
        .padding(.top, scope == .mine ? -1 : -2)
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareToFollowerSheet(postID: sessionID, isPresented: $isShareSheetPresented)
        }
        }
    }

    private func shareText() -> String {
        let title = SessionActivity.feedTitle(for: session)
        return "Check out my session: \(title) — via Études"
    }
}

