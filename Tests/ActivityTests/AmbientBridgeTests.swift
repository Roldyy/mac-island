import Foundation
import IslandUI
import Testing
@testable import IslandKit

@Suite struct AmbientBridgeTests {
    private let since = Date(timeIntervalSince1970: 1_000)

    private func layout(_ leading: CompactItem?, _ trailing: CompactItem? = nil, dot: IslandStatus? = nil) -> ActivityLayout {
        ActivityLayout(leading: leading, trailing: trailing, dot: dot)
    }

    @Test func claudeWorkingBecomesOneBusyClockIndicator() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "sparkles", status: .info)),
            claude: ClaudeWorkSample(id: "s", isWaiting: false, since: since))
        #expect(out.count == 1)
        let claude = out[0]
        #expect(claude.channel == AmbientChannel.claude)
        #expect(claude.isBusy && !claude.isUrgent)
        #expect(claude.priority == .claudeWorking)
        #expect(claude.clockSince == since)
        #expect(claude.isPinned)
    }

    @Test func claudeWaitingIsUrgentAndNotBusy() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "hand.raised.fill", status: .warning)),
            claude: ClaudeWorkSample(id: "s", isWaiting: true, since: since))
        #expect(out[0].isUrgent && !out[0].isBusy)
        #expect(out[0].priority == .claudeWaiting)
        #expect(out[0].label == "Claude attend")
    }

    @Test func theFolderNameNoLongerTakesAWing() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "sparkles", status: .info), CompactItem(symbol: "folder", text: "mac-island")),
            claude: nil)
        #expect(out.map(\.id) == ["claude"])
    }

    @Test func musicTakesTheTitleFromTheTrailingWingAndTheProgressFromTheLeadingOne() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "music.note", progress: 0.4), CompactItem(symbol: "waveform", text: "Hollow Years")),
            claude: nil)
        #expect(out.count == 1)
        #expect(out[0].glyph == .equalizer)
        #expect(out[0].text == "Hollow Years")
        #expect(out[0].progress == 0.4)
        #expect(out[0].priority == .music)
    }

    @Test func musicAndClaudeShareTheIslandWhenTheFolderIsGone() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "sparkles", status: .info), CompactItem(symbol: "waveform", text: "Titre")),
            claude: nil)
        #expect(Set(out.map(\.id)) == ["claude", "music"])
        #expect(out.first { $0.id == "music" }?.progress == nil)  // the progress rode on the lost leading item
    }

    @Test func theLimitsGaugeIsNotBridgedTheRestingReadingOwnsIt() {
        // `AmbientCenter.setClaudeRest` draws the limits (it knows how old the reading is); a bridged copy would
        // double it and could show an old session percentage as live.
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "gauge", text: "58%", status: .warning, progress: 0.58)), claude: nil)
        #expect(out.isEmpty)
    }

    @Test func anythingElseIsAnAlertThatPins() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "sparkles", text: "Nettoyage : 45 s", status: .warning)), claude: nil)
        #expect(out.count == 1)
        #expect(out[0].channel == AmbientChannel.alert)
        #expect(out[0].priority == .alert && out[0].isPinned && out[0].isUrgent)
        #expect(out[0].text == "45 s")
        #expect(out[0].label == "Nettoyage : 45 s")
    }

    @Test func aSuccessNoticeIsAnAlertWithoutThePulse() {
        let out = AmbientBridge.indicators(
            from: layout(CompactItem(symbol: "checkmark.circle.fill", text: "Nettoyage terminé", status: .success)), claude: nil)
        #expect(out[0].isPinned && !out[0].isUrgent)
        #expect(out[0].text == "Nettoyage terminé")  // no " : ", so it stays whole
    }

    @Test func shortTextsAndEmptyOnesAreKept() {
        #expect(AmbientBridge.shortened("45 s").text == "45 s")
        #expect(AmbientBridge.shortened("45 s").label == nil)
        #expect(AmbientBridge.shortened("a : b").text == "a : b")  // short enough as it is
        #expect(AmbientBridge.shortened(nil).text == nil)
        #expect(AmbientBridge.shortened("").text == nil)
        #expect(AmbientBridge.shortened("Verrouillage impossible : ").text == "Verrouillage impossible : ")
    }

    @Test func anEmptyLayoutGivesNoIndicators() {
        #expect(AmbientBridge.indicators(from: .empty, claude: nil).isEmpty)
    }

    // MARK: Accessibility

    @Test func theSpokenLabelCarriesTheStatusAndNeverRepeatsThePercent() {
        let gauge = AmbientIndicator(id: "l", symbol: "sparkle", text: "58%", status: .warning, progress: 0.58, label: "Limite Claude")
        #expect(gauge.accessibilityLabel() == "Limite Claude, 58%, attention")
        let ring = AmbientIndicator(id: "r", symbol: "x", progress: 0.4)
        #expect(ring.accessibilityLabel() == "40 %")
        #expect(AmbientIndicator(id: "z", symbol: "x").accessibilityLabel() == "Indicateur de l’île")
    }

    @Test func theSpokenLabelUsesTheClockWhenThereIsOne() {
        let claude = AmbientIndicator(id: "claude", symbol: "sparkles", clockSince: since, label: "Claude travaille")
        #expect(claude.accessibilityLabel(clock: "7:33") == "Claude travaille, 7:33")
    }
}
