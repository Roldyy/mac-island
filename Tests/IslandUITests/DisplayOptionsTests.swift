import SwiftUI
import Testing
@testable import IslandUI

@Suite struct DisplayOptionsTests {
    @Test func glassFallsBackToSolidUnderReduceTransparency() {
        #expect(IslandGlassSpec.resolve(.standard).usesMaterial)
        #expect(!IslandGlassSpec.resolve(IslandDisplayOptions(reduceTransparency: true)).usesMaterial)
    }

    @Test func increaseContrastStrengthensTheBorder() {
        let normal = IslandGlassSpec.resolve(.standard)
        let strong = IslandGlassSpec.resolve(IslandDisplayOptions(increaseContrast: true))
        #expect(strong.borderWidth > normal.borderWidth)
        #expect(strong.border == IslandPalette.separatorStrong)
        #expect(normal.border == IslandPalette.separator)
    }

    @Test func reduceMotionRemovesAnimation() {
        #expect(IslandMotion.animation(.easeIn, reduceMotion: true) == nil)
        #expect(IslandMotion.animation(.easeIn, reduceMotion: false) != nil)
        #expect(IslandMotion.animation(reduceMotion: true) == nil)
    }

    @Test func providersAreInjectable() {
        let forced = IslandDisplayOptions(reduceTransparency: true, increaseContrast: true, reduceMotion: true)
        #expect(FixedDisplayOptions(forced).current == forced)
        // The system provider only has to answer without crashing; its values depend on the machine.
        _ = SystemDisplayOptions().current
    }

    @Test func mergeIsAnOr() {
        let a = IslandDisplayOptions(reduceTransparency: true)
        let b = IslandDisplayOptions(reduceMotion: true)
        #expect(a.merged(with: b) == IslandDisplayOptions(reduceTransparency: true, reduceMotion: true))
    }

    @Test func hudClampsItsValue() {
        #expect(IslandHUD.clamped(-1) == 0)
        #expect(IslandHUD.clamped(2) == 1)
        #expect(IslandHUD.clamped(.nan) == 0)
        #expect(IslandHUD.percentText(0.456) == "46 %")
    }

    @Test func everyStatusHasASymbolAndAFrenchLabel() {
        for status in IslandStatus.allCases {
            #expect(!status.symbol.isEmpty)
            #expect(!status.label.isEmpty)
        }
        #expect(Set(IslandStatus.allCases.map(\.symbol)).count == IslandStatus.allCases.count)
    }

    @Test func typeScaleHasNoTextUnderEleven() {
        for size in [IslandType.body, IslandType.caption, IslandType.footnote] {
            #expect(size >= IslandType.minimumSize)
        }
        #expect([IslandType.body, IslandType.caption, IslandType.footnote] == [13, 12, 11])
    }
}
