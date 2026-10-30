import Testing
@testable import NowPlayingFeature

@Suite struct MediaKeyTests {
    @Test func keyCodes() {
        #expect(MediaKey.playPause.rawValue == 16)
        #expect(MediaKey.next.rawValue == 17)
        #expect(MediaKey.previous.rawValue == 18)
    }

    @Test func playDownData() {
        let e = MediaKeyEvent.compose(.playPause, down: true)
        #expect(e.data1 == 0x100A00)
        #expect(e.modifierFlags == 0xA00)
        #expect(e.subtype == 8)
    }

    @Test func nextUpData() {
        let e = MediaKeyEvent.compose(.next, down: false)
        #expect(e.data1 == 0x110B00)
        #expect(e.modifierFlags == 0xB00)
    }

    @Test func previousDownData() {
        #expect(MediaKeyEvent.compose(.previous, down: true).data1 == 0x120A00)
    }

    @Test func transportPrefersScriptForRunningScriptedSource() async {
        let keys = Box<[MediaKey]>([])
        let scripts = Box<[String]>([])
        let t = NowPlayingTransport(
            runner: StubRunner(scripts: scripts, fail: false),
            running: StubRunning(ids: [BundleIDs.spotify]),
            postKey: { keys.set(keys.get() + [$0]) })
        await t.send(.next, source: BundleIDs.spotify)
        #expect(scripts.get() == ["tell application id \"com.spotify.client\" to next track"])
        #expect(keys.get().isEmpty)
    }

    @Test func transportUsesMediaKeyForOtherSource() async {
        let keys = Box<[MediaKey]>([])
        let t = NowPlayingTransport(
            runner: StubRunner(scripts: Box([]), fail: false), running: StubRunning(ids: []),
            postKey: { keys.set(keys.get() + [$0]) })
        await t.send(.playPause, source: "org.mozilla.firefox")
        #expect(keys.get() == [.playPause])
    }

    @Test func transportFallsBackToKeyWhenScriptFails() async {
        let keys = Box<[MediaKey]>([])
        let t = NowPlayingTransport(
            runner: StubRunner(scripts: Box([]), fail: true), running: StubRunning(ids: [BundleIDs.music]),
            postKey: { keys.set(keys.get() + [$0]) })
        await t.send(.previous, source: BundleIDs.music)
        #expect(keys.get() == [.previous])
    }
}

struct StubRunning: RunningAppChecking {
    let ids: Set<String>
    func isRunning(bundleID: String) -> Bool { ids.contains(bundleID) }
}

struct StubRunner: AppleScriptRunning {
    let scripts: Box<[String]>
    let fail: Bool
    func run(_ source: String) async throws -> ScriptResult {
        scripts.set(scripts.get() + [source])
        if fail { throw NowPlayingError.scriptFailed(code: -1) }
        return ScriptResult(text: "", data: nil)
    }
}
