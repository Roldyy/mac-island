import Foundation
import Testing
@testable import NowPlayingFeature

/// The real Spotify path, as far as it can be reproduced without Spotify: what the status script returns and how
/// it is read, then every outcome of the reading (granted and playing, paused, empty, refused, never asked, no
/// answer, player not found, unreadable, hung) and what the Home card is told about it. Fakes only: no
/// AppleScript, no TCC, no player.
@Suite struct StatusParsingTests {
    private let sep = "\u{1F}"

    private func raw(_ f: [String]) -> String { f.joined(separator: sep) }

    @Test func spotifyPlayingWithThePlayersOwnFormats() throws {
        // Spotify: position in seconds as a real, duration in milliseconds as an integer.
        let s = try #require(try PlayerScriptParser.parse(
            raw(["playing", "Reason", "Bonobo", "Migration", "83.4", "215000", "https://i.scdn.co/image/ab67"]),
            bundleID: BundleIDs.spotify, durationUnit: .milliseconds))
        #expect(s.isPlaying && s.position == 83.4 && s.duration == 215)
        #expect(s.progress.map { abs($0 - 83.4 / 215) < 0.0001 } == true)
    }

    @Test func aFrenchDecimalSeparatorAndScientificNotation() throws {
        let s = try #require(try PlayerScriptParser.parse(
            raw(["paused", "T", "A", "B", "83,4", "2,15E+5", ""]), bundleID: BundleIDs.spotify,
            durationUnit: .milliseconds))
        #expect(!s.isPlaying && s.position == 83.4 && s.duration == 215)
    }

    @Test func titlesWithCommasQuotesAndEmojiSurvive() throws {
        let title = "Hello, \"World\" - Part 2 (feat. A, B) 🎵 é"
        let s = try #require(try PlayerScriptParser.parse(
            raw(["playing", title, "Artist, With Comma", "Album \"Q\"", "1", "1000", ""]),
            bundleID: BundleIDs.spotify, durationUnit: .milliseconds))
        #expect(s.title == title && s.artist == "Artist, With Comma" && s.album == "Album \"Q\"")
    }

    @Test func rawStateCodesAreReadWhenTheDictionaryWasNotApplied() throws {
        let playing = try #require(try PlayerScriptParser.parse(
            raw(["«constant ****kPSP»", "T", "A", "B", "1", "1000", ""]), bundleID: "x", durationUnit: .seconds))
        #expect(playing.isPlaying)
        let paused = try #require(try PlayerScriptParser.parse(
            raw(["«constant ****kPSp»", "T", "A", "B", "1", "1000", ""]), bundleID: "x", durationUnit: .seconds))
        #expect(!paused.isPlaying)
        #expect(try PlayerScriptParser.parse(raw(["«constant ****kPSS»", "", "", "", "0", "0", ""]),
                                              bundleID: "x", durationUnit: .seconds) == nil)
    }

    @Test func missingValueFieldsBecomeEmptyAndTheTrackIsStillRead() throws {
        let s = try #require(try PlayerScriptParser.parse(
            raw(["playing", "missing value", "missing value", "missing value", "missing value", "missing value",
                 "missing value"]), bundleID: BundleIDs.spotify, durationUnit: .milliseconds))
        #expect(s.title == "" && s.artist == "" && s.album == "" && s.artworkURL == nil)
        #expect(s.position == 0 && s.duration == 0, "an unreadable number never loses the track")
    }

    @Test func aNonHttpArtworkIsIgnored() throws {
        let s = try #require(try PlayerScriptParser.parse(
            raw(["playing", "T", "A", "B", "1", "1", "file:///etc/passwd"]), bundleID: "x", durationUnit: .seconds))
        #expect(s.artworkURL == nil)
    }

    @Test func musicStatesThatMeanPlaying() throws {
        for state in ["fast forwarding", "rewinding"] {
            let s = try #require(try PlayerScriptParser.parse(
                raw([state, "T", "A", "B", "1", "100", ""]), bundleID: BundleIDs.music, durationUnit: .seconds))
            #expect(s.isPlaying)
        }
    }

    @Test func stoppedAndNotRunningAreTheOnlyEmptyAnswers() throws {
        #expect(try PlayerScriptParser.parse("stopped", bundleID: "x", durationUnit: .seconds) == nil)
        #expect(try PlayerScriptParser.parse("none", bundleID: "x", durationUnit: .seconds) == nil)
        #expect(try PlayerScriptParser.parse(raw(["stopped", "", "", "", "0", "0", ""]),
                                              bundleID: "x", durationUnit: .seconds) == nil)
    }

    @Test func anEmptyReplyIsAFaultNotNothingLoaded() {
        for text in ["", "  \n"] {
            #expect(throws: NowPlayingError.emptyReply) {
                try PlayerScriptParser.parse(text, bundleID: "x", durationUnit: .seconds)
            }
        }
    }

    @Test func anUnreadableReplyIsAFault() {
        #expect(throws: NowPlayingError.malformedOutput) {
            try PlayerScriptParser.parse("something else entirely", bundleID: "x", durationUnit: .seconds)
        }
        #expect(throws: NowPlayingError.malformedOutput) {   // an unknown state word
            try PlayerScriptParser.parse(raw(["buffering", "T", "A", "B", "1", "1", ""]), bundleID: "x",
                                         durationUnit: .seconds)
        }
        #expect(throws: NowPlayingError.malformedOutput) {   // a title that holds the separator: 8 fields
            try PlayerScriptParser.parse(raw(["playing", "T", "A", "B", "1", "1", "", "x"]), bundleID: "x",
                                         durationUnit: .seconds)
        }
    }

    @Test func theStatusScriptReadsEveryFieldOnItsOwnAndHasATimeout() {
        let script = PlayerScripts.status(bundleID: BundleIDs.spotify)
        #expect(script.contains("with timeout of 4 seconds"))
        // The first Apple Event is outside any `try`, so -1743 / -1744 / -1712 reach the caller.
        let firstTry = script.range(of: "try")!.lowerBound
        let state = script.range(of: "player state as text")!.lowerBound
        #expect(state < firstTry)
        #expect(script.components(separatedBy: "    try\n").count - 1 >= 6, "one try per track field")
        #expect(script.contains("artwork url of current track"))
        let music = PlayerScripts.status(bundleID: BundleIDs.music)
        #expect(!music.contains("artwork url"))
    }

    @Test func errorNumbersMapToTheirOwnCase() {
        #expect(NowPlayingError.from(scriptErrorCode: -1744) == .consentRequired)
        #expect(NowPlayingError.from(scriptErrorCode: -1712) == .timedOut)
        #expect(NowPlayingError.from(scriptErrorCode: -600) == .appNotFound)
        #expect(NowPlayingError.from(scriptErrorCode: -10004) == .scriptFailed(code: -10004))
        for error in [NowPlayingError.permissionDenied, .consentRequired, .timedOut, .appNotFound, .noCurrentTrack,
                      .scriptFailed(code: -10004)] {
            #expect(NowPlayingError.from(scriptErrorCode: error.code!) == error)
        }
    }

    @Test func everyFaultLineNamesThePlayerAndANumberAndNothingElse() {
        let errors: [NowPlayingError] = [.permissionDenied, .consentRequired, .timedOut, .appNotFound, .noCurrentTrack,
                                         .emptyReply, .malformedOutput, .scriptFailed(code: -10004)]
        let lines = errors.map { NowPlayingFault($0, bundleID: BundleIDs.spotify).line }
        #expect(lines == [
            "Spotify : autorisation refusée (-1743)",
            "Spotify : autorisation à accorder (-1744)",
            "Spotify : pas de réponse (-1712)",
            "Spotify : application introuvable (-600)",
            "Spotify : aucun morceau lisible (-1728)",
            "Spotify : réponse vide",
            "Spotify : réponse illisible",
            "Spotify : erreur AppleScript (-10004)",
        ])
        #expect(NowPlayingFault(.timedOut, bundleID: BundleIDs.music).line == "Musique : pas de réponse (-1712)")
    }
}

/// A runner that answers with a fixed result or error.
struct CannedRunner: AppleScriptRunning {
    let result: Result<ScriptResult, NowPlayingError>
    func run(_ source: String) async throws -> ScriptResult { try result.get() }
}

@Suite struct ProviderOutcomeTests {
    private let sep = "\u{1F}"

    private func provider(_ result: Result<ScriptResult, NowPlayingError>) -> SpotifyProvider {
        SpotifyProvider(runner: CannedRunner(result: result), running: StubRunning(ids: [BundleIDs.spotify]))
    }

    @Test func aPlayingReplyIsAPlayingSnapshot() async throws {
        let text = ["playing", "Reason", "Bonobo", "Migration", "10", "215000", ""].joined(separator: sep)
        let s = try await provider(.success(ScriptResult(text: text, data: nil))).snapshot()
        #expect(s?.title == "Reason" && s?.isPlaying == true && s?.duration == 215)
    }

    @Test func aReplyThatIsNotAStringIsEmptyNotNothingLoaded() async {
        await #expect(throws: NowPlayingError.emptyReply) {
            try await provider(.success(ScriptResult(text: nil, data: nil))).snapshot()
        }
    }

    @Test func everyScriptErrorReachesTheCaller() async {
        for error in [NowPlayingError.permissionDenied, .consentRequired, .timedOut, .appNotFound, .noCurrentTrack,
                      .scriptFailed(code: -10004)] {
            await #expect(throws: error) { try await provider(.failure(error)).snapshot() }
        }
    }

    @Test func aClosedPlayerIsNilWithoutRunningAnyScript() async throws {
        let closed = SpotifyProvider(runner: CannedRunner(result: .failure(.timedOut)), running: StubRunning(ids: []))
        #expect(try await closed.snapshot() == nil)
    }
}

/// Counts every silent permission check and where it ran.
final class ThreadAwareAutomation: AutomationChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var status: AutomationStatus
    private var silent = 0
    private var prompts = 0
    private var mainThread = 0
    init(_ status: AutomationStatus) { self.status = status }
    func status(bundleID: String, askUser: Bool) -> AutomationStatus {
        lock.lock(); defer { lock.unlock() }
        if askUser { prompts += 1 } else { silent += 1 }
        if Thread.isMainThread { mainThread += 1 }
        return status
    }
    func set(_ new: AutomationStatus) { lock.lock(); status = new; lock.unlock() }
    var silentChecks: Int { lock.lock(); defer { lock.unlock() }; return silent }
    var promptCount: Int { lock.lock(); defer { lock.unlock() }; return prompts }
    var checksOnMainThread: Int { lock.lock(); defer { lock.unlock() }; return mainThread }
}

/// Never answers until cancelled: a player that hangs.
struct HangingProvider: NowPlayingProvider {
    let bundleID: String
    func snapshot() async throws -> NowPlayingSnapshot? {
        try await Task.sleep(for: .seconds(60))
        return nil
    }
}

@MainActor
@Suite struct ReadingOutcomeTests {
    private let spotify = BundleIDs.spotify

    private func flags(authorized: Bool = true) -> MemoryFlags {
        let f = MemoryFlags()
        if authorized { f.set(true, forKey: "nowplaying.automationRequested") }
        return f
    }

    private func model(_ providers: [any NowPlayingProvider], flags: MemoryFlags? = nil,
                       automation: (any AutomationChecking)? = nil, running: Set<String> = [BundleIDs.spotify],
                       pollTimeout: Duration = .seconds(8), clock: CountingClock = CountingClock()) -> NowPlayingModel {
        NowPlayingModel(providers: providers, defaults: flags ?? self.flags(), interval: .seconds(1),
                        transport: nil, artwork: nil, pollTimeout: pollTimeout, automation: automation,
                        running: StubRunning(ids: running), sleep: clock.sleep)
    }

    // MARK: granted

    @Test func grantedAndPlayingShowsTheTrackAndNoFault() async {
        let m = model([FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: true)))])
        await m.poll()
        let r = m.homeReading()
        #expect(r.access == .ready && r.track?.title == "Reason" && r.track?.isPlaying == true)
        #expect(r.diagnostic == nil && m.fault == nil)
    }

    @Test func grantedAndPausedShowsThePausedTrack() async {
        let m = model([FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: false)))])
        await m.poll()
        let r = m.homeReading()
        #expect(r.track?.isPlaying == false && r.track?.title == "Reason" && r.diagnostic == nil)
    }

    @Test func grantedAndReallyEmptyIsNothingLoadedWithNoCause() async {
        let m = model([FakeProvider(spotify, .success(nil))])
        await m.poll()
        let r = m.homeReading()
        #expect(r.access == .ready && r.track == nil && r.runningPlayer?.name == "Spotify")
        #expect(r.diagnostic == nil, "a stopped player is not a failure")
    }

    // MARK: failures: each one has its own line and never reads as "nothing loaded"

    @Test func refusedIsDeniedWithItsNumber() async {
        let m = model([FakeProvider(spotify, .failure(.permissionDenied))])
        await m.poll()
        let r = m.homeReading()
        #expect(r.access == .denied && r.track == nil)
        #expect(r.diagnostic == "Spotify : autorisation refusée (-1743)")
    }

    @Test func neverAskedFromTheScriptSendsTheCardBackToTheClick() async {
        let f = flags()
        let m = model([FakeProvider(spotify, .failure(.consentRequired))], flags: f)
        await m.poll()
        let r = m.homeReading()
        #expect(r.access == .needsAuthorization, "the card shows Autoriser, not Spotify est ouvert")
        #expect(r.diagnostic == "Spotify : autorisation à accorder (-1744)")
        #expect(!f.bool(forKey: "nowplaying.automationRequested"), "the remembered permission is forgotten")
    }

    @Test func noAnswerIsReportedAsATimeout() async {
        let m = model([FakeProvider(spotify, .failure(.timedOut))])
        await m.poll()
        let r = m.homeReading()
        #expect(r.access == .ready && r.track == nil)
        #expect(r.diagnostic == "Spotify : pas de réponse (-1712)")
    }

    @Test func aPlayerAppleScriptCannotFindIsReported() async {
        let m = model([FakeProvider(spotify, .failure(.appNotFound))])
        await m.poll()
        #expect(m.homeReading().diagnostic == "Spotify : application introuvable (-600)")
    }

    @Test func anEmptyReplyAndAnUnreadableOneAreReported() async {
        let empty = model([FakeProvider(spotify, .failure(.emptyReply))])
        await empty.poll()
        #expect(empty.homeReading().diagnostic == "Spotify : réponse vide")
        let bad = model([FakeProvider(spotify, .failure(.malformedOutput))])
        await bad.poll()
        #expect(bad.homeReading().diagnostic == "Spotify : réponse illisible")
        let other = model([FakeProvider(spotify, .failure(.scriptFailed(code: -10004)))])
        await other.poll()
        #expect(other.homeReading().diagnostic == "Spotify : erreur AppleScript (-10004)")
    }

    @Test func aHungPlayerTimesOutInsteadOfWaitingForEver() async {
        let m = model([HangingProvider(bundleID: spotify)], pollTimeout: .milliseconds(80))
        let started = Date()
        await m.poll()
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(m.homeReading().diagnostic == "Spotify : pas de réponse (-1712)")
        #expect(m.access == .ready, "a slow player is not a refusal")
    }

    @Test func theFaultClearsWhenTheNextReadingWorks() async {
        let p = FakeProvider(spotify, .failure(.timedOut))
        let m = model([p])
        await m.poll()
        #expect(m.homeReading().diagnostic != nil)
        p.result.set(.success(snap(spotify, playing: true)))
        await m.poll()
        #expect(m.homeReading().diagnostic == nil && m.fault == nil)
    }

    @Test func aFaultOfAClosedPlayerIsNotShown() async {
        let m = model([FakeProvider(spotify, .failure(.timedOut))], running: [])
        await m.poll()
        #expect(m.homeReading().runningPlayer == nil)
        #expect(m.homeReading().diagnostic == nil)
    }

    @Test func aTrackFromAnotherPlayerHidesTheOtherPlayersFault() async {
        let m = model([FakeProvider(spotify, .failure(.timedOut)),
                       FakeProvider(BundleIDs.music, .success(snap(BundleIDs.music, title: "Song", playing: true)))],
                      running: [spotify, BundleIDs.music])
        await m.poll()
        #expect(m.homeReading().track?.title == "Song" && m.homeReading().diagnostic == nil)
    }

    // MARK: the silent permission check (task 2): nothing collapses into "open, nothing loaded"

    @Test func neverAllowedShowsTheCallToActionNotAnEmptyPlayer() async {
        let automation = ThreadAwareAutomation(.notAsked)   // AEDeterminePermissionToAutomateTarget -> -1744
        let p = FakeProvider(spotify, .success(nil))
        let m = model([p], flags: flags(authorized: false), automation: automation)
        await m.refreshNow()
        let r = m.homeReading()
        #expect(r.access == .needsAuthorization)
        #expect(r.runningPlayer?.name == "Spotify")
        #expect(r.diagnostic == "Spotify : autorisation à accorder (-1744)")
        #expect(p.calls.get() == 0, "no Apple Event before the click: it would prompt by itself")
        #expect(automation.promptCount == 0)
    }

    @Test func aRememberedPermissionThatMacOSDoesNotKnowAnymoreIsAskedAgainByClickOnly() async {
        // The flag says "allowed" (an earlier build) but the TCC entry is gone: the first poll would prompt.
        let automation = ThreadAwareAutomation(.notAsked)
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = model([p], automation: automation)
        #expect(m.access == .ready)
        await m.refreshNow()
        #expect(m.access == .needsAuthorization)
        #expect(p.calls.get() == 0)
        #expect(m.homeReading().diagnostic == "Spotify : autorisation à accorder (-1744)")
    }

    @Test func refusedInSystemSettingsShowsDeniedWithTheNumber() async {
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false),
                      automation: ThreadAwareAutomation(.denied))
        await m.refreshNow()
        #expect(m.homeReading().access == .denied)
        #expect(m.homeReading().diagnostic == "Spotify : autorisation refusée (-1743)")
    }

    @Test func procNotFoundForARunningPlayerIsReportedNotCollapsed() async {
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false),
                      automation: ThreadAwareAutomation(.notRunning))
        await m.refreshNow()
        let r = m.homeReading()
        #expect(r.access == .needsAuthorization, "never 'ready with nothing loaded'")
        #expect(r.diagnostic == "Spotify : autorisation indéterminée (-600)")
    }

    @Test func anyOtherCodeIsShownWithItsNumber() async {
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false),
                      automation: ThreadAwareAutomation(.failed(-50)))
        await m.refreshNow()
        #expect(m.homeReading().access == .needsAuthorization)
        #expect(m.homeReading().diagnostic == "Spotify : autorisation indéterminée (-50)")
        let unknown = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false),
                            automation: ThreadAwareAutomation(.unknown))
        await unknown.refreshNow()
        #expect(unknown.homeReading().diagnostic == "Spotify : autorisation indéterminée")
    }

    @Test func aGrantedSilentCheckStartsTheReadingAndClearsTheCause() async {
        let automation = ThreadAwareAutomation(.notAsked)
        let m = model([FakeProvider(spotify, .success(snap(spotify, title: "Reason", playing: true)))],
                      flags: flags(authorized: false), automation: automation)
        await m.refreshNow()
        #expect(m.access == .needsAuthorization)
        automation.set(.granted)
        await m.refreshNow()
        #expect(m.access == .ready && m.homeReading().track?.title == "Reason" && m.fault == nil)
    }

    @Test func theClickThatStaysUnansweredLeavesTheCauseVisible() async {
        let automation = ThreadAwareAutomation(.notRunning)
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false), automation: automation)
        await m.requestAutomation()
        #expect(automation.promptCount == 1)
        #expect(m.homeReading().access == .needsAuthorization)
        #expect(m.homeReading().diagnostic == "Spotify : autorisation indéterminée (-600)")
    }

    // MARK: no TCC on a timer, nothing on the main thread

    @Test func theSilentCheckRunsOffTheMainThread() async {
        let automation = ThreadAwareAutomation(.granted)
        let m = model([FakeProvider(spotify, .success(nil))], automation: automation)
        await m.refreshNow()
        await m.requestAutomation()
        #expect(automation.silentChecks == 1 && automation.promptCount == 1)
        #expect(automation.checksOnMainThread == 0)
        m.setBackground(false)
    }

    @Test func aRememberedPermissionIsCheckedOncePerPlayerNotOnEveryRefresh() async {
        let automation = ThreadAwareAutomation(.granted)
        let m = model([FakeProvider(spotify, .success(nil))], automation: automation)
        for _ in 0..<5 { await m.refreshNow() }
        #expect(automation.silentChecks == 1)
    }

    @Test func theClosedBackgroundPollNeverCallsTCC() async {
        let automation = ThreadAwareAutomation(.granted)
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = model([p], automation: automation, clock: clock)
        await m.refreshNow()                 // the one check at start
        let checks = automation.silentChecks
        m.setBackground(true)                // the closed island's slow poll
        #expect(await eventually { clock.requested.get().count >= 4 })
        #expect(p.calls.get() >= 4, "the poll runs")
        #expect(automation.silentChecks == checks, "and never asks macOS again")
        #expect(Set(clock.requested.get()) == [.seconds(3)])
        m.setBackground(false)
    }

    @Test func withoutPermissionAndTheHomeClosedNothingPollsAtAll() async {
        let automation = ThreadAwareAutomation(.notAsked)
        let clock = CountingClock()
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false), automation: automation,
                      clock: clock)
        await m.refreshNow()                 // launch
        let checks = automation.silentChecks
        m.setBackground(true)
        m.setVisible(false)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(automation.silentChecks == checks && clock.requested.get().isEmpty)
        m.setBackground(false)
    }

    @Test func aRefusedPermissionDoesNotKeepPollingInTheBackground() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .failure(.permissionDenied))
        let m = model([p], clock: clock)
        await m.poll()
        #expect(m.access == .denied)
        m.setBackground(true)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(p.calls.get() == 1, "closed and refused: no Apple Event on a timer")
        #expect(clock.requested.get().isEmpty)
    }

    @Test func whileTheHomeIsOpenAndThePermissionMissingTheSilentCheckIsSlowAndOffTheMainThread() async {
        let automation = ThreadAwareAutomation(.notAsked)
        let clock = CountingClock()
        let m = model([FakeProvider(spotify, .success(nil))], flags: flags(authorized: false), automation: automation,
                      clock: clock)
        m.setHomeOpen(true)
        #expect(await eventually { automation.silentChecks >= 3 })
        #expect(Set(clock.requested.get()) == [.seconds(3)], "every 3 s, not every second")
        #expect(automation.checksOnMainThread == 0)
        m.setHomeOpen(false)
        try? await Task.sleep(for: .milliseconds(60))
        let after = automation.silentChecks
        try? await Task.sleep(for: .milliseconds(80))
        #expect(automation.silentChecks == after, "closing the Home ends the checks")
    }
}
