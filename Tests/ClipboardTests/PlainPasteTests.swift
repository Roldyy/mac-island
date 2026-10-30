import Testing
@testable import ClipboardFeature

@Suite struct PlainPasteTests {
    @Test func normalizesLineEndings() {
        #expect(PlainPaste.normalize("a\r\nb\rc\nd") == "a\nb\nc\nd")
    }

    @Test func replacesOddSpacesAndStripsInvisibles() {
        #expect(PlainPaste.normalize("a\u{00A0}b\u{2009}c") == "a b c")
        #expect(PlainPaste.normalize("a\u{200B}b\u{FEFF}c") == "abc")
    }

    @Test func keepsTabsAndNewlinesDropsControls() {
        #expect(PlainPaste.normalize("a\tb\u{0007}c\n") == "a\tbc\n")
    }

    @Test func composesUnicode() {
        #expect(PlainPaste.normalize("e\u{0301}") == "\u{00E9}")
    }

    @Test func plainTextIsIdempotent() {
        let once = PlainPaste.normalize("x\u{00A0}y\r\n")
        #expect(PlainPaste.normalize(once) == once)
    }
}
