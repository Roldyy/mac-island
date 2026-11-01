// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W5C (command bar). The lane owns this file.

import AppKit
import IslandKit
import SwiftUI

// MARK: - Lane

/// Binds the ported command bar. It REPLACES our old `Sources/Features/CommandBar` module: the registry keeps OUR
/// descriptor (title "Commandes", switch, island tab `commandbar`, Home tile, migrated `shell.enabled.commandbar`),
/// so nothing is added to the feature list.
///
/// What the registry does, all through `Runtime` so tests never register a hotkey or build a panel:
/// - start (`commandbar` switched on, not killed, not in safe mode) = move the old module's settings across once
///   (its shortcut and its switch, never the old defaults of other keys), then `CommandBarService.syncWithPreferences()`:
///   registers the global shortcut (the one the person had), prepares one hidden panel, nothing else. No permission
///   gates the start: the menus and the selection need Accessibility and each source re-checks it, without ever asking.
/// - stop (switch off, kill switch, safe mode, quarantine) = the shortcut and every row shortcut go, the panel closes
///   and every cache is dropped (`syncWithPreferences` sees the feature unavailable, then `suspend`).
///
/// One owner per shortcut: the old Carbon registrar of our module ('MICB') is gone for good, the ported service owns
/// `commandBarShortcut` (see `PortShortcutOwnership.commandBarShortcut`). The panel never activates the app, closes on
/// Escape, on a click outside and when another app comes forward, takes no query into any log, and runs no result by
/// itself: a row runs on Return or on a shortcut the person gave to that very row.
enum CommandBarLane {
    struct Runtime {
        /// The old module's shortcut, switch and sources, once, into the ported keys.
        var migrateLegacySettings: @MainActor () -> Void
        var sync: @MainActor () -> Void
        /// Shortcut off, panel closed, caches dropped. Safe on a bar that never started.
        var suspend: @MainActor () -> Void

        /// The service is only built once a start reached it: a Mac where the feature stays off builds nothing.
        @MainActor private static var touched = false

        static let live = Runtime(
            migrateLegacySettings: { PortCommandBarLegacy.migrate(in: PortHost.defaults) },
            sync: { touched = true; CommandBarService.shared.syncWithPreferences() },
            suspend: {
                guard touched else { return }
                // The registry already denied the feature, so this pass unregisters, hides and clears.
                CommandBarService.shared.syncWithPreferences()
                CommandBarService.shared.suspend()
            })
    }

    static let upstreamID = "commandBar"
    static let pageID = "commandbar"

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installPage()
    }

    @MainActor @discardableResult
    static func bind(into binding: PortFeatureBinding, runtime: Runtime) -> Bool {
        binding.bindReplacing(
            upstreamID,
            start: {
                runtime.migrateLegacySettings()
                runtime.sync()
            },
            stop: { runtime.suspend() })
    }

    private static var didInstallPage = false

    /// The page row of the catalog already carries the `commandbar` feature card, so the body is a plain page body.
    @MainActor private static func installPage() {
        guard !didInstallPage else { return }
        didInstallPage = true
        PortBridge.register(pageID: pageID) { AnyView(CommandBarPage().defaultAppStorage(PortHost.defaults)) }
    }
}

// MARK: - Public surface

/// The command bar as the host sees it: the Home tile and the round button open it, the island hosts its page in a
/// tab, and the shell hands it commands (open an island tab).
public enum PortCommandBar {
    /// A command the host adds to the bar's own actions.
    public struct HostCommand {
        public let id: String
        public let title: String
        public let keywords: [String]
        public let run: @MainActor () -> Void

        public init(id: String, title: String, keywords: [String] = [], run: @escaping @MainActor () -> Void) {
            self.id = id
            self.title = title
            self.keywords = keywords
            self.run = run
        }
    }

    /// True once the registry started the command bar and until it stopped it.
    @MainActor public static var isRunning: Bool { PortShortcutOwnership.isRunning(.commandBar) }

    /// Opens the bar now, from a button. False when the registry holds the feature down (switch off, kill switch, safe
    /// mode, quarantine): nothing opens and the caller says so. Never prompts for a permission.
    @MainActor @discardableResult
    public static func show() -> Bool {
        guard isRunning else { return false }
        CommandBarService.shared.show()
        return true
    }

    /// Adds commands to the bar. A command with an id already registered replaces the earlier one.
    @MainActor public static func registerHostCommands(_ commands: [HostCommand]) {
        PortCommandBarHost.register(commands)
    }

    /// The island's "Commandes" tab (id `commandbar`, kept): the ported page, hosted with the island presentation.
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "commandbar", title: "Commandes", systemImage: "command") {
            AnyView(CommandBarIslandTab())
        }
    }
}

private struct CommandBarIslandTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CommandBarPage()
            }
            .padding(10)
        }
        .environment(\.notchPresentation, true)
        .environment(\.colorScheme, .dark)
        .defaultAppStorage(PortHost.defaults)
    }
}

// MARK: - Shortcut ownership

extension PortShortcutOwnership {
    /// The command bar's global shortcut as the ported service reads it: the person's own choice, off until switched
    /// on (the migration carries the old module's state). The ONLY registrar is `CommandBarService`
    /// (`QuickToolHotkey` id 20); our retired Carbon one is gone.
    static func commandBarShortcut(in defaults: UserDefaults) -> (enabled: Bool, shortcut: GlobalShortcut) {
        let enabled = defaults.bool(forKey: DefaultsKey.commandBarShortcutEnabled)
        let stored = defaults.string(forKey: DefaultsKey.commandBarShortcut).flatMap { GlobalShortcut(storageValue: $0) }
        return (enabled, stored ?? .commandBarDefault)
    }
}

// MARK: - Scripts

/// What a saved script is allowed to be. The command bar runs ONLY the person's own executable files, chosen by them
/// in the page, on an explicit selection: nothing here ever builds a command from clipboard text, from the
/// selection or from the typed words. The typed words are one argument of the file, never part of its path and never
/// text given to a shell (no shell and no interpreter is involved: `BoundedProcessRunner` runs the file directly).
enum PortCommandBarScripts {
    /// Longest argument handed to a script, in characters.
    static let maxArgumentLength = 2000

    /// The path to run, or nil when the destination is not a safe executable file: it must be absolute (after `~`), carry
    /// no placeholder (`{query}`, `{clipboard}`, `{selection}`, `{date}`: text must never build a path), contain no line
    /// break or NUL, and name an existing, executable regular file.
    static func executablePath(for destination: String, fileManager: FileManager = .default) -> String? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"), !trimmed.contains("\n"), !trimmed.contains("\r"),
              !CommandBarLinkPlaceholder.allCases.contains(where: { trimmed.contains($0.token) })
        else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: expanded)
        else { return nil }
        return expanded
    }

    /// The argument array of a run: exactly one entry, the typed words, without NUL and capped. Never split on blanks.
    static func arguments(forTyped typed: String) -> [String] {
        [String(typed.replacingOccurrences(of: "\0", with: "").prefix(maxArgumentLength))]
    }
}

// MARK: - Web search

/// The last row of a typed search: the words go to a web search in the default browser, on Return only. The app makes
/// no network call itself. Only the engines listed here exist (https, the query after the `?`), so neither the stored
/// choice nor the typed words can change the scheme or the host.
enum PortCommandBarWebSearch {
    struct Engine: Equatable, Identifiable {
        let id: String
        let name: String
        /// `{query}` is replaced by the percent-encoded words.
        let template: String
    }

    static let engines: [Engine] = [
        Engine(id: "duckduckgo", name: "DuckDuckGo", template: "https://duckduckgo.com/?q={query}"),
        Engine(id: "google", name: "Google", template: "https://www.google.com/search?q={query}"),
        Engine(id: "bing", name: "Bing", template: "https://www.bing.com/search?q={query}"),
        Engine(id: "ecosia", name: "Ecosia", template: "https://www.ecosia.org/search?q={query}"),
        Engine(id: "qwant", name: "Qwant", template: "https://www.qwant.com/?q={query}"),
    ]

    static let defaultEngineID = "duckduckgo"
    /// The switch of our retired module (`commandBarSourceWeb`), kept: on unless the person turned it off.
    static let enabledKey = "commandBarSourceWeb"
    static let engineKey = "commandBarWebSearchEngine"
    static let maxQueryLength = 200
    static let placeholder = "{query}"

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func engine(id: String?) -> Engine {
        engines.first { $0.id == id } ?? engines[0]
    }

    /// A template is usable when it is https, names its host, and holds the placeholder once, after the `?`.
    static func isValid(template: String) -> Bool {
        guard template.hasPrefix("https://"),
              template.components(separatedBy: placeholder).count == 2,
              let query = template.firstIndex(of: "?"),
              let mark = template.range(of: placeholder), query < mark.lowerBound
        else { return false }
        let fixed = template.replacingOccurrences(of: placeholder, with: "x")
        guard let url = URL(string: fixed), url.scheme == "https", let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// The address to open, or nil for an empty query or a template that is not valid. The words are trimmed, capped and
    /// percent-encoded down to the unreserved characters, so a `&`, a `#`, a space or a line break stays inside the value.
    static func url(forQuery query: String, template: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValid(template: template),
              let encoded = String(trimmed.prefix(maxQueryLength)).addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        return URL(string: template.replacingOccurrences(of: placeholder, with: encoded))
    }

    static func isEnabled(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    static func selectedEngine(in defaults: UserDefaults = PortHost.defaults) -> Engine {
        engine(id: defaults.string(forKey: engineKey))
    }

    static func rowTitle(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        return "Rechercher « \(shown) » sur le web"
    }

    /// The row, or nil when the source is off or there is nothing to search. Opening is the row's `run`: the bar only
    /// builds the address, `NSWorkspace` opens it, on Return.
    static func entry(for query: String, defaults: UserDefaults = PortHost.defaults) -> CommandBarEntry? {
        guard isEnabled(in: defaults) else { return nil }
        let engine = selectedEngine(in: defaults)
        guard let url = url(forQuery: query, template: engine.template) else { return nil }
        return CommandBarEntry(
            id: "websearch.query",
            title: rowTitle(for: query),
            subtitle: "\(engine.name) : ouvre le navigateur par défaut",
            icon: .symbol("magnifyingglass"),
            countsUsage: false,
            run: { _ in NSWorkspace.shared.open(url) })
    }
}

// MARK: - Learning switch

/// Our retired module's "Retenir ce que j’utilise le plus" (`commandBarHabitsEnabled`) still rules what the bar stores.
enum PortCommandBarLearning {
    static let key = "commandBarHabitsEnabled"

    static func isEnabled(in defaults: UserDefaults = PortHost.defaults) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? true
    }
}

// MARK: - Host commands

/// Commands the shell registers (our "Ouvrir <onglet>" commands). They are actions of the bar like any other.
enum PortCommandBarHost {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var commands: [PortCommandBar.HostCommand] = []

    static func register(_ new: [PortCommandBar.HostCommand]) {
        lock.lock()
        defer { lock.unlock() }
        for command in new {
            if let index = commands.firstIndex(where: { $0.id == command.id }) { commands[index] = command } else { commands.append(command) }
        }
    }

    static var registered: [PortCommandBar.HostCommand] {
        lock.lock()
        defer { lock.unlock() }
        return commands
    }

    static func removeAll() {
        lock.lock()
        commands = []
        lock.unlock()
    }

    static func entries() -> [CommandBarEntry] {
        registered.map { command in
            CommandBarEntry(
                id: "host.\(command.id)",
                title: command.title,
                subtitle: "Mac Island",
                keywords: command.keywords.joined(separator: " "),
                icon: .symbol("command"),
                run: { _ in
                    let run = command.run
                    Task { @MainActor in run() }
                })
        }
    }
}

// MARK: - Sources: what each one needs

/// What every kind of row needs to exist, in one table. A source whose need is missing is hidden by the ported code
/// itself (its own guard) and the page says why in French, so a missing row is never a mystery.
enum PortCommandBarSources {
    /// The state of a feature another lane owns, as the registry sees it.
    enum FeatureState: Equatable { case unbound, off, running }

    enum Need: Equatable {
        case accessibility
        /// Needs this ported feature running; `label` is how the page names it.
        case feature(AppFeature, label: String)
        /// Needs one of these two features running.
        case anyFeature(AppFeature, AppFeature, label: String)
        /// Needs the person to name folders first (the Spotlight index is read without any permission).
        case folders
    }

    struct Environment {
        var accessibility: Bool
        var featureState: (AppFeature) -> FeatureState
        var hasFileFolders: Bool

        /// What the app reads right now.
        @MainActor static func live(defaults: UserDefaults = PortHost.defaults) -> Environment {
            Environment(
                accessibility: Permissions.shared.accessibility,
                featureState: { feature in
                    switch PortHost.availability?(feature.registryID) {
                    case .none: .unbound
                    case .some(false): .off
                    case .some(true): .running
                    }
                },
                hasFileFolders: !(defaults.string(forKey: DefaultsKey.commandBarFileScopes) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// The needs of each source. Sources with no entry need nothing at all (apps, the Mac's Settings panes, saved
    /// links, emoji, answers, the calculator and the app's own actions).
    static func needs(of source: CommandBarSource) -> [Need] {
        switch source {
        case .menus: [.accessibility]
        case .selection: [.accessibility]
        case .windows: [.accessibility, .anyFeature(.switcher, .windowLayout, label: "le sélecteur de fenêtres ou la disposition des fenêtres")]
        case .clipboard: [.feature(.clipboardHistory, label: "l’historique du presse-papiers")]
        case .snippets: [.feature(.textSnippets, label: "les extraits de texte")]
        case .killProcess: [.feature(.killProcess, label: "Forcer à quitter")]
        case .uninstallApps: [.feature(.uninstaller, label: "le programme de désinstallation")]
        case .files: [.folders]
        case .actions, .apps, .quitApps, .settingsPages, .macSettings, .emoji, .folders, .answers, .calculator, .links: []
        }
    }

    /// Why a source cannot answer right now, in French. Nil when it can.
    static func unavailableReason(of source: CommandBarSource, in environment: Environment) -> String? {
        for need in needs(of: source) {
            switch need {
            case .accessibility:
                if !environment.accessibility {
                    return "Autorisez l’Accessibilité (Réglages Système) pour lire les menus, les fenêtres et le texte sélectionné de l’app au premier plan."
                }
            case .feature(let feature, let label):
                if let reason = featureReason(environment.featureState(feature), label: label) { return reason }
            case .anyFeature(let first, let second, let label):
                let states = [environment.featureState(first), environment.featureState(second)]
                if !states.contains(.running) {
                    return featureReason(states.contains(.off) ? .off : .unbound, label: label)
                }
            case .folders:
                if !environment.hasFileFolders {
                    return "Choisissez les dossiers où chercher dans la page de la barre de commande : sans dossier, aucun fichier n’est cherché."
                }
            }
        }
        return nil
    }

    private static func featureReason(_ state: FeatureState, label: String) -> String? {
        switch state {
        case .running: nil
        case .off: "Activez \(label) dans Fonctions : cette source reste cachée tant qu’elle est éteinte."
        case .unbound: "\(label.prefix(1).uppercased() + label.dropFirst()) n’est pas encore repris dans cette version : cette source reste cachée."
        }
    }

    /// Every source that cannot answer now, with its reason, in the order of `CommandBarSource.allCases`.
    static func notices(in environment: Environment) -> [(source: CommandBarSource, reason: String)] {
        CommandBarSource.allCases.compactMap { source in
            unavailableReason(of: source, in: environment).map { (source, $0) }
        }
    }

    /// A short name for the page.
    static func title(of source: CommandBarSource) -> String {
        switch source {
        case .actions: "Actions"
        case .apps: "Apps"
        case .menus: "Menus de l’app au premier plan"
        case .windows: "Fenêtres ouvertes"
        case .quitApps: "Quitter une app"
        case .uninstallApps: "Désinstaller une app"
        case .settingsPages: "Pages des Réglages"
        case .macSettings: "Volets des Réglages Système"
        case .snippets: "Extraits"
        case .clipboard: "Presse-papiers"
        case .emoji: "Émoji"
        case .folders: "Dossiers"
        case .answers: "Réponses sur ce Mac"
        case .calculator: "Calculs et conversions"
        case .selection: "Texte sélectionné"
        case .links: "Liens, dossiers et scripts enregistrés"
        case .files: "Fichiers"
        case .killProcess: "Forcer à quitter un processus"
        }
    }
}

// MARK: - The old module's settings

/// Moves what our retired command bar stored into the ported keys, once (marker `macisland.commandBar.legacyMoved`):
///
/// - `commandBarHotkey` ("option:space", our format) -> `commandBarShortcut`, and `commandBarEnabled` (on unless the
///   person turned it off) -> `commandBarShortcutEnabled`: the shortcut the person has keeps working, on the same key.
///   The ported default is OFF, the old one was ON, so the old state always wins here.
/// - `commandBarSourceApps / Files / Calculator` switched off -> `commandBarDisabledSources`. `commandBarSourceCommands`
///   has no counterpart (the app's own actions cannot be switched off any more).
/// - `commandBarSourceWeb` and `commandBarHabitsEnabled` keep their names and meaning (the web row and the learning switch).
/// - The old usage file `CommandBarHabits.json` (counts per row id, ids that no longer exist) is deleted.
///
/// The old keys that were carried are removed. `commandBarQueryHabitKey` is never touched: it is the ported digest key.
enum PortCommandBarLegacy {
    static let doneKey = "macisland.commandBar.legacyMoved"
    static let oldEnabledKey = "commandBarEnabled"
    static let oldHotkeyKey = "commandBarHotkey"
    static let oldSourceKeys: [(key: String, source: CommandBarSource?)] = [
        ("commandBarSourceApps", .apps), ("commandBarSourceFiles", .files),
        ("commandBarSourceCalculator", .calculator), ("commandBarSourceCommands", nil),
    ]
    static let habitsFileName = "CommandBarHabits.json"

    struct Report: Equatable {
        var enabled = false
        var shortcut: String?
        var disabledSources: [String] = []
        var removedKeys: [String] = []
        var removedHabitsFile = false
    }

    /// The key names our old hotkey field wrote, by virtual key code (ANSI layout, plus a few named keys). A digit here
    /// is a key NAME ("option+command:9" is the 9 key, code 25): the ported parser reads a number after the colon as
    /// a key CODE (9 is "v"), so our format is read with this table and never with `GlobalShortcut(storageValue:)`.
    static let legacyKeyCodes: [String: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    ]

    /// Our old stored shortcut ("option:space", "control+option+command:k", "option+command:9") as the ported type, or nil
    /// when it is not a shortcut: an unknown key, an unknown modifier, or no command, option or control (shift alone
    /// only types a capital).
    static func shortcut(fromLegacy raw: String) -> GlobalShortcut? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let code = legacyKeyCodes[parts[1].trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }
        var modifiers: GlobalShortcutModifiers = []
        for token in parts[0].split(separator: "+", omittingEmptySubsequences: false) {
            switch token.trimmingCharacters(in: .whitespaces).lowercased() {
            case "command", "cmd": modifiers.insert(.command)
            case "option", "alt", "opt": modifiers.insert(.option)
            case "control", "ctrl": modifiers.insert(.control)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        return GlobalShortcut(keyCode: code, modifiers: modifiers)
    }

    /// `~/Library/Application Support/be.roldy.macisland/Data`, where the old module kept its file.
    static func defaultDataDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    /// Nil when it already ran.
    @discardableResult
    static func migrate(in defaults: UserDefaults, dataDirectory: URL = defaultDataDirectory(),
                        fileManager: FileManager = .default) -> Report? {
        guard !defaults.bool(forKey: doneKey) else { return nil }
        var report = Report()

        report.enabled = (defaults.object(forKey: oldEnabledKey) as? Bool) ?? true
        defaults.set(report.enabled, forKey: DefaultsKey.commandBarShortcutEnabled)

        if let raw = defaults.string(forKey: oldHotkeyKey), let parsed = shortcut(fromLegacy: raw) {
            defaults.set(parsed.storageValue, forKey: DefaultsKey.commandBarShortcut)
            report.shortcut = parsed.storageValue
        }

        var disabled = CommandBarPreferences.disabledSources(
            from: defaults.string(forKey: DefaultsKey.commandBarDisabledSources) ?? "")
        for (key, source) in oldSourceKeys {
            guard let old = defaults.object(forKey: key) as? Bool else { continue }
            if !old, let source { disabled.insert(source); report.disabledSources.append(source.rawValue) }
        }
        if !report.disabledSources.isEmpty {
            defaults.set(CommandBarPreferences.storageValue(for: disabled), forKey: DefaultsKey.commandBarDisabledSources)
        }

        for key in [oldEnabledKey, oldHotkeyKey] + oldSourceKeys.map(\.key) where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            report.removedKeys.append(key)
        }

        let habits = dataDirectory.appendingPathComponent(habitsFileName)
        if fileManager.fileExists(atPath: habits.path) {
            report.removedHabitsFile = (try? fileManager.removeItem(at: habits)) != nil
        }

        defaults.set(true, forKey: doneKey)
        return report
    }
}

// MARK: - Settings page

/// The page of the command bar: Mac Island's own card first (web search, learning, what each source needs), then the
/// ported settings (shortcut, compact mode, emoji, folders, saved links and scripts, row shortcuts).
struct CommandBarPage: View {
    @AppStorage(PortCommandBarWebSearch.enabledKey) private var webSearch = true
    @AppStorage(PortCommandBarWebSearch.engineKey) private var engineID = PortCommandBarWebSearch.defaultEngineID
    @AppStorage(PortCommandBarLearning.key) private var learns = true
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    Toggle("Recherche sur le web", isOn: $webSearch)
                    if webSearch {
                        Picker("Moteur", selection: $engineID) {
                            ForEach(PortCommandBarWebSearch.engines) { engine in
                                Text(engine.name).tag(engine.id)
                            }
                        }
                    }
                    Text("Une dernière ligne ouvre ce que vous avez tapé dans votre navigateur, seulement quand vous appuyez sur Retour. Mac Island ne fait aucune requête réseau lui-même.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Retenir ce que j’utilise le plus", isOn: $learns)
                    Text("Remonte vos choix habituels dans les résultats. Éteint, rien de ce que vous choisissez n’est enregistré.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Dans Mac Island")
                }
                sourceNotices
            }
            .formStyle(.grouped)
            CommandBarSettings()
        }
    }

    @ViewBuilder
    private var sourceNotices: some View {
        let notices = PortCommandBarSources.notices(in: .live())
        if !notices.isEmpty {
            Section {
                ForEach(notices, id: \.source) { notice in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PortCommandBarSources.title(of: notice.source))
                        Text(notice.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Sources indisponibles pour l’instant")
            }
        }
    }
}
