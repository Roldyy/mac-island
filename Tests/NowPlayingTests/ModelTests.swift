import Foundation
import Testing
@testable import NowPlayingFeature

@MainActor
@Suite struct ModelTests {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "np-test-\(UUID().uuidString)")!
        return d
    }

    private func model(_ providers: [any NowPlayingProvider], defaults: UserDefaults) -> NowPlayingModel {
        NowPlayingModel(providers: providers, defaults: defaults, interval: .milliseconds(10),
                        transport: nil, artwork: nil)
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
}
