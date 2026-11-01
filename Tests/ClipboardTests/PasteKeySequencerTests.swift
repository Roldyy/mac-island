import ApplicationServices
import Testing
@testable import ClipboardFeature

@Suite @MainActor struct PasteKeySequencerTests {
    final class Rig {
        var sleeps = 0
        var posted: [CGEventFlags] = []
        var sleepsAtPost: [Int] = []
        var postResult = true
    }

    /// `heldFor`: how many sleeps the modifiers stay down (nil = never released).
    func sequencer(_ rig: Rig, heldFor: Int?) -> PasteKeySequencer {
        PasteKeySequencer(
            modifiersHeld: { heldFor.map { rig.sleeps < $0 } ?? true },
            sleep: { _ in rig.sleeps += 1 },
            post: { flags in
                rig.posted.append(flags)
                rig.sleepsAtPost.append(rig.sleeps)
                return rig.postResult
            })
    }

    @Test func heldThenReleasedPostsOnlyAfterReleaseWithOnlyCommand() async {
        let rig = Rig()
        let result = await sequencer(rig, heldFor: 3).run()
        #expect(result == .posted)
        #expect(rig.posted == [.maskCommand])
        #expect(rig.sleepsAtPost == [3])                       // not before the third poll saw them up
        #expect(!rig.posted[0].contains(.maskAlternate))
    }

    @Test func alreadyReleasedPostsAtOnce() async {
        let rig = Rig()
        _ = await sequencer(rig, heldFor: 0).run()
        #expect(rig.sleepsAtPost == [0])
        #expect(rig.posted == [.maskCommand])
    }

    @Test func timeoutStillPostsWithClearedFlags() async {
        let rig = Rig()
        let result = await sequencer(rig, heldFor: nil).run()
        #expect(result == .posted)
        #expect(rig.sleeps == PasteKeySequencer.maxPolls)      // about 1 s of 10 ms polls
        #expect(rig.posted == [.maskCommand])                  // Option is never in the posted flags
    }

    @Test func failedEventCreationIsReported() async {
        let rig = Rig()
        rig.postResult = false
        #expect(await sequencer(rig, heldFor: 0).run() == .eventFailed)
    }

    @Test func pollWindowIsAboutOneSecond() {
        let total = PasteKeySequencer.pollInterval * PasteKeySequencer.maxPolls
        #expect(total == .seconds(1))
    }
}
