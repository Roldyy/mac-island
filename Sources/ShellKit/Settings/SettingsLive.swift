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

    static let table: [String: Page] = [
        // "monitor" has no live entry any more: the ported Monitor page (PortKit, W6 lane) draws the whole page, the
        // menu bar metrics, the panel blocks, the readings and the alerts, under the `monitor` feature card its
        // catalog row carries. (Our island card's own alert keys stay what they were; they keep their stored value.)
        // "commandbar" has no live entry any more: the ported command bar page (PortKit, W5-C lane) draws the whole
        // page, under the `commandbar` feature card its catalog row carries.
        // "keepawake" has no live entry any more: the ported Keep Awake page (PortKit, Energy lane) draws the whole
        // page, its default duration, automation, jiggle, display sleep, battery limit, island hold and closed lid.
        // "dockpreview" and "dockclicks" have no live entry any more: the ported Dock pages (PortKit, Dock lane) draw
        // both pages whole, under the `dock` feature card their catalog rows carry.
        // "quitonclose" has no live entry any more: the ported auto-quit page (PortKit, W3D lane) draws the whole
        // page, last-window quit, the inactivity delay and simulation, the never-quit list.
        // Every row of both pages is live: the Clipboard module (`Sources/Features/Clipboard`) reads these keys, the
        // app delegate registers the actions and counts (`SettingsActions`). Nothing on them reads "Bientôt" any more.
        "clipboard": Page(
            bound: [
                "Garder l’historique du presse-papiers": flag("clipboardHistoryEnabled", true),
                "Raccourci de l’historique": flag(
                    "clipboardHistoryShortcutEnabled", true,
                    hint: "Ouvre l’île sur le presse-papiers. Sans effet quand l’historique est éteint."),
                "Raccourci": C("clipboardHistoryShortcut", .shortcut(defaultValue: "control+option+command:9")),
                // The label of this row is empty in the noted page: the caption before it names it.
                "": C("clipboardHistoryLayout", .stringChoice(options: [
                    .init("Liste", "list"), .init("Cartes", "cards"),
                ], defaultValue: "list")),
                "Ouvrir l’historique": C("clipboard.openHistory", .action(title: "Ouvrir", confirm: nil)),
                "Afficher la dernière copie dans la barre des menus": flag(
                    "clipboardHistoryMenuBarPreview", false,
                    hint: "Un aperçu court de la dernière copie à côté de l’icône. Un clic dessus ouvre l’historique."),
                "Longueur de l’aperçu": C("clipboardHistoryMenuBarPreviewLength",
                                          .stepper(range: 5...50, defaultValue: 20, unit: "caractères")),
                // The migrated key our Clipboard module reads (`ClipboardSettings.includeImagesAndFilesKey`): off keeps text only.
                "Enregistrer aussi les images et fichiers copiés": flag("clipboardHistoryIncludeImagesFiles", true),
                "Ignorer le texte qui semble sensible": flag(
                    "clipboardHistoryFilterSensitiveText", false,
                    hint: "Peut écarter du texte ordinaire qui ressemble à un mot de passe ou à un jeton. "
                        + "Le contenu que l’app source marque confidentiel est toujours écarté."),
                "Limite": C("clipboardHistoryLimit", .choice(options: [
                    .init("10", 10), .init("25", 25), .init("50", 50), .init("100", 100), .init("200", 200), .init("500", 500),
                ], defaultValue: 50)),
                "Conserver les éléments": C("clipboardHistoryRetentionDays", .choice(options: [
                    .init("Toujours", 0), .init("1 jour", 1), .init("7 jours", 7), .init("30 jours", 30),
                    .init("90 jours", 90), .init("1 an", 365),
                ], defaultValue: 0), hint: "Les éléments plus anciens sont supprimés, même sous la limite. Les épinglés restent."),
                "Afficher dans le panneau": flag("panelUtilityClipboard", true),
                "Vider le presse-papiers automatiquement après": flag("clipboardAutoClearOnDelay", false),
                "Délai avant effacement": C("clipboardAutoClearDelaySeconds", .stepper(range: 5...3600, defaultValue: 20, unit: "s")),
                "Vider le presse-papiers à la mise en veille du Mac": flag("clipboardAutoClearOnSleep", false),
                "Vider le presse-papiers à l’extinction de l’écran": flag("clipboardAutoClearOnDisplaySleep", false),
                "Vider le presse-papiers au verrouillage de l’écran": flag(
                    "clipboardAutoClearOnScreenLock", false,
                    hint: "Seul le presse-papiers du système est vidé. L’historique enregistré reste."),
                "Coller les images copiées comme fichiers": flag("finderPasteImageAsFile", true),
            ]),
        "pasteplain": Page(bound: [
            "Coller en texte brut": flag("pastePlainEnabled", true),
            "Raccourci": C("pastePlainShortcut", .shortcut(defaultValue: "option+command:9")),
            "Épinglés": C("clipboard.pinnedCount", .readout),
            "Récents": C("clipboard.recentCount", .readout),
            "Effacer non épinglés": C("clipboard.clearUnpinned", .action(title: "Effacer", confirm: "Confirmer l’effacement")),
        ]),
        // "cutpaste" and "renameshortcut" have no live entry any more: the ported Finder page (PortKit, W7-A lane) draws
        // both pages whole, under the `finder` feature card their catalog rows carry.
        // "shelf" has no live entry any more: the ported shelf page (PortKit, Shelf lane) draws the whole page. The two
        // Downloads switches (shelfDownloads*) are back, drawn by the ported body itself (PortKit `IslandShelfDownloadsSettings`,
        // lane W8C): a live entry here would bring the greyed noted rows of the old page back with them.
        "island": Page(
            extras: [
                flag("notchIdleShowLimits", true, title: "Limites Claude", hint: AmbientChannel.hint("limits")),
                flag("notchIdleShowClaude", true, title: "Claude au travail", hint: AmbientChannel.hint("claude")),
                flag("notchIdleShowMusic", false, title: "Lecture en cours", hint: AmbientChannel.hint("music")),
                flag("notchIdleShowBattery", true, title: "Batterie", hint: AmbientChannel.hint("battery")),
                flag("notchIdleShowKeepAwake", true, title: "Maintien d’éveil", hint: AmbientChannel.hint("keepawake")),
                flag("notchIdleKeepAwakeAlways", false, title: "Toujours afficher la tasse",
                     hint: "Montre la tasse atténuée même quand Garder éveillé est éteint."),
                flag("notchIdleShowClock", true, title: AmbientChannel.title("clock"), hint: AmbientChannel.hint("clock")),
                C("notchIdleClockHours", .choice(options: [.init("Système", 0), .init("24 h", 24), .init("12 h", 12)], defaultValue: 0),
                  title: "Format de l’heure", hint: "Suit le réglage du système, sauf si vous en choisissez un."),
                flag("notchIdleShowSystem", false, title: AmbientChannel.title("system"), hint: AmbientChannel.hint("system")),
                flag("notchIdleShowNetwork", false, title: AmbientChannel.title("network"), hint: AmbientChannel.hint("network")),
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
