import Foundation
import Testing
@testable import FinderFeature

@Suite struct PendingCutTests {
    let t0 = Date(timeIntervalSince1970: 1_000)
    let a = URL(fileURLWithPath: "/a/one"), b = URL(fileURLWithPath: "/a/two")

    @Test func markAndRead() {
        var c = PendingCut()
        c.mark([a, b], now: t0)
        #expect(c.activeItems(now: t0.addingTimeInterval(10)) == [a, b])
        #expect(c.count(now: t0) == 2)
    }
    @Test func expires() {
        var c = PendingCut()
        c.mark([a], now: t0)
        #expect(c.isActive(now: t0.addingTimeInterval(PendingCut.lifetime - 1)))
        #expect(!c.isActive(now: t0.addingTimeInterval(PendingCut.lifetime + 1)))
        #expect(c.count(now: t0.addingTimeInterval(PendingCut.lifetime + 1)) == 0)
    }
    @Test func newCutReplacesAndEmptyCancels() {
        var c = PendingCut()
        c.mark([a], now: t0)
        c.mark([b], now: t0)
        #expect(c.activeItems(now: t0) == [b])
        c.mark([], now: t0)
        #expect(!c.isActive(now: t0))
    }
    @Test func cancel() {
        var c = PendingCut()
        c.mark([a], now: t0)
        c.cancel()
        #expect(c.activeItems(now: t0).isEmpty)
    }
    @Test func duplicatesCollapsed() {
        var c = PendingCut()
        c.mark([a, a, b], now: t0)
        #expect(c.count(now: t0) == 2)
    }
    @Test func expiryDateIsMarkedAtPlusLifetime() {
        var c = PendingCut()
        #expect(c.expiresAt == nil)
        c.mark([a], now: t0)
        #expect(c.expiresAt == t0.addingTimeInterval(PendingCut.lifetime))
    }
    @Test func aPasteboardChangeEndsTheCut() {
        var c = PendingCut()
        c.mark([a], now: t0, pasteboardChangeCount: 5)
        #expect(c.isActive(now: t0, pasteboardChangeCount: 5))
        #expect(!c.isActive(now: t0, pasteboardChangeCount: 6))
        #expect(c.count(now: t0, pasteboardChangeCount: 6) == 0)
        #expect(c.isActive(now: t0))     // no count given: not checked
    }
    @Test func retainKeepsTheFirstMarkedAtAndCount() {
        var c = PendingCut()
        c.mark([a, b], now: t0, pasteboardChangeCount: 5)
        c.retain([b])
        #expect(c.items == [b])
        #expect(c.markedAt == t0 && c.pasteboardChangeCount == 5)
        #expect(!c.isActive(now: t0.addingTimeInterval(PendingCut.lifetime + 1), pasteboardChangeCount: 5))
        c.retain([])
        #expect(c.items.isEmpty && c.markedAt == nil)
    }
}
