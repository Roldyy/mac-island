import Foundation
import IslandKit

/// The one catalog of what the app can do, for the extra dock and its picker. Everything comes from what exists at
/// that moment: the registered panels, the registry's features, the Settings pages, the quick actions, then the
/// commands the app registered (`dockExtras`). Each entry is wired to the same entry point the rest of the app uses.
@MainActor
extension ShellContext {
    /// Every command, core first, with no repeated id.
    public func dockCatalog() -> [DockCommand] {
        ExtraDockCatalog.unique(coreDockCommands() + dockExtras.commands)
    }

    /// The commands of a dock layout, in its order. An id nothing provides (a command from another build) is skipped.
    public func dockCommands(for layout: ExtraDockLayout) -> [DockCommand] {
        let byID = Dictionary(dockCatalog().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return layout.ids.compactMap { byID[$0] }
    }

    public func dockAvailability(_ command: DockCommand) -> DockAvailability {
        DockAvailabilityRules.evaluate(
            featureTitle: command.featureID.flatMap { registry.descriptor($0)?.title },
            featureState: command.featureID.map { registry.state(for: $0) },
            ownReason: command.unavailableReason?())
    }

    /// Runs a command that is available. The confirmation of a destructive one is the caller's job (the dock asks
    /// first, then calls this); a disabled command does nothing.
    public func performDock(_ command: DockCommand) {
        guard dockAvailability(command).isAvailable else { return }
        command.run()
    }

    // MARK: - Core commands

    private func coreDockCommands() -> [DockCommand] {
        let context = self
        var list: [DockCommand] = [
            DockCommand(id: "nav.explore", title: "Explorer", systemImage: "square.grid.2x2", category: .panels,
                        keywords: ["raccourcis", "grille"]) { context.navigation.toggleExplore() },
            DockCommand(id: "nav.settings", title: "Réglages", systemImage: "gearshape", category: .settings,
                        keywords: ["préférences", "settings"]) { context.openSettings() },
        ]

        // Panels: every registered tab, the same way a tile opens it.
        for tab in tabs {
            let tabID = tab.id
            list.append(DockCommand(
                id: "tab.\(tabID)", title: tab.title, systemImage: tab.systemImage, category: .panels,
                keywords: [tabID, "onglet", "panneau"],
                unavailableReason: { context.isTabEnabled(tabID) ? nil : "« \(tab.title) » est désactivé. Active-le dans Fonctionnalités." },
                run: { context.navigation.open(tabID: tabID) }))
        }

        // Quick actions (the bar of the home): same table, same handlers.
        let quick: [(id: String, category: DockCategory, keywords: [String])] = [
            ("commands", .tools, ["barre de commande", "command bar", "calculatrice"]),
            ("capture", .capture, ["capture d'écran", "screenshot", "zone", "fenêtre"]),
            ("lockScreen", .system, ["verrouiller", "lock", "écran"]),
            ("cleaning", .tools, ["nettoyage", "clavier", "cleaning"]),
            ("keepawake", .system, ["éveil", "caféine", "veille", "keep awake"]),
        ]
        for entry in quick {
            guard let action = HomeActionCatalog.action(entry.id) else { continue }
            let quickID = entry.id
            var isOn: (@MainActor () -> Bool)?
            if action.activeSystemImage != nil { isOn = { context.quickAccess.table.isOn(quickID) } }
            let reason: @MainActor () -> String? = {
                context.quickAccess.table.isAvailable(quickID) ? nil : "Pas encore disponible dans cette version."
            }
            let fire: @MainActor () -> Void = { context.quickAccess.table.fire(quickID) }
            list.append(DockCommand(
                id: "quick.\(quickID)", title: action.title, systemImage: action.systemImage,
                activeSystemImage: action.activeSystemImage, category: entry.category, keywords: entry.keywords,
                featureID: HomeTileCatalog.quickActionFeatures[quickID], isOn: isOn, unavailableReason: reason, run: fire))
        }

        // Features: switch any of them on or off. A privileged one asks first.
        for descriptor in registry.descriptors {
            let featureID = descriptor.id
            list.append(DockCommand(
                id: "feature.\(featureID)", title: "Basculer : \(descriptor.title)", systemImage: descriptor.systemImage,
                category: .features, keywords: [descriptor.title, featureID, "activer", "désactiver", "couper", "interrupteur"],
                confirmation: descriptor.risk == .privileged
                    ? "« \(descriptor.title) » agit avec des droits élevés. Changer son interrupteur ?" : nil,
                isOn: { context.registry.switches[featureID] == true },
                run: { context.registry.setSwitch(featureID, to: context.registry.switches[featureID] != true) }))
        }

        // Settings pages.
        for page in SettingsPageCatalog.all {
            let pageID = page.id
            let keywords: [String] = page.keywords + [pageID, page.section.title]
            let open: @MainActor () -> Void = {
                if let openPage = context.openSettingsPage { openPage(pageID) } else { context.openSettings() }
            }
            list.append(DockCommand(id: "settings.\(pageID)", title: "Réglages : \(page.title)", systemImage: page.symbol,
                                    category: .settings, keywords: keywords, run: open))
        }

        // The app itself. Both end or restart everything the island runs: always asked first.
        if let relaunch {
            list.append(DockCommand(
                id: "app.relaunch", title: "Relancer Mac Island", systemImage: "arrow.clockwise", category: .system,
                keywords: ["redémarrer", "relaunch"],
                confirmation: "Relancer Mac Island ? Les panneaux ouverts se ferment.") { relaunch() })
        }
        list.append(DockCommand(
            id: "app.quit", title: "Quitter Mac Island", systemImage: "power", category: .system, keywords: ["fermer", "quit"],
            confirmation: "Quitter Mac Island ? Le dock, l'île et les fonctions actives s'arrêtent.") { context.quit() })
        return list
    }
}
