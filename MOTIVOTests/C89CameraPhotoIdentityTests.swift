//
//  C89CameraPhotoIdentityTests.swift
//  MOTIVOTests
//
//  C-89 — A CAMERA PHOTO STAGED IN THE TIMER MUST HAVE ONE ID.
//
//  `stageImage` showed the photo under one id and staged it without `id:`, so
//  the store minted another. Both delete paths look the ref up by the visible
//  id, found nothing, and the next foreground mirror restored the photo.
//
//  `PracticeTimerView` is driven by SwiftUI `@State`, which XCTest cannot drive
//  here (the C-84 constraint), so:
//   - S-1 and S-2 pin the executable staging calls. COMMENTS ARE REMOVED FIRST,
//     and each call's own argument list is inspected. They are the only cases
//     that fail against the old product.
//   - B-1…B-3 run the real store with the fixed and the old CALL SHAPES,
//     reloading `staged.json` from disk. They establish the store contract the
//     fix relies on; they do not execute the view.
//
//  STORE HYGIENE: the simulator's staging store is snapshotted in setUp and
//  restored exactly in tearDown -- `staged.json` existence and bytes, the legacy
//  `stagedAttachments_v2` defaults key (which `loadRefs` migrates and removes
//  when the file is absent), and the day folders (`cleanupAbandoned()` deletes
//  empty ones). Only files this test created are removed.
//

import XCTest
@testable import Etudes

@MainActor
final class C89CameraPhotoIdentityTests: XCTestCase {

    // MARK: - Store snapshot

    private let legacyDefaultsKey = "stagedAttachments_v2"
    private var refsURL: URL { StagingStore.baseURL.appendingPathComponent("staged.json") }

    private var baseExisted = false
    private var refsExisted = false
    private var refsBytes: Data?
    private var legacyDefaults: Data?
    private var dirsBefore: Set<String> = []
    private var emptyDirsBefore: Set<String> = []
    private var ownedPaths: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        let fm = FileManager.default
        baseExisted = fm.fileExists(atPath: StagingStore.baseURL.path)
        refsExisted = fm.fileExists(atPath: refsURL.path)
        refsBytes = refsExisted ? try Data(contentsOf: refsURL) : nil
        legacyDefaults = UserDefaults.standard.data(forKey: legacyDefaultsKey)
        (dirsBefore, emptyDirsBefore) = Self.stagingDirectories()
        try StagingStore.bootstrap()
    }

    override func tearDown() async throws {
        let fm = FileManager.default
        for p in ownedPaths where fm.fileExists(atPath: p.path) { try? fm.removeItem(at: p) }
        ownedPaths = []

        if let refsBytes {
            try refsBytes.write(to: refsURL, options: .atomic)
        } else if fm.fileExists(atPath: refsURL.path) {
            try fm.removeItem(at: refsURL)
        }
        if let legacyDefaults {
            UserDefaults.standard.set(legacyDefaults, forKey: legacyDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }

        let (dirsNow, _) = Self.stagingDirectories()
        for d in emptyDirsBefore where !fm.fileExists(atPath: d) {
            try? fm.createDirectory(atPath: d, withIntermediateDirectories: true)
        }
        for d in dirsNow.subtracting(dirsBefore) where (try? fm.contentsOfDirectory(atPath: d))?.isEmpty == true {
            try? fm.removeItem(atPath: d)
        }
        if !baseExisted, (try? fm.contentsOfDirectory(atPath: StagingStore.baseURL.path))?.isEmpty == true {
            try? fm.removeItem(at: StagingStore.baseURL)
        }

        XCTAssertEqual(fm.fileExists(atPath: refsURL.path), refsExisted, "teardown: staged.json existence is restored")
        if let refsBytes {
            XCTAssertEqual(try? Data(contentsOf: refsURL), refsBytes, "teardown: staged.json content is restored")
        }
        XCTAssertEqual(UserDefaults.standard.data(forKey: legacyDefaultsKey), legacyDefaults,
                       "teardown: the legacy staging defaults key is restored")
        XCTAssertEqual(Self.stagingDirectories().empty.intersection(emptyDirsBefore), emptyDirsBefore,
                       "teardown: pre-existing empty staging folders are restored")
        try await super.tearDown()
    }

    private static func stagingDirectories() -> (all: Set<String>, empty: Set<String>) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: StagingStore.baseURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return ([], [])
        }
        var all = Set<String>(), empty = Set<String>()
        for u in items where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            all.insert(u.path)
            if (try? fm.contentsOfDirectory(atPath: u.path))?.isEmpty == true { empty.insert(u.path) }
        }
        return (all, empty)
    }

    // MARK: - Call shapes

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0xFF, 0xD9])

    /// What `stageImage` writes first: `tmp/<visible id>.jpg`.
    private func cameraTemp(for id: UUID) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
        ownedPaths.append(tmp)
        try Self.jpeg.write(to: tmp, options: .atomic)
        return tmp
    }

    /// Tracked before any assertion can fail.
    private func own(_ ref: StagedAttachmentRef) {
        ownedPaths.append(StagingStore.absoluteURL(for: ref))
        if let p = ref.posterPath { ownedPaths.append(StagingStore.absoluteURL(forRelative: p)) }
    }

    /// The FIXED call in `stageImage`.
    private func stageFixedShape(_ id: UUID) async throws -> StagedAttachmentRef {
        let ref = try await StagingStore.saveNew(from: try cameraTemp(for: id), kind: .image,
                                                 suggestedName: id.uuidString, duration: nil, poster: nil, id: id)
        own(ref)
        return ref
    }

    /// The PRE-FIX call in `stageImage`: no `id:`.
    private func stageOldShape(_ id: UUID) async throws -> StagedAttachmentRef {
        let ref = try await StagingStore.saveNew(from: try cameraTemp(for: id), kind: .image,
                                                 suggestedName: id.uuidString, duration: nil, poster: nil)
        own(ref)
        return ref
    }

    /// Exactly what both delete paths do (`AttachmentsCard`, the viewer's `onDelete`).
    @discardableResult
    private func deleteLikeTheTimer(visibleID: UUID) -> Bool {
        if let ref = StagingStore.list().first(where: { $0.id == visibleID }) {
            StagingStore.remove(ref)
            return true
        }
        return false
    }

    /// A reload: `staged.json` decoded from disk, independently of the store's reader.
    private func refsOnDisk() throws -> [StagedAttachmentRef] {
        guard FileManager.default.fileExists(atPath: refsURL.path) else { return [] }
        return try JSONDecoder().decode([StagedAttachmentRef].self, from: Data(contentsOf: refsURL))
    }

    private func stem(_ ref: StagedAttachmentRef) -> String {
        URL(fileURLWithPath: ref.relativePath).deletingPathExtension().lastPathComponent
    }

    // MARK: - B-1

    func testCompletedPhotoStageDeletedByVisibleIDStaysDeletedAfterReload() async throws {
        let visible = UUID()
        let ref = try await stageFixedShape(visible)
        let media = StagingStore.absoluteURL(for: ref)
        XCTAssertEqual(ref.id, visible, "B-1: the stored ref carries the visible id")
        XCTAssertEqual(media.deletingPathExtension().lastPathComponent, visible.uuidString, "B-1: …and so does its file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path), "B-1 precondition: the media is staged")
        XCTAssertTrue(try refsOnDisk().contains { $0.id == visible }, "B-1 precondition: the ref is on disk")

        XCTAssertTrue(deleteLikeTheTimer(visibleID: visible), "B-1: the delete path finds the ref by the visible id")

        let reloaded = try refsOnDisk()
        XCTAssertFalse(reloaded.contains { $0.id == visible }, "B-1: after reload the ref is gone")
        XCTAssertFalse(reloaded.contains { stem($0) == visible.uuidString }, "B-1: no ref for this photo remains under any id")
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path), "B-1: the media is gone")

        StagingStore.cleanupAbandoned()
        XCTAssertFalse(try refsOnDisk().contains { stem($0) == visible.uuidString }, "B-1: cleanup brings no ref back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.path), "B-1: …and no media")
    }

    // MARK: - B-2 (negative control)

    func testOldCallShapeLeavesTheMismatchedRefOnDisk() async throws {
        let visible = UUID()
        let ref = try await stageOldShape(visible)
        let media = StagingStore.absoluteURL(for: ref)
        XCTAssertNotEqual(ref.id, visible, "B-2 control: the old call shape stores a different id")
        XCTAssertEqual(media.deletingPathExtension().lastPathComponent, visible.uuidString,
                       "B-2 control: …while the file is named for the visible id")

        XCTAssertFalse(deleteLikeTheTimer(visibleID: visible), "B-2 control: the delete path finds nothing by the visible id")

        let left = try refsOnDisk().filter { $0.kind == .image && stem($0) == visible.uuidString }
        XCTAssertEqual(left.map(\.id), [ref.id], "B-2 control: after reload the photo's ref remains, under the store's id")
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.path),
                      "B-2 control: …with its media — exactly what the foreground mirror restores")
    }

    // MARK: - B-3

    func testReconciliationInputsAgreeAfterACompletedPhotoStage() async throws {
        let visible = UUID()
        _ = try await stageFixedShape(visible)
        func storeImageIDs() throws -> Set<UUID> {
            Set(try refsOnDisk().filter { $0.kind == .image && stem($0) == visible.uuidString }.map(\.id))
        }
        XCTAssertEqual(try storeImageIDs(), [visible],
                       "B-3: the store's image ids for this photo equal the visible ids, so the timer's idsDiffer stays false")
        deleteLikeTheTimer(visibleID: visible)
        XCTAssertEqual(try storeImageIDs(), [], "B-3: after the delete, both are empty")
    }

    // MARK: - S-1

    func testStageImagePassesTheVisibleIDToTheStore() throws {
        let src = try timerSource()
        let body = try XCTUnwrap(src.body(ofFunction: "stageImage"), "S-1: func stageImage not found")
        let calls = src.calls(to: "StagingStore.saveNew(", within: body)
        XCTAssertEqual(calls.count, 1, "S-1: stageImage makes exactly one staging call")
        guard let call = calls.first else { return }
        XCTAssertTrue(call.arguments.contains("kind: .image"), "S-1: it stages an image — \(call.arguments)")
        XCTAssertTrue(call.arguments.contains("id: id"),
                      "S-1: it must pass the visible id (`id: id`) — found \(call.arguments)")
    }

    // MARK: - S-2

    func testEveryTimerStagingCallKeepsOneIdentity() throws {
        let src = try timerSource()
        let calls = src.calls(to: "StagingStore.saveNew(", within: 0..<src.c.count)
        XCTAssertEqual(calls.count, 4, "S-2: the timer's staging calls are audio, video, camera photo and trim")
        var unclassified: [String] = []
        for call in calls {
            if call.arguments.contains(where: { $0.hasPrefix("id:") }) { continue }
            if call.arguments.contains("kind: .audio"), src.reKeysToReturnedID(call) { continue }
            unclassified.append(call.arguments.joined(separator: ", "))
        }
        XCTAssertEqual(unclassified, [],
                       "S-2: every staging call must pass the visible id, or (audio) re-key to the returned ref.id")
    }

    // MARK: - Source helpers (comments removed; strings kept and skipped)

    private func timerSource() throws -> SwiftSource {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO/PracticeTimerView.swift")
        return SwiftSource(stripping: try String(contentsOf: url, encoding: .utf8))
    }
}

/// A NARROW source reader for these assertions, not a Swift parser. It skips
/// `"…"` and `"""…"""` literals (including `\( … )`), removes `//` and nested
/// `/* */` comments, and matches brackets outside literals. Raw `#"…"#` strings
/// are not modelled.
private struct SwiftSource {
    let c: [Character]

    struct Call {
        let start: Int
        let close: Int
        let arguments: [String]
    }

    init(stripping text: String) {
        let s = Array(text)
        var out: [Character] = []
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if s[i] == "\"" {
                let end = SwiftSource.endOfString(s, at: i)
                out.append(contentsOf: s[i..<end]); i = end
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "/" {
                while i < s.count, s[i] != "\n" { i += 1 }
            } else if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" {
                var depth = 0
                while i < s.count {
                    if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" { depth += 1; i += 2; continue }
                    if s[i] == "*", i + 1 < s.count, s[i + 1] == "/" { depth -= 1; i += 2; if depth == 0 { break }; continue }
                    i += 1
                }
            } else {
                out.append(s[i]); i += 1
            }
        }
        c = out
    }

    /// Index just past the string literal starting at `i`.
    static func endOfString(_ s: [Character], at i: Int) -> Int {
        let triple = i + 2 < s.count && s[i + 1] == "\"" && s[i + 2] == "\""
        var j = i + (triple ? 3 : 1)
        while j < s.count {
            if s[j] == "\\" {
                if j + 1 < s.count, s[j + 1] == "(" {
                    var depth = 1; j += 2
                    while j < s.count, depth > 0 {
                        if s[j] == "\"" { j = endOfString(s, at: j); continue }
                        if s[j] == "(" { depth += 1 } else if s[j] == ")" { depth -= 1 }
                        j += 1
                    }
                    continue
                }
                j += 2; continue
            }
            if s[j] == "\"" {
                if !triple { return j + 1 }
                if j + 2 < s.count, s[j + 1] == "\"", s[j + 2] == "\"" { return j + 3 }
            }
            if !triple, s[j] == "\n" { return j }
            j += 1
        }
        return s.count
    }

    func occurrences(of needle: String, in range: Range<Int>) -> [Int] {
        let n = Array(needle)
        var out: [Int] = []
        var i = range.lowerBound
        while i + n.count <= range.upperBound {
            if c[i] == "\"" { i = SwiftSource.endOfString(c, at: i); continue }
            var k = 0
            while k < n.count, c[i + k] == n[k] { k += 1 }
            if k == n.count { out.append(i) }
            i += 1
        }
        return out
    }

    /// Index of the bracket that closes the one at `open`.
    func matching(_ open: Int) -> Int? {
        let pairs: [Character: Character] = ["(": ")", "{": "}", "[": "]"]
        guard let close = pairs[c[open]] else { return nil }
        var depth = 0
        var j = open
        while j < c.count {
            if c[j] == "\"" { j = SwiftSource.endOfString(c, at: j); continue }
            if c[j] == c[open] { depth += 1 } else if c[j] == close { depth -= 1; if depth == 0 { return j } }
            j += 1
        }
        return nil
    }

    /// The brace-delimited body of `func name(`.
    func body(ofFunction name: String) -> Range<Int>? {
        for start in occurrences(of: "func \(name)(", in: 0..<c.count) {
            guard let paren = matching(start + "func \(name)".count),
                  let open = (paren..<c.count).first(where: { c[$0] == "{" }),
                  let close = matching(open) else { continue }
            return open..<(close + 1)
        }
        return nil
    }

    /// Every call to `callee` (ending in `(`) within `range`, with its top-level arguments.
    func calls(to callee: String, within range: Range<Int>) -> [Call] {
        occurrences(of: callee, in: range).compactMap { start in
            let open = start + callee.count - 1
            guard let close = matching(open) else { return nil }
            var args: [String] = []
            var current: [Character] = []
            var depth = 0
            var j = open + 1
            while j < close {
                let ch = c[j]
                if ch == "\"" {
                    let end = SwiftSource.endOfString(c, at: j)
                    current.append(contentsOf: c[j..<end]); j = end; continue
                }
                if "([{".contains(ch) { depth += 1 } else if ")]}".contains(ch) { depth -= 1 }
                if ch == ",", depth == 0 {
                    args.append(String(current).trimmingCharacters(in: .whitespacesAndNewlines)); current = []
                } else {
                    current.append(ch)
                }
                j += 1
            }
            let last = String(current).trimmingCharacters(in: .whitespacesAndNewlines)
            if !last.isEmpty { args.append(last) }
            return Call(start: start, close: close, arguments: args)
        }
    }

    /// The innermost function body that contains `index`.
    func enclosingFunctionBody(of index: Int) -> Range<Int>? {
        var best: Range<Int>?
        for f in occurrences(of: "func ", in: 0..<index) {
            if f > 0, c[f - 1].isLetter || c[f - 1].isNumber || c[f - 1] == "_" { continue }
            guard let open = (f..<c.count).first(where: { c[$0] == "{" }), open < index,
                  let close = matching(open), close > index else { continue }
            if best == nil || open > best!.lowerBound { best = open..<(close + 1) }
        }
        return best
    }

    /// The audio path: the call's result is bound to `ref`, and the SAME function
    /// then re-keys the visible item to `ref.id`.
    func reKeysToReturnedID(_ call: Call) -> Bool {
        guard let fn = enclosingFunctionBody(of: call.start) else { return false }
        let binding = Array("let ref = try await ")
        guard call.start >= binding.count, Array(c[(call.start - binding.count)..<call.start]) == binding else { return false }
        let after = call.close..<fn.upperBound
        return !occurrences(of: "if ref.id != id", in: after).isEmpty
            && !occurrences(of: "StagedAttachment(id: ref.id", in: after).isEmpty
    }
}
