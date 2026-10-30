import Foundation
import Testing
@testable import DockFeature

@Suite final class DockSettingsTests {
    /// Kept until the suite instance dies, so each domain is removed after its test.
    private var made: [TempDefaults] = []
    func fresh() -> UserDefaults { let t = TempDefaults(); made.append(t); return t.defaults }

    @Test func defaultsWhenAbsentAreOptIn() {
        let s = DockSettings(defaults: fresh())
        #expect(s.clickOptions == DockClickOptions(minimize: false, hide: false, cycle: false))
        #expect(!s.previewEnabled)
        #expect(s.previewDelay == 0.4)
    }
    @Test func readsTheMigratedKeysWithTheirOldNames() {
        let d = fresh()
        d.set(true, forKey: "dockClickMinimize")
        d.set(true, forKey: "dockClickHide")
        d.set(true, forKey: "dockClickCycleWindows")
        d.set(true, forKey: "dockPreviewEnabled")
        let s = DockSettings(defaults: d)
        #expect(s.clickOptions == DockClickOptions(minimize: true, hide: true, cycle: true))
        #expect(s.previewEnabled)
    }
    @Test func numericOneAndZeroAreReadAsBooleans() {
        let d = fresh()
        d.set(NSNumber(value: 1), forKey: "dockClickMinimize")
        d.set(NSNumber(value: 0), forKey: "dockClickHide")
        #expect(DockSettings(defaults: d).clickOptions.minimize)
        #expect(!DockSettings(defaults: d).clickOptions.hide)
    }
    @Test func settersWriteTheSameKeys() {
        let d = fresh()
        let s = DockSettings(defaults: d)
        s.clickMinimize = true; s.clickHide = true; s.clickCycle = true; s.previewEnabled = true
        s.previewDelayMilliseconds = 700
        #expect(d.bool(forKey: "dockClickMinimize") && d.bool(forKey: "dockClickHide"))
        #expect(d.bool(forKey: "dockClickCycleWindows") && d.bool(forKey: "dockPreviewEnabled"))
        #expect(d.integer(forKey: "dockPreviewDelayMilliseconds") == 700)
        #expect(s.previewDelay == 0.7)
    }
    @Test func delayIsClamped() {
        let d = fresh()
        d.set(5, forKey: "dockPreviewDelayMilliseconds")
        #expect(DockSettings(defaults: d).previewDelayMilliseconds == 100)
        d.set(60000, forKey: "dockPreviewDelayMilliseconds")
        #expect(DockSettings(defaults: d).previewDelayMilliseconds == 2000)
    }
}
