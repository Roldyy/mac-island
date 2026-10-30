import Foundation
import Testing
@testable import FinderFeature

@Suite final class FinderSettingsTests {
    private var made: [TempDefaults] = []
    func defaults() -> UserDefaults { let t = TempDefaults(); made.append(t); return t.defaults }

    @Test func keysAreTheMigratedNames() {
        #expect(FinderSettings.cutPasteKey == "finderCutPasteEnabled")
        #expect(FinderSettings.imageKey == "finderPasteImageAsFile")
        #expect(FinderSettings.suiteName == "be.roldy.macisland")
    }
    @Test func defaultsWhenEmpty() {
        let s = FinderSettings(defaults: defaults())
        #expect(!s.cutPasteEnabled)
        #expect(s.pasteImageAsFile)
    }
    @Test func readsAndWrites() {
        let d = defaults()
        d.set(true, forKey: "finderCutPasteEnabled")
        d.set(false, forKey: "finderPasteImageAsFile")
        let s = FinderSettings(defaults: d)
        #expect(s.cutPasteEnabled)
        #expect(!s.pasteImageAsFile)
        s.cutPasteEnabled = false
        s.pasteImageAsFile = true
        #expect(d.bool(forKey: "finderCutPasteEnabled") == false)
        #expect(d.bool(forKey: "finderPasteImageAsFile") == true)
    }
}
