import Testing
@testable import ClipboardFeature

@Suite struct HotkeyShortcutTests {
    @Test func parsesObservedValue() throws {
        let s = try #require(HotkeyShortcut.parse("option+command:9"))
        #expect(s.modifiers == [.option, .command])
        #expect(s.keyCode == 25)
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
    }

    @Test func defaultIsOptionCommandNine() {
        #expect(HotkeyShortcut.default.modifiers == [.option, .command])
        #expect(HotkeyShortcut.default.keyCode == 25)
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
