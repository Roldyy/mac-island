// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W2B (mixer). The lane owns this file.

import AppKit
import CoreAudio
import IslandKit
import SwiftUI

// MARK: - Permission: System Audio Recording

/// What is known about the System Audio Recording permission (TCC `kTCCServiceAudioCapture`) without asking.
///
/// macOS has no public call that reads it. The only evidence is the outcome of creating a process tap, which is also
/// what makes macOS show its prompt, so Mac Island creates one tap, destroys it at once and stores the status, and
/// does that only from a click on "Autoriser" (`MixerAudioCapture.requestByClick`). Everything else reads the stored
/// status: the probe never prompts. Until the click has run, no per-app tap exists at all (patch 0450).
enum MixerAudioCaptureState: Equatable {
    /// The running bundle has no `NSAudioCaptureUsageDescription` (`swift run`): the system cannot ask.
    case needsBundledApp
    /// Never asked by a click, or the stored status is unreadable.
    case notAsked
    /// The last probe tap was created.
    case granted
    /// The last probe tap failed with this `OSStatus`.
    case denied(Int32)

    /// Per-app taps (and so the prompt) are allowed only once a click proved the grant.
    var allowsTaps: Bool { self == .granted }

    /// The permission to give, named as the system pane names it, nil when nothing is missing.
    var missingPermission: String? {
        self == .granted ? nil : "Enregistrement audio du système"
    }

    /// Why the per-app volume cannot work yet, in French. Nil when it can.
    var reason: String? {
        switch self {
        case .needsBundledApp:
            return "Volume par app indisponible : cette version n’est pas l’app signée (aucune description de capture audio). Lancez l’app installée, pas « swift run »."
        case .notAsked:
            return "Volume par app : l’autorisation « Enregistrement audio du système » n’a pas encore été demandée. Cliquez sur Autoriser."
        case .denied(let status):
            return "Volume par app : « Enregistrement audio du système » est refusé (code \(status)). Cliquez sur Autoriser puis cochez Mac Island dans Réglages Système > Confidentialité et sécurité."
        case .granted:
            return nil
        }
    }

    /// True when a click on "Autoriser" can still change something.
    var canRequest: Bool {
        switch self {
        case .notAsked, .denied: true
        case .needsBundledApp, .granted: false
        }
    }
}

enum MixerAudioCapture {
    /// `OSStatus` of the last probe tap, in the host's defaults. Written by the click path only.
    static let evidenceKey = "macisland.mixer.audioCaptureProbeStatus"

    /// Pure: the state for a stored status and the bundle's description.
    static func state(evidence: Int?, hasUsageDescription: Bool) -> MixerAudioCaptureState {
        guard hasUsageDescription else { return .needsBundledApp }
        guard let evidence, let status = Int32(exactly: evidence) else { return .notAsked }
        return status == 0 ? .granted : .denied(status)
    }

    static let hasUsageDescription: Bool = {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String
        return !(value ?? "").isEmpty
    }()

    /// Reads the stored evidence. Never asks, never touches Core Audio.
    static func currentState(defaults: UserDefaults = PortHost.defaults,
                             hasUsageDescription: Bool = MixerAudioCapture.hasUsageDescription) -> MixerAudioCaptureState {
        state(evidence: defaults.object(forKey: evidenceKey) as? Int, hasUsageDescription: hasUsageDescription)
    }

    /// What `AppVolumeMixer` asks before it builds a tap (patch 0450).
    static var allowsTaps: Bool { currentState().allowsTaps }

    /// Creates one global tap and destroys it: the public trigger that makes macOS list Mac Island under
    /// "Enregistrement audio du système" and ask. Unmuted and private, so it changes no sound. ONLY from a click.
    static func probeTap() -> Int32 {
        guard #available(macOS 14.2, *) else { return -1 }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Mac Island permission probe"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        if status == noErr { AudioHardwareDestroyProcessTap(tapID) }
        return status
    }

    /// The "Autoriser" click. Behind the feature switch (`isAvailable`): with the mixer off nothing is asked. A
    /// grant restarts the per-app taps; a refusal opens the pane. Every dependency is injectable for the tests.
    @MainActor @discardableResult
    static func requestByClick(defaults: UserDefaults = PortHost.defaults,
                               hasUsageDescription: Bool = MixerAudioCapture.hasUsageDescription,
                               isAvailable: () -> Bool = { AppFeature.mixer.isAvailable },
                               probe: () -> Int32 = MixerAudioCapture.probeTap,
                               openPane: () -> Void = { Permissions.shared.openAudioCaptureSettings() },
                               didGrant: () -> Void = { AppVolumeMixer.shared.refreshApps() }) -> MixerAudioCaptureState {
        guard isAvailable() else { return currentState(defaults: defaults, hasUsageDescription: hasUsageDescription) }
        guard hasUsageDescription else {
            return currentState(defaults: defaults, hasUsageDescription: false)
        }
        let status = probe()
        defaults.set(Int(status), forKey: evidenceKey)
        let now = currentState(defaults: defaults, hasUsageDescription: hasUsageDescription)
        if now.allowsTaps { didGrant() } else { openPane() }
        return now
    }
}

// MARK: - Safety: output switch guard, AirPlay probe, volume math

/// A device the mixer is about to make the system default must still exist. The mixer lists devices from a HAL
/// snapshot that can be a few hundred milliseconds old, so a device unplugged since is re-checked right before the
/// write (patch 0452) and the write is refused when it is gone, not an output, or cannot be the default.
enum MixerOutputSwitchGuard {
    /// What a live read of the device said. `isAlive` is nil when the device does not answer that property (some
    /// virtual devices do not): then the streams decide, as the mixer's own device list does.
    struct Reading: Equatable {
        var isAlive: Bool?
        var hasOutputStreams: Bool
        var canBeDefault: Bool

        init(isAlive: Bool?, hasOutputStreams: Bool, canBeDefault: Bool) {
            self.isAlive = isAlive
            self.hasOutputStreams = hasOutputStreams
            self.canBeDefault = canBeDefault
        }
    }

    static func allows(_ reading: Reading) -> Bool {
        reading.isAlive != false && reading.hasOutputStreams && reading.canBeDefault
    }
}

/// AirPlay per-app routing uses a private class (`AVOutputContext`); the upstream manager only enables it on
/// macOS 27 and fails closed. This only words the reason for the page.
enum MixerAirPlayProbe {
    static let minimumMajor = 27

    static func unavailableReason(osMajor: Int, managerAvailable: Bool?) -> String? {
        if osMajor < minimumMajor {
            return "AirPlay par app : indisponible avant macOS \(minimumMajor) (routage privé d’Apple, laissé éteint)."
        }
        if managerAvailable == false {
            return "AirPlay par app : le routage système n’a pas répondu sur ce Mac, la fonction reste éteinte."
        }
        return nil
    }
}

/// The 0 to 200 % slider, kept in one place so tests and the page agree: a stored value is a slider position, the
/// gain squares below 100 % and is linear above, and nothing leaves 0...2.
enum MixerVolumeMath {
    static let range: ClosedRange<Double> = 0...AppVolumeMixer.maxVolume

    static func clamped(_ volume: Double) -> Double { Defaults.sanitizedAppVolume(volume) }

    static func percent(forVolume volume: Double) -> Int { MixerRoutingSupport.displayPercent(forVolume: clamped(volume)) }

    static func gain(forVolume volume: Double) -> Float { MixerRoutingSupport.gain(forVolume: clamped(volume)) }
}

// MARK: - Stale aggregate devices

/// Every tap the mixer builds comes with a PRIVATE aggregate device named with one of these prefixes. A private
/// aggregate belongs to the process that made it and the HAL drops it when that process dies, but a crash inside
/// the HAL or a wedged teardown is exactly the case nobody has measured, so the launch sweep destroys any aggregate
/// of ours that is still listed, by name prefix. UNVERIFIED on a real crash: the sweep is a safety net.
protocol MixerHAL {
    /// Every aggregate device the HAL lists: (object id, name).
    func aggregateDevices() -> [(id: UInt32, name: String)]
    /// True when the device is gone afterwards.
    func destroyAggregate(_ id: UInt32) -> Bool
}

enum MixerStaleAggregateSweeper {
    /// The names `AppVolumeMixer` gives its aggregates (device engine, AirPlay engine). The recorder and the island
    /// level meter name theirs differently and belong to other lanes.
    static let namePrefixes = ["Mac Island Mixer", "Mac Island AirPlay"]

    static func isOurs(_ name: String) -> Bool { namePrefixes.contains { name.hasPrefix($0) } }

    /// Destroys the stale aggregates of ours and returns the names it removed. Anything else is left alone.
    @discardableResult
    static func sweep(hal: any MixerHAL) -> [String] {
        var removed: [String] = []
        for device in hal.aggregateDevices() where isOurs(device.name) {
            if hal.destroyAggregate(device.id) { removed.append(device.name) }
        }
        return removed
    }
}

/// The real HAL. Reading the device list and each device's class and name never prompts.
struct CoreAudioMixerHAL: MixerHAL {
    func aggregateDevices() -> [(id: UInt32, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard Self.classID(of: id) == kAudioAggregateDeviceClassID, let name = Self.name(of: id) else { return nil }
            return (id, name)
        }
    }

    func destroyAggregate(_ id: UInt32) -> Bool {
        AudioHardwareDestroyAggregateDevice(id) == noErr
    }

    private static func classID(of object: AudioObjectID) -> AudioClassID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyClass,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: AudioClassID = 0
        var size = UInt32(MemoryLayout<AudioClassID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func name(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value as String : nil
    }
}

// MARK: - Legacy settings

/// The retired `AudioFeature` kept a per-app mute set under `mixerMutedApps` (the Vorssaint data had no mute key).
/// The port mutes by volume 0, so each muted app becomes volume 0 once and the old key goes away. A slider position
/// the user already set to something else for that app is left as it is.
enum MixerLegacySettings {
    static let mutedAppsKey = "mixerMutedApps"

    @discardableResult
    static func migrateMutedApps(in defaults: UserDefaults) -> [String] {
        guard let muted = defaults.array(forKey: mutedAppsKey) as? [String] else { return [] }
        var volumes = defaults.dictionary(forKey: DefaultsKey.appVolumes) ?? [:]
        var changed: [String] = []
        for id in muted where !id.isEmpty && volumes[id] == nil {
            volumes[id] = 0.0
            changed.append(id)
        }
        if !changed.isEmpty { defaults.set(volumes, forKey: DefaultsKey.appVolumes) }
        defaults.removeObject(forKey: mutedAppsKey)
        return changed
    }
}

// MARK: - Lane

/// Binds the three ported audio features: the volume mixer (replaces our `audio` module under the same registry id
/// and island tab), the output switcher and the audio device priority. Called once at launch by `PortLanes`.
///
/// What the registry does to each, all through `Runtime` so tests never touch Core Audio:
/// - `mixer` starts the precise volume roller, the per-app mixer (device watching, process watching, taps built only
///   once the click path proved System Audio Recording) and the microphone manager, after a once-per-launch sweep of
///   stale aggregate devices. It stops by tearing every tap down first, then re-syncing the three services, which
///   now read the feature as unavailable and fall back to what the sibling features need.
/// - `soundOutputSwitcher` registers its global key; `audioPriority` runs the priority policy. Both share the
///   mixer's device observation (`AppVolumeMixer.syncWithPreferences` watches devices when any of the three runs).
///
/// Nothing here prompts. The one prompt-capable call is `MixerAudioCapture.probeTap`, reachable only from a click.
enum MixerLane {
    struct Runtime {
        /// Once per launch, off the main thread, before the first tap can exist; then `done` runs on the main actor.
        var sweepStaleAggregates: @MainActor (@escaping @MainActor () -> Void) -> Void
        var migrateLegacySettings: @MainActor () -> Void
        var syncRoller: @MainActor () -> Void
        var syncMixer: @MainActor () -> Void
        var syncInput: @MainActor () -> Void
        var syncSwitcher: @MainActor () -> Void
        var stopSwitcher: @MainActor () -> Void
        var syncPriority: @MainActor () -> Void
        /// Tears every per-app tap down whatever the preferences say.
        var stopAllTaps: @MainActor () -> Void
        /// Re-reads what depends on app activation and quits cleanly (live: two observers; fake: records).
        var watchApp: @MainActor () -> Void
        var unwatchApp: @MainActor () -> Void

        static let live: Runtime = {
            let watcher = LiveAppWatcher()
            return Runtime(
                sweepStaleAggregates: { done in LiveSweep.run(done) },
                migrateLegacySettings: { MixerLegacySettings.migrateMutedApps(in: PortHost.defaults) },
                syncRoller: { PreciseVolumeRollerService.shared.syncWithPreferences() },
                syncMixer: { AppVolumeMixer.shared.syncWithPreferences() },
                syncInput: { AudioInputDeviceManager.shared.syncWithPreferences() },
                syncSwitcher: { SoundOutputSwitcher.shared.syncWithPreferences() },
                stopSwitcher: { SoundOutputSwitcher.shared.stop() },
                syncPriority: { AudioPriorityService.shared.syncWithPreferences() },
                stopAllTaps: { AppVolumeMixer.shared.stopAll() },
                watchApp: { watcher.install() },
                unwatchApp: { watcher.remove() })
        }()
    }

    /// Upstream feature id -> our Settings page id (`SettingsPageCatalog`, rows 20, 21, 22).
    static let pageIDs: [String: String] = [
        "mixer": "mixer", "soundOutputSwitcher": "outputswitch", "audioPriority": "audiopriority",
    ]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bindReplacing(
            "mixer", page: PortFeaturePage(pageID: "mixer") { AnyView(MixerPage()) },
            start: { [weak binding] in
                runtime.migrateLegacySettings()
                runtime.sweepStaleAggregates {
                    // The feature may have been stopped while the sweep ran: then it must stay stopped.
                    guard binding?.isStarted(AppFeature.mixer.registryID) == true else { return }
                    runtime.syncRoller()
                    runtime.syncMixer()
                    runtime.syncInput()
                    runtime.watchApp()
                }
            },
            stop: {
                runtime.unwatchApp()
                runtime.stopAllTaps()  // taps first: the sound goes back to the real output before anything else
                runtime.syncRoller()
                runtime.syncMixer()
                runtime.syncInput()
            })
        binding.bind(
            "soundOutputSwitcher", page: PortFeaturePage(pageID: "outputswitch") { AnyView(OutputSwitcherPage()) },
            start: {
                runtime.syncMixer()
                runtime.syncSwitcher()
            },
            stop: {
                runtime.stopSwitcher()
                runtime.syncMixer()
            })
        binding.bind(
            "audioPriority", page: PortFeaturePage(pageID: "audiopriority") { AnyView(AudioPriorityPage()) },
            start: {
                runtime.syncMixer()
                runtime.syncInput()
                runtime.syncPriority()
            },
            stop: {
                runtime.syncPriority()
                runtime.syncInput()
                runtime.syncMixer()
            })
    }
}

/// The two app-level watches of the mixer: coming back to the app re-reads the roller's Accessibility gate (the
/// monitor does not restart this feature on an Accessibility grant), and quitting tears every tap down.
private final class LiveAppWatcher: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    @MainActor func install() {
        guard tokens.isEmpty else { return }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                         queue: .main) { _ in
            MainActor.assumeIsolated { PreciseVolumeRollerService.shared.syncWithPreferences() }
        })
        tokens.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                         queue: .main) { _ in
            MainActor.assumeIsolated { AppVolumeMixer.shared.stopAll() }
        })
    }

    @MainActor func remove() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens = []
    }
}

/// The launch sweep: once per process, on a utility queue, then back on the main actor.
private enum LiveSweep {
    private nonisolated(unsafe) static var done = false
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "be.roldy.macisland.mixer.sweep", qos: .utility)

    @MainActor static func run(_ finished: @escaping @MainActor () -> Void) {
        lock.lock()
        let already = done
        done = true
        lock.unlock()
        guard !already else {
            finished()
            return
        }
        queue.async {
            MixerStaleAggregateSweeper.sweep(hal: CoreAudioMixerHAL())
            DispatchQueue.main.async { MainActor.assumeIsolated { finished() } }
        }
    }
}

// MARK: - Island tab

/// The island's "Mixer" tab (id `audio`, kept): the ported panel section, hosted with the island presentation.
public enum PortMixer {
    /// The "Autoriser" click for System Audio Recording (`UserPermissionRequest.audioCaptureRequest`): one probe
    /// tap, only with the mixer switched on, then the pane when the system refuses. Never called outside a click.
    @MainActor public static func requestAudioCaptureByClick() {
        MixerAudioCapture.requestByClick()
    }

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "audio", title: "Mixer", systemImage: "slider.vertical.3") {
            AnyView(MixerIslandTab())
        }
    }
}

private struct MixerIslandTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                MixerPermissionNotice()
                MixerSection(collapsible: false)
            }
            .padding(10)
        }
        .environment(\.notchPresentation, true)
        .environment(\.colorScheme, .dark)
        .defaultAppStorage(PortHost.defaults)
    }
}

// MARK: - Pages (settings 20, 21, 22)

/// Page 20: the upstream mixer card (device pickers, per-app sliders, options), under the permission notice.
private struct MixerPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MixerPermissionNotice()
            MixerSection(settingsMode: true)
            if let airplay = MixerAirPlayProbe.unavailableReason(
                osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion, managerAvailable: nil) {
                Text(airplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Page 21.
private struct OutputSwitcherPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        SettingsCard(title: l10n.s.soundOutputSwitcherTitle) {
            SoundOutputSwitcherControls()
        }
    }
}

/// Page 22.
private struct AudioPriorityPage: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        SettingsCard(title: l10n.s.audioPrioritySection) {
            AudioPriorityDisclosure(initiallyExpanded: true, showsHeader: false)
        }
    }
}

/// What is missing for the per-app volume, with the click that asks. Reads the stored status only.
private struct MixerPermissionNotice: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @State private var state = MixerAudioCapture.currentState()

    var body: some View {
        Group {
            if let reason = state.reason {
                VStack(alignment: .leading, spacing: 6) {
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.canRequest {
                        Button("Autoriser") {
                            state = MixerAudioCapture.requestByClick()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear { state = MixerAudioCapture.currentState() }
        .onChange(of: mixer.needsPermission) { _, _ in state = MixerAudioCapture.currentState() }
    }
}
