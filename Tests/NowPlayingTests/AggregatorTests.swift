import Foundation
import Testing
@testable import NowPlayingFeature

@Suite struct AggregatorTests {
    private func make() -> (NowPlayingAggregator, Box<Date>) {
        let now = Box(Date(timeIntervalSince1970: 1000))
        return (NowPlayingAggregator(clock: { now.get() }), now)
    }

    @Test func emptyGivesNil() {
        var (agg, _) = make()
        #expect(agg.select(from: []) == nil)
    }

    @Test func playingBeatsPaused() {
        var (agg, _) = make()
        let r = agg.select(from: [snap("a", playing: false), snap("b", playing: true)])
        #expect(r?.sourceBundleID == "b")
    }

    @Test func mostRecentlyStartedPlayingWins() {
        var (agg, now) = make()
        _ = agg.select(from: [snap("a", playing: true), snap("b", playing: false)])
        now.set(now.get().addingTimeInterval(5))
        let r = agg.select(from: [snap("a", playing: true), snap("b", playing: true)])
        #expect(r?.sourceBundleID == "b")
        now.set(now.get().addingTimeInterval(5))
        // a keeps playing, b keeps playing: b started later, still wins
        #expect(agg.select(from: [snap("a", playing: true), snap("b", playing: true)])?.sourceBundleID == "b")
    }

    @Test func pausedPicksMostRecentlyPlayed() {
        var (agg, now) = make()
        _ = agg.select(from: [snap("a", playing: true), snap("b", playing: false)])
        now.set(now.get().addingTimeInterval(10))
        _ = agg.select(from: [snap("a", playing: false), snap("b", playing: true)])
        now.set(now.get().addingTimeInterval(10))
        let r = agg.select(from: [snap("a", playing: false), snap("b", playing: false)])
        #expect(r?.sourceBundleID == "b")
    }

    @Test func neverPlayedTiesKeepInputOrder() {
        var (agg, _) = make()
        let r = agg.select(from: [snap("a", playing: false), snap("b", playing: false)])
        #expect(r?.sourceBundleID == "a")
    }

    @Test func currentSkipsNilAndSwallowsFailures() async {
        var (agg, _) = make()
        let providers: [any NowPlayingProvider] = [
            FakeProvider("x", .success(nil)),
            FakeProvider("y", .failure(.scriptFailed(code: -1))),
            FakeProvider("z", .success(snap("z", playing: true))),
        ]
        let out = await agg.current(from: providers)
        #expect(out.snapshot?.sourceBundleID == "z")
        #expect(out.permissionDenied == false)
    }

    @Test func currentReportsDeniedWhenNothingElse() async {
        var (agg, _) = make()
        let out = await agg.current(from: [FakeProvider("x", .failure(.permissionDenied))])
        #expect(out.snapshot == nil)
        #expect(out.permissionDenied)
    }
}
