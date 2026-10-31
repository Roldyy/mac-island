import Foundation
import IslandUI
import Testing
@testable import IslandKit

@Suite struct ClaudeWingTests {
    @Test func formatsMinutesAndSeconds() {
        #expect(ElapsedTime.text(0) == "0:00")
        #expect(ElapsedTime.text(7) == "0:07")
        #expect(ElapsedTime.text(453) == "7:33")
        #expect(ElapsedTime.text(3599) == "59:59")
    }

    @Test func formatsHoursFromOneHour() {
        #expect(ElapsedTime.text(3600) == "1:00:00")
        #expect(ElapsedTime.text(3600 + 125) == "1:02:05")
        #expect(ElapsedTime.text(10 * 3600 + 59 * 60 + 9) == "10:59:09")
    }

    @Test func negativeAndNonFiniteNeverCrash() {
        #expect(ElapsedTime.text(-30) == "0:00")
        #expect(ElapsedTime.text(.nan) == "0:00")
        #expect(ElapsedTime.text(.infinity) == "0:00")
        #expect(ElapsedTime.text(1e18) == "99:59:59")
    }

    @Test func elapsedSinceADate() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(ElapsedTime.text(since: start, now: start.addingTimeInterval(453.9)) == "7:33")
        #expect(ElapsedTime.text(since: start, now: start.addingTimeInterval(-5)) == "0:00")  // clock went back
    }

    private let working = CompactItem(symbol: "sparkles", status: .info)
    private let waiting = CompactItem(symbol: "hand.raised.fill", status: .warning)

    @Test func recognisesOnlyTheClaudeGlyphs() {
        #expect(ClaudeWing.isClaudeWing(working))
        #expect(ClaudeWing.isClaudeWing(waiting))
        #expect(!ClaudeWing.isClaudeWing(nil))
        #expect(!ClaudeWing.isClaudeWing(CompactItem(symbol: "sparkles", text: "03:00", status: .info)))  // cleaning countdown
        #expect(!ClaudeWing.isClaudeWing(CompactItem(symbol: "music.note")))
    }

    @Test func layoutShowsGlyphAndElapsedTime() {
        let since = Date(timeIntervalSince1970: 5_000)
        let base = ActivityLayout(leading: working, trailing: CompactItem(symbol: "folder", text: "app"), dot: nil)
        let out = ClaudeWing.layout(base, sample: ClaudeWorkSample(id: "1", isWaiting: false, since: since),
                                    now: since.addingTimeInterval(453))
        #expect(out.leading == working)
        #expect(out.trailing?.text == "7:33")
        #expect(out.trailing?.symbol == "")
        #expect(out.trailing?.status == .info)
    }

    @Test func layoutIsUntouchedWithoutASampleOrADateOrAClaudeWing() {
        let base = ActivityLayout(leading: working, trailing: nil, dot: nil)
        let now = Date()
        #expect(ClaudeWing.layout(base, sample: nil, now: now) == base)
        #expect(ClaudeWing.layout(base, sample: ClaudeWorkSample(id: "1", isWaiting: false, since: nil), now: now) == base)
        let music = ActivityLayout(leading: CompactItem(symbol: "music.note"), trailing: nil, dot: nil)
        let sample = ClaudeWorkSample(id: "1", isWaiting: false, since: now)
        #expect(ClaudeWing.layout(music, sample: sample, now: now) == music)
    }

    @Test func waitingBeatsWorkingThenSmallestId() {
        let a = ClaudeWorkSample(id: "b", isWaiting: false, since: nil)
        let b = ClaudeWorkSample(id: "a", isWaiting: false, since: nil)
        let c = ClaudeWorkSample(id: "z", isWaiting: true, since: nil)
        #expect(ClaudeWing.pick([a, b])?.id == "a")
        #expect(ClaudeWing.pick([a, b, c])?.id == "z")
        #expect(ClaudeWing.pick([]) == nil)
    }

    @Test func claudeBeatsMusicInTheArbiterAndTheWingTextFollows() {
        let claude = IslandActivity(id: "claude.1", source: "claude", priority: .claudeWorking, leading: working)
        let music = IslandActivity(id: "music", source: "nowplaying", priority: .music,
                                   leading: CompactItem(symbol: "music.note"), trailing: CompactItem(symbol: "waveform", text: "Titre"))
        let layout = ActivityArbiter.resolve([music, claude])
        #expect(ClaudeWing.isClaudeWing(layout.leading))
        // Without Claude the music wing is what shows.
        #expect(ActivityArbiter.resolve([music]).leading?.symbol == "music.note")
    }
}
