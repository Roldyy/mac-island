import Foundation
import Testing
@testable import FinderFeature

@Suite struct FinderPathParserTests {
    /// What the selection script returns: item 1 is Finder's count, then one path per list item.
    func list(count: Int, _ paths: [String]) -> NSAppleEventDescriptor {
        let l = NSAppleEventDescriptor.list()
        l.insert(NSAppleEventDescriptor(int32: Int32(count)), at: 1)
        for (i, p) in paths.enumerated() { l.insert(NSAppleEventDescriptor(string: p), at: i + 2) }
        return l
    }
    func urls(_ d: NSAppleEventDescriptor?) throws -> [String] { try FinderPathParser.parseSelection(d).map(\.path) }
    func refused(_ d: NSAppleEventDescriptor?) -> Bool {
        do { _ = try FinderPathParser.parseSelection(d); return false }
        catch { return (error as? FinderScriptError) == .badResult }
    }

    @Test func parsesSelection() throws {
        let got = try urls(list(count: 3, ["/Users/x/a.txt", "/Users/x/dir/", "/Users/x/b c.png"]))
        #expect(got == ["/Users/x/a.txt", "/Users/x/dir", "/Users/x/b c.png"])
    }
    @Test func emptySelectionIsAnEmptyList() throws {
        #expect(try urls(list(count: 0, [])).isEmpty)
    }
    /// The injection: with a joined string a name holding U+001E became a second absolute path.
    @Test func recordSeparatorInANameStaysOneItem() throws {
        let evil = "/Users/x/a\u{1E}/Users/x/secret.txt"
        let got = try urls(list(count: 1, [evil]))
        #expect(got == [evil])
    }
    @Test func newlinesAndQuotesInNamesSurvive() throws {
        let names = ["/a/we\nird", "/a/q\"uote", "/a/it's", "/a/tab\there", "/a/x\u{1E}\n\"y"]
        #expect(try urls(list(count: names.count, names)) == names)
    }
    @Test func countThatDiffersFromFindersIsRefused() {
        #expect(refused(list(count: 2, ["/a/b"])))
        #expect(refused(list(count: 1, ["/a/b", "/a/c"])))
    }
    @Test func anItemThatIsNotACleanPathIsRefused() {
        #expect(refused(list(count: 1, ["relative/a"])))
        #expect(refused(list(count: 1, ["/"])))
        #expect(refused(list(count: 1, ["/a/../b"])))
        #expect(refused(list(count: 1, ["/a/b\u{0}c"])))
    }
    @Test func duplicateItemsAreRefusedBecauseTheCountNoLongerMatches() {
        #expect(refused(list(count: 2, ["/a/b", "/a/b"])))
    }
    @Test func nonListAndNilAreRefused() {
        #expect(refused(nil))
        #expect(refused(NSAppleEventDescriptor(string: "/a/b")))
        // First item is not the count.
        let l = NSAppleEventDescriptor.list()
        l.insert(NSAppleEventDescriptor(string: "/a/b"), at: 1)
        #expect(refused(l))
    }
    @Test func parsesFolder() {
        #expect(FinderPathParser.parseFolder("/Users/x/Documents/\n")?.path == "/Users/x/Documents")
        #expect(FinderPathParser.parseFolder("/")?.path == "/")
        #expect(FinderPathParser.parseFolder("") == nil)
        #expect(FinderPathParser.parseFolder(nil) == nil)
        #expect(FinderPathParser.parseFolder("Recents") == nil)
        #expect(FinderPathParser.parseFolder("/a/../b") == nil)
    }
    @Test func automationStatusMapping() {
        #expect(AutomationStatus(osStatus: 0) == .granted)
        #expect(AutomationStatus(osStatus: -1743) == .denied)
        #expect(AutomationStatus(osStatus: -1744) == .notDetermined)
        #expect(AutomationStatus(osStatus: -600) == .finderNotRunning)
        #expect(AutomationStatus(osStatus: 42) == .unknown)
    }
    @Test func textRoles() {
        #expect(TextEditingRole.isTextEditing(role: "AXTextField", subrole: nil))
        #expect(TextEditingRole.isTextEditing(role: "AXTextArea", subrole: nil))
        #expect(TextEditingRole.isTextEditing(role: "AXComboBox", subrole: nil))
        #expect(TextEditingRole.isTextEditing(role: "AXGroup", subrole: "AXSearchField"))
        #expect(!TextEditingRole.isTextEditing(role: "AXOutline", subrole: nil))
        #expect(!TextEditingRole.isTextEditing(role: nil, subrole: nil))
    }
    @Test func watchdogActions() {
        #expect(TapWatchdog.shouldReenable(disabledByTimeout: true, disabledByUserInput: false))
        #expect(TapWatchdog.shouldReenable(disabledByTimeout: false, disabledByUserInput: true))
        #expect(!TapWatchdog.shouldReenable(disabledByTimeout: false, disabledByUserInput: false))
    }
}

/// NSAppleScript is not thread safe: one test at a time.
@Suite(.serialized) struct FinderAppleScriptTests {
    func urls(_ d: NSAppleEventDescriptor?) throws -> [String] { try FinderPathParser.parseSelection(d).map(\.path) }

    /// Real AppleScript list through the real decoder, with the nasty characters built by AppleScript itself.
    @Test func realAppleScriptListRoundTrips() throws {
        let src = #"""
        set out to {2}
        set end of out to "/a" & (character id 30) & "/etc/x"
        set end of out to "/b/q\"uote" & (character id 10) & "name"
        return out
        """#
        var info: NSDictionary?
        let desc = try #require(NSAppleScript(source: src)).executeAndReturnError(&info)
        #expect(info == nil)
        let got = try urls(desc)
        #expect(got == ["/a\u{1E}/etc/x", "/b/q\"uote\nname"])
    }
    @Test func selectionScriptCompiles() {
        var info: NSDictionary?
        #expect(NSAppleScript(source: FinderScripts.selection)?.compileAndReturnError(&info) == true)
        #expect(info == nil)
    }
}
