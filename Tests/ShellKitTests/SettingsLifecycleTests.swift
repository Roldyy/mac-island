import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct SettingsLifecycleTests {
    @Test func relaunchCommandPassesTheBundlePathAsAnArgument() throws {
        let url = URL(fileURLWithPath: "/Applications/Mac Island; rm -rf x.app")
        let command = try #require(RelaunchCommand.make(bundleURL: url))
        #expect(command.executable == "/bin/sh")
        #expect(command.arguments.last == url.path)
        #expect(!command.arguments[1].contains("rm"))
        #expect(command.arguments[1].contains("/usr/bin/open -n"))
    }

    @Test func relaunchIsRefusedOutsideAnAppBundle() {
        #expect(RelaunchCommand.make(bundleURL: URL(fileURLWithPath: "/tmp/.build/debug/MacIsland")) == nil)
    }

    @Test func relaunchSpawnsThenTerminates() {
        var spawned: RelaunchCommand?
        var terminated = false
        let ok = AppLifecycle.relaunch(
            bundleURL: URL(fileURLWithPath: "/Applications/Mac Island.app"),
            spawn: { spawned = $0; return true }, terminate: { terminated = true })
        #expect(ok && spawned != nil && terminated)
    }

    @Test func relaunchDoesNotTerminateWhenSpawnFails() {
        var terminated = false
        let ok = AppLifecycle.relaunch(
            bundleURL: URL(fileURLWithPath: "/Applications/Mac Island.app"),
            spawn: { _ in false }, terminate: { terminated = true })
        #expect(!ok && !terminated)
    }

    @Test func languageAndAppearancePersist() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        #expect(LanguagePreference.load(from: b.defaults) == .french)
        #expect(AppearancePreference.load(from: b.defaults) == .system)
        LanguagePreference.dutch.save(to: b.defaults)
        AppearancePreference.dark.save(to: b.defaults)
        #expect(LanguagePreference.load(from: b.defaults) == .dutch)
        #expect(AppearancePreference.load(from: b.defaults) == .dark)
        b.defaults.set("garbage", forKey: AppearancePreference.key)
        #expect(AppearancePreference.load(from: b.defaults) == .system)
    }

    @Test func routerPersistsSelectionAndKeepsHistory() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let r = SettingsRouter(defaults: b.defaults)
        #expect(r.selection == "general")
        r.open("keepawake"); r.open("shelf")
        #expect(SettingsRouter(defaults: b.defaults).selection == "shelf")
        r.goBack()
        #expect(r.selection == "keepawake" && r.canGoForward)
        r.goForward()
        #expect(r.selection == "shelf")
        r.open("nonexistent")
        #expect(r.selection == "shelf")
        b.defaults.set("gone", forKey: SettingsRouter.selectionKey)
        #expect(SettingsRouter(defaults: b.defaults).selection == "general")
    }

    @Test func shortcutRoundTrips() throws {
        #expect(ShortcutSpec.keepAwakeDefault.display == "⌃⌥⌘K")
        let parsed = try #require(ShortcutSpec.parse(ShortcutSpec.keepAwakeDefault.stored))
        #expect(parsed == .keepAwakeDefault)
        #expect(ShortcutSpec.parse("shift:a") == nil)
    }

    @Test func backupExportsAndRestores() throws {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let domain = "mis-test-domain-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "dockPreviewEnabled")
        let backup = SettingsBackup(defaults: defaults, domain: domain, directory: dir)
        let file = try backup.export()
        #expect(backup.list().map(\.lastPathComponent) == [file.lastPathComponent])
        defaults.set(false, forKey: "dockPreviewEnabled")
        try backup.restore(from: file)
        #expect(defaults.bool(forKey: "dockPreviewEnabled"))
        let bad = dir.appendingPathComponent("settings-bad.plist")
        try Data("nope".utf8).write(to: bad)
        #expect(throws: (any Error).self) { try backup.restore(from: bad) }
    }

    @Test func liveStoreHonoursDefaultsAndInversion() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let store = LiveStore(defaults: b.defaults)
        let normal = LiveControl("k1", .toggle(defaultValue: true, inverted: false))
        let inverted = LiveControl("k2", .toggle(defaultValue: true, inverted: true))
        #expect(store.bool(normal) && store.bool(inverted))
        store.setBool(false, inverted)
        #expect(b.defaults.bool(forKey: "k2") == true && !store.bool(inverted))
        let stepper = LiveControl("k3", .stepper(range: 1...10, defaultValue: 5, unit: ""))
        store.setInt(99, stepper)
        #expect(store.int(stepper) == 10)
    }
}
