import AppKit
import Foundation
import Testing
@testable import IslandKit

/// NSPasteboard keeps a mutable type cache on the shared general instance; two threads inside it crashed 1.1.0
/// (SIGABRT in `-[NSPasteboard _updateTypeCacheIfNeeded]`). Everything touching the general pasteboard goes through
/// ONE serial lane. These tests pin the lane's behaviour and scan the sources for a path around it.
@Suite struct GeneralPasteboardLaneTests {
    /// A pasteboard stand-in that counts how many callers are inside it at once.
    final class FakePasteboard: @unchecked Sendable {
        private let lock = NSLock()
        private var inside = 0
        private(set) var maxInside = 0
        private(set) var entries = 0
        func read() {
            lock.lock(); inside += 1; entries += 1; maxInside = max(maxInside, inside); lock.unlock()
            usleep(300)   // long enough for a second thread to walk in if nothing serialised them
            lock.lock(); inside -= 1; lock.unlock()
        }
    }

    @Test func readersFromManyThreadsNeverOverlapOnTheLane() {
        let lane = GeneralPasteboardLane(label: "test.lane.overlap")
        let fake = FakePasteboard()
        let group = DispatchGroup()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<40 {
                group.enter()
                lane.async { fake.read(); group.leave() }
            }
        }
        #expect(group.wait(timeout: .now() + 30) == .success)
        #expect(fake.entries == 320)
        #expect(fake.maxInside == 1, "two readers were inside the pasteboard at the same time")
    }

    @Test func withoutTheLaneTheSameReadersDoOverlap() {
        // Control: proves the fake can see an overlap, so the test above is not vacuous.
        let fake = FakePasteboard()
        let group = DispatchGroup()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<10 { fake.read() }
        }
        group.wait()
        #expect(fake.maxInside > 1)
    }

    @Test func workKeepsItsSubmissionOrder() {
        let lane = GeneralPasteboardLane(label: "test.lane.order")
        let box = OrderBox()
        let group = DispatchGroup()
        for i in 0..<50 { group.enter(); lane.async { box.append(i); group.leave() } }
        #expect(group.wait(timeout: .now() + 10) == .success)
        #expect(box.values == Array(0..<50))
    }
    final class OrderBox: @unchecked Sendable {
        private let lock = NSLock(); private var items: [Int] = []
        func append(_ i: Int) { lock.lock(); items.append(i); lock.unlock() }
        var values: [Int] { lock.lock(); defer { lock.unlock() }; return items }
    }

    @Test func aWedgedLaneNeverBlocksTheCaller() {
        let lane = GeneralPasteboardLane(label: "test.lane.wedged")
        let gate = DispatchSemaphore(value: 0)
        lane.async { gate.wait() }                 // the pasteboard server stopped answering
        let start = Date()
        lane.async({ 1 }, then: { _ in })          // submitting returns at once
        #expect(Date().timeIntervalSince(start) < 1)
        gate.signal()
    }

    /// The hub's count read shares the app-wide lane: held behind a busy lane, it does not run.
    @Test @MainActor func theHubReadsTheCountOnTheSharedLane() async {
        let gate = DispatchSemaphore(value: 0)
        GeneralPasteboardLane.shared.async { gate.wait() }
        final class Flag: @unchecked Sendable { var answered = false }
        let flag = Flag()
        PasteboardChangeHub.generalReader { _ in flag.answered = true }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!flag.answered, "the hub read the pasteboard beside the lane instead of through it")
        gate.signal()
        let deadline = Date().addingTimeInterval(10)
        while !flag.answered && Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(flag.answered)
    }
}

/// Source scan: no file may touch `NSPasteboard.general` outside the lane, except the listed ones.
@Suite struct PasteboardLaneGuardTests {
    private static let sources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Files that ARE the lane or build on it: every access in them is deliberate and reviewed.
    private static let laneFiles: [String: String] = [
        "IslandKit/GeneralPasteboardLane.swift": "the lane itself",
        "IslandKit/PasteboardChangeHub.swift": "generalReader: the count is read inside GeneralPasteboardLane.shared.async",
        "PortKit/Services/GeneralPasteboardAccess.swift": "the imported facade; shares GeneralPasteboardLane's queue (patch 2400)",
        "Features/Clipboard/PasteboardWatcher.swift": "constructor default only; every read runs through its lane (PasteboardLaneReader)",
        "Features/Clipboard/ClipboardModel.swift": "constructor default only; writes go through GeneralPasteboardLane.shared",
        "PortKit/Services/Clipboard/ClipboardHistoryService.swift": "readPasteboard(): documented lane-only helper, its callers submit it to GeneralPasteboardAccess",
        "PortKit/Services/URLCleanerService.swift": "writeToPasteboard() / pollPasteboard(): lane-only helpers, every caller submits them to GeneralPasteboardAccess",
    ]

    /// Main-thread accesses that are NOT behind the lane yet: a one-shot the user triggers by a click or a key, or a
    /// synchronous answer an event tap needs. The ratchet: the count per file may only go DOWN. Move one behind the
    /// lane and lower the number; a new file or a higher count fails the test.
    private static let knownMainThreadResiduals: [String: (max: Int, why: String)] = [
        "Features/Finder/PasteboardReading.swift": (1, "event tap needs the answer now (Cmd+V in Finder): types / canReadObject / data"),
        "PortKit/Compat/ShareStubs.swift": (2, "copy-link buttons, result Bool is returned to the caller"),
        "PortKit/Services/Finder/FinderCutPaste.swift": (2, "event tap reads the count to decide whether Cmd+V is a move, and the image-paste anchor; the cut write and cancel are on the lane (patch 2402)"),
        "PortKit/Services/Homebrew/HomebrewManager.swift": (1, "copy-for-terminal click, uses setString's Bool"),
        "PortKit/Services/QuickTools/ScreenshotService.swift": (2, "changeCount snapshot (no `types` read, the call behind the 1.1.0 crashes) before a detached task"),
        "PortKit/Services/QuickTools/ScreenTextService.swift": (2, "changeCount snapshot (no `types` read) before a detached task"),
        "PortKit/Services/Recorder/RecorderEditorController.swift": (1, "export-to-clipboard click, uses writeObjects' Bool"),
        "PortKit/Services/Recorder/RecorderGIFClipboard.swift": (1, "default argument of an injectable writer"),
        "PortKit/Services/Snippets/SnippetLibraryService.swift": (1, "snippet {clipboard} variable: synchronous read inside an expansion"),
        "PortKit/Services/Snippets/TextSnippetService.swift": (1, "snippet {clipboard} variable: synchronous read inside an expansion"),
        "PortKit/UI/MenuPanel/ClipboardEntryPreviewSidebar.swift": (2, "changeCount snapshots only"),
    ]

    private static let pattern = try! NSRegularExpression(
        pattern: #"NSPasteboard\.general|NSPasteboard\s*=\s*\.general|\bfrom:\s*\.general\b"#)
    private static let laneMarkers = ["GeneralPasteboardAccess.shared.async", "GeneralPasteboardLane.shared.async", "lane.async"]

    /// Hits per file that are neither on a comment line nor within 14 lines after a lane submission.
    private static func unlanedHits() -> [String: Int] {
        var result: [String: Int] = [:]
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for url in files {
            let rel = String(url.path.dropFirst(sources.path.count + 1))
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard pattern.firstMatch(in: line, range: range) != nil else { continue }
                let window = lines[max(0, i - 14)...i]
                if window.contains(where: { l in laneMarkers.contains(where: l.contains) }) { continue }
                result[rel, default: 0] += 1
            }
        }
        return result
    }

    @Test func noFileTouchesTheGeneralPasteboardOutsideTheLane() {
        let hits = Self.unlanedHits()
        var problems: [String] = []
        for (file, count) in hits.sorted(by: { $0.key < $1.key }) {
            if Self.laneFiles[file] != nil { continue }
            if let known = Self.knownMainThreadResiduals[file] {
                if count > known.max { problems.append("\(file): \(count) direct accesses, the ratchet allows \(known.max)") }
            } else {
                problems.append("\(file): \(count) direct access(es) to NSPasteboard.general outside GeneralPasteboardLane")
            }
        }
        #expect(problems.isEmpty, Comment(rawValue: "\n" + problems.joined(separator: "\n")))
    }

    @Test func theResidualListStaysHonest() {
        let hits = Self.unlanedHits()
        for (file, known) in Self.knownMainThreadResiduals {
            let count = hits[file] ?? 0
            #expect(count > 0, "\(file) no longer touches the general pasteboard off the lane: remove it from the list")
            if count < known.max { Issue.record("\(file): \(count) left, list says \(known.max): lower the ratchet") }
        }
        for file in Self.laneFiles.keys {
            #expect(FileManager.default.fileExists(atPath: Self.sources.appendingPathComponent(file).path), "\(file) moved")
        }
    }

    /// Drag, find and app-private pasteboards have their own type cache: the scan above only matches `.general`,
    /// and a named pasteboard stays out of it on purpose.
    @Test func theScanSeesTheWholeTree() {
        let swift = FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.count ?? 0
        #expect(swift > 300)
    }
}
