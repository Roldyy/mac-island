// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W5D (quick launcher, quick toggles, radial menu). The lane owns this file.

import AppKit
import SwiftUI

// MARK: - Lane

/// Binds the three ported features of lane W5-D through `PortFeatureBinding`, each OFF until the registry says on
/// (a migrated or user-chosen `shell.enabled.<id>`), and none of them ever prompts:
///
/// - `quickLauncher` (Settings page `quickpanel`): the floating panel of tool tiles and its global shortcut. No
///   permission. Start = `QuickLauncherService.syncWithPreferences()` (one Carbon hotkey, nothing else at rest),
///   stop = `suspend()` (hotkey released, panel hidden).
/// - `quickToggles` (page `quickactions`): one-click system actions, all on demand: nothing runs, observes or polls
///   at rest, so start only recovers a Finder preference a crashed temporary mode left behind. Every private call sits
///   behind `QuickToggleProbe`; the lock action goes through the app's own locker (`PortQuickToggles`).
/// - `radialMenu` (page `radial`): the wheel. Accessibility gates the start (its mouse-button trigger is an event
///   tap), so a Mac without the grant starts nothing and the registry restarts the feature on the grant. Start =
///   `RadialMenuService.syncWithPreferences()` (Carbon hotkeys, the button tap, a hidden pre-warmed panel), stop =
///   `suspend()` (hotkeys and tap removed, the open wheel closed, the panel dropped) then the trackpad tap, which
///   belongs to the middle-click service, is re-read.
///
/// Services are only built once a start reached them: a Mac where a feature stays off builds nothing.
enum LauncherLane {
    static let pageIDs: [String: String] = ["quickLauncher": "quickpanel", "quickToggles": "quickactions", "radialMenu": "radial"]

    /// What the lane does to the ported services. Tests pass fakes: the live one arms hotkeys and an event tap.
    struct Runtime {
        var startLauncher: @MainActor () -> Void
        var stopLauncher: @MainActor () -> Void
        var startToggles: @MainActor () -> Void
        var stopToggles: @MainActor () -> Void
        var startRadial: @MainActor () -> Void
        var stopRadial: @MainActor () -> Void
        /// The app is quitting; `togglesStarted` is whether the registry had started the quick toggles.
        var quit: @MainActor (_ togglesStarted: Bool) -> Void

        static let live = Runtime(
            startLauncher: { LauncherLive.launcherTouched = true; QuickLauncherService.shared.syncWithPreferences() },
            stopLauncher: { if LauncherLive.launcherTouched { QuickLauncherService.shared.suspend() } },
            startToggles: { LauncherLive.restoreOwedFinderFlags() },
            stopToggles: { LauncherLive.restoreOwedFinderFlags() },
            startRadial: { LauncherLive.radialTouched = true; RadialMenuService.shared.syncWithPreferences() },
            stopRadial: {
                guard LauncherLive.radialTouched else { return }
                RadialMenuService.shared.suspend()
                // The four-finger tap that opens a wheel is read by the middle-click service: let it drop the finger count.
                MiddleClickService.shared.syncWithPreferences()
            },
            quit: { togglesStarted in
                if togglesStarted { LauncherLive.restoreOwedFinderFlagsAtQuit() }
            })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        guard !didInstallLaunchSafety else { return }
        didInstallLaunchSafety = true
        observeTermination(of: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(.quickLauncher,
                     page: PortFeaturePage(pageID: "quickpanel") { AnyView(QuickPanelPage()) },
                     start: runtime.startLauncher, stop: runtime.stopLauncher)
        binding.bind(.quickToggles,
                     page: PortFeaturePage(pageID: "quickactions") { AnyView(QuickActionsPage()) },
                     start: runtime.startToggles, stop: runtime.stopToggles)
        binding.bind(.radialMenu,
                     page: PortFeaturePage(pageID: "radial") { AnyView(RadialMenuPage()) },
                     start: runtime.startRadial, stop: runtime.stopRadial)
    }

    private nonisolated(unsafe) static var didInstallLaunchSafety = false

    /// Leaving the app hands a temporary Finder setting back. No queue: the notification is posted on the main
    /// thread and the preference write must finish before the process goes.
    @MainActor @discardableResult
    static func observeTermination(of binding: PortFeatureBinding, runtime: Runtime,
                                   center: NotificationCenter = .default) -> NSObjectProtocol {
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                runtime.quit(binding.isStarted(PortFeatureIDs.registryID(forUpstream: "quickToggles")))
            }
        }
    }
}

/// The live side of the runtime: the services that were touched, and the Finder restore.
enum LauncherLive {
    @MainActor static var launcherTouched = false
    @MainActor static var radialTouched = false

    private static let restoreQueue = DispatchQueue(label: "be.roldy.macisland.launcher.finder-restore", qos: .utility)

    /// A temporary Finder setting the user chose (and a crash or a stop left applied) goes back. Off the main thread:
    /// the polite Finder restart polls for the quit.
    @MainActor static func restoreOwedFinderFlags() {
        let defaults = PortHost.defaults
        guard FinderFlags.owesRestore(defaults: defaults) else { return }
        let prefs = QuickToggleSeams.finderPrefs
        let box = LauncherLockedBox(defaults)  // UserDefaults is thread-safe; the box tells the compiler
        restoreQueue.async {
            _ = FinderFlags.restoreTemporary(prefs: prefs, defaults: box.value,
                                             restart: { QuickTogglesService.shared.restartFinder() })
        }
    }

    /// The same at quit, in place: the preference is written before the process ends and the Finder is restarted
    /// with the one-shot `killall` (no waiting on a polite quit).
    @MainActor static func restoreOwedFinderFlagsAtQuit() {
        let defaults = PortHost.defaults
        guard FinderFlags.owesRestore(defaults: defaults) else { return }
        _ = FinderFlags.restoreTemporary(prefs: QuickToggleSeams.finderPrefs, defaults: defaults,
                                         restart: { Shell.run("/usr/bin/killall", ["Finder"]).status == 0 })
    }
}

// MARK: - Seams the app and the tests plug into

/// The one lock path of the app. The quick toggle "Verrouiller l'écran" asks the host's locker instead of loading the
/// login framework a second time: `Sources/MacIsland/PrivateLockScreen.swift` stays the only file with that symbol.
public enum PortQuickToggles {
    /// The app delegate's locker (`SACLockScreenImmediate`, then `pmset displaysleepnow`): true when a request was made.
    /// Never prompts. Unset (tests, a build without it): the toggle falls back to the screen saver.
    public static func installLockScreen(_ lock: (@MainActor () -> Bool)?) { QuickToggleSeams.installLock(lock) }
}

private final class LauncherLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

enum QuickToggleSeams {
    /// com.apple.finder, read and written through this struct only. Tests swap it for a dictionary.
    nonisolated(unsafe) static var finderPrefs: FinderPreferenceStore = .live

    private static let lockBox = LauncherLockedBox<(@MainActor () -> Bool)?>(nil)

    static var hasLock: Bool { lockBox.value != nil }

    static func installLock(_ lock: (@MainActor () -> Bool)?) { lockBox.value = lock }

    /// nil when the app installed no locker; otherwise whether the request was made. From the main thread it runs at
    /// once; from any other it is handed to the main thread and counts as made.
    static func performLock() -> Bool? {
        guard let lock = lockBox.value else { return nil }
        if Thread.isMainThread { return MainActor.assumeIsolated { lock() } }
        Task { @MainActor in _ = lock() }
        return true
    }
}

// MARK: - Private-API probe

enum QuickToggleCapability: CaseIterable, Equatable {
    /// The window server's light/dark switch (SkyLight). Without it the dark-mode toggle stays inert.
    case appearance
    /// The app's own screen locker, installed by the app delegate. Without it the screen saver stands in.
    case lockScreen

    /// Only the appearance switch blocks its toggle; the lock has a public fallback.
    var blocksAction: Bool { self == .appearance }

    var symbols: [String] {
        switch self {
        case .appearance: ["SLSGetAppearanceThemeLegacy", "SLSSetAppearanceThemeLegacy"]
        case .lockScreen: []
        }
    }

    var reason: String {
        switch self {
        case .appearance:
            "Ce macOS n’expose plus le réglage système du mode clair ou sombre : le bouton reste sans effet. Utilisez Réglages Système > Apparence."
        case .lockScreen:
            "Le verrouillage immédiat n’est pas branché : l’économiseur d’écran est lancé à la place (il verrouille si un mot de passe est exigé)."
        }
    }
}

/// What the quick toggles need from private frameworks, probed by symbol name and never called: each capability that
/// is missing is named with a French reason, and only the appearance one blocks its action (fails closed).
struct QuickToggleProbeReport: Equatable {
    struct Finding: Equatable {
        let capability: QuickToggleCapability
        let reason: String
    }

    let findings: [Finding]

    func allows(_ capability: QuickToggleCapability) -> Bool {
        !findings.contains { $0.capability == capability }
    }

    var blockingReasons: [String] { findings.filter { $0.capability.blocksAction }.map(\.reason) }
}

enum QuickToggleProbe {
    /// The report for a symbol table and for whether the app installed its locker. A capability is missing when ANY
    /// of its symbols is.
    static func evaluate(isPresent: (String) -> Bool, lockInstalled: Bool) -> QuickToggleProbeReport {
        QuickToggleProbeReport(findings: QuickToggleCapability.allCases.compactMap { capability in
            let present = capability == .lockScreen ? lockInstalled : capability.symbols.allSatisfy(isPresent)
            return present ? nil : QuickToggleProbeReport.Finding(capability: capability, reason: capability.reason)
        })
    }

    /// The symbol lookups, made once (a lookup, never a call). They live in `QuickTogglesService`, a file the
    /// private-API allowlist already lists.
    private static let symbolTable: [String: Bool] = Dictionary(
        uniqueKeysWithValues: QuickToggleCapability.appearance.symbols.map {
            ($0, QuickTogglesService.isPrivateSymbolAvailable($0))
        })

    static var live: QuickToggleProbeReport {
        evaluate(isPresent: { symbolTable[$0] ?? false }, lockInstalled: QuickToggleSeams.hasLock)
    }
}

// MARK: - Finder flags (hidden files, desktop icons)

/// com.apple.finder as the quick toggles use it: read a key, write a Bool (nil removes the key), flush.
struct FinderPreferenceStore {
    var read: (String) -> Any?
    var write: (String, Bool?) -> Void
    var synchronize: () -> Void

    static let live = FinderPreferenceStore(
        read: { CFPreferencesCopyAppValue($0 as CFString, QuickTogglesSupport.finderDomain as CFString) },
        write: { key, value in
            CFPreferencesSetAppValue(key as CFString, value.map { $0 as CFBoolean },
                                     QuickTogglesSupport.finderDomain as CFString)
        },
        synchronize: { _ = CFPreferencesAppSynchronize(QuickTogglesSupport.finderDomain as CFString) })
}

/// The Finder preferences behind "Afficher les fichiers cachés" and "Icônes du bureau".
///
/// The Finder restarts ONLY from an explicit toggle (`apply`) or, when the user chose the temporary mode, to give the
/// original value back (`restoreTemporary`). In the temporary mode the original of a key is written to a journal in
/// the host's defaults BEFORE the preference is touched, so a crash leaves a note the next start pays. Without the
/// temporary mode (the default) nothing is journaled and nothing is restored: the user's choice stays.
enum FinderFlags {
    static let journalKey = "quickToggles.finderJournal.macisland"
    static let temporaryKey = "quickToggles.temporaryFinderFlags.macisland"

    enum RestoreOutcome: Equatable { case nothingOwed, restored, restartFailed }

    static func isTemporary(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: temporaryKey) }

    static func journal(_ defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: journalKey) as? [String: String] ?? [:]
    }

    static func clearJournal(_ defaults: UserDefaults) { defaults.removeObject(forKey: journalKey) }

    /// True when the temporary mode is on and a journal entry is waiting.
    static func owesRestore(defaults: UserDefaults) -> Bool {
        isTemporary(defaults) && !journal(defaults).isEmpty
    }

    private static func writeJournal(_ journal: [String: String], _ defaults: UserDefaults) {
        if journal.isEmpty { clearJournal(defaults) } else { defaults.set(journal, forKey: journalKey) }
    }

    private static func original(of value: Any?) -> String {
        guard value != nil else { return "absent" }
        return QuickTogglesSupport.finderFlag(value, default: false) ? "1" : "0"
    }

    private static func state(of value: Any?) -> Bool? {
        value == nil ? nil : QuickTogglesSupport.finderFlag(value, default: false)
    }

    /// The user's explicit toggle: journal the original (temporary mode only), write the key, restart the Finder.
    /// False when the restart failed (the preference is written; the next Finder launch applies it).
    static func apply(key: String, to value: Bool, prefs: FinderPreferenceStore, defaults: UserDefaults,
                      restart: () -> Bool) -> Bool {
        var entries = journal(defaults)
        if isTemporary(defaults) {
            if entries[key] == nil {
                entries[key] = original(of: prefs.read(key))
                writeJournal(entries, defaults)  // before the preference is touched
            }
        } else if entries[key] != nil {
            entries[key] = nil  // a permanent choice from here on
            writeJournal(entries, defaults)
        }
        prefs.write(key, value)
        prefs.synchronize()
        return restart()
    }

    /// Gives the journaled originals back, only in the temporary mode. The Finder restarts only when a value really
    /// changes; the journal is cleared once the restart worked, kept otherwise so the next start tries again.
    static func restoreTemporary(prefs: FinderPreferenceStore, defaults: UserDefaults,
                                 restart: () -> Bool) -> RestoreOutcome {
        guard isTemporary(defaults) else { return .nothingOwed }
        let entries = journal(defaults)
        guard !entries.isEmpty else { return .nothingOwed }
        var changed = false
        for (key, saved) in entries.sorted(by: { $0.key < $1.key }) {
            let target: Bool? = saved == "1" ? true : (saved == "0" ? false : nil)
            if state(of: prefs.read(key)) != target {
                prefs.write(key, target)
                changed = true
            }
        }
        if changed {
            prefs.synchronize()
            guard restart() else { return .restartFailed }
        }
        clearJournal(defaults)
        return changed ? .restored : .nothingOwed
    }
}

// MARK: - Radial menu rules

/// When a radial wheel that nobody is driving goes away. Pure, so the close rules are tested without a window.
enum RadialOverlayRules {
    /// Seconds without a pointer move, a key or a modifier change before the wheel closes by itself.
    static let idleTimeout: TimeInterval = 3

    /// Another app became frontmost (a click elsewhere, Mission Control, a dialog): the wheel is over. The app's own
    /// windows are not a change.
    static func closesOnActivation(activated: String?, own: String?) -> Bool { activated != own }

    /// A held summoner (a mouse button) was released while the wheel is still in its hold phase.
    static func releaseEndsHold(holdPhase: Bool, heldButton: Int64?, released: Int64) -> Bool {
        holdPhase && heldButton == released
    }

    enum EscapeAction: Equatable { case stepBack, close }

    /// Escape leaves a submenu first, then the wheel.
    static func escapeAction(depth: Int) -> EscapeAction { depth > 1 ? .stepBack : .close }
}

/// One timer that fires `onExpire` once the wheel has seen no activity for `timeout`. `touch` only stamps the clock
/// (it runs on every pointer move), the timer re-checks that stamp when it fires. Main thread only. The scheduler and
/// the clock are seams so a test advances time by hand.
final class RadialIdleWatchdog {
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

    private let timeout: TimeInterval
    private let schedule: Schedule
    private let now: () -> TimeInterval
    private var lastActivity: TimeInterval = 0
    private var onExpire: (() -> Void)?
    private var cancelPending: (() -> Void)?

    init(timeout: TimeInterval = RadialOverlayRules.idleTimeout, schedule: @escaping Schedule = liveSchedule,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.timeout = timeout
        self.schedule = schedule
        self.now = now
    }

    var isArmed: Bool { onExpire != nil }

    func arm(onExpire: @escaping () -> Void) {
        disarm()
        self.onExpire = onExpire
        lastActivity = now()
        scheduleCheck(after: timeout)
    }

    /// Activity: pointer move, key, modifier change, selection. A no-op when not armed.
    func touch() {
        guard isArmed else { return }
        lastActivity = now()
    }

    func disarm() {
        cancelPending?()
        cancelPending = nil
        onExpire = nil
    }

    private func scheduleCheck(after delay: TimeInterval) {
        cancelPending = schedule(delay) { [weak self] in self?.check() }
    }

    private func check() {
        cancelPending = nil
        guard let onExpire else { return }
        let idleFor = now() - lastActivity
        if idleFor >= timeout {
            self.onExpire = nil
            onExpire()
        } else {
            scheduleCheck(after: timeout - idleFor)
        }
    }

    static let liveSchedule: Schedule = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

/// What the button-trigger tap does on each sync. Upstream's three conditions in one pure function: a tap that may
/// not run is removed (stop, no Accessibility, the login session switched away), a tap the system disabled is
/// rebuilt (it never revives by itself), a healthy one stays, a missing wanted one is created.
enum RadialTapPolicy {
    enum Action: Equatable { case teardown, keep, rebuild, create }

    static func decide(tapHeld: Bool, tapEnabled: Bool, featureWanted: Bool, accessibilityGranted: Bool,
                       sessionIsActive: Bool) -> Action {
        guard SessionActivitySupport.tapShouldRun(featureWanted: featureWanted,
                                                  accessibilityGranted: accessibilityGranted,
                                                  sessionIsActive: sessionIsActive) else { return .teardown }
        guard tapHeld else { return .create }
        return tapEnabled ? .keep : .rebuild
    }
}

// MARK: - Opening what the user configured

/// The three things a radial slice can open for the user. Tests pass a fake: nothing here may reach a shell.
protocol RadialWorkspace {
    func openApplication(at url: URL, onFailure: @escaping () -> Void)
    func open(_ url: URL)
    func fileExists(atPath path: String) -> Bool
}

struct LiveRadialWorkspace: RadialWorkspace {
    func openApplication(at url: URL, onFailure: @escaping () -> Void) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { DispatchQueue.main.async(execute: onFailure) }
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func fileExists(atPath path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// An app, a file or a link the user put on a wheel, opened with fixed `NSWorkspace` calls: a path or a URL is
/// data, never a command line.
enum RadialItemLauncher {
    enum Outcome: Equatable { case launched, missingFile, ignored }

    @discardableResult
    static func launch(_ item: RadialMenuItem, workspace: RadialWorkspace, beep: @escaping () -> Void) -> Outcome {
        switch item.kind {
        case .app:
            workspace.openApplication(at: URL(fileURLWithPath: (item.payload as NSString).expandingTildeInPath),
                                      onFailure: beep)
            return .launched
        case .file:
            let path = (item.payload as NSString).expandingTildeInPath
            guard workspace.fileExists(atPath: path) else {
                beep()
                return .missingFile
            }
            workspace.open(URL(fileURLWithPath: path))
            return .launched
        case .url:
            guard let normalized = RadialMenuSupport.normalizedURL(item.payload), let url = URL(string: normalized) else {
                return .ignored
            }
            workspace.open(url)
            return .launched
        default:
            return .ignored
        }
    }
}

// MARK: - Pages

/// Page 8: the quick panel (the launcher section of the ported quick tools page).
private struct QuickPanelPage: View {
    var body: some View { QuickToolsSettings(parts: [.launcher]) }
}

/// Page 9: the quick toggles, then what this lane adds: the temporary Finder mode and what this macOS cannot do.
private struct QuickActionsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuickToolsSettings(parts: [.toggles])
            QuickTogglesNotes()
        }
    }
}

/// Page 18: the wheel. The ported page already carries the Accessibility rows.
private struct RadialMenuPage: View {
    var body: some View { RadialMenuSettings() }
}

private struct QuickTogglesNotes: View {
    @AppStorage(FinderFlags.temporaryKey) private var temporary = false

    var body: some View {
        Form {
            Section {
                Toggle("Mode temporaire", isOn: $temporary)
                    .onChange(of: temporary) { _, on in
                        // Leaving the temporary mode makes the current state the user's own.
                        if !on { FinderFlags.clearJournal(PortHost.defaults) }
                    }
                Text("Activé : Mac Island remet les fichiers cachés et les icônes du bureau comme avant quand la fonction s’arrête ou que l’app se ferme (le Finder redémarre alors une fois). Désactivé : vos choix restent tels quels. Le Finder ne redémarre jamais sans votre clic.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Fichiers cachés et icônes du bureau")
            }
            let findings = QuickToggleProbe.live.findings
            if !findings.isEmpty {
                Section {
                    ForEach(findings.indices, id: \.self) { index in
                        Text(findings[index].reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Disponibilité sur ce macOS")
                }
            }
        }
        .formStyle(.grouped)
    }
}
