import Foundation
import IslandKit
import Testing
@testable import ShellKit

@MainActor
private final class FakeLock: ScreenLocking {
    let result: Bool
    private(set) var calls = 0
    init(_ result: Bool) { self.result = result }
    func lock() -> Bool { calls += 1; return result }
}

@MainActor
@Suite struct QuickAccessSupportTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let date = Date(timeIntervalSince1970: 1_000_000_000)  // 2001-09-09 01:46:40 UTC

    @Test func lockUsesThePreferredLockerFirst() {
        let a = FakeLock(true), b = FakeLock(true)
        #expect(ScreenLockChain.lock(primary: a, fallback: b) == .locked)
        #expect(a.calls == 1 && b.calls == 0)
    }

    @Test func lockFallsBackWhenPrimaryMissingOrFailing() {
        let b = FakeLock(true)
        #expect(ScreenLockChain.lock(primary: nil, fallback: b) == .lockedByFallback)
        let a = FakeLock(false), c = FakeLock(true)
        #expect(ScreenLockChain.lock(primary: a, fallback: c) == .lockedByFallback)
        #expect(a.calls == 1 && c.calls == 1)
        #expect(ScreenLockChain.lock(primary: nil, fallback: FakeLock(false)) == .failed)
    }

    @Test func screenshotArgumentsAreFixed() {
        let url = URL(fileURLWithPath: "/tmp/x.png")
        #expect(ScreenshotPlan.arguments(file: url) == ["-i", "-t", "png", "/tmp/x.png"])
    }

    @Test func screenshotNameHasNoColonAndNeverOverwrites() {
        #expect(ScreenshotPlan.fileName(date: date, timeZone: utc) == "Capture Mac Island 2001-09-09 01.46.40.png")
        let dir = URL(fileURLWithPath: "/tmp/d")
        let first = dir.appendingPathComponent("Capture Mac Island 2001-09-09 01.46.40.png")
        let taken: Set<URL> = [first, dir.appendingPathComponent("Capture Mac Island 2001-09-09 01.46.40 2.png")]
        #expect(ScreenshotPlan.destination(in: dir, date: date, timeZone: utc, exists: { _ in false }) == first)
        #expect(ScreenshotPlan.destination(in: dir, date: date, timeZone: utc, exists: { taken.contains($0) }).lastPathComponent
                == "Capture Mac Island 2001-09-09 01.46.40 3.png")
    }

    @Test func permissionNoticeNamesThePane() {
        #expect(QuickActionNotice.permission(.screenRecording) == "Accès requis : Enregistrement de l'écran")
    }

    @Test func toggleButtonReportsItsState() {
        let t = QuickActionTable()
        var on = false
        #expect(!t.isOn("keepawake"))
        t.registerState("keepawake") { on }
        #expect(!t.isOn("keepawake"))
        on = true
        #expect(t.isOn("keepawake"))
        #expect(QuickAccessCatalog.item("keepawake")?.activeSystemImage == "cup.and.saucer.fill")
        #expect(QuickAccessCatalog.item("settings")?.activeSystemImage == nil)
    }
}
