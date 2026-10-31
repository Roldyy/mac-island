import Testing
@testable import IslandUI

@Suite struct ContrastTests {
    @Test func ratioMatchesWCAGReferenceValues() {
        let black = IslandRGB(white: 0), white = IslandRGB(white: 1)
        #expect(abs(IslandContrast.ratio(black, white) - 21) < 0.001)
        #expect(abs(IslandContrast.ratio(white, white) - 1) < 0.001)
        // #767676 on white is the textbook 4.54:1.
        let gray = IslandRGB(0x76 / 255.0, 0x76 / 255.0, 0x76 / 255.0)
        #expect(abs(IslandContrast.ratio(gray, white) - 4.54) < 0.01)
        #expect(IslandContrast.ratio(black, gray) == IslandContrast.ratio(gray, black))
    }

    @Test func everyTokenPairMeetsItsMinimum() {
        let pairs = IslandPalette.contrastPairs
        #expect(pairs.count >= 30)
        for pair in pairs {
            for scheme in pair.schemes {
                let ratio = pair.ratio(in: scheme)
                #expect(ratio >= pair.minimum, "\(pair.name) (\(scheme)) : \(ratio) < \(pair.minimum)")
            }
        }
    }

    @Test func textTokensAreHeldToFourPointFive() {
        for pair in IslandPalette.contrastPairs where pair.name.hasPrefix("text") || pair.name.hasPrefix("status") {
            #expect(pair.minimum == IslandContrast.textMinimum, "\(pair.name)")
        }
    }

    @Test func coversBothSchemesAndEveryStatus() {
        let names = Set(IslandPalette.contrastPairs.map(\.name))
        for status in IslandStatus.allCases {
            let token = "status" + status.rawValue.prefix(1).uppercased() + status.rawValue.dropFirst()
            #expect(names.contains("\(token) sur verre"), "\(token)")
        }
        #expect(IslandPalette.contrastPairs.contains { $0.schemes.contains(.light) })
        #expect(IslandPalette.contrastPairs.contains { $0.schemes.contains(.dark) })
    }

    @Test func badgeTextIsHeldToFourPointFiveOnItsOwnTint() {
        let names = IslandPalette.contrastPairs.filter { $0.name.hasPrefix("badge ") }
        // 5 statuses on 2 surfaces.
        #expect(names.count == IslandStatus.allCases.count * 2)
        for pair in names {
            #expect(pair.minimum == IslandContrast.textMinimum, "\(pair.name)")
            // The tint must be visible at all: the background is not the bare surface.
            #expect(pair.background != IslandSurface.solid && pair.background != IslandSurface.glassReference)
        }
    }

    @Test func switchGlyphAndOutlineAreReadable() {
        let glyph = IslandPalette.contrastPairs.first { $0.name == "glyphe sur bouton" }
        #expect(glyph != nil)
        for scheme in IslandScheme.allCases { #expect((glyph?.ratio(in: scheme) ?? 0) >= 3.0) }
        // The off track is outlined with separatorStrong: held to 3:1 on every surface by the pairs above.
        for surface in ["verre", "solide", "encoche"] {
            #expect(IslandPalette.contrastPairs.contains { $0.name == "separatorStrong sur \(surface)" && $0.minimum == 3.0 })
        }
    }

    @Test func notchStaysBlack() {
        #expect(IslandSurface.notchBlackColor.light == IslandRGB(white: 0))
        #expect(IslandSurface.notchBlackColor.dark == IslandRGB(white: 0))
    }
}
