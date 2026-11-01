import Foundation
import IslandKit

/// Which rows of which page really work. Everything else on a page is shown greyed and marked "Bientôt".
///
/// The keys are the ones the feature modules already read (see each feature's settings type): ShellKit
/// does not depend on the feature targets, so the names live here as plain strings and a test keeps
/// them honest.
public enum SettingsLive {
    public struct Page: Sendable {
        /// Row label (as noted from the reference page) to the control that replaces it.
        public var bound: [String: LiveControl] = [:]
        /// Controls with no matching row, shown first.
        public var extras: [LiveControl] = []
        /// More registry features whose switch and status open the page (besides the page's own).
        public var featureIDs: [String] = []
    }

    public static func controls(for pageID: String) -> Page? { table[pageID] }

    /// True when the page has no working control of its own.
    public static func isEmpty(pageID: String) -> Bool {
        guard let page = table[pageID] else { return true }
        return page.bound.isEmpty && page.extras.isEmpty && page.featureIDs.isEmpty
    }

    private typealias C = LiveControl

    private static func flag(_ key: String, _ fallback: Bool, inverted: Bool = false, title: String? = nil, hint: String? = nil) -> C {
        C(key, .toggle(defaultValue: fallback, inverted: inverted), title: title, hint: hint)
    }

    private static func source(_ id: String) -> C { flag(CommandBarKeys.source(id), true) }

    enum CommandBarKeys {
        static func source(_ id: String) -> String { "commandBarSource" + id.prefix(1).uppercased() + id.dropFirst() }
    }

    static let table: [String: Page] = [
        "monitor": Page(
            bound: [
                "Répéter la même alerte après": C("monitorAlertCooldownMinutes", .choice(options: [
                    .init("5 minutes", 5), .init("15 minutes", 15), .init("30 minutes", 30),
                    .init("1 heure", 60), .init("2 heures", 120),
                ], defaultValue: 15)),
            ],
            extras: [
                flag("monitorAlertsEnabled", false, title: "Alertes de charge",
                     hint: "Prévient quand le processeur ou la mémoire reste trop haut. Éteint tant que vous ne l’activez pas."),
                C("monitorAlertCPUThreshold", .slider(range: 1...100, defaultValue: 90, unit: "%"), title: "Seuil du processeur"),
                C("monitorAlertMemoryThreshold", .slider(range: 1...100, defaultValue: 90, unit: "%"), title: "Seuil de la mémoire"),
                C("monitorAlertSustainedSeconds", .stepper(range: 0...3600, defaultValue: 30, unit: "s"),
                  title: "Durée au-dessus du seuil", hint: "Combien de secondes la charge doit durer avant l’alerte."),
                flag("monitorSystemNotificationsEnabled", false, title: "Notifications système",
                     hint: "Affiche aussi l’alerte dans le centre de notifications."),
            ]),
        "commandbar": Page(
            bound: [
                "Apps": source("apps"), "Fichiers": source("files"), "Calculs et conversions": source("calculator"),
                "Actions Mac Island": source("commands"),
                "Raccourci": C("commandBarHotkey", .shortcut(defaultValue: "option:space")),
            ],
            extras: [
                flag("commandBarEnabled", true, title: "Activer la barre de commande"),
                flag("commandBarHabitsEnabled", true, title: "Retenir ce que j’utilise le plus",
                     hint: "Remonte vos choix habituels dans les résultats."),
                source("web").withTitle("Recherche sur le web"),
            ]),
        // "keepawake" has no live entry any more: the ported Keep Awake page (PortKit, Energy lane) draws the whole
        // page, its default duration, automation, jiggle, display sleep, battery limit, island hold and closed lid.
        // "dockpreview" and "dockclicks" have no live entry any more: the ported Dock pages (PortKit, Dock lane) draw
        // both pages whole, under the `dock` feature card their catalog rows carry.
        "quitonclose": Page(
            bound: ["Quitter les apps à la fermeture de leur dernière fenêtre": flag("autoQuitEnabled", false)],
            extras: [
                C("autoQuitDelayMinutes", .stepper(range: 1...1440, defaultValue: 30, unit: "min"),
                  title: "Minutes sans fenêtre visible", hint: "Délai avant qu’une app soit annoncée comme à quitter."),
                flag("autoQuitDryRun", true, title: "Simulation",
                     hint: "Annonce ce qui serait quitté sans rien fermer. Laissée active jusqu’à votre choix."),
            ]),
        "clipboard": Page(
            bound: [
                "Garder l’historique du presse-papiers": flag("clipboardHistoryEnabled", true),
                "Limite": C("clipboardHistoryLimit", .choice(options: [
                    .init("10", 10), .init("25", 25), .init("50", 50), .init("100", 100), .init("200", 200), .init("500", 500),
                ], defaultValue: 50)),
                "Vider le presse-papiers automatiquement après": flag("clipboardAutoClearOnDelay", false),
                "Coller les images copiées comme fichiers": flag("finderPasteImageAsFile", true),
            ],
            extras: [
                C("clipboardAutoClearDelaySeconds", .stepper(range: 1...3600, defaultValue: 20, unit: "s"),
                  title: "Délai avant effacement", hint: "Compte seulement si l’effacement automatique est activé."),
            ]),
        "pasteplain": Page(bound: [
            "Coller en texte brut": flag("pastePlainEnabled", true),
            "Raccourci": C("pastePlainShortcut", .shortcut(defaultValue: "option+command:9")),
        ]),
        "cutpaste": Page(bound: ["Couper-coller dans le Finder": flag("finderCutPasteEnabled", false)]),
        "shelf": Page(
            bound: ["Activer l’étagère": flag("shelfEnabled", true)],
            extras: [
                flag("shelfDownloadsEnabled", true, title: "Montrer les téléchargements récents",
                     hint: "Les derniers fichiers téléchargés apparaissent sur l’étagère."),
                C("shelfDownloadsLimit", .stepper(range: 1...50, defaultValue: 8, unit: ""), title: "Nombre de téléchargements affichés"),
            ]),
        "island": Page(
            extras: [
                flag("notchIdleShowLimits", true, title: "Limites Claude", hint: AmbientChannel.hint("limits")),
                flag("notchIdleShowClaude", true, title: "Claude au travail", hint: AmbientChannel.hint("claude")),
                flag("notchIdleShowMusic", true, title: "Lecture en cours", hint: AmbientChannel.hint("music")),
                flag("notchIdleShowBattery", true, title: "Batterie", hint: AmbientChannel.hint("battery")),
                flag("notchIdleShowKeepAwake", true, title: "Maintien d’éveil", hint: AmbientChannel.hint("keepawake")),
                flag("notchIdleKeepAwakeAlways", false, title: "Toujours afficher la tasse",
                     hint: "Montre la tasse atténuée même quand Garder éveillé est éteint."),
                flag("notchIdleShowClock", true, title: AmbientChannel.title("clock"), hint: AmbientChannel.hint("clock")),
                C("notchIdleClockHours", .choice(options: [.init("Système", 0), .init("24 h", 24), .init("12 h", 12)], defaultValue: 0),
                  title: "Format de l’heure", hint: "Suit le réglage du système, sauf si vous en choisissez un."),
                flag("notchIdleShowSystem", true, title: AmbientChannel.title("system"), hint: AmbientChannel.hint("system")),
                flag("notchIdleShowNetwork", true, title: AmbientChannel.title("network"), hint: AmbientChannel.hint("network")),
                flag("notchIdleShowDisk", false, title: AmbientChannel.title("disk"), hint: AmbientChannel.hint("disk")),
                flag("notchIdleShowMic", false, title: AmbientChannel.title("mic"), hint: AmbientChannel.hint("mic")),
                flag("notchIdleShowCamera", false, title: AmbientChannel.title("camera"), hint: AmbientChannel.hint("camera")),
                flag("notchIdleShowVolume", false, title: AmbientChannel.title("volume"), hint: AmbientChannel.hint("volume")),
                flag("notchIdleRotates", true, title: "Faire défiler les indicateurs"),
                flag("notchRememberLastTrack", true, title: "Mémoriser la dernière lecture",
                     hint: "Garde le dernier morceau pour le rouvrir depuis l’accueil. Reste sur ce Mac et n’est jamais envoyé. Désactivé, il est effacé."),
                C("notchIdlePerWing", .choice(options: [.init("1", 1), .init("2", 2)], defaultValue: 2),
                  title: "Indicateurs par côté"),
            ],
            featureIDs: ["agents", "nowplaying", "terminal"]),
    ]
}

private extension LiveControl {
    func withTitle(_ title: String) -> LiveControl { LiveControl(key, kind, title: title, hint: hint) }
}
