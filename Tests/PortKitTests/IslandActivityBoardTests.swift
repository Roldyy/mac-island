import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit

/// Wave 8 (group 2): the board that turns the ported features' state into closed-island activities, and the "Combiner"
/// choice. A recorder stands in for `ActivityCenter`; no sleep is real.
@MainActor
@Suite(.serialized) struct IslandActivityBoardTests {
    final class Recorder: IslandActivityPosting {
        var live: [String: IslandActivity] = [:]
        var posts = 0
        var withdrawals: [String] = []
        func post(_ activity: IslandActivity, expiresAfter: Duration?) {
            posts += 1
            live[activity.id] = activity
        }
        func withdraw(id: String) {
            withdrawals.append(id)
            live.removeValue(forKey: id)
        }
    }

    struct Rig {
        let board: IslandActivityBoard
        let recorder: Recorder
        let defaults: UserDefaults
        let cleanup: () -> Void
    }

    func rig(sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }) -> Rig {
        let recorder = Recorder()
        let bench = TestDefaults.make()
        let board = IslandActivityBoard(poster: { recorder }, defaults: { bench.defaults }, sleep: sleep)
        board.register(IslandActivitySource(id: "notchDownloads", title: "Téléchargements", symbol: "arrow.down.circle"))
        board.register(IslandActivitySource(id: "notchWatch", title: "Surveillance", symbol: "eye"))
        return Rig(board: board, recorder: recorder, defaults: bench.defaults, cleanup: bench.cleanup)
    }

    let download = IslandActivity(id: "downloads.progress", source: "notchDownloads", priority: .ambient,
                                  leading: CompactItem(symbol: "arrow.down.circle", status: .info, progress: 0.4),
                                  trailing: CompactItem(symbol: "arrow.down", text: "40 %", status: .info))
    let watch = IslandActivity(id: "watch.state", source: "notchWatch", priority: .alert,
                               leading: CompactItem(symbol: "eye", status: .success),
                               trailing: CompactItem(symbol: "checkmark.circle", text: "Terminé", status: .success))

    @Test func theClosedIslandStaysAsItWasWhileNothingIsPosted() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.recorder.live.isEmpty && r.recorder.posts == 0, "no feature on: nothing reaches the island")
        #expect(r.board.offeredCombinations.isEmpty)
        #expect(r.board.combination == nil)
    }

    @Test func aLoneActivityGoesToTheCenterUnchangedAndWithdrawsCleanly() {
        let r = rig()
        defer { r.cleanup() }
        r.board.post(download)
        #expect(r.recorder.live == ["downloads.progress": download])
        r.board.withdraw(id: "downloads.progress")
        #expect(r.recorder.live.isEmpty)
        r.board.withdraw(id: "downloads.progress")
        #expect(r.recorder.withdrawals == ["downloads.progress"], "a second withdraw tells the center nothing")
    }

    @Test func aFeatureTurningOffDropsEverythingItPosted() {
        let r = rig()
        defer { r.cleanup() }
        r.board.post(download)
        r.board.post(watch)
        r.board.withdrawAll(source: "notchDownloads")
        #expect(Set(r.recorder.live.keys) == ["watch.state"])
    }

    @Test func theMenuOffersPairsOfActiveSourcesOnlyAndNamesThemLeftToRight() {
        let r = rig()
        defer { r.cleanup() }
        r.board.post(download)
        #expect(r.board.offeredCombinations.isEmpty, "one source cannot pair with itself")
        r.board.post(watch)
        let pairs = r.board.offeredCombinations
        #expect(pairs == [IslandCombination(primary: "notchDownloads", companion: "notchWatch"),
                          IslandCombination(primary: "notchWatch", companion: "notchDownloads")])
        #expect(r.board.title(of: pairs[0]) == "Surveillance + Téléchargements", "companion on the left, primary on the right")
    }

    @Test func aChosenPairBecomesOneMergedActivityAndSplitsWhenOneEnds() {
        let r = rig()
        defer { r.cleanup() }
        r.board.post(download)
        r.board.post(watch)
        r.board.select(IslandCombination(primary: "notchDownloads", companion: "notchWatch"))
        #expect(Set(r.recorder.live.keys) == [IslandActivityBoard.combinedID], "the two it replaces are withdrawn")
        let merged = r.recorder.live[IslandActivityBoard.combinedID]
        #expect(merged?.leading?.symbol == "eye" && merged?.leading?.text == nil, "the companion's mark only")
        #expect(merged?.trailing == download.trailing, "the primary keeps its reading right of the camera")
        #expect(merged?.priority == .alert, "the better of the two")
        #expect(merged?.showsDot == false)
        // The watch ends: the download comes back by itself, the merge goes.
        r.board.withdrawAll(source: "notchWatch")
        #expect(r.recorder.live == ["downloads.progress": download])
        // It is back: the choice was only waiting.
        r.board.post(watch)
        #expect(Set(r.recorder.live.keys) == [IslandActivityBoard.combinedID])
        r.board.select(nil)
        #expect(Set(r.recorder.live.keys) == ["downloads.progress", "watch.state"], "separated again")
    }

    @Test func theChoiceIsStoredAndASecondBoardReadsIt() {
        let r = rig()
        defer { r.cleanup() }
        let pair = IslandCombination(primary: "notchWatch", companion: "notchDownloads")
        r.board.select(pair)
        #expect(r.defaults.string(forKey: IslandCombination.storageKey) == "notchWatch+notchDownloads")
        let other = IslandActivityBoard(poster: { Recorder() }, defaults: { r.defaults })
        #expect(other.combination == pair)
        r.defaults.set("garbage", forKey: IslandCombination.storageKey)
        #expect(other.combination == nil)
        #expect(IslandCombination(stored: "a+a") == nil && IslandCombination(stored: "+b") == nil)
    }

    @Test func anExpiringActivityLeavesOnItsOwnAndAReplacementKeepsItsOwnClock() async throws {
        let r = rig(sleep: { _ in try await Task.sleep(for: .milliseconds(20)) })
        defer { r.cleanup() }
        r.board.post(download, expiresAfter: .milliseconds(20))
        #expect(r.recorder.live.count == 1)
        // Polled, not slept: a loaded main actor can run the expiry task seconds late (waits tolerate a long backlog).
        let deadline = ContinuousClock.now + .seconds(120)
        while !r.recorder.live.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.recorder.live.isEmpty, "gone after its lifetime")
        // Posted again without a lifetime before the first one ran out: the old clock must not take it down.
        r.board.post(watch, expiresAfter: .milliseconds(20))
        r.board.post(watch)
        try await Task.sleep(for: .milliseconds(400))
        #expect(r.recorder.live["watch.state"] == watch)
    }
}
