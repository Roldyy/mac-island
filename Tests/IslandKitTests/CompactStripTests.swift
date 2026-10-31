import Testing
import IslandUI
@testable import IslandKit

@Suite struct CompactStripTests {
    @Test func labelCombinesTextStatusAndProgressInFrench() {
        let item = CompactItem(symbol: "sparkles", text: "Claude attend", status: .warning, progress: 0.426)
        #expect(CompactStrip.accessibilityLabel(for: item) == "Claude attend, attention, 43 %")
    }

    @Test func neutralItemWithoutTextStillSpeaks() {
        #expect(CompactStrip.accessibilityLabel(for: CompactItem(symbol: "x")) == "Activité en cours")
    }

    @Test func everyNonNeutralStatusHasAWord() {
        for status in IslandStatus.allCases where status != .neutral {
            #expect(CompactStrip.statusWord(status) != nil)
            #expect(CompactStrip.dotLabel(status).hasPrefix("Pastille d'état : "))
        }
        #expect(CompactStrip.dotLabel(.neutral) == "Pastille d'état")
    }

    @Test func progressIsClampedAndNaNSafe() {
        #expect(CompactStrip.clampedProgress(-1) == 0)
        #expect(CompactStrip.clampedProgress(2) == 1)
        #expect(CompactStrip.clampedProgress(.nan) == 0)
        #expect(CompactStrip.clampedProgress(0.5) == 0.5)
    }
}
