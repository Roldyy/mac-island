// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W2C (energy and microphone). The lane owns this file.

import AppKit
import Combine
import IslandKit
import IslandUI
import SwiftUI

// MARK: - Closed-lid safety policy (pure)

/// When the closed-lid mode (`pmset disablesleep 1`) must end by itself. Read by the patched `KeepAwakeManager`
/// every 30 s while a session runs, and before it ever disables lid sleep. Ending it never ends the keep-awake
/// session itself, only the lid override, and the preference goes off so a new click is needed to start again.
enum ClamshellSafetyPolicy {
    /// Unplugged under this level, closed-lid mode ends. Strictly under: 20 % itself is still allowed.
    static let minimumBatteryPercent = 20
    /// A closed Mac in a bag for longer than this is a risk whatever the battery says.
    static let maximumDuration: TimeInterval = 8 * 3600

    enum Violation: Equatable {
        case lowBattery(percent: Int)
        case hot
        case tooLong

        /// The line the island and the page show, in French.
        var message: String {
            switch self {
            case .lowBattery(let percent):
                "Mode capot fermé arrêté : batterie à \(percent) % sur batterie (seuil \(ClamshellSafetyPolicy.minimumBatteryPercent) %)."
            case .hot:
                "Mode capot fermé arrêté : le Mac chauffe trop."
            case .tooLong:
                "Mode capot fermé arrêté : durée maximale de \(Int(ClamshellSafetyPolicy.maximumDuration / 3600)) h atteinte."
            }
        }
    }

    /// The first reason to stop, nil when the mode may go on. Heat first, then battery, then duration.
    /// `activeSince` is nil before the mode is on (then only heat and battery can say no). An unplugged Mac whose
    /// level cannot be read counts as empty: the policy fails closed.
    static func violation(onBattery: Bool, batteryPercent: Int?, thermalState: ProcessInfo.ThermalState,
                          activeSince: Date?, now: Date) -> Violation? {
        if thermalState == .serious || thermalState == .critical { return .hot }
        if onBattery {
            let percent = batteryPercent ?? 0
            if percent < minimumBatteryPercent { return .lowBattery(percent: percent) }
        }
        if let activeSince, now.timeIntervalSince(activeSince) >= maximumDuration { return .tooLong }
        return nil
    }
}

// MARK: - Sudoers rule check (pure)

/// The one line the closed-lid setup may write into `/etc/sudoers.d`. The installer builds it with
/// `SudoersSupport.clamshellRule(uid:)` and puts it inside single quotes of a root shell command, so anything but
/// this exact shape (a quote, a newline, a wildcard, a username, another command) is refused before the system
/// password is ever asked for.
enum ClosedLidRule {
    static let commands = "/usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"

    static func isValid(_ rule: String, uid: uid_t) -> Bool {
        rule == "#\(uid) ALL=(root) NOPASSWD: \(commands)"
            && rule.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7F && $0 != UInt8(ascii: "'") }
    }
}

// MARK: - Keep Awake: what ours did that the port does not

/// One-time reconciliation of our old Keep Awake choices with the ported manager's keys.
enum EnergyMerge {
    static let seededKey = "macIslandEnergyMergeV1"

    /// Our module kept the display free to sleep unless `keepAwakePreventDisplaySleep` said otherwise; the ported
    /// manager holds the display awake unless `keepAwakeAllowDisplaySleep` says otherwise. So a session behaves as
    /// it did before the merge, the ported key is seeded once from ours, unless the person already chose it
    /// (`stored` is the persistent domain: registered defaults are not in it).
    static func seedDisplaySleep(in defaults: UserDefaults, stored: [String: Any]) {
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)
        guard stored[DefaultsKey.keepAwakeAllowDisplaySleep] == nil else { return }
        let prevent = (stored["keepAwakePreventDisplaySleep"] as? Bool) ?? false
        defaults.set(!prevent, forKey: DefaultsKey.keepAwakeAllowDisplaySleep)
    }
}

// MARK: - The closed island, as the energy features show themselves

/// One indicator of the closed island.
struct EnergyIndicator: Equatable {
    let id: String
    let symbol: String
    let text: String
    let status: IslandStatus
    /// Seconds before it withdraws itself; nil stays until withdrawn.
    let lifetime: Double?
}

/// What the island says about closed-lid mode, a sleep that could not be restored, and a muted microphone.
/// Pure: the posting is `EnergyIslandBridge`.
enum EnergyIndicators {
    static let closedLidID = "energy.closedLid"
    static let restoreID = "energy.sleepRestore"
    static let stoppedID = "energy.closedLidStopped"
    static let micID = "energy.micMuted"
    static let all = [closedLidID, restoreID, stoppedID, micID]

    static func indicators(closedLidActive: Bool, sleepRestoreNeeded: Bool,
                           stopReason: ClamshellSafetyPolicy.Violation?, micMuted: Bool) -> [EnergyIndicator] {
        var result: [EnergyIndicator] = []
        if closedLidActive {
            result.append(EnergyIndicator(id: closedLidID, symbol: "laptopcomputer", text: "Mode capot fermé actif",
                                          status: .warning, lifetime: nil))
        }
        if sleepRestoreNeeded {
            result.append(EnergyIndicator(id: restoreID, symbol: "exclamationmark.triangle.fill",
                                          text: "Veille désactivée : à rétablir", status: .danger, lifetime: nil))
        }
        if let stopReason {
            result.append(EnergyIndicator(id: stoppedID, symbol: "laptopcomputer.slash", text: stopReason.message,
                                          status: .warning, lifetime: 12))
        }
        if micMuted {
            result.append(EnergyIndicator(id: micID, symbol: "mic.slash.fill", text: "Micro coupé", status: .info,
                                          lifetime: nil))
        }
        return result
    }

    /// The short notice when a session ends by itself (timer, battery); nil when nothing needs saying.
    static func endNotice(minutesWereSet: Bool, battery: Bool) -> String? {
        if battery { return "Éveil arrêté : batterie faible" }
        return minutesWereSet ? "Éveil terminé" : nil
    }
}

/// Posts `EnergyIndicators` to the closed island. The sources are attached when their feature starts, never before,
/// so a feature that is off builds no manager and no subscription.
@MainActor
final class EnergyIslandBridge {
    static let shared = EnergyIslandBridge()

    private var post: (IslandActivity, Duration?) -> Void = { ActivityCenter.shared.post($0, expiresAfter: $1) }
    private var withdraw: (String) -> Void = { ActivityCenter.shared.withdraw(id: $0) }
    private var closedLid = false
    private var restoreNeeded = false
    private var stopReason: ClamshellSafetyPolicy.Violation?
    private var micMuted = false
    private var keepAwakeCancellables: [AnyCancellable] = []
    private var micCancellable: AnyCancellable?
    private var postedStopReason: ClamshellSafetyPolicy.Violation?

    init() {}

    /// Tests inject the sink.
    init(post: @escaping (IslandActivity, Duration?) -> Void, withdraw: @escaping (String) -> Void) {
        self.post = post
        self.withdraw = withdraw
    }

    func update(closedLid: Bool? = nil, restoreNeeded: Bool? = nil, stopReason: ClamshellSafetyPolicy.Violation?? = nil,
                micMuted: Bool? = nil) {
        if let closedLid { self.closedLid = closedLid }
        if let restoreNeeded { self.restoreNeeded = restoreNeeded }
        if let stopReason { self.stopReason = stopReason }
        if let micMuted { self.micMuted = micMuted }
        let wanted = EnergyIndicators.indicators(closedLidActive: self.closedLid,
                                                 sleepRestoreNeeded: self.restoreNeeded,
                                                 stopReason: self.stopReason, micMuted: self.micMuted)
        let wantedIDs = Set(wanted.map(\.id))
        for id in EnergyIndicators.all where !wantedIDs.contains(id) { withdraw(id) }
        for item in wanted {
            // The stop notice is posted once per reason: a later update must not restart its lifetime.
            if item.id == EnergyIndicators.stoppedID {
                guard postedStopReason != self.stopReason else { continue }
                postedStopReason = self.stopReason
            }
            post(IslandActivity(id: item.id, source: "energy", priority: .alert,
                                leading: CompactItem(symbol: item.symbol, text: item.text, status: item.status)),
                 item.lifetime.map { .seconds($0) })
        }
        if self.stopReason == nil { postedStopReason = nil }
    }

    func attachKeepAwake(_ manager: KeepAwakeManager) {
        guard keepAwakeCancellables.isEmpty else { return }
        keepAwakeCancellables = [
            manager.$clamshellActive.sink { [weak self] value in
                MainActor.assumeIsolated { self?.update(closedLid: value) }
            },
            manager.$sleepRestoreNeeded.sink { [weak self] value in
                MainActor.assumeIsolated { self?.update(restoreNeeded: value) }
            },
            manager.$clamshellStopReason.sink { [weak self] value in
                MainActor.assumeIsolated { self?.update(stopReason: .some(value)) }
            },
        ]
        manager.onSessionEnded = { [weak self] reason in
            MainActor.assumeIsolated { self?.sessionEnded(reason) }
        }
    }

    func attachMic(_ service: MicMuteService) {
        guard micCancellable == nil else { return }
        micCancellable = service.$isMuted.sink { [weak self] value in
            MainActor.assumeIsolated { self?.update(micMuted: value) }
        }
    }

    private func sessionEnded(_ reason: KeepAwakeManager.EndReason) {
        let notice = EnergyIndicators.endNotice(minutesWereSet: reason == .timer, battery: reason == .battery)
        guard let notice else { return }
        post(IslandActivity(id: "energy.sessionEnded", source: "energy", priority: .alert,
                            leading: CompactItem(symbol: "cup.and.saucer", text: notice,
                                                 status: reason == .battery ? .warning : .info)),
             .seconds(5))
    }
}

// MARK: - Keep Awake, for the shell

/// What the island shell (our `KeepAwakeFeature`) sees of the ported Keep Awake manager: the one implementation.
/// Public because PortKit's other surface is `PortBridge`; the manager itself stays internal.
@MainActor
public enum PortKeepAwake {
    public struct Snapshot: Equatable, Sendable {
        public var isActive = false
        public var endDate: Date?
        /// Started by an automation (power adapter, external display, running apps), not by a click.
        public var isAutomatic = false
        public var closedLidActive = false
        public var closedLidPreferred = false
        public var sleepRestoreNeeded = false

        public init(isActive: Bool = false, endDate: Date? = nil, isAutomatic: Bool = false, closedLidActive: Bool = false,
                    closedLidPreferred: Bool = false, sleepRestoreNeeded: Bool = false) {
            self.isActive = isActive
            self.endDate = endDate
            self.isAutomatic = isAutomatic
            self.closedLidActive = closedLidActive
            self.closedLidPreferred = closedLidPreferred
            self.sleepRestoreNeeded = sleepRestoreNeeded
        }
    }

    private static var manager: KeepAwakeManager { .shared }

    public static var snapshot: Snapshot {
        let m = manager
        return Snapshot(isActive: m.isActive, endDate: m.endDate, isAutomatic: m.sessionTrigger == .automation,
                        closedLidActive: m.clamshellActive, closedLidPreferred: m.clamshellPreferred,
                        sleepRestoreNeeded: m.sleepRestoreNeeded)
    }

    /// The current state, then one value per change (delivered on the main queue, after the change landed).
    public static func snapshots() -> AnyPublisher<Snapshot, Never> {
        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .map { _ in MainActor.assumeIsolated { snapshot } }
            .prepend(snapshot)
            .eraseToAnyPublisher()
    }

    /// Stops a running session, otherwise starts the last pick (the default duration, or the saved end time).
    public static func toggle() { manager.toggle() }

    /// Starts a session of `minutes` (0 = no limit) and remembers it as the last pick.
    public static func start(minutes: Int) { manager.activate(minutes: minutes) }

    /// Ends the running session, as a click would.
    public static func stop() { if manager.isActive { manager.toggle() } }

    /// The saved default duration in minutes (0 = no limit).
    public static var defaultMinutes: Int { Defaults.sanitizedDefaultDuration(PortHost.defaults.integer(forKey: DefaultsKey.defaultDuration)) }
}

// MARK: - The lane

/// Binds this lane's four ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// - `keepAwake` is OURS in the registry (id `keepawake`, Home tile, Éveil tab, shortcut): the ported
///   `KeepAwakeManager` covers everything ours did (timers, end time, three automation triggers, jiggle, display
///   sleep, battery protection, pause when locked) and more (closed lid), so it is the ONE implementation and our
///   `KeepAwakeController` is gone. The lane only `adopt`s the starter and stopper.
///   Start = recover once, sync the preferences, arm the launch-time auto start (first start only).
///   Stop = `syncWithFeatures()`, which ends the session and the automation because the registry already
///   marked the feature unavailable (switch off, kill switch, safe mode, quarantine).
/// - `bluetoothSleep`: start/stop = the service's `syncWithPreferences()`, which also pays a restore still owed;
///   the quit pays it too. The private IOBluetooth switch is probed first (`isSupported`): without it nothing runs
///   and the page says so.
/// - `micMute`: start = sync (hotkey, a mute carried over a relaunch); stop = sync again with the feature
///   unavailable, which unmutes every device and drops the shortcut; the quit unmutes synchronously.
/// - `musicBlock`: start = sync (needs Accessibility, the binding already waits for it); stop = remove the tap.
enum EnergyLane {
    struct Runtime {
        var keepAwakeStart: @MainActor () -> Void
        var keepAwakeStop: @MainActor () -> Void
        var keepAwakeQuit: @MainActor () -> Void
        var bluetoothStart: @MainActor () -> Void
        var bluetoothStop: @MainActor () -> Void
        var bluetoothQuit: @MainActor () -> Void
        var micStart: @MainActor () -> Void
        var micStop: @MainActor () -> Void
        var micQuit: @MainActor () -> Void
        var musicStart: @MainActor () -> Void
        var musicStop: @MainActor () -> Void

        /// First `keepAwakeStart` of the process only (launch-time auto start must not re-run on a restart).
        @MainActor static var keepAwakeStartedOnce = false
        @MainActor static var micStarted = false

        @MainActor static let live = Runtime(
            keepAwakeStart: {
                let defaults = PortHost.defaults
                EnergyMerge.seedDisplaySleep(in: defaults, stored: defaults.persistentDomain(forName: PortHost.bundleID) ?? [:])
                let manager = KeepAwakeManager.shared
                EnergyIslandBridge.shared.attachKeepAwake(manager)
                // The launch plan only recovers when a marker exists; automation waits for a finished recovery.
                if !manager.recoveryCompleted { manager.recoverIfNeeded() }
                manager.syncWithPreferences()
                if !Runtime.keepAwakeStartedOnce {
                    Runtime.keepAwakeStartedOnce = true
                    manager.activateOnLaunchIfNeeded()
                }
            },
            keepAwakeStop: { KeepAwakeManager.shared.syncWithFeatures() },
            keepAwakeQuit: { KeepAwakeManager.shared.deactivate(reason: .quit) },
            bluetoothStart: { BluetoothSleepService.shared.syncWithPreferences() },
            bluetoothStop: {
                BluetoothSleepService.shared.syncWithPreferences()
                BluetoothSleepService.shared.stop()
            },
            bluetoothQuit: {
                if PortHost.defaults.bool(forKey: DefaultsKey.bluetoothSleepRestorePending) {
                    BluetoothSleepService.shared.restoreNow()
                }
            },
            micStart: {
                Runtime.micStarted = true
                EnergyIslandBridge.shared.attachMic(MicMuteService.shared)
                MicMuteService.shared.syncWithPreferences()
            },
            micStop: {
                MicMuteService.shared.syncWithPreferences()
                MicMuteService.shared.suspend()
            },
            micQuit: {
                let defaults = PortHost.defaults
                let owed = defaults.bool(forKey: DefaultsKey.micMuteActive)
                    || !(defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).isEmpty
                if Runtime.micStarted || owed { MicMuteService.shared.unmuteForTeardown() }
            },
            musicStart: { MusicLaunchBlocker.shared.syncWithPreferences() },
            musicStop: { MusicLaunchBlocker.shared.stop() })
    }

    /// Our Settings page ids (`SettingsPageCatalog`).
    static let pageIDs: [AppFeature: String] = [
        .keepAwake: "keepawake", .bluetoothSleep: "btsleep", .micMute: "mutemic", .musicBlock: "musicblock",
    ]

    private static var didInstallLiveWiring = false

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installLiveWiring(runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.adopt(.keepAwake, start: runtime.keepAwakeStart, stop: runtime.keepAwakeStop)
        binding.bind(.bluetoothSleep, page: PortFeaturePage(pageID: "btsleep") { AnyView(BluetoothSleepPage()) },
                     start: runtime.bluetoothStart, stop: runtime.bluetoothStop)
        binding.bind(.micMute, page: PortFeaturePage(pageID: "mutemic") { AnyView(MicMutePage()) },
                     start: runtime.micStart, stop: runtime.micStop)
        binding.bind(.musicBlock, page: PortFeaturePage(pageID: "musicblock") { AnyView(MusicBlockPage()) },
                     start: runtime.musicStart, stop: runtime.musicStop)
    }

    /// What only the real app does: the Keep Awake page (its catalog row already carries the feature card, so it
    /// is a plain page body) and the quit hook that gives sleep, the microphone and Bluetooth back.
    @MainActor private static func installLiveWiring(runtime: Runtime) {
        guard !didInstallLiveWiring else { return }
        didInstallLiveWiring = true
        PortBridge.register(pageID: "keepawake") {
            AnyView(KeepAwakePage().defaultAppStorage(PortHost.defaults))
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { quit(runtime: runtime) }
        }
    }

    /// Everything the energy features must give back before the process ends. Synchronous on purpose.
    @MainActor static func quit(runtime: Runtime) {
        runtime.keepAwakeQuit()
        runtime.micQuit()
        runtime.bluetoothQuit()
    }
}

// MARK: - Page 24: Garder éveillé

struct KeepAwakePage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var autoStart = false
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var allowDisplaySleep = false
    @AppStorage(DefaultsKey.keepAwakePauseWhenLocked) private var pauseWhenLocked = false
    @AppStorage(DefaultsKey.keepAwakeAutomationRequireAll) private var requireAll = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var jiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var jiggleInterval = 5
    @AppStorage("notchKeepAwakeActivity") private var islandActivity = true
    @State private var untilDraft: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            sessionCard
            optionsCard
            closedLidCard
        }
        .toggleStyle(.switch)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            jiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(jiggleInterval)
        }
    }

    // MARK: Session

    private var sessionCard: some View {
        SettingsCard {
            if awake.isActive, awake.sessionTrigger != .automation, let end = awake.endDate {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    sessionRow(status: "\(l10n.s.keepAwakeEndsIn) \(KeepAwakeCard.remainingText(until: end))")
                }
            } else {
                sessionRow(status: sessionStatus)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.s.defaultDurationLabel).font(.subheadline.weight(.medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                    ForEach(DurationPicker.choices, id: \.self) { minutes in durationChip(minutes) }
                }
                KeepAwakeEndTimePicker(selection: untilBinding, activeEnd: untilActiveEnd,
                                       onStop: { awake.toggle() }, onStart: startUntil)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(automationStrings.automationSection).font(.subheadline.weight(.medium))
                Text(automationStrings.caption(requireAll: requireAll))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                KeepAwakeAutomationEditor()
            }
            SettingsRow(symbol: "lock.fill", title: automationStrings.pauseWhenLockedToggle,
                        caption: automationStrings.pauseWhenLockedCaption) {
                Toggle(automationStrings.pauseWhenLockedToggle, isOn: $pauseWhenLocked).labelsHidden()
            }
        }
    }

    private func sessionRow(status: String) -> some View {
        SettingsRow(symbol: "moon.zzz.fill", title: l10n.s.keepAwakeTitle, caption: status) {
            Toggle(l10n.s.keepAwakeTitle, isOn: Binding(
                get: { awake.isActive },
                set: { on in
                    if on { awake.startLastPick() } else if awake.isActive { awake.toggle() }
                })).labelsHidden()
        }
    }

    private var sessionStatus: String {
        guard awake.isActive else { return l10n.s.keepAwakeNormalRules }
        if awake.sessionTrigger == .automation {
            return automationStrings.activeStatus(for: awake.activeAutomationConditions)
        }
        return l10n.s.keepAwakeUntilDisabled
    }

    private func durationChip(_ minutes: Int) -> some View {
        let selected = defaultDuration == minutes
        return Button {
            defaultDuration = minutes
            // A chosen default is the newest pick, so the switch starts it.
            PortHost.defaults.set(false, forKey: DefaultsKey.keepAwakeSwitchUsesUntil)
        } label: {
            Text(DurationPicker.title(for: minutes, l10n.s))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var untilBinding: Binding<Date> {
        Binding(get: { untilDraft ?? Date().addingTimeInterval(3600) }, set: { untilDraft = $0 })
    }

    /// The end of a running "until" session, for the chip.
    private var untilActiveEnd: Date? {
        awake.isActive && awake.sessionTrigger == .manual && awake.sessionMinutes == nil ? awake.endDate : nil
    }

    private func startUntil() {
        let picked = untilDraft ?? Date().addingTimeInterval(3600)
        awake.activate(until: KeepAwakeAutomationSupport.resolvedUntilDate(picked: picked, now: Date()))
        untilDraft = nil
    }

    // MARK: Options

    private var optionsCard: some View {
        SettingsCard(title: l10n.s.keepAwakeOptions) {
            SettingsRow(symbol: "play.circle", title: l10n.s.keepAwakeAutoStart,
                        caption: l10n.s.keepAwakeAutoStartCaption) {
                Toggle(l10n.s.keepAwakeAutoStart, isOn: $autoStart).labelsHidden()
            }
            SettingsRow(symbol: "display", title: displaySleepStrings.allowDisplaySleep,
                        caption: displaySleepStrings.allowDisplaySleepCaption) {
                Toggle(displaySleepStrings.allowDisplaySleep, isOn: $allowDisplaySleep).labelsHidden()
            }
            SettingsRow(symbol: "cursorarrow.motionlines", title: l10n.s.keepAwakeMouseJiggle,
                        caption: l10n.s.keepAwakeMouseJiggleCaption) {
                Toggle(l10n.s.keepAwakeMouseJiggle, isOn: $jiggle).labelsHidden()
            }
            if jiggle {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(l10n.s.keepAwakeMouseJiggleInterval)
                        Spacer()
                        KeepAwakeMouseJiggleIntervalPicker(selection: $jiggleInterval)
                    }
                    if !permissions.accessibility { PermissionRow(kind: .accessibility) }
                }
                .padding(.leading, settingsRowTextInset)
            }
            SettingsRow(symbol: "rectangle.topthird.inset.filled", title: "Rester éveillé tant que l’île est utilisée",
                        caption: "Ouvrir ou utiliser l’île retarde la veille de deux minutes, même sans session.") {
                Toggle("Rester éveillé tant que l’île est utilisée", isOn: $islandActivity).labelsHidden()
            }
            if PowerSampler.hasInternalBattery {
                Divider()
                SettingsRow(symbol: "battery.25percent", title: l10n.s.batteryDisableBelow,
                            caption: l10n.s.batteryProtectionCaption) {
                    Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                        Text(l10n.s.batteryNever).tag(0)
                        Text("5%").tag(5)
                        Text("10%").tag(10)
                        Text("15%").tag(15)
                        Text("20%").tag(20)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: Closed lid

    private var closedLidCard: some View {
        SettingsCard(title: "Mode capot fermé") {
            SettingsRow(symbol: "laptopcomputer", title: l10n.s.clamshellTitle, caption: closedLidCaption) {
                if awake.clamshellPreferred {
                    Button("Désactiver") { awake.setClosedLidMode(false) }
                } else {
                    Button("Activer…") { awake.setClosedLidMode(true) }
                        .disabled(awake.clamshellSetupInProgress)
                }
            }
            if awake.clamshellActive {
                Label("Mode capot fermé actif", systemImage: "laptopcomputer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.leading, settingsRowTextInset)
            }
            if awake.clamshellSetupFailed {
                Text(l10n.s.sudoersFailed)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, settingsRowTextInset)
            }
            if let reason = awake.clamshellStopReason {
                Text(reason.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
            if awake.clamshellPreferred {
                SettingsRow(symbol: "sun.min", title: l10n.s.dimScreenOnLidCloseTitle,
                            caption: l10n.s.dimScreenOnLidCloseCaption) {
                    Toggle(l10n.s.dimScreenOnLidCloseTitle, isOn: $awake.dimScreenOnLidClose).labelsHidden()
                }
                .padding(.leading, settingsRowTextInset)
            }
            Text("Arrêt automatique : batterie sous \(ClamshellSafetyPolicy.minimumBatteryPercent) % sur batterie, Mac qui chauffe, ou après \(Int(ClamshellSafetyPolicy.maximumDuration / 3600)) h. À réserver au branché ; ne rangez jamais le Mac dans un sac pendant ce mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)
            if awake.sleepRestoreNeeded {
                Divider()
                SettingsRow(symbol: "exclamationmark.triangle.fill", title: "La veille du Mac est restée désactivée",
                            caption: "Un arrêt brutal a laissé « pmset disablesleep » à 1 et Mac Island n’a pas pu le remettre à 0 sans mot de passe.") {
                    Button("Rétablir la veille maintenant") { awake.restoreSleepFromClick() }
                }
                Text("Sinon, dans le Terminal : sudo pmset -a disablesleep 0")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var closedLidCaption: String {
        if awake.clamshellSetupInProgress { return l10n.s.configuring }
        return "Désactivé par défaut. Garde le Mac éveillé capot fermé pendant une session. Le bouton demande une fois votre mot de passe administrateur pour créer une règle limitée à « pmset disablesleep »."
    }

    private var automationStrings: KeepAwakeAutomationStrings { FeatureStrings.keepAwakeAutomation(l10n.language) }
    private var displaySleepStrings: KeepAwakeDisplaySleepStrings { FeatureStrings.keepAwakeDisplaySleep(l10n.language) }
}

// MARK: - Page 27: Bluetooth en veille

struct BluetoothSleepPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.bluetoothSleepEnabled) private var enabled = false
    @AppStorage(DefaultsKey.bluetoothSleepRestoreOnWake) private var restoreOnWake = true

    var body: some View {
        let strings = FeatureStrings.bluetoothSleep(l10n.language)
        SettingsCard {
            if BluetoothSleepService.isSupported {
                SettingsRow(symbol: "dot.radiowaves.left.and.right", title: strings.enable, caption: strings.enableCaption) {
                    Toggle(strings.enable, isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: enabled) { _, _ in BluetoothSleepService.shared.syncWithPreferences() }
                }
                if enabled {
                    SettingsRow(symbol: "arrow.counterclockwise", title: strings.restoreToggle,
                                caption: strings.restoreCaption) {
                        Toggle(strings.restoreToggle, isOn: $restoreOnWake).labelsHidden().toggleStyle(.switch)
                    }
                }
                Text("Mac Island ne remet en marche que le Bluetooth qu’il a coupé lui-même, et le rétablit aussi en quittant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SettingsRow(symbol: "dot.radiowaves.left.and.right", title: strings.pageTitle,
                            caption: "Indisponible : ce Mac n’a pas de contrôleur Bluetooth, ou macOS ne donne pas accès à son interrupteur.") {
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Page 23: Couper le micro

struct MicMutePage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @AppStorage(DefaultsKey.micMuteShortcutEnabled) private var shortcutEnabled = false

    var body: some View {
        SettingsCard(title: l10n.s.micMuteName) {
            Button {
                MicMuteService.shared.toggle()
            } label: {
                Label(micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                      systemImage: micMute.isMuted ? "mic.slash.fill" : "mic")
            }
            if micMute.isMuted {
                Label(l10n.s.micMutedHUD, systemImage: "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(l10n.s.micMuteCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                .toggleStyle(.switch)
                .onChange(of: shortcutEnabled) { _, _ in MicMuteService.shared.syncWithPreferences() }
            ShortcutPreferenceRow(role: .micMute, isEnabled: shortcutEnabled) {
                MicMuteService.shared.syncWithPreferences()
            }
            if shortcutEnabled, micMute.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("Le micro est rétabli quand Mac Island quitte. Pendant la coupure, l’île affiche « Micro coupé ».")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 19: Blocage de l'app Musique

struct MusicBlockPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var musicBlocker = MusicLaunchBlocker.shared
    @State private var replacementRejected = false
    @AppStorage(DefaultsKey.musicBlockEnabled) private var enabled = false
    @AppStorage(DefaultsKey.musicBlockReplacementPath) private var replacementPath = ""
    @AppStorage(DefaultsKey.musicBlockPlayReplacement) private var playReplacement = true

    var body: some View {
        SettingsCard(title: l10n.s.musicBlockSection) {
            SettingsRow(symbol: "playpause.fill", title: l10n.s.musicBlockTitle, caption: l10n.s.musicBlockCaption) {
                Toggle(l10n.s.musicBlockTitle, isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { _, _ in musicBlocker.syncWithPreferences() }
            }
            if enabled {
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility).padding(.leading, settingsRowTextInset)
                } else if !musicBlocker.isMonitoring {
                    Text(l10n.s.musicBlockUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
                HStack(spacing: 8) {
                    Text(l10n.s.musicBlockReplacementLabel)
                    Spacer()
                    Text(replacementName).foregroundStyle(.secondary)
                    Button(l10n.s.musicBlockChooseApp) { chooseReplacement() }
                    if !replacementPath.isEmpty {
                        Button {
                            replacementPath = ""
                            replacementRejected = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Retirer l’app de remplacement")
                    }
                }
                .padding(.leading, settingsRowTextInset)
                if !replacementPath.isEmpty {
                    Toggle(l10n.s.musicBlockPlayReplacement, isOn: $playReplacement)
                        .toggleStyle(.switch)
                        .padding(.leading, settingsRowTextInset)
                }
                if replacementRejected {
                    Text(l10n.s.musicBlockReplacementBlocked)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, settingsRowTextInset)
                }
            }
        }
    }

    private var replacementName: String {
        guard !replacementPath.isEmpty else { return l10n.s.musicBlockReplacementNone }
        return (FileManager.default.displayName(atPath: replacementPath) as NSString).deletingPathExtension
    }

    private func chooseReplacement() {
        replacementRejected = false
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Picking the blocked app itself would start a launch-and-kill loop.
        if let bundleID = Bundle(url: url)?.bundleIdentifier, MusicLaunchBlocker.blockedBundleIDs.contains(bundleID) {
            replacementRejected = true
            return
        }
        replacementPath = url.path
    }
}
