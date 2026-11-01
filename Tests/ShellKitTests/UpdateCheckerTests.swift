import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

@Suite struct ReleaseVersionTests {
    @Test func parsesTagsWithAndWithoutV() {
        #expect(ReleaseVersion("v2.0.1")?.numbers == [2, 0, 1])
        #expect(ReleaseVersion("1.0")?.numbers == [1, 0])
        #expect(ReleaseVersion("2.0.0-beta.2")?.preRelease == ["beta", "2"])
        #expect(ReleaseVersion("développement") == nil)
        #expect(ReleaseVersion("") == nil)
    }

    @Test func ordersLikeSemanticVersions() throws {
        func v(_ s: String) throws -> ReleaseVersion { try #require(ReleaseVersion(s)) }
        #expect(try v("1.0.0") < v("1.0.1"))
        #expect(try v("1.9") < v("1.10"))
        #expect(try !(v("1.0") < v("1.0.0")) && !(v("1.0.0") < v("1.0")))
        #expect(try v("2.0.0-beta.1") < v("2.0.0"))
        #expect(try v("2.0.0-beta.1") < v("2.0.0-beta.2"))
        #expect(try v("2.0.0-beta.2") < v("2.0.0-beta.10"))
        #expect(try !(v("2.0.0") < v("2.0.0")))
    }
}

@MainActor
@Suite struct UpdateCheckerTests {
    static let body = """
    [
      {"tag_name": "v2.1.0-beta.1", "html_url": "https://github.com/Roldyy/mac-island/releases/tag/v2.1.0-beta.1", "prerelease": true, "draft": false, "body": "bêta"},
      {"tag_name": "v2.0.0", "html_url": "https://github.com/Roldyy/mac-island/releases/tag/v2.0.0", "prerelease": false, "draft": false, "body": "Notes 2.0"},
      {"tag_name": "v9.9.9", "html_url": "https://github.com/Roldyy/mac-island/releases/tag/v9.9.9", "prerelease": false, "draft": true},
      {"tag_name": "v1.0.0", "html_url": "https://evil.example/x", "prerelease": false, "draft": false},
      {"tag_name": "v1.0.0", "html_url": "https://github.com/Roldyy/mac-island/releases/tag/v1.0.0", "draft": false}
    ]
    """

    func checker(current: String, now: Date = Date(timeIntervalSince1970: 1_000_000)) -> UpdateChecker {
        UpdateChecker(fetch: { _ in Data(Self.body.utf8) }, currentVersion: { current }, now: { now })
    }

    @Test func draftsAndForeignLinksAreLeftOut() throws {
        let releases = try UpdateChecker.parse(Data(Self.body.utf8))
        #expect(releases.map(\.tag) == ["v2.1.0-beta.1", "v2.0.0", "v1.0.0"])
        #expect(releases.first { $0.tag == "v2.1.0-beta.1" }?.isPreRelease == true)
        #expect(releases.allSatisfy { $0.pageURL.host == "github.com" })
    }

    @Test func aNewerReleaseIsOfferedAndABetaOnlyWhenAsked() async throws {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let c = checker(current: "1.0.0")
        await c.check(defaults: bench.defaults)
        guard case .available(let release) = c.state else { Issue.record("state \(c.state)"); return }
        #expect(release.tag == "v2.0.0")
        #expect(release.notes == "Notes 2.0")
        bench.defaults.set(true, forKey: UpdateChecker.betaKey)
        await c.check(defaults: bench.defaults)
        guard case .available(let beta) = c.state else { Issue.record("state \(c.state)"); return }
        #expect(beta.tag == "v2.1.0-beta.1")
    }

    @Test func theInstalledVersionIsUpToDate() async {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let c = checker(current: "2.0.0")
        await c.check(defaults: bench.defaults)
        #expect(c.state == .upToDate)
        #expect(c.lastCheck == Date(timeIntervalSince1970: 1_000_000))
        #expect(bench.defaults.double(forKey: UpdateChecker.lastCheckKey) == 1_000_000)
    }

    @Test func aDevelopmentBuildIsNeverCalledUpToDate() async {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let c = checker(current: "développement")
        await c.check(defaults: bench.defaults)
        guard case .failed = c.state else { Issue.record("state \(c.state)"); return }
    }

    @Test func aNetworkFailureIsSaidAndKeepsNoStamp() async {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let c = UpdateChecker(fetch: { _ in throw URLError(.notConnectedToInternet) }, currentVersion: { "1.0.0" })
        await c.check(defaults: bench.defaults)
        guard case .failed = c.state else { Issue.record("state \(c.state)"); return }
        #expect(bench.defaults.object(forKey: UpdateChecker.lastCheckKey) == nil)
    }

    @Test func theAutomaticCheckHonoursItsSwitchAndTheDay() async {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let calls = Box(0)
        let c = UpdateChecker(fetch: { _ in calls.value += 1; return Data(Self.body.utf8) }, currentVersion: { "1.0.0" },
                              now: { Date(timeIntervalSince1970: 5_000_000) })
        bench.defaults.set(false, forKey: UpdateChecker.autoKey)
        await c.checkIfStale(defaults: bench.defaults)
        #expect(calls.value == 0, "switch off: no request")
        bench.defaults.set(true, forKey: UpdateChecker.autoKey)
        bench.defaults.set(5_000_000.0 - 3600, forKey: UpdateChecker.lastCheckKey)
        await c.checkIfStale(defaults: bench.defaults)
        #expect(calls.value == 0, "checked an hour ago: no request")
        bench.defaults.set(5_000_000.0 - 3 * 86_400, forKey: UpdateChecker.lastCheckKey)
        await c.checkIfStale(defaults: bench.defaults)
        #expect(calls.value == 1, "checked three days ago: one request")
    }

    @Test func whatsNewOpensOnceAfterAnUpdateOnly() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        #expect(!WhatsNewAfterUpdate.consume(defaults: bench.defaults, current: "1.0.0"), "first run only records")
        #expect(!WhatsNewAfterUpdate.consume(defaults: bench.defaults, current: "1.0.0"))
        #expect(WhatsNewAfterUpdate.consume(defaults: bench.defaults, current: "2.0.0"), "a new version opens it")
        #expect(!WhatsNewAfterUpdate.consume(defaults: bench.defaults, current: "2.0.0"), "once")
        bench.defaults.set(false, forKey: WhatsNewAfterUpdate.wantedKey)
        #expect(!WhatsNewAfterUpdate.consume(defaults: bench.defaults, current: "3.0.0"), "switched off")
    }
}

/// A thread-safe counter for the `@Sendable` fakes above.
private final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
