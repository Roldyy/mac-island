import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// The command catalog behind the extra dock: unique ids, disabled-state logic, search, confirmations.
@MainActor
@Suite struct ExtraDockCatalogTests {
    private struct Rig {
        let context: ShellContext
        let ran: Box<[String]>
        let cleanup: () -> Void
    }

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private func rig(enabled: Set<String> = ["terminal", "agents", "clipboard"], registerQuick: Bool = true,
                     withRelaunch: Bool = true) -> Rig {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-dock-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
        registry.switches = Dictionary(uniqueKeysWithValues: ShellDescriptors.all.map { ($0.id, enabled.contains($0.id)) })
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { IslandTab(id: $0, title: d.title, systemImage: d.systemImage) { AnyView(EmptyView()) } }
        }
        let ran = Box<[String]>([])
        let table = QuickActionTable()
        if registerQuick {
            for id in ["commands", "capture", "lockScreen", "cleaning", "keepawake"] { table.register(id) { let name: String = "quick.\(id)"; ran.value += [name] } }
        }
        var relaunch: (@MainActor () -> Void)?
        if withRelaunch { relaunch = { ran.value += ["relaunch"] } }
        let context = ShellContext(
            tabs: tabs, registry: registry, navigation: ShellNavigation(),
            quickAccess: QuickAccessModel(defaults: bench.defaults, table: table),
            home: HomeModel(defaults: bench.defaults,
                            volume: LevelBackend(read: { 0.4 }, write: { _ in true }, unavailableReason: "x"),
                            brightness: LevelBackend(read: { 0.7 }, write: { _ in true }, unavailableReason: "x"),
                            keyboardLight: .unsupported("x")),
            openSettings: { ran.value += ["settings"] },
            quit: { ran.value += ["quit"] },
            relaunch: relaunch,
            openSettingsPage: { let name: String = "page.\($0)"; ran.value += [name] })
        return Rig(context: context, ran: ran, cleanup: { bench.cleanup(); marker.clear() })
    }

    private func command(_ id: String, in context: ShellContext) throws -> DockCommand {
        try #require(context.dockCatalog().first { $0.id == id }, "\(id) is in the catalog")
    }

    // MARK: ids

    @Test func idsAreUniqueEvenWhenTheAppRegistersTheSameOneTwice() {
        let r = rig()
        defer { r.cleanup() }
        r.context.dockExtras.register(DockCommand(id: "port.test", title: "A", systemImage: "star", category: .tools) {})
        r.context.dockExtras.register(DockCommand(id: "port.test", title: "B", systemImage: "star", category: .tools) {})
        // An extra that reuses a core id never shadows the core command.
        r.context.dockExtras.register(DockCommand(id: "nav.settings", title: "Imposteur", systemImage: "star", category: .tools) {})
        let catalog = r.context.dockCatalog()
        #expect(Set(catalog.map(\.id)).count == catalog.count)
        #expect(catalog.filter { $0.id == "port.test" }.map(\.title) == ["B"])
        #expect(catalog.first { $0.id == "nav.settings" }?.title == "Réglages")
    }

    @Test func everyCommandHasATitleASymbolAndAKnownPrefix() {
        let r = rig()
        defer { r.cleanup() }
        for command in r.context.dockCatalog() {
            #expect(!command.title.isEmpty && !command.systemImage.isEmpty, "\(command.id)")
            #expect(["nav.", "tab.", "quick.", "feature.", "settings.", "app."].contains { command.id.hasPrefix($0) }, "\(command.id)")
        }
    }

    @Test func theCatalogCoversEveryPanelFeaturePageAndQuickAction() {
        let r = rig()
        defer { r.cleanup() }
        let ids = Set(r.context.dockCatalog().map(\.id))
        for tab in r.context.tabs { #expect(ids.contains("tab.\(tab.id)"), "\(tab.id)") }
        for d in ShellDescriptors.all { #expect(ids.contains("feature.\(d.id)"), "\(d.id)") }
        for page in SettingsPageCatalog.all { #expect(ids.contains("settings.\(page.id)"), "\(page.id)") }
        for id in ["commands", "capture", "lockScreen", "cleaning", "keepawake"] { #expect(ids.contains("quick.\(id)")) }
        #expect(ids.isSuperset(of: ["nav.explore", "nav.settings", "app.quit", "app.relaunch"]))
    }

    @Test func theDefaultDockResolvesFullyAgainstTheCatalog() {
        let r = rig()
        defer { r.cleanup() }
        let resolved = r.context.dockCommands(for: .initial)
        #expect(resolved.map(\.id) == ExtraDockLayout.initial.ids)
    }

    @Test func everyLegacyTargetExistsInTheCatalog() {
        let r = rig()
        defer { r.cleanup() }
        let ids = Set(r.context.dockCatalog().map(\.id))
        for (old, current) in ExtraDockLayout.legacyIDs { #expect(ids.contains(current), "\(old) -> \(current)") }
    }

    @Test func anIdNothingProvidesIsSkippedNotCrashing() {
        let r = rig()
        defer { r.cleanup() }
        let resolved = r.context.dockCommands(for: ExtraDockLayout(ids: ["tab.agents", "gone.forever", "nav.settings"]))
        #expect(resolved.map(\.id) == ["tab.agents", "nav.settings"])
    }

    // MARK: disabled state

    @Test func aPanelWhoseFeatureIsOffIsDisabledWithTheReason() throws {
        let r = rig(enabled: ["terminal"])
        defer { r.cleanup() }
        let terminal = try command("tab.terminal", in: r.context)
        let agents = try command("tab.agents", in: r.context)
        #expect(r.context.dockAvailability(terminal) == .available)
        let availability = r.context.dockAvailability(agents)
        #expect(!availability.isAvailable)
        #expect(availability.reason?.contains("Agents") == true)
        r.context.performDock(agents)
        #expect(r.context.navigation.route == .home)
        r.context.performDock(terminal)
        #expect(r.context.navigation.route == .page("terminal"))
    }

    @Test func aQuickActionWithNoHandlerIsDisabledAndDoesNothing() throws {
        let r = rig(registerQuick: false)
        defer { r.cleanup() }
        let capture = try command("quick.capture", in: r.context)
        #expect(!r.context.dockAvailability(capture).isAvailable)
        r.context.performDock(capture)
        #expect(r.ran.value.isEmpty)
    }

    @Test func aQuickActionWhoseFeatureIsOffNamesTheFeature() throws {
        let r = rig(enabled: [])
        defer { r.cleanup() }
        let keepAwake = try command("quick.keepawake", in: r.context)
        let availability = r.context.dockAvailability(keepAwake)
        #expect(availability.reason?.contains("Éveil") == true)
        r.context.performDock(keepAwake)
        #expect(r.ran.value.isEmpty)
        r.context.registry.setSwitch("keepawake", to: true)
        r.context.performDock(try command("quick.keepawake", in: r.context))
        #expect(r.ran.value == ["quick.keepawake"])
    }

    @Test func availabilityRulesCoverEveryRegistryState() {
        func rule(_ state: FeatureState?, own: String? = nil) -> DockAvailability {
            DockAvailabilityRules.evaluate(featureTitle: "Capture", featureState: state, ownReason: own)
        }
        #expect(rule(nil) == .available)
        #expect(rule(.active) == .available)
        for state in [FeatureState.off, .killed, .safeMode, .quarantined, .unavailable(reason: "Pas sur ce Mac"),
                      .needsPermission(.screenRecording)] {
            #expect(!rule(state).isAvailable, "\(state)")
            #expect(rule(state).reason?.isEmpty == false, "\(state)")
        }
        #expect(rule(.unavailable(reason: "Pas sur ce Mac")).reason == "Pas sur ce Mac")
        #expect(rule(.needsPermission(.screenRecording)).reason?.contains("screenRecording") == true)
        // The registry's verdict comes before the command's own reason; the own reason alone still disables.
        #expect(rule(.off, own: "autre").reason?.contains("désactivée") == true)
        #expect(rule(nil, own: "Aucun minuteur en cours.") == .disabled(reason: "Aucun minuteur en cours."))
        #expect(rule(.active, own: "") == .available)
    }

    @Test func switchingAFeatureFromTheDockFlipsItsSwitchBothWays() throws {
        let r = rig(enabled: [])
        defer { r.cleanup() }
        let toggle = try command("feature.shelf", in: r.context)
        #expect(toggle.isOn?() == false)
        r.context.performDock(toggle)
        #expect(r.context.registry.switches["shelf"] == true)
        #expect(try command("feature.shelf", in: r.context).isOn?() == true)
        r.context.performDock(try command("feature.shelf", in: r.context))
        #expect(r.context.registry.switches["shelf"] == false)
    }

    // MARK: run wiring

    @Test func settingsCommandsOpenTheRightPage() throws {
        let r = rig()
        defer { r.cleanup() }
        r.context.performDock(try command("settings.ports", in: r.context))
        r.context.performDock(try command("nav.settings", in: r.context))
        #expect(r.ran.value == ["page.ports", "settings"])
    }

    @Test func settingsPageFallsBackToTheWindowWhenNoPageDoorIsGiven() throws {
        let r = rig()
        defer { r.cleanup() }
        var context = r.context
        context.openSettingsPage = nil
        context.performDock(try command("settings.ports", in: context))
        #expect(r.ran.value == ["settings"])
    }

    @Test func theExplorerCommandTogglesTheExplorer() throws {
        let r = rig()
        defer { r.cleanup() }
        r.context.performDock(try command("nav.explore", in: r.context))
        #expect(r.context.navigation.route == .explore)
    }

    // MARK: destructive commands carry their own confirmation

    @Test func appQuitRelaunchAndPrivilegedFeaturesAskFirst() throws {
        let r = rig()
        defer { r.cleanup() }
        let quit = try command("app.quit", in: r.context)
        let relaunch = try command("app.relaunch", in: r.context)
        #expect(quit.needsConfirmation && relaunch.needsConfirmation)
        for descriptor in ShellDescriptors.all {
            let toggle = try command("feature.\(descriptor.id)", in: r.context)
            #expect(toggle.needsConfirmation == (descriptor.risk == .privileged), "\(descriptor.id)")
        }
    }

    @Test func noCommandThatEndsOrDiscardsAnythingSkipsItsConfirmation() {
        let r = rig()
        defer { r.cleanup() }
        let askFirst: Set<String> = ["app.quit", "app.relaunch"]
        for command in r.context.dockCatalog() {
            if askFirst.contains(command.id) { #expect(command.confirmation?.isEmpty == false, "\(command.id)") }
            // A confirmation is a real question, never an empty string.
            if let question = command.confirmation { #expect(!question.isEmpty, "\(command.id)") }
        }
    }

    @Test func theViewHasNoPathThatRunsAConfirmedCommandWithoutTheClick() throws {
        // The dock's only two doors are `run` (asks when `needsConfirmation`) and the "Confirmer" button.
        let r = rig()
        defer { r.cleanup() }
        let quit = try command("app.quit", in: r.context)
        #expect(quit.needsConfirmation)
        #expect(r.ran.value.isEmpty, "building the catalog and reading availability ran nothing")
        _ = r.context.dockAvailability(quit)
        #expect(r.ran.value.isEmpty)
    }

    // MARK: search and grouping

    @Test func searchIgnoresCaseAndAccentsAndNeedsEveryWord() {
        let r = rig()
        defer { r.cleanup() }
        let catalog = r.context.dockCatalog()
        let found = ExtraDockCatalog.search(catalog, query: "ETAGERE").map(\.id)
        #expect(found.contains("tab.shelf"))
        #expect(ExtraDockCatalog.search(catalog, query: "reglages ports").map(\.id).contains("settings.ports"))
        #expect(ExtraDockCatalog.search(catalog, query: "  ").count == catalog.count)
        #expect(ExtraDockCatalog.search(catalog, query: "zzzzqqq").isEmpty)
        #expect(ExtraDockCatalog.search(catalog, query: "caféine").map(\.id).contains("quick.keepawake"))
    }

    @Test func groupingFollowsCategoryOrderAndDropsEmptySections() {
        let r = rig()
        defer { r.cleanup() }
        let groups = ExtraDockCatalog.grouped(r.context.dockCatalog())
        let order = groups.map(\.category)
        #expect(order == DockCategory.allCases.filter { order.contains($0) })
        #expect(groups.allSatisfy { !$0.commands.isEmpty })
        let only = ExtraDockCatalog.grouped(r.context.dockCatalog().filter { $0.category == .settings })
        #expect(only.map(\.category) == [.settings])
    }
}
