// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W8D (lock screen, gestures, mascot). The lane owns this file.

import AppKit
import IslandKit
import SwiftUI

// MARK: - Lock-screen island: the session

/// What the ported lock-screen service needs from outside, so a test never builds a panel or plays a sound.
@MainActor
protocol LockScreenServing: AnyObject {
    func sync(_ session: NotchSessionState)
    func playSound(locking: Bool)
    func close()
}

extension NotchLockScreenService: LockScreenServing {}

/// The session events upstream's island listened to. Pure: `apply` is the whole state machine.
enum IslandLockSession {
    enum Event: Equatable {
        case willSleep, didWake, screensSleep, screensWake, resignActive, becomeActive
        case locked, unlocked, saverStarted, saverStopped
    }

    static func apply(_ event: Event, to session: inout NotchSessionState) {
        switch event {
        case .willSleep: session.sleeping = true
        // Sleep ends a screen saver even when its stop goes unannounced.
        case .didWake: session.sleeping = false; session.screenSaverRunning = false
        case .screensSleep: session.displaysSleeping = true
        case .screensWake: session.displaysSleeping = false
        case .resignActive: session.onConsole = false
        case .becomeActive: session.onConsole = true
        case .locked: session.locked = true
        // No screen saver outlasts an unlock, whether or not its stop was announced.
        case .unlocked: session.locked = false; session.screenSaverRunning = false
        case .saverStarted: session.screenSaverRunning = true
        case .saverStopped: session.screenSaverRunning = false
        }
    }

    static let names: [(center: Center, name: Notification.Name, event: Event)] = [
        (.workspace, NSWorkspace.willSleepNotification, .willSleep),
        (.workspace, NSWorkspace.didWakeNotification, .didWake),
        (.workspace, NSWorkspace.screensDidSleepNotification, .screensSleep),
        (.workspace, NSWorkspace.screensDidWakeNotification, .screensWake),
        (.workspace, NSWorkspace.sessionDidResignActiveNotification, .resignActive),
        (.workspace, NSWorkspace.sessionDidBecomeActiveNotification, .becomeActive),
        (.distributed, Notification.Name("com.apple.screenIsLocked"), .locked),
        (.distributed, Notification.Name("com.apple.screenIsUnlocked"), .unlocked),
        (.distributed, Notification.Name("com.apple.screensaver.didstart"), .saverStarted),
        (.distributed, Notification.Name("com.apple.screensaver.didstop"), .saverStopped),
    ]

    enum Center { case workspace, distributed }
}

/// Tracks the session and drives the ported lock-screen service from it, as upstream's island did. It runs only between the
/// registry's start and stop of the `lockscreen` feature, and never calls the service while the private Space is not
/// available (`PrivateOverlaySpace`): the padlock sound still plays, the island over the lock screen simply does not show.
@MainActor
final class IslandLockScreenController {
    private let service: LockScreenServing
    private let capability: () -> OverlaySpaceCapability
    private let playsSounds: () -> Bool
    private(set) var session = NotchSessionState()
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isRunning = false

    init(service: LockScreenServing,
         capability: @escaping () -> OverlaySpaceCapability = { PrivateOverlaySpace.provider.capability(needsLevel: true) },
         playsSounds: @escaping () -> Bool = { NotchLockScreenSupport.playsSounds() }) {
        self.service = service
        self.capability = capability
        self.playsSounds = playsSounds
    }

    /// `observe: false` is the test seam: events are fed by `handle`.
    func start(initial: NotchSessionState, observe: Bool = true) {
        guard !isRunning else { return }
        isRunning = true
        session = initial
        if observe { install() }
        sync()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        session = NotchSessionState()
        service.close()
    }

    func handle(_ event: IslandLockSession.Event) {
        guard isRunning else { return }
        let wasLocked = session.locked
        IslandLockSession.apply(event, to: &session)
        // Someone at the Mac hears it lock or unlock; a closed lid or a screen saver does not count.
        if session.locked != wasLocked, session.locked ? session.hearsLockChange : session.onConsole, playsSounds() {
            service.playSound(locking: session.locked)
        }
        sync()
    }

    private func sync() {
        switch capability() {
        case .available: service.sync(session)
        case .unavailable: service.close()
        }
    }

    private func install() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for entry in IslandLockSession.names {
            let center: NotificationCenter = entry.center == .workspace ? workspace : distributed
            let event = entry.event
            let token = center.addObserver(forName: entry.name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            }
            tokens.append((center, token))
        }
    }

    static func currentSession() -> NotchSessionState {
        var state = NotchSessionState()
        state.onConsole = SessionActivity.shared.isActive
        state.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return state
    }
}

// MARK: - Gestures

/// One scroll event, reduced to what the state machine reads. Built from an `NSEvent` by the live monitor, by hand in tests.
struct IslandScrollSample: Equatable {
    var deltaX: Double
    var deltaY: Double
    var precise: Bool
    var inverted: Bool
    var timestamp: TimeInterval
    var began: Bool
    var ended: Bool
    var momentum: Bool
    var hasPhase: Bool
    var location: CGPoint
    var plainModifiers: Bool = true
}

/// What the host tells the gesture engine about the island at that instant.
struct IslandGestureContext: Equatable {
    var frame: CGRect
    var expanded: Bool
    var overHeader: Bool
    var musicSurface: Bool
}

/// Upstream's scroll gestures on the island (swipe down opens, up closes, sideways skips a track) as a pure engine: public
/// scroll events only, no `MultitouchSupport` and no tap. The state machine is upstream's `NotchGestureSupport`, unchanged.
struct IslandGestureEngine {
    private(set) var state = NotchGestureSupport()

    mutating func reset() { state = NotchGestureSupport() }

    mutating func handle(_ sample: IslandScrollSample, context: IslandGestureContext?) -> NotchGestureSupport.Action? {
        guard let context, sample.plainModifiers, context.frame.contains(sample.location) else { reset(); return nil }
        // The island's controls and scroll views keep their own scrolling (the host says where the pointer is).
        let vertical = NotchGestureSupport.allowsVertical(expanded: context.expanded, inHeader: context.overHeader,
                                                          musicSurface: context.musicSurface, control: false, scroll: false)
        let horizontal = !context.overHeader && context.musicSurface
        let x = NotchGestureSupport.movement(sample.deltaX, precise: sample.precise, inverted: sample.inverted)
        let y = NotchGestureSupport.movement(sample.deltaY, precise: sample.precise, inverted: sample.inverted)
        return state.handle(x: x, y: y, timestamp: sample.timestamp, began: sample.began, ended: sample.ended,
                            momentum: sample.momentum, precise: sample.precise, hasPhase: sample.hasPhase,
                            allowVertical: vertical, allowHorizontal: horizontal, expanded: context.expanded)
    }
}

/// The two hooks the app delegate fills (PortKit cannot see the island window): where the island is and what to do. With
/// either missing the monitor does nothing, so the feature is unavailable rather than half wired.
@MainActor
enum IslandGestures {
    static var context: (@MainActor () -> IslandGestureContext?)?
    static var perform: (@MainActor (NotchGestureSupport.Action) -> Void)?
}

/// What a gesture asks of the app, in plain public terms (the engine's own `Action` is internal to PortKit).
public enum PortIslandGestureAction: Equatable, Sendable {
    case openIsland, closeIsland, nextTrack, previousTrack
}

/// Where the island is, in plain public terms (screen coordinates, as `NSEvent.mouseLocation`).
public struct PortIslandGestureSpot: Equatable, Sendable {
    public var frame: CGRect
    public var expanded: Bool
    public var overHeader: Bool
    public var musicSurface: Bool

    public init(frame: CGRect, expanded: Bool, overHeader: Bool, musicSurface: Bool) {
        self.frame = frame
        self.expanded = expanded
        self.overHeader = overHeader
        self.musicSurface = musicSurface
    }
}

/// The app delegate's door to the gestures: it says where the island is and what each action does. The kill switch
/// (a plain defaults flag, `macIslandGesturesKill`) cuts both hooks at once, whatever the feature switch says, and the
/// hooks are released when the app calls `uninstall`.
@MainActor
public enum PortIslandGestureHost {
    public static let killKey = "macIslandGesturesKill"

    /// True when the kill switch is on (read live, so flipping it takes effect on the next scroll).
    public static func isKilled(defaults: UserDefaults = PortHost.defaults) -> Bool { defaults.bool(forKey: killKey) }

    /// `spot` is read on each scroll event; `perform` runs the action. Both are skipped while the kill switch is on.
    public static func install(
        defaults: UserDefaults = PortHost.defaults,
        spot: @escaping @MainActor () -> PortIslandGestureSpot?,
        perform: @escaping @MainActor (PortIslandGestureAction) -> Void
    ) {
        IslandGestures.context = {
            guard !isKilled(defaults: defaults), let spot = spot() else { return nil }
            return IslandGestureContext(frame: spot.frame, expanded: spot.expanded, overHeader: spot.overHeader,
                                        musicSurface: spot.musicSurface)
        }
        IslandGestures.perform = { action in
            guard !isKilled(defaults: defaults) else { return }
            perform(mapped(action))
        }
    }

    public static func uninstall() {
        IslandGestures.context = nil
        IslandGestures.perform = nil
    }

    static func mapped(_ action: NotchGestureSupport.Action) -> PortIslandGestureAction {
        switch action {
        case .open: .openIsland
        case .close: .closeIsland
        case .nextTrack: .nextTrack
        case .previousTrack: .previousTrack
        }
    }

    /// Track change on the ported player (the "Musique" tab), for the delegate's `perform`.
    public static func skipOnPortedPlayer(forward: Bool) { NotchMusicService.shared.skipFromGesture(forward: forward) }
}

@MainActor
final class IslandGestureMonitor {
    private var engine = IslandGestureEngine()
    private var monitors: [Any] = []
    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        engine.reset()
        let handler: (NSEvent) -> Void = { [weak self] event in
            let sample = IslandScrollSample(
                deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
                timestamp: event.timestamp, began: event.phase.contains(.began),
                ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                momentum: !event.momentumPhase.isEmpty, hasPhase: !event.phase.isEmpty,
                location: NSEvent.mouseLocation,
                plainModifiers: event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty)
            MainActor.assumeIsolated { self?.receive(sample) }
        }
        // Scroll wheel events are not a keyboard tap: the global monitor needs no permission, and it only ever reads.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handler) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in handler(event); return event }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        engine.reset()
    }

    func receive(_ sample: IslandScrollSample) {
        guard let context = IslandGestures.context?(), let perform = IslandGestures.perform else { engine.reset(); return }
        if let action = engine.handle(sample, context: context) { perform(action) }
    }
}

// MARK: - The lane

/// Binds the lock-screen island (a feature Mac Island adds: upstream makes it an option of its island), the island gestures
/// and the mascot. All three are OFF until the person switches them on in Fonctions.
///
/// - `lockscreen`: start = take the hosting flag, track the session and (when the private Space is available and the
///   person ticked "écran verrouillé" in the island settings) show the ported lock-screen scene; the padlock sounds follow
///   their own tick. Stop = the scene goes, the observers go, the flag is released. The private WindowServer calls live in
///   `PrivateOverlaySpace.swift` only: capability probe, kill switch, a journal written BEFORE the first call, and a launch
///   check that keeps the island down after a crash (`recoverAtLaunch`). Never a prompt, never a crash for a missing symbol.
/// - `notchGestures`: start = the scroll monitor (public events only).
/// - `notchMascot`: start = the hosting flag, the seeded toggle and the companion's indicator in a wing of the closed island
///   (`IslandMascotPresence`); the same view (`IslandMascotView`) is the Compagnon tab's.
enum IslandLockScreenLane {
    static let lockScreenID = "lockscreen"

    struct Runtime {
        var startLock: @MainActor () -> Void
        var stopLock: @MainActor () -> Void
        var startGestures: @MainActor () -> Void
        var stopGestures: @MainActor () -> Void
        var startMascot: @MainActor () -> Void
        var stopMascot: @MainActor () -> Void

        @MainActor private static var controller: IslandLockScreenController?
        @MainActor private static let monitor = IslandGestureMonitor()

        static let live = Runtime(
            startLock: {
                IslandActivityHost.shared.acquire(lockScreenID)
                let made = controller ?? IslandLockScreenController(service: NotchLockScreenService.shared)
                controller = made
                made.start(initial: IslandLockScreenController.currentSession())
            },
            stopLock: {
                controller?.stop()
                IslandActivityHost.shared.release(lockScreenID)
            },
            startGestures: {
                IslandActivityHost.shared.acquire("notchGestures")
                monitor.start()
            },
            stopGestures: {
                monitor.stop()
                IslandActivityHost.shared.release("notchGestures")
            },
            startMascot: { mascotStart(presence: mascotPresence)() },
            stopMascot: { mascotStop(presence: mascotPresence)() })

        @MainActor private static let mascotPresence = IslandMascotPresence(hooks: .live)

        /// What the registry runs when the Compagnon switch goes on: take the hosting flag, seed the ported toggle (the
        /// switch in Fonctions is the opt-in, `IslandFeatureSeed`), give the closed island its drawing, then show the
        /// companion in a wing. Tests pass a presence wired to a local `AmbientCenter`.
        @MainActor static func mascotStart(presence: IslandMascotPresence) -> @MainActor () -> Void {
            {
                IslandActivityHost.shared.acquire("notchMascot")
                // The Fonctionnalites switch IS the opt-in: the page's own key follows it (`CompanionSwitch`, one source of truth).
                PortHost.defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
                AmbientMascotSlot.make = { size in AnyView(IslandMascotView(size: size)) }
                presence.start()
            }
        }

        @MainActor static func mascotStop(presence: IslandMascotPresence) -> @MainActor () -> Void {
            {
                presence.stop()
                IslandActivityHost.shared.release("notchMascot")
            }
        }
    }

    static let descriptor = FeatureDescriptor(
        id: lockScreenID, title: "Île sur l’écran verrouillé",
        summary: "Affiche l’île et ses activités sur l’écran de verrouillage, avec les sons du cadenas. Éteint tant que vous ne l’activez pas.",
        systemImage: "lock.display", category: .island, permissions: [], risk: .touchesSystem,
        enabledByDefault: false, tabID: nil)

    @MainActor private static var didRecover = false

    @MainActor static func bind(into binding: PortFeatureBinding) {
        recoverAtLaunch()
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(custom: descriptor, start: { runtime.startLock() }, stop: { runtime.stopLock() })
        binding.bind("notchGestures", start: { runtime.startGestures() }, stop: { runtime.stopGestures() })
        binding.bind("notchMascot", start: { runtime.startMascot() }, stop: { runtime.stopMascot() })
    }

    /// Reads the journal of the lock-screen Space once per launch (it writes nothing without one). Called at bind time,
    /// which is before the registry starts anything, so a Space a crash left armed keeps the island down this run.
    @MainActor static func recoverAtLaunch(journal: OverlaySpaceJournaling = FileOverlaySpaceJournal(),
                                           defaults: UserDefaults = PortHost.defaults) {
        guard !didRecover else { return }
        didRecover = true
        OverlaySpaceGuard.recoverAtLaunch(journal: journal, defaults: defaults)
    }
}

// MARK: - Views

/// The mascot as a bare view for the island (beside the camera, on a page): empty while the feature is off.
public struct IslandMascotView: View {
    private let size: CGFloat
    @ObservedObject private var ticker = IslandHostTicker.shared

    public init(size: CGFloat = 20) { self.size = size }

    public var body: some View {
        if IslandActivityHost.shared.holds("notchMascot"), NotchMascotSupport.isEnabled() {
            NotchMascotView(look: NotchMascotSupport.look(), size: size)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// The Compagnon page: the companion at the top while its feature runs (live, `IslandHostTicker`), its settings below.
private struct CompanionTabContent: View {
    @ObservedObject private var ticker = IslandHostTicker.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if IslandActivityHost.shared.holds("notchMascot") {
                    IslandMascotView(size: 64)
                }
                NotchMascotSettings(embedded: true)
            }
            .padding(12)
        }
        .defaultAppStorage(PortHost.defaults)
    }
}

extension IslandPortTabs {
    /// The tab of wave 8D: the companion, with its own settings (style, palette, side, visits).
    @MainActor public static func companion() -> IslandTab {
        IslandTab(id: "companion", title: "Compagnon", systemImage: "face.smiling") {
            AnyView(CompanionTabContent())
        }
    }

    /// The tabs of lane group 2, in the order the island lists them.
    @MainActor public static func laneGroup2() -> [IslandTab] { lane8C() + [companion()] }
}

/// The ported island settings the island page hosts below its own editors: the lock-screen switches, the companion's
/// look and the "Combiner" menu. The companion shows in the closed island only while its feature is on
/// (`IslandMascotPresence`, an opt-in indicator in a wing); this view is settings only.
public struct PortIslandExtrasSettings: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IslandLockScreenSettingsView()
            NotchMascotSettings(embedded: true)
            HStack {
                Text("Combiner deux activités").font(.callout)
                Spacer()
                IslandCombineMenu()
            }
        }
        .environment(\.colorScheme, .dark)
        .defaultAppStorage(PortHost.defaults)
    }
}

/// Settings of the lock-screen island: the two upstream switches in French, and the state of the private part, with the way
/// back from a crash lock. For the island settings page (wave 9B) to host.
public struct IslandLockScreenSettingsView: View {
    @AppStorage(DefaultsKey.notchLockScreen) private var showsLockScreen = false
    @AppStorage(DefaultsKey.notchLockSounds) private var playsSounds = false
    @AppStorage(OverlaySpaceGuard.killKey) private var killed = false
    @AppStorage(OverlaySpaceGuard.crashedKey) private var crashed = false

    public init() {}

    var statusText: String {
        IslandLockScreenSettingsView.statusText(PrivateOverlaySpace.provider.capability(needsLevel: true))
    }

    static func statusText(_ capability: OverlaySpaceCapability) -> String {
        switch capability {
        case .available:
            return "Disponible sur ce Mac."
        case .unavailable(.crashed):
            return "Coupé : le dernier affichage sur l’écran verrouillé s’est mal terminé. Réessayez quand vous voulez."
        case .unavailable(.killSwitch):
            return "Coupé à votre demande."
        case .unavailable(.symbolsMissing(let names)):
            return names.isEmpty
                ? "Indisponible : cette version de macOS ne le permet pas."
                : "Indisponible : cette version de macOS n’offre pas \(names.count) appel(s) système nécessaire(s)."
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Écran verrouillé").font(.headline)
            Toggle("Afficher l’île sur l’écran verrouillé", isOn: $showsLockScreen)
            Text("La lecture en cours et les activités apparaissent entre l’horloge et la zone de mot de passe.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Jouer les sons du cadenas", isOn: $playsSounds)
            Divider()
            Text(statusText).font(.callout)
            Toggle("Couper l’affichage sur l’écran verrouillé", isOn: $killed)
                .accessibilityHint("Garde l’île éteinte sur l’écran verrouillé tant que vous ne la rallumez pas.")
            if crashed || killed {
                Button("Réessayer") {
                    OverlaySpaceGuard.reset(defaults: PortHost.defaults)
                    killed = false
                    crashed = false
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
