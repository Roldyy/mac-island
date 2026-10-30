import Foundation
import Testing
@testable import NowPlayingFeature

@MainActor
@Suite struct ModelTests {
    private func defaults() -> MemoryFlags { MemoryFlags() }

    private func model(_ providers: [any NowPlayingProvider], defaults: MemoryFlags,
                       artwork: (any ArtworkLoading)? = nil,
                       artworkTimeout: Duration = .seconds(5)) -> NowPlayingModel {
        NowPlayingModel(providers: providers, defaults: defaults, interval: .milliseconds(10),
                        transport: nil, artwork: artwork, artworkTimeout: artworkTimeout)
    }

    @Test func noQueryBeforeAuthorization() async throws {
        let p = FakeProvider("a", .success(snap("a", playing: true)))
        let m = model([p], defaults: defaults())
        m.setVisible(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(p.calls.get() == 0)
        #expect(m.access == .needsAuthorization)
        m.setVisible(false)
    }

    @Test func authorizeQueriesAndPublishes() async {
        let p = FakeProvider("a", .success(snap("a", playing: true)))
        let m = model([p], defaults: defaults())
        m.setVisible(true)
        await m.authorize()
        #expect(m.access == .ready)
        #expect(m.snapshot?.sourceBundleID == "a")
        m.setVisible(false)
    }

    @Test func deniedShowsState() async {
        let p = FakeProvider("a", .failure(.permissionDenied))
        let m = model([p], defaults: defaults())
        await m.authorize()
        #expect(m.access == .denied)
        #expect(m.snapshot == nil)
    }

    @Test func authorizedFlagPersistsAcrossModels() async throws {
        let d = defaults()
        let m1 = model([FakeProvider("a", .success(nil))], defaults: d)
        await m1.authorize()
        m1.setVisible(false)
        let p = FakeProvider("a", .success(snap("a", playing: true)))
        let m2 = model([p], defaults: d)
        #expect(m2.access == .ready)
        m2.setVisible(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(p.calls.get() > 0)
        m2.setVisible(false)
    }

    @Test func hiddenStopsPolling() async throws {
        let d = defaults()
        let p = FakeProvider("a", .success(snap("a", playing: true)))
        let m = model([p], defaults: d)
        await m.authorize()
        m.setVisible(true)
        try await Task.sleep(for: .milliseconds(60))
        m.setVisible(false)
        try await Task.sleep(for: .milliseconds(30))
        let n = p.calls.get()
        try await Task.sleep(for: .milliseconds(80))
        #expect(p.calls.get() == n)
    }

    @Test func slowEarlierCoverNeverOverwritesTheNewTrack() async throws {
        let p = FakeProvider("a", .success(snap("a", title: "slow", playing: true)))
        let loader = FakeLoader(delays: ["slow": .milliseconds(200)])
        let m = model([p], defaults: defaults(), artwork: loader)
        let first = Task { await m.poll() }
        try await Task.sleep(for: .milliseconds(30))   // the slow fetch is in flight
        p.result.set(.success(snap("a", title: "fast", playing: true)))
        await m.poll()
        await first.value
        #expect(await eventually { m.artwork == Data("fast".utf8) })
        try await Task.sleep(for: .milliseconds(300))  // the slow one finishes now
        #expect(m.artwork == Data("fast".utf8))
    }

    @Test func pollDoesNotWaitForTheCoverDownload() async {
        let p = FakeProvider("a", .success(snap("a", title: "hang", playing: true)))
        let loader = FakeLoader(delays: ["hang": .seconds(30)])
        let m = model([p], defaults: defaults(), artwork: loader, artworkTimeout: .milliseconds(100))
        let start = ContinuousClock.now
        await m.poll()
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(m.snapshot?.title == "hang")
        #expect(m.artwork == nil)
    }

    @Test func hungCoverTimesOutAndTheNextTrackStillGetsItsCover() async {
        let p = FakeProvider("a", .success(snap("a", title: "hang", playing: true)))
        let loader = FakeLoader(delays: ["hang": .seconds(30)])
        let m = model([p], defaults: defaults(), artwork: loader, artworkTimeout: .milliseconds(100))
        await m.poll()
        p.result.set(.success(snap("a", title: "next", playing: true)))
        await m.poll()
        #expect(await eventually { m.artwork == Data("next".utf8) })
    }

    @Test func coverIsClearedWhenTheTrackChanges() async {
        let p = FakeProvider("a", .success(snap("a", title: "one", playing: true)))
        let loader = FakeLoader(delays: ["two": .seconds(30)])
        let m = model([p], defaults: defaults(), artwork: loader, artworkTimeout: .seconds(5))
        await m.poll()
        #expect(await eventually { m.artwork == Data("one".utf8) })
        p.result.set(.success(snap("a", title: "two", playing: true)))
        await m.poll()
        #expect(m.artwork == nil)   // never the previous track's cover
    }
}
