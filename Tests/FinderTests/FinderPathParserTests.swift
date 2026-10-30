import Foundation
import Testing
@testable import FinderFeature

@Suite struct FinderPathParserTests {
    let rs = "\u{1E}"

    @Test func parsesSelection() {
        let urls = FinderPathParser.parseSelection("/Users/x/a.txt\(rs)/Users/x/dir/\(rs)/Users/x/b c.png")
        #expect(urls.map(\.path) == ["/Users/x/a.txt", "/Users/x/dir", "/Users/x/b c.png"])
    }
    @Test func emptyAndNil() {
        #expect(FinderPathParser.parseSelection(nil).isEmpty)
        #expect(FinderPathParser.parseSelection("").isEmpty)
        #expect(FinderPathParser.parseSelection("\n").isEmpty)
    }
    @Test func rejectsRelativeRootDotDotAndNul() {
        #expect(FinderPathParser.parseSelection("relative/a\(rs)/\(rs)/a/../b\(rs)/a/b\u{0}c").isEmpty)
    }
    @Test func dedupesKeepingOrder() {
        let urls = FinderPathParser.parseSelection("/a/b\(rs)/a/c\(rs)/a/b")
        #expect(urls.map(\.path) == ["/a/b", "/a/c"])
    }
    @Test func newlineInsideNameSurvives() {
        let urls = FinderPathParser.parseSelection("/a/we\nird\(rs)/a/ok")
        #expect(urls.count == 2)
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
