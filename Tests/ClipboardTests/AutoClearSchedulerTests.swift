import AppKit
import Testing
@testable import ClipboardFeature

@Suite @MainActor struct AutoClearSchedulerTests {
    @Test func clearsAfterDelayWhenUnchanged() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("secret", forType: .string)
        let scheduler = AutoClearScheduler(pasteboard: pb)
        var cleared = 0
        scheduler.didClear = { cleared += 1 }
        scheduler.schedule(delaySeconds: 0.15, expectedChangeCount: pb.changeCount)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(pb.string(forType: .string) == nil)
        #expect(cleared == 1)
    }

    @Test func laterCopyIsNotCleared() async throws {
        let pb = makePasteboard()
        pb.clearContents(); pb.setString("first", forType: .string)
        let scheduler = AutoClearScheduler(pasteboard: pb)
        var cleared = 0
        scheduler.didClear = { cleared += 1 }
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
}
