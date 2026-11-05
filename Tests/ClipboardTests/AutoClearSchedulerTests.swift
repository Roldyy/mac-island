import AppKit
import Testing
@testable import ClipboardFeature

@Suite @MainActor struct AutoClearSchedulerTests {
    @Test func clearsAfterDelayWhenUnchanged() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("secret", forType: .string)
        let scheduler = AutoClearScheduler(pasteboard: pb)
        var cleared = 0
        scheduler.didClear = { _ in cleared += 1 }
        scheduler.schedule(delaySeconds: 0.15, expectedChangeCount: pb.changeCount)
        #expect(await eventually { cleared == 1 })
        #expect(pb.string(forType: .string) == nil)
    }

    @Test func laterCopyIsNotCleared() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("first", forType: .string)
        let scheduler = AutoClearScheduler(pasteboard: pb)
        var cleared = 0
        scheduler.didClear = { _ in cleared += 1 }
        scheduler.schedule(delaySeconds: 0.15, expectedChangeCount: pb.changeCount)
        pb.clearContents(); pb.setString("second", forType: .string)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(pb.string(forType: .string) == "second")
        #expect(cleared == 0)
    }

    @Test func rescheduleCancelsTheOldTimer() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("a", forType: .string)
        let scheduler = AutoClearScheduler(pasteboard: pb)
        scheduler.schedule(delaySeconds: 0.15, expectedChangeCount: pb.changeCount)
        scheduler.schedule(delaySeconds: 0, expectedChangeCount: pb.changeCount)   // off: cancels
        try await Task.sleep(nanoseconds: 450_000_000)
        #expect(pb.string(forType: .string) == "a")
    }

    /// `didClear` carries the count read in the clear's own lane block, not one read later.
    @Test func didClearReceivesTheCountOfTheClear() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("secret", forType: .string)
        let before = pb.changeCount
        let scheduler = AutoClearScheduler(pasteboard: pb)
        var received: Int?
        scheduler.didClear = { count in
            received = count
            pb.clearContents(); pb.setString("copied after", forType: .string)   // a later copy must not leak in
        }
        scheduler.schedule(delaySeconds: 0.15, expectedChangeCount: before)
        #expect(await eventually { received != nil })
        #expect(received == before + 1)
        #expect(pb.changeCount > before + 1)
    }
}
