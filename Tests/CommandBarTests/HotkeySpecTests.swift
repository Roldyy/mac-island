import Testing
@testable import CommandBarFeature

@Suite struct HotkeySpecTests {
    @Test func defaultIsOptionSpace() {
        #expect(HotkeySpec.default.stored == "option:space")
        #expect(HotkeySpec.default.keyCode == 49)
        #expect(HotkeySpec.default.carbonModifiers == 2048)
    }

    @Test func parsesOldAppStyle() throws {
        let s = try #require(HotkeySpec.parse("option+command:9"))
        #expect(s.modifiers == [.option, .command])
        #expect(s.keyCode == 25)
        #expect(s.carbonModifiers == 2048 | 256)
        #expect(s.display == "\u{2325}\u{2318}9")
    }

    @Test func parsesAliasesAndCase() throws {
        let s = try #require(HotkeySpec.parse(" Ctrl + ALT : Space "))
        #expect(s.modifiers == [.control, .option])
        #expect(s.key == "space")
    }

    @Test func storedRoundTrips() throws {
        let s = try #require(HotkeySpec.parse("shift+command+control:k"))
        #expect(HotkeySpec.parse(s.stored) == s)
    }

    @Test(arguments: ["", ":", "option", "option:", ":space", "option:space:x", "hyper:space",
                      "option:nokey", "shift:a", "+:a", "option++:a"])
    func rejectsMalformed(_ raw: String) {
        #expect(HotkeySpec.parse(raw) == nil)
    }

    @Test func shiftAloneIsRefused() {
        // Shift + letter is just typing a capital: not a usable global shortcut.
        #expect(HotkeySpec.parse("shift:a") == nil)
        #expect(HotkeySpec.parse("shift+option:a") != nil)
    }
}
