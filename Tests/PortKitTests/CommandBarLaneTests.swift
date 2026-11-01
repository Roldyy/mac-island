import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W5-C: the ported command bar, which replaces our `commandbar` module, bound through a fake runtime and a real
/// `FeatureRegistry`. Nothing here registers a hotkey, builds the bar's panel, reads the clipboard or touches Accessibility.
@MainActor
@Suite(.serialized) struct CommandBarLaneTests {
    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func runtime(_ log: Log) -> CommandBarLane.Runtime {
        CommandBarLane.Runtime(
            migrateLegacySettings: { log.events.append("migrate") },
            sync: { log.events.append("sync") },
            suspend: { log.events.append("suspend") })
    }

    /// The registry as the app builds it: our descriptors plus what the binding adds (nothing: the lane REPLACES the
    /// module, it does not add a second switch).
    func rig(switchedOn: Bool = true, accessibility: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        CommandBarLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { accessibility }, screenRecording: { false }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["commandbar"] = switchedOn
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor, permission and page tables

    @Test func theBarReplacesOurModuleAndAddsNoDescriptor() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(r.binding.descriptors.isEmpty, "the registry keeps OUR commandbar descriptor")
        #expect(ShellDescriptors.all.filter { $0.id == "commandbar" }.count == 1)
        #expect(r.registry.descriptors.filter { $0.id == "commandbar" }.count == 1)
        let bar = r.registry.descriptor("commandbar")
        #expect(bar?.tabID == "commandbar", "the island tab and the Home tile keep their id")
        #expect(bar?.title == "Commandes")
        #expect(r.registry.state(for: "commandbar") == .off)
        #expect(r.log.events.isEmpty, "binding starts nothing")
        #expect(r.binding.pages.isEmpty, "the page is a plain body: its catalog row already carries the commandbar card")
        #expect(PortFeatureIDs.existing["commandBar"] == "commandbar" && AppFeature.commandBar.registryID == "commandbar")
    }

    @Test func theDescriptorPermissionTableMatchesWhatTheBarCanUse() {
        // Upstream: the bar can use Accessibility (menus, selected text, typing and pasting, windows). Our descriptor
        // asks for nothing at start because every source re-checks the grant itself and the bar never prompts.
        #expect(AppFeature.commandBar.permissions.contains(.accessibility))
        #expect(PortFeatureBinding.featurePermissions(of: .commandBar) == [.accessibility])
        #expect(PortFeatureBinding.risk(of: .commandBar) == .touchesInput)
        let ours = ShellDescriptors.all.first { $0.id == "commandbar" }
        #expect(ours?.permissions.contains(.screenRecording) != true && ours?.permissions.contains(.fullDiskAccess) != true)
    }

    @Test func bindReplacingTakesTheBarOnceAndBindRefusesIt() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        #expect(binding.bind("commandBar", start: {}, stop: {}) == nil, "bind() refuses an existing module's id")
        #expect(CommandBarLane.bind(into: binding, runtime: runtime(Log())))
        #expect(binding.bindReplacing("commandBar", start: {}, stop: {}) == false, "already bound")
        #expect(binding.availability("commandbar") == false, "bound: the registry's verdict, off until started")
    }

    @Test func thePageCarriesTheBarCardAndHasNoLiveRowsOfItsOwn() {
        let page = SettingsPageCatalog.page("commandbar")
        #expect(page?.featureID == "commandbar")
        #expect(SettingsLive.controls(for: "commandbar") == nil, "the ported body draws the whole page")
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        SettingsPageBodies.register(pageID: "commandbar") { AnyView(CommandBarPage()) }
        #expect(page?.isComingSoon == false)
    }

    @Test func theLaneRegistersItsPageBodyOnBind() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        CommandBarLane.bind(into: binding)
        #expect(PortBridge.registeredPageIDs.contains("commandbar"))
    }

    @Test func thePageAndTheTabRender() {
        PortHostFixture.isolated { _ in
            let tab = PortCommandBar.tab()
            #expect(tab.id == "commandbar" && tab.title == "Commandes" && tab.systemImage == "command")
            for view in [AnyView(CommandBarPage().defaultAppStorage(PortHost.defaults))] {
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 60, "rendered: \(host.fittingSize)")
            }
        }
    }

    // MARK: Start, stop, kill switch

    @Test func switchingTheBarOnStartsItOnceAndOffStopsIt() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["commandbar"] = true
        r.registry.switches["commandbar"] = true
        #expect(r.log.events == ["migrate", "sync"], "idempotent: one start, the old settings moved first")
        #expect(r.binding.availability("commandbar") == true)
        r.log.events.removeAll()
        r.registry.switches["commandbar"] = false
        #expect(r.log.events == ["suspend"])
        #expect(r.binding.availability("commandbar") == false)
        r.registry.switches["commandbar"] = false
        #expect(r.log.count("suspend") == 1, "a second off changes nothing")
    }

    @Test func killSwitchAndSafeModeStopTheBarAndItComesBack() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.log.events == ["migrate", "sync"])
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.events == ["suspend"], "the kill switch removes the shortcut and closes the panel")
        #expect(r.binding.availability("commandbar") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.events == ["migrate", "sync"])
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.count("suspend") == 1, "safe mode stops it too")
        #expect(r.binding.availability("commandbar") == false)
    }

    @Test func aMissingAccessibilityGrantNeverBlocksTheStartAndTheBarNeverAsksForIt() {
        let r = rig(accessibility: false)
        defer { r.cleanup() }
        #expect(r.registry.state(for: "commandbar") == .active, "no permission gates the start")
        #expect(r.log.events == ["migrate", "sync"])
        // The grant does not restart anything: the sources read the grant live.
        let none = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false)
        let ax = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        r.log.events.removeAll()
        r.registry.permissionsChanged(PermissionChange(old: none, new: ax))
        #expect(r.log.count("migrate") <= 1 && r.log.count("suspend") <= 1)
    }

    @Test func theBarOpensOnlyWhileTheRegistryLetsItRun() {
        PortHostFixture.isolated { _ in
            #expect(PortCommandBar.show() == false, "nothing bound: nothing opens")
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            #expect(!PortCommandBar.isRunning && PortCommandBar.show() == false, "bound but off")
            r.registry.switches["commandbar"] = true
            #expect(PortCommandBar.isRunning)
            r.registry.killSwitch = true
            #expect(!PortCommandBar.isRunning && PortCommandBar.show() == false, "the kill switch closes the button too")
        }
    }

    // MARK: Replacement of ours

    @Test func theLaneIsInTheLaneListAndOurOldModuleIsNotStartedByTheApp() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("CommandBarLane.bind(into:)"))
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        #expect(!delegate.contains("CommandBarFeature.start") && !delegate.contains("CommandBarFeature.stop"),
                "a registry starter of ours would win over the ported one (`{ _, ours in ours }`)")
        #expect(delegate.contains("CommandBarFeature.tab()") && delegate.contains("CommandBarFeature.register(commands:"),
                "the island tab and the shell's commands stay")
        let actions = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/SystemActions.swift"), encoding: .utf8)
        #expect(actions.contains("CommandBarFeature.show()"), "the Home tile and the round button open the ported bar")
    }

    @Test func ourOldModuleIsGoneAndOnlyTheAdapterRemains() throws {
        let dir = PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/Features/CommandBar")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["BarCommand.swift", "CommandBarFeature.swift"], "the old hotkey, panel, model and sources are deleted")
        for name in names {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            #expect(!text.contains("RegisterEventHotKey") && !text.contains("InstallEventHandler"),
                    "\(name): no second registrar of the shortcut")
        }
    }

    // MARK: Shortcut: one owner, the one the person has

    @Test func theShortcutHasOneOwnerAndItsDefaultsAreThePortedKeys() {
        PortHostFixture.isolated { defaults in
            #expect(GlobalShortcutRole.commandBar.storageKey == "commandBarShortcut")
            #expect(GlobalShortcutRole.commandBar.feature == .commandBar)
            var state = PortShortcutOwnership.commandBarShortcut(in: defaults)
            #expect(!state.enabled && state.shortcut == .commandBarDefault, "ported default: off, Option-Space")
            defaults.set(true, forKey: DefaultsKey.commandBarShortcutEnabled)
            defaults.set("control+option+command:k", forKey: DefaultsKey.commandBarShortcut)  // our own format
            state = PortShortcutOwnership.commandBarShortcut(in: defaults)
            #expect(state.enabled && state.shortcut == GlobalShortcut(keyCode: 40, modifiers: [.control, .option, .command]))
            defaults.set("not a shortcut", forKey: DefaultsKey.commandBarShortcut)
            #expect(PortShortcutOwnership.commandBarShortcut(in: defaults).shortcut == .commandBarDefault)
        }
    }

    @Test func theShortcutSurfacesFollowTheRegistryBinding() {
        PortHostFixture.isolated { _ in
            #expect(!PortShortcutOwnership.isBound(.commandBar), "unbound: the central editor never starts it")
            PortHost.availability = { $0 == "commandbar" ? false : nil }
            #expect(PortShortcutOwnership.isBound(.commandBar) && !PortShortcutOwnership.isRunning(.commandBar))
            PortHost.availability = { $0 == "commandbar" ? true : nil }
            #expect(PortShortcutOwnership.isRunning(.commandBar))
        }
    }

    @Test func theBarsRegistrarIsTheSharedQuickToolHotkeyAndNothingElse() throws {
        let service = try String(contentsOf: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Sources/PortKit/Services/CommandBar/CommandBarService.swift"), encoding: .utf8)
        #expect(service.contains("QuickToolHotkey(id: 20)"))
        #expect(service.contains("hotkey.sync(enabled: enabled, shortcut: shortcut"))
        // The ported hotkey claims the key for the system-shortcut takeover under the stored key, and releases it.
        let hotkey = try String(contentsOf: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Sources/PortKit/Services/QuickTools/QuickToolHotkey.swift"), encoding: .utf8)
        #expect(hotkey.contains("SystemShortcutTakeover.claim") && hotkey.contains("SystemShortcutTakeover.release"))
    }

    // MARK: The old module's settings

    @Test func theOldShortcutAndSwitchMoveAcrossOnceOnTheSameKey() {
        PortHostFixture.isolated { defaults in
            defaults.set("option+command:9", forKey: PortCommandBarLegacy.oldHotkeyKey)
            defaults.set(true, forKey: PortCommandBarLegacy.oldEnabledKey)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-legacy-\(UUID().uuidString)")
            let report = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(report?.enabled == true && report?.shortcut != nil)
            let state = PortShortcutOwnership.commandBarShortcut(in: defaults)
            #expect(state.enabled)
            #expect(state.shortcut == GlobalShortcut(keyCode: 25, modifiers: [.option, .command]), "the key the person had")
            #expect(defaults.object(forKey: PortCommandBarLegacy.oldHotkeyKey) == nil
                    && defaults.object(forKey: PortCommandBarLegacy.oldEnabledKey) == nil, "the old keys are removed")
            #expect(PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir) == nil, "once")
            defaults.set("control:k", forKey: DefaultsKey.commandBarShortcut)
            _ = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(defaults.string(forKey: DefaultsKey.commandBarShortcut) == "control:k", "a second run never overwrites")
        }
    }

    @Test func ourOldShortcutFormatIsReadByKeyNameNotByKeyCode() {
        typealias Legacy = PortCommandBarLegacy
        #expect(Legacy.shortcut(fromLegacy: "option+command:9") == GlobalShortcut(keyCode: 25, modifiers: [.option, .command]),
                "the 9 key")
        #expect(GlobalShortcut(storageValue: "option+command:9") == GlobalShortcut(keyCode: 9, modifiers: [.option, .command]),
                "the ported reader would have picked the V key: that is why the migration has its own parser")
        #expect(Legacy.shortcut(fromLegacy: "option:space") == .commandBarDefault)
        #expect(Legacy.shortcut(fromLegacy: "control+option+command:k") == GlobalShortcut(keyCode: 40, modifiers: [.control, .option, .command]))
        #expect(Legacy.shortcut(fromLegacy: "Cmd+Alt:Return") == GlobalShortcut(keyCode: 36, modifiers: [.command, .option]))
        #expect(Legacy.shortcut(fromLegacy: "shift+command:0") == GlobalShortcut(keyCode: 29, modifiers: [.shift, .command]))
        for bad in ["shift:a", "option:", "option:nonsense", "hyper:a", "a", "option:space:x", "", ":space", "+:a"] {
            #expect(Legacy.shortcut(fromLegacy: bad) == nil, "\(bad)")
        }
        #expect(Set(Legacy.legacyKeyCodes.values).count == Legacy.legacyKeyCodes.count, "one name per key code")
    }

    @Test func aFreshInstallKeepsTheOldDefaultOnWithOptionSpace() {
        PortHostFixture.isolated { defaults in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-legacy-\(UUID().uuidString)")
            let report = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(report?.enabled == true, "the old module was on by default")
            #expect(report?.shortcut == nil && report?.removedKeys.isEmpty == true)
            let state = PortShortcutOwnership.commandBarShortcut(in: defaults)
            #expect(state.enabled && state.shortcut == .commandBarDefault)
        }
    }

    @Test func aSwitchedOffBarStaysOffAndAnUnreadableShortcutIsLeftAlone() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: PortCommandBarLegacy.oldEnabledKey)
            defaults.set("shift:nonsense", forKey: PortCommandBarLegacy.oldHotkeyKey)
            defaults.set("command:j", forKey: DefaultsKey.commandBarShortcut)  // chosen in the old app and migrated
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-legacy-\(UUID().uuidString)")
            let report = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(report?.enabled == false && report?.shortcut == nil)
            #expect(!PortShortcutOwnership.commandBarShortcut(in: defaults).enabled)
            #expect(defaults.string(forKey: DefaultsKey.commandBarShortcut) == "command:j")
        }
    }

    @Test func switchedOffSourcesAreCarriedAndTheCommandsSourceHasNoCounterpart() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: "commandBarSourceApps")
            defaults.set(false, forKey: "commandBarSourceCommands")
            defaults.set(true, forKey: "commandBarSourceFiles")
            defaults.set(false, forKey: "commandBarSourceWeb")
            defaults.set(false, forKey: "commandBarHabitsEnabled")
            defaults.set("emoji", forKey: DefaultsKey.commandBarDisabledSources)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-legacy-\(UUID().uuidString)")
            let report = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(report?.disabledSources == ["apps"])
            let disabled = CommandBarPreferences.disabledSources(
                from: defaults.string(forKey: DefaultsKey.commandBarDisabledSources) ?? "")
            #expect(disabled == [.apps, .emoji], "merged with what was already off, the always-on actions never")
            #expect(!PortCommandBarWebSearch.isEnabled(in: defaults), "the web switch keeps its name and its meaning")
            #expect(!PortCommandBarLearning.isEnabled(in: defaults), "so does the learning switch")
            #expect(defaults.object(forKey: "commandBarSourceApps") == nil && defaults.object(forKey: "commandBarSourceCommands") == nil)
            #expect(defaults.object(forKey: "commandBarSourceWeb") != nil && defaults.object(forKey: "commandBarHabitsEnabled") != nil)
        }
    }

    @Test func theOldUsageFileIsRemovedAndTheDigestKeyIsNeverTouched() throws {
        try PortHostFixture.isolated { defaults in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-legacy-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let habits = dir.appendingPathComponent(PortCommandBarLegacy.habitsFileName)
            let other = dir.appendingPathComponent("ClipboardHistory.json")
            try Data("{}".utf8).write(to: habits)
            try Data("{}".utf8).write(to: other)
            defaults.set(Data([1, 2, 3]), forKey: DefaultsKey.commandBarQueryHabitKey)
            let report = PortCommandBarLegacy.migrate(in: defaults, dataDirectory: dir)
            #expect(report?.removedHabitsFile == true)
            #expect(!FileManager.default.fileExists(atPath: habits.path))
            #expect(FileManager.default.fileExists(atPath: other.path), "nothing else in the folder is touched")
            #expect(defaults.data(forKey: DefaultsKey.commandBarQueryHabitKey) == Data([1, 2, 3]))
        }
    }

    // MARK: Host commands

    @Test func commandsTheShellRegistersJoinTheActionsAndAnIdReplacesTheEarlierOne() async {
        PortCommandBarHost.removeAll()
        defer { PortCommandBarHost.removeAll() }
        final class Flag: @unchecked Sendable { var value = ""; }
        let flag = Flag()
        PortCommandBar.registerHostCommands([
            .init(id: "island.tab.dock", title: "Ouvrir Dock", keywords: ["île", "dock"]) { flag.value = "first" },
            .init(id: "island.tab.fans", title: "Ouvrir Ventilateurs") {},
        ])
        PortCommandBar.registerHostCommands([.init(id: "island.tab.dock", title: "Ouvrir Dock") { flag.value = "second" }])
        let entries = PortCommandBarHost.entries()
        #expect(entries.map(\.id) == ["host.island.tab.dock", "host.island.tab.fans"])
        #expect(entries[0].title == "Ouvrir Dock" && entries[0].subtitle == "Mac Island")
        for entry in entries {
            #expect(CommandBarPreferences.source(ofRowID: entry.id) == .actions, "no source prefix: an action of the app")
            #expect(entry.countsUsage, "the learned order applies to them")
        }
        entries[0].run(nil)
        for _ in 0..<600 where flag.value.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
        #expect(flag.value == "second", "run on the main actor, the replacing command only")
    }

    // MARK: Sources: what each needs

    @Test func everySourceHasATitleAndAKnownNeed() {
        #expect(CommandBarSource.allCases.count == 18)
        for source in CommandBarSource.allCases {
            #expect(!PortCommandBarSources.title(of: source).isEmpty)
            _ = PortCommandBarSources.needs(of: source)
        }
        #expect(PortCommandBarSources.needs(of: .apps).isEmpty && PortCommandBarSources.needs(of: .calculator).isEmpty)
        #expect(PortCommandBarSources.needs(of: .menus) == [.accessibility])
        #expect(PortCommandBarSources.needs(of: .selection) == [.accessibility])
        #expect(PortCommandBarSources.needs(of: .files) == [.folders])
    }

    private func environment(accessibility: Bool = true, folders: Bool = true,
                             states: [AppFeature: PortCommandBarSources.FeatureState] = [:]) -> PortCommandBarSources.Environment {
        PortCommandBarSources.Environment(accessibility: accessibility, featureState: { states[$0] ?? .running },
                                          hasFileFolders: folders)
    }

    @Test func theClipboardSourceIsHiddenWithAReasonUntilTheClipboardLaneBindsIt() {
        let unbound = environment(states: [.clipboardHistory: .unbound])
        let reason = PortCommandBarSources.unavailableReason(of: .clipboard, in: unbound)
        #expect(reason?.contains("pas encore repris") == true && reason?.contains("cachée") == true)
        let off = environment(states: [.clipboardHistory: .off])
        #expect(PortCommandBarSources.unavailableReason(of: .clipboard, in: off)?.contains("Activez") == true)
        #expect(PortCommandBarSources.unavailableReason(of: .clipboard, in: environment(states: [.clipboardHistory: .running])) == nil)
        // The ported rows really are guarded by the same feature: nothing is read from the clipboard store unbound.
        PortHostFixture.isolated { _ in
            PortHost.availability = { _ in nil }
            #expect(CommandBarCatalog.clipboardEntries(matching: "abc", bar: FeatureStrings.commandBar(.fr)) { _ in }.isEmpty)
            #expect(CommandBarCatalog.clipboardBrowseEntries(limit: 5, bar: FeatureStrings.commandBar(.fr)) { _ in }.isEmpty)
        }
    }

    @Test func snippetsWindowsMenusAndSelectionNeedTheirFeatureOrAccessibility() {
        #expect(PortCommandBarSources.unavailableReason(of: .snippets, in: environment(states: [.textSnippets: .unbound]))?.contains("extraits de texte") == true)
        #expect(PortCommandBarSources.unavailableReason(of: .snippets, in: environment()) == nil)
        let noAX = environment(accessibility: false)
        for source in [CommandBarSource.menus, .selection, .windows] {
            #expect(PortCommandBarSources.unavailableReason(of: source, in: noAX)?.contains("Accessibilité") == true, "\(source)")
        }
        #expect(PortCommandBarSources.unavailableReason(of: .menus, in: environment()) == nil)
        // Windows: one of the two window features must run.
        let neither = environment(states: [.switcher: .off, .windowLayout: .unbound])
        #expect(PortCommandBarSources.unavailableReason(of: .windows, in: neither)?.contains("Activez") == true)
        let one = environment(states: [.switcher: .off, .windowLayout: .running])
        #expect(PortCommandBarSources.unavailableReason(of: .windows, in: one) == nil)
        #expect(PortCommandBarSources.unavailableReason(of: .killProcess, in: environment(states: [.killProcess: .off]))?.contains("Forcer à quitter") == true)
        #expect(PortCommandBarSources.unavailableReason(of: .uninstallApps, in: environment(states: [.uninstaller: .unbound])) != nil)
    }

    @Test func filesNeedFoldersAndNeverAPermission() {
        #expect(PortCommandBarSources.unavailableReason(of: .files, in: environment(folders: false))?.contains("dossiers") == true)
        #expect(PortCommandBarSources.unavailableReason(of: .files, in: environment()) == nil)
        PortHostFixture.isolated { defaults in
            #expect(!PortCommandBarSources.Environment.live(defaults: defaults).hasFileFolders)
            defaults.set("~/Documents", forKey: DefaultsKey.commandBarFileScopes)
            #expect(PortCommandBarSources.Environment.live(defaults: defaults).hasFileFolders)
            defaults.set("  \n ", forKey: DefaultsKey.commandBarFileScopes)
            #expect(!PortCommandBarSources.Environment.live(defaults: defaults).hasFileFolders)
        }
    }

    @Test func sourcesWithNoNeedAreNeverReportedAndTheNoticesKeepTheSourceOrder() {
        let all = PortCommandBarSources.notices(in: environment(accessibility: false, folders: false,
                                                                  states: [.clipboardHistory: .unbound, .textSnippets: .off,
                                                                           .killProcess: .off, .uninstaller: .off,
                                                                           .switcher: .off, .windowLayout: .off]))
        let sources = all.map(\.source)
        #expect(sources == [.menus, .windows, .uninstallApps, .snippets, .clipboard, .selection, .files, .killProcess])
        #expect(Set(sources).isDisjoint(with: [.apps, .actions, .calculator, .emoji, .links, .macSettings, .settingsPages,
                                               .folders, .answers, .quitApps]))
        #expect(PortCommandBarSources.notices(in: environment()).isEmpty)
    }
}
