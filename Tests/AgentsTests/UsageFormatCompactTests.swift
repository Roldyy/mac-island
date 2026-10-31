import Foundation
import Testing
@testable import AgentsFeature

@Suite struct UsageFormatCompactTests {
    static let fr = Locale(identifier: "fr_BE")

    @Test func costShortDropsTheUSSuffixAndKeepsCents() {
        let text = UsageFormat.costShort(1_681.76, estimated: false, locale: Self.fr)
        #expect(text.hasSuffix("$") && !text.contains("US"))
        #expect(text.filter { $0.isNumber || $0 == "," } == "1681,76")
        #expect(UsageFormat.costShort(0.39, estimated: false, locale: Self.fr).filter { $0.isNumber || $0 == "," } == "0,39")
    }

    @Test func costShortGoesToThousandsFromTenThousand() {
        let text = UsageFormat.costShort(12_345.67, estimated: false, locale: Self.fr)
        #expect(text == "12,3\u{202F}k$")
        #expect(UsageFormat.costShort(9_999, estimated: false, locale: Self.fr).hasSuffix("$"))
        #expect(!UsageFormat.costShort(9_999, estimated: false, locale: Self.fr).contains("k"))
    }

    @Test func anEstimatedCostKeepsItsTilde() {
        #expect(UsageFormat.costShort(5, estimated: true, locale: Self.fr).hasPrefix("~"))
        #expect(UsageFormat.costShort(50_000, estimated: true, locale: Self.fr).hasPrefix("~"))
    }

    @Test func aCostIsShortEnoughForItsColumn() {
        for value in [0, 0.2, 16.15, 329.44, 2_324.79, 9_999.99, 12_345.67, 1_234_567] as [Double] {
            #expect(UsageFormat.costShort(value, estimated: true, locale: Self.fr).count <= 11, "\(value)")
        }
    }

    @Test func tokensShortDropsATrailingZeroDecimal() {
        #expect(UsageFormat.tokensShort(10_000_000_000, locale: Self.fr) == "10\u{202F}Md")
        #expect(UsageFormat.tokensShort(3_700_000_000, locale: Self.fr) == "3,7\u{202F}Md")
        #expect(UsageFormat.tokensShort(522_500_000, locale: Self.fr) == "522,5\u{202F}M")
        #expect(UsageFormat.tokensShort(100_000, locale: Self.fr) == "100\u{202F}k")
        #expect(UsageFormat.tokensShort(950, locale: Self.fr) == "950")
    }
}
