import Testing
@testable import ClipboardFeature

@Suite struct HotkeyShortcutTests {
    /// Vorssaint's stored form: the number after ":" is a virtual key code, 9 = V (the regression: it was read
    /// as the digit key 9, so the shortcut fired on option-command-9 and never on option-command-V).
    @Test func numberAfterColonIsAKeyCode() throws {
        let s = try #require(HotkeyShortcut.parse("option+command:9"))
        #expect(s.modifiers == [.option, .command])
        #expect(s.keyCode == 9)
        #expect(s.key == "v")
    }

    @Test func allThreeSpellingsAgree() throws {
        #expect(HotkeyShortcut.parse("option+command:9") == HotkeyShortcut.parse("option+command+v"))
        #expect(HotkeyShortcut.parse("option+command:v") == HotkeyShortcut.parse("option+command+v"))
        let k = try #require(HotkeyShortcut.parse("control+option+command:40"))
        #expect(k.modifiers == [.control, .option, .command])
        #expect(k.keyCode == 40)
        #expect(k == HotkeyShortcut.parse("control+option+command+k"))
        #expect(k == HotkeyShortcut.parse("control+option+command:k"))
    }

    @Test func digitKeyIsWrittenAsItsCode() throws {
        let nine = try #require(HotkeyShortcut.parse("option+command:25"))
        #expect(nine.key == "9")
        #expect(nine.stored == "option+command:25")
        #expect(HotkeyShortcut.parse(nine.stored) == nine)
    }

    @Test func keyCodeBoundsAndUnnamedCodes() throws {
        #expect(HotkeyShortcut.parse("command:128") == nil)
        let f2 = try #require(HotkeyShortcut.parse("command:120"))
        #expect(f2.keyCode == 120)
        #expect(HotkeyShortcut.parse(f2.stored) == f2)
    }

    @Test func parsesAliasesAndCase() throws {
        let s = try #require(HotkeyShortcut.parse(" Ctrl+Shift+Alt+Cmd : V "))
        #expect(s.modifiers == [.control, .shift, .option, .command])
        #expect(s.keyCode == 9)
    }

    @Test func rejectsMalformed() {
        #expect(HotkeyShortcut.parse("") == nil)
        #expect(HotkeyShortcut.parse("command") == nil)          // no key
        #expect(HotkeyShortcut.parse("9") == nil)                // no modifier
        #expect(HotkeyShortcut.parse("command:") == nil)
        #expect(HotkeyShortcut.parse("hyper+command:9") == nil)  // unknown modifier
        #expect(HotkeyShortcut.parse("command:nope") == nil)     // unknown key
        #expect(HotkeyShortcut.parse("command+") == nil)         // no key
        #expect(HotkeyShortcut.parse("a:b:c") == nil)
    }

    @Test func defaultIsOptionCommandV() {
        #expect(HotkeyShortcut.default.modifiers == [.option, .command])
        #expect(HotkeyShortcut.default.keyCode == 9)
        #expect(HotkeyShortcut.parse("option+command:9") == .default)   // the Settings page default string
    }

    @Test func carbonFlags() {
        #expect(HotkeyShortcut.default.carbonModifiers == UInt32(2048 | 256))
        #expect(HotkeyShortcut.parse("control+shift:space")?.carbonModifiers == UInt32(4096 | 512))
    }

    @Test func roundTripsDescription() throws {
        let s = try #require(HotkeyShortcut.parse("option+command:9"))
        #expect(HotkeyShortcut.parse(s.stored) == s)
    }
}
