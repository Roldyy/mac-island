import AppKit
import Foundation
import Testing
@testable import TerminalFeature

@Suite struct TerminalKeyRoutingTests {
    private func route(_ key: String, _ flags: NSEvent.ModifierFlags = .command, selection: Bool = false)
        -> TerminalKeyAction?
    {
        TerminalKeyRouting.action(modifiers: flags, key: key, hasSelection: selection)
    }

    @Test func commandShortcutsMapToActions() {
        #expect(route("v") == .paste)
        #expect(route("a") == .selectAll)
        #expect(route("k") == .clear)
        #expect(route("=") == .fontLarger)
        #expect(route("+", [.command, .shift]) == .fontLarger)
        #expect(route("-") == .fontSmaller)
        #expect(route("0") == .fontReset)
    }

    @Test func uppercaseKeyStillMatches() {
        #expect(route("V") == .paste)
    }

    @Test func copyNeedsASelection() {
        #expect(route("c", selection: true) == .copy)
        #expect(route("c", selection: false) == .interrupt)
    }

    @Test func otherCombinationsAreNotOurs() {
        #expect(route("q") == nil)
        #expect(route("v", [.command, .option]) == nil)
        #expect(route("v", [.command, .shift]) == nil)
        #expect(route("c", [.control]) == nil)
        #expect(route("v", []) == nil)
        #expect(route("ab") == nil)
        #expect(route(nil) == nil)
    }

    @Test func capsLockDoesNotBreakAShortcut() {
        #expect(route("v", [.command, .capsLock]) == .paste)
    }

    private func route(_ key: String?) -> TerminalKeyAction? {
        TerminalKeyRouting.action(modifiers: .command, key: key, hasSelection: false)
    }
}

@Suite struct TerminalPasteTests {
    private func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    @Test func plainPasteKeepsTheText() {
        #expect(text(TerminalPaste.payload(text: "ls -la", bracketed: false)) == "ls -la")
    }

    @Test func lineBreaksBecomeCarriageReturns() {
        #expect(text(TerminalPaste.payload(text: "a\nb\r\nc", bracketed: false)) == "a\rb\rc")
    }

    @Test func bracketedPasteIsWrapped() {
        let bytes = TerminalPaste.payload(text: "echo 1\necho 2", bracketed: true)
        #expect(Array(bytes.prefix(6)) == [0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e])
        #expect(Array(bytes.suffix(6)) == [0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e])
        #expect(text(Array(bytes.dropFirst(6).dropLast(6))) == "echo 1\recho 2")
    }

    @Test func bracketedPasteCannotCloseItself() {
        let bytes = TerminalPaste.payload(text: "x\u{1b}[201~rm -rf ~", bracketed: true)
        #expect(!bytes.dropFirst(6).dropLast(6).contains(0x1b))
    }

    @Test func unicodeSurvives() {
        #expect(text(TerminalPaste.payload(text: "é 日本 🙂", bracketed: false)) == "é 日本 🙂")
    }

    @Test func copiedFilesWinOverTheirNames() {
        let url = URL(fileURLWithPath: "/tmp/a b.txt")
        #expect(TerminalPaste.content(fileURLs: [url], string: "a b.txt") == "'/tmp/a b.txt' ")
    }

    @Test func textIsUsedWithoutFiles() {
        #expect(TerminalPaste.content(fileURLs: [], string: "hello") == "hello")
        #expect(TerminalPaste.content(fileURLs: [], string: "") == nil)
        #expect(TerminalPaste.content(fileURLs: [], string: nil) == nil)
    }
}

@Suite struct ShellEscapeTests {
    @Test func safePathIsLeftAlone() {
        #expect(ShellEscape.quote("/Users/me/file-1.txt") == "/Users/me/file-1.txt")
    }

    @Test func spacesAreQuoted() {
        #expect(ShellEscape.quote("/tmp/my file.txt") == "'/tmp/my file.txt'")
    }

    @Test func singleQuotesAreClosedAndEscaped() {
        #expect(ShellEscape.quote("/tmp/it's") == #"'/tmp/it'\''s'"#)
    }

    @Test func shellMetacharactersAreInert() {
        #expect(ShellEscape.quote("/tmp/$(rm -rf ~);`x`") == "'/tmp/$(rm -rf ~);`x`'")
    }

    @Test func unicodeIsQuotedNotMangled() {
        #expect(ShellEscape.quote("/tmp/café 日本") == "'/tmp/café 日本'")
    }

    @Test func newlineUsesAnsiCQuoting() {
        #expect(ShellEscape.quote("/tmp/a\nb") == #"$'/tmp/a\nb'"#)
        #expect(ShellEscape.quote("/tmp/a\tb'c\\") == #"$'/tmp/a\tb\'c\\'"#)
    }

    @Test func emptyAndLists() {
        #expect(ShellEscape.quote("") == "''")
        #expect(ShellEscape.argumentList(["/a", "/b c"]) == "/a '/b c' ")
    }
}

@Suite struct TerminalFontSizeTests {
    private func defaults() -> (UserDefaults, String) {
        let name = "mac-island.terminal-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func clampStaysInRange() {
        #expect(TerminalFontSize.clamp(1) == 9)
        #expect(TerminalFontSize.clamp(500) == 32)
        #expect(TerminalFontSize.clamp(.nan) == TerminalFontSize.defaultSize)
        #expect(TerminalFontSize.clamp(14) == 14)
    }

    @Test func zoomStepsAndStopsAtTheBounds() {
        #expect(TerminalFontSize.next(12.5, action: .fontLarger) == 13.5)
        #expect(TerminalFontSize.next(12.5, action: .fontSmaller) == 11.5)
        #expect(TerminalFontSize.next(32, action: .fontLarger) == 32)
        #expect(TerminalFontSize.next(9, action: .fontSmaller) == 9)
        #expect(TerminalFontSize.next(20, action: .fontReset) == TerminalFontSize.defaultSize)
        #expect(TerminalFontSize.next(20, action: .paste) == 20)
    }

    @Test func sizePersistsAcrossInstances() {
        let (suite, name) = defaults()
        defer { suite.removePersistentDomain(forName: name) }
        #expect(TerminalFontSize(defaults: suite).current == TerminalFontSize.defaultSize)
        TerminalFontSize(defaults: suite).current = 18
        #expect(TerminalFontSize(defaults: suite).current == 18)
    }

    @Test func storedGarbageIsClamped() {
        let (suite, name) = defaults()
        defer { suite.removePersistentDomain(forName: name) }
        suite.set(900.0, forKey: TerminalFontSize.key)
        #expect(TerminalFontSize(defaults: suite).current == 32)
    }
}
