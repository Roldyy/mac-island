import Foundation
import Testing
@testable import ShelfFeature

@Suite struct DownloadFilterTests {
    @Test(arguments: ["a.crdownload", "a.DOWNLOAD", "a.part", "a.opdownload", "a.tmp", ".DS_Store",
                      ".localized", ".hidden.txt", "", "a.zip.crdownload"])
    func partialOrHidden(name: String) {
        #expect(DownloadFilter.isPartialOrHidden(name))
    }

    @Test(arguments: ["a.zip", "report.pdf", "partial.txt", "download", "x.crdownloaded"])
    func finishedNames(name: String) {
        #expect(!DownloadFilter.isPartialOrHidden(name))
    }
}

@Suite struct DownloadTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func freshlyModifiedIsNotFinished() {
        var tr = DownloadTracker(settle: 2)
        let r1 = tr.isFinished(path: "/d/a", size: 10, modified: t0, now: t0.addingTimeInterval(1))
        #expect(!r1)
    }

    @Test func oldAndFirstSeenIsFinished() {
        var tr = DownloadTracker(settle: 2)
        let r2 = tr.isFinished(path: "/d/a", size: 10, modified: t0, now: t0.addingTimeInterval(5))
        #expect(r2)
    }

    @Test func growingFileWaitsForSettle() {
        var tr = DownloadTracker(settle: 2)
        let r3 = tr.isFinished(path: "/d/a", size: 10, modified: t0, now: t0.addingTimeInterval(5))
        #expect(r3)
        // size changed, even though mtime looks old (clock skew): not finished
        let r4 = tr.isFinished(path: "/d/a", size: 20, modified: t0, now: t0.addingTimeInterval(6))
        #expect(!r4)
        // unchanged but observed change less than settle ago
        let r5 = tr.isFinished(path: "/d/a", size: 20, modified: t0, now: t0.addingTimeInterval(7))
        #expect(!r5)
        let r6 = tr.isFinished(path: "/d/a", size: 20, modified: t0, now: t0.addingTimeInterval(8.5))
        #expect(r6)
    }

    @Test func futureModificationDateReliesOnSizeStabilityAlone() {
        var tr = DownloadTracker(settle: 2)
        let future = t0.addingTimeInterval(3600)
        let r1 = tr.isFinished(path: "/d/a", size: 10, modified: future, now: t0)
        let r2 = tr.isFinished(path: "/d/a", size: 10, modified: future, now: t0.addingTimeInterval(1))
        let r3 = tr.isFinished(path: "/d/a", size: 10, modified: future, now: t0.addingTimeInterval(2.5))
        #expect(!r1 && !r2 && r3)
        // still growing: waits again
        let r4 = tr.isFinished(path: "/d/a", size: 20, modified: future, now: t0.addingTimeInterval(3))
        let r5 = tr.isFinished(path: "/d/a", size: 20, modified: future, now: t0.addingTimeInterval(5.5))
        #expect(!r4 && r5)
    }

    @Test func forgetsPathsThatDisappear() {
        var tr = DownloadTracker(settle: 2)
        _ = tr.isFinished(path: "/d/a", size: 1, modified: t0, now: t0.addingTimeInterval(5))
        tr.retain(only: ["/d/b"])
        #expect(tr.observedCount == 0)
    }
}

@Suite struct DownloadsListerTests {
    @Test func newestFirstLimitedAndFiltered() {
        let dir = makeTempDir()
        let now = Date()
        let old = makeFile("old.pdf", in: dir); setModified(old, now.addingTimeInterval(-300))
        let mid = makeFile("mid.zip", in: dir); setModified(mid, now.addingTimeInterval(-200))
        let new = makeFile("new.png", in: dir); setModified(new, now.addingTimeInterval(-100))
        let part = makeFile("x.crdownload", in: dir); setModified(part, now.addingTimeInterval(-400))
        let hidden = makeFile(".DS_Store", in: dir); setModified(hidden, now.addingTimeInterval(-10))
        var tracker = DownloadTracker(settle: 2)
        let snap = DownloadsLister.list(directory: dir, limit: 2, now: now, tracker: &tracker)
        #expect(snap.state == .ok)
        #expect(snap.items.map(\.name) == ["new.png", "mid.zip"])
        #expect(!snap.hasPending)
    }

    @Test func stillWritingFileIsHiddenAndPending() {
        let dir = makeTempDir()
        let now = Date()
        makeFile("fresh.bin", in: dir)
        var tracker = DownloadTracker(settle: 2)
        let snap = DownloadsLister.list(directory: dir, limit: 8, now: now, tracker: &tracker)
        #expect(snap.items.isEmpty)
        #expect(snap.hasPending)
        let later = DownloadsLister.list(directory: dir, limit: 8, now: now.addingTimeInterval(5), tracker: &tracker)
        #expect(later.items.map(\.name) == ["fresh.bin"])
        #expect(!later.hasPending)
    }

    @Test func missingDirectory() {
        var tracker = DownloadTracker()
        let snap = DownloadsLister.list(directory: makeTempDir().appendingPathComponent("nope"),
                                        limit: 8, now: .now, tracker: &tracker)
        #expect(snap.state == .missing)
    }

    @Test func blockedDirectoryReportsDenied() throws {
        let dir = makeTempDir()
        makeFile("a.txt", in: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        var tracker = DownloadTracker()
        let snap = DownloadsLister.list(directory: dir, limit: 8, now: .now, tracker: &tracker)
        #expect(snap.state == .denied)
        #expect(snap.items.isEmpty)
    }

    @Test func symlinkIsListedButFlagged() throws {
        let dir = makeTempDir()
        let target = makeFile("t.txt", in: makeTempDir())
        let link = dir.appendingPathComponent("l")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        setModified(target, .now.addingTimeInterval(-100))
        var tracker = DownloadTracker(settle: 2)
        let snap = DownloadsLister.list(directory: dir, limit: 8, now: .now.addingTimeInterval(100), tracker: &tracker)
        #expect(snap.items.count == 1)
        #expect(snap.items[0].isSymlink)
    }
}

@Suite struct ShelfSettingsTests {
    @Test func defaultsAndClamps() {
        let t = TempDefaults()
        let s = ShelfSettings(defaults: t.defaults)
        #expect(s.shelfEnabled)
        #expect(s.downloadsEnabled)
        #expect(s.downloadsLimit == 8)
        t.defaults.set(false, forKey: "shelfEnabled")
        t.defaults.set(0, forKey: "shelfDownloadsLimit")
        #expect(!s.shelfEnabled)
        #expect(s.downloadsLimit == 1)
        t.defaults.set(9999, forKey: "shelfDownloadsLimit")
        #expect(s.downloadsLimit == 50)
        #expect(ShelfSettings.suiteName == "be.roldy.macisland")
    }
}

private final class FakeAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var _granted = false
    private var _opens = 0
    private var _lists = 0
    private var _snaps: [DownloadsSnapshot] = []
    let dir: URL
    init(dir: URL) { self.dir = dir }

    var granted: Bool { get { lock.withLock { _granted } } set { lock.withLock { _granted = newValue } } }
    var opens: Int { lock.withLock { _opens } }
    var lists: Int { lock.withLock { _lists } }
    var snaps: [DownloadsSnapshot] { lock.withLock { _snaps } }
    func record(_ s: DownloadsSnapshot) { lock.withLock { _snaps.append(s) } }

    var fileSystem: DownloadsFileSystem {
        DownloadsFileSystem(
            list: { [self] _, _, _, _ in
                lock.withLock { _lists += 1 }
                let ok = granted
                return DownloadsSnapshot(state: ok ? .ok : .denied, items: [], hasPending: false)
            },
            openForEvents: { [self] path in
                guard granted else { return -1 }
                lock.withLock { _opens += 1 }
                return open(path, O_EVTONLY)
            })
    }
}

/// The monitor publishes with `DispatchQueue.main.async`, and a full run queues about a thousand main-actor tests
/// ahead of that block (measured: it can wait over a minute behind them). A short deadline therefore tests the
/// machine, not the monitor. The deadline only costs time when the behaviour really is wrong.
private func waitUntil(timeout: TimeInterval = 240, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@Suite struct DownloadsMonitorTests {
    @Test func deniedThenGrantedReattachesOnRefresh() async {
        let access = FakeAccess(dir: makeTempDir())
        let monitor = DownloadsMonitor(directory: access.dir, fileSystem: access.fileSystem,
                                       limit: { 8 }, onSnapshot: { access.record($0) })
        monitor.start()
        #expect(await waitUntil { access.snaps.last?.state == .denied })
        #expect(access.opens == 0)

        monitor.refresh()
        #expect(await waitUntil { access.snaps.count >= 2 })
        #expect(access.snaps.last?.state == .denied)
        #expect(access.opens == 0)

        access.granted = true   // the user grants access in System Settings
        monitor.refresh()
        #expect(await waitUntil { access.snaps.last?.state == .ok })
        #expect(access.opens == 1)

        // attached for real: a new file in the folder triggers a rescan without any refresh()
        let before = access.lists
        makeFile("new.zip", in: access.dir)
        #expect(await waitUntil { access.lists > before })

        monitor.refresh()
        try? await Task.sleep(for: .milliseconds(300))   // a negative check: nothing to wait for, only to give it a chance
        #expect(access.opens == 1) // idempotent: never a second source
        monitor.stop()
    }
}
