import Foundation
import Observation
import os

/// State of the mixer: which apps exist, their position and mute, and which taps are live.
/// Pure logic over `AudioSystem` + `MixerEngine`.
///
/// Safety rule: an app at full volume and unmuted has NO tap, so its audio is never touched. A tap
/// exists only while the user asked for something AND capture is authorised (creating a tap is what
/// triggers the system prompt, which may only come from the permission button), and every exit path (`stop`, app exit, no output
/// device, device change, failure) releases it.
@MainActor @Observable
final class MixerModel {
    private(set) var apps: [MixerApp] = []
    private(set) var failedTapCount = 0

    var hasLiveTaps: Bool { !live.isEmpty }

    private struct Target: Equatable {
        var processIDs: [UInt32]
        var output: String
    }

    private struct Group {
        var name: String
        var pid: Int32
        var processIDs: [UInt32]
        var visible: Bool
    }

    @ObservationIgnored private let engine: MixerEngine
    @ObservationIgnored private let system: AudioSystem
    @ObservationIgnored private let settings: AudioSettings
    @ObservationIgnored private let ownPID: Int32
    @ObservationIgnored private var positions: [String: Double]
    @ObservationIgnored private var muted: Set<String>
    @ObservationIgnored private var live: [String: Target] = [:]
    @ObservationIgnored private var liveGain: [String: Float] = [:]
    @ObservationIgnored private var failed: [String: Target] = [:]
    @ObservationIgnored private var groups: [String: Group] = [:]
    @ObservationIgnored private var output: String?
    @ObservationIgnored private let log = Logger(subsystem: "be.roldy.macisland", category: "audio")

    /// Taps start only while this says capture is authorised (`AudioPermission.ready`): creating one
    /// is what makes the system show its capture prompt, which may only come from the button.
    @ObservationIgnored private let isCaptureReady: () -> Bool

    init(engine: MixerEngine, system: AudioSystem, settings: AudioSettings,
         ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
         isCaptureReady: @escaping () -> Bool = { false }) {
        self.isCaptureReady = isCaptureReady
        self.engine = engine
        self.system = system
        self.settings = settings
        self.ownPID = ownPID
        var positions = settings.appPositions
        var muted = settings.mutedApps
        // A migrated 0.0 is not a request for silence through a hidden gain-0 tap: show it as an
        // explicit mute (visible row, one click to undo) with the slider back at full.
        for (id, position) in positions where position <= 0 {
            positions[id] = 1
            muted.insert(id)
            settings.setPosition(1, for: id)
            settings.setMuted(true, for: id)
        }
        self.positions = positions
        self.muted = muted
    }

    /// Re-read the process list and the default output, then reconcile taps with the wanted state.
    func refresh() {
        output = system.defaultDeviceUID(.output)
        var byBundle: [String: [AudioProcess]] = [:]
        for p in system.processes() where !p.bundleID.isEmpty && p.pid != ownPID {
            byBundle[p.bundleID, default: []].append(p)
        }
        var next: [String: Group] = [:]
        for (id, ps) in byBundle {
            let visible = ps.contains(where: \.isRunningOutput) || live[id] != nil || isControlled(id)
            next[id] = Group(name: ps.first(where: \.isRunningOutput)?.name ?? ps[0].name,
                             pid: ps[0].pid, processIDs: ps.map(\.objectID).sorted(), visible: visible)
        }
        groups = next

        for id in Array(live.keys) where next[id] == nil || output == nil {
            release(id)
        }
        failed = failed.filter { next[$0.key] != nil }
        for (id, group) in next where group.visible { reconcile(id) }
        rebuild()
    }

    func setPosition(_ position: Double, for id: String) {
        let p = min(max(position, 0), 1)
        guard positions[id] != p else { return }
        positions[id] = p
        settings.setPosition(p, for: id)
        reconcile(id)
        rebuild()
    }

    func setMuted(_ isMuted: Bool, for id: String) {
        guard muted.contains(id) != isMuted else { return }
        if isMuted { muted.insert(id) } else { muted.remove(id) }
        settings.setMuted(isMuted, for: id)
        reconcile(id)
        rebuild()
    }

    /// Release every tap. Idempotent. Safe to call from quit, stop and deinit paths.
    func stop() {
        engine.stopAll()
        live.removeAll()
        liveGain.removeAll()
        rebuild()
    }

    // MARK: Internals

    private func position(_ id: String) -> Double { positions[id] ?? 1 }

    private func isControlled(_ id: String) -> Bool { muted.contains(id) || position(id) < 1 }

    private func currentGain(_ id: String) -> Float {
        muted.contains(id) ? 0 : VolumeCurve.gain(forPosition: position(id))
    }

    private func release(_ id: String) {
        engine.stop(app: id)
        live[id] = nil
        liveGain[id] = nil
    }

    private func reconcile(_ id: String) {
        guard let group = groups[id], let output, isControlled(id), isCaptureReady() else {
            if live[id] != nil { release(id) }
            return
        }
        let target = Target(processIDs: group.processIDs, output: output)
        let gain = currentGain(id)
        if let current = live[id] {
            if current == target {
                if liveGain[id] != gain {
                    engine.setGain(gain, app: id)
                    liveGain[id] = gain
                }
                return
            }
            release(id)
        }
        if failed[id] == target { return } // same inputs failed already: do not retry on every refresh
        do {
            try engine.start(app: id, processes: target.processIDs, outputDeviceUID: output, gain: gain)
            live[id] = target
            liveGain[id] = gain
            failed[id] = nil
        } catch {
            failed[id] = target
            failedTapCount += 1
            log.error("tap start failed, total \(self.failedTapCount)")
        }
    }

    private func rebuild() {
        let list = groups.compactMap { id, g -> MixerApp? in
            guard g.visible else { return nil }
            return MixerApp(id: id, name: g.name, pid: g.pid, processIDs: g.processIDs,
                            position: position(id), isMuted: muted.contains(id), isLive: live[id] != nil)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if list != apps { apps = list }
        log.debug("mixer apps \(list.count) live \(self.live.count)")
    }
}
