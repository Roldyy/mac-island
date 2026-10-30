import Foundation
import Testing
@testable import ClipboardFeature

@Suite struct ClipboardSettingsTests {
    func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "clip-test-\(UUID().uuidString)")!
        return d
    }

    @Test func defaultsWhenEmpty() {
        let s = ClipboardSettings(defaults: defaults())
        #expect(s.historyLimit == 50)
        #expect(s.autoClearDelay == 0)
        #expect(s.historyEnabled)
        #expect(s.pastePlainEnabled)
        #expect(s.pastePlainShortcut == .default)
        #expect(s.excludedBundleIDs.isEmpty)
    }

    @Test func readsMigratedKeys() {
        let d = defaults()
        d.set(20, forKey: "clipboardHistoryLimit")
        d.set(20.0, forKey: "clipboardAutoClearDelaySeconds")
        d.set(false, forKey: "pastePlainEnabled")
        d.set("control+shift:v", forKey: "pastePlainShortcut")
        d.set(false, forKey: "clipboardHistoryEnabled")
        d.set(["com.example.vault"], forKey: "clipboardExcludedBundleIDs")
        let s = ClipboardSettings(defaults: d)
        #expect(s.historyLimit == 20)
        #expect(s.autoClearDelay == 20)
        #expect(!s.pastePlainEnabled)
        #expect(!s.historyEnabled)
        #expect(s.pastePlainShortcut.keyCode == 9)
        #expect(s.excludedBundleIDs == ["com.example.vault"])
    }

    @Test func clampsAndFallsBack() {
        let d = defaults()
        d.set(0, forKey: "clipboardHistoryLimit")
        #expect(ClipboardSettings(defaults: d).historyLimit == 1)
        d.set(100_000, forKey: "clipboardHistoryLimit")
        #expect(ClipboardSettings(defaults: d).historyLimit == 500)
        d.set("garbage", forKey: "pastePlainShortcut")
        #expect(ClipboardSettings(defaults: d).pastePlainShortcut == .default)
        d.set(-3, forKey: "clipboardAutoClearDelaySeconds")
        #expect(ClipboardSettings(defaults: d).autoClearDelay == 0)
    }
}
