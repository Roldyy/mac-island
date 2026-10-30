import AppKit
import Foundation
import Observation
import os

/// Glue between the HAL, the priority controller, the mixer and the view.
/// Listeners: the HAL listener runs from `start()` (device priority needs it). Mixer work from
/// those events runs only while the tab is visible or a tap is live (teardown on app exit / device change).
/// The 2 s poll (for "is playing" changes, which have no listener here) runs only while visible.
@MainActor @Observable
final class AudioFeatureModel {
    let mixer: MixerModel
    let priority: DevicePriorityController
    private(set) var devices: [AudioDeviceInfo] = []
    private(set) var defaultOutput: String?
    private(set) var defaultInput: String?
    private(set) var permission: AudioPermission
    private(set) var isRunning = false
    private(set) var isVisible = false
    let deviceNames: () -> [String: String]

    @ObservationIgnored private let system: AudioSystem
    @ObservationIgnored private let hasUsageDescription: () -> Bool
    @ObservationIgnored private let probe: () -> Int32
    @ObservationIgnored private var probeResult: Int32?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: "be.roldy.macisland", category: "audio")

    init(system: AudioSystem, engine: MixerEngine, settings: AudioSettings,
         hasUsageDescription: @escaping () -> Bool = { AudioPermissionProbe.hasUsageDescription },
         probe: @escaping () -> Int32 = { AudioPermissionProbe.probe() }) {
        self.system = system
        self.hasUsageDescription = hasUsageDescription
        self.probe = probe
        mixer = MixerModel(engine: engine, system: system, settings: settings)
        priority = DevicePriorityController(system: system, settings: settings)
        permission = AudioPermission.resolve(hasUsageDescription: hasUsageDescription(), probe: nil)
        deviceNames = { settings.deviceNames }
        priority.onEvent = { [weak self] event in self?.didHandle(event) }
    }

    static func live() -> AudioFeatureModel {
        AudioFeatureModel(system: CoreAudioSystem(), engine: CoreAudioMixerEngine(), settings: .standard())
    }

    /// Idempotent.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        refreshDevices()
        priority.start()
        refreshDevices()
        if isVisible { mixer.refresh() }
    }

    /// Idempotent. Releases every tap and removes the listener.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        poll?.cancel()
        poll = nil
        priority.stop()
        mixer.stop()
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
        terminateObserver = nil
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        poll?.cancel()
        poll = nil
        guard visible, isRunning else { return }
        refreshAll()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.refreshAll()
            }
        }
    }

    func requestPermission() {
        guard permission.canRequest else { return }
        probeResult = probe()
        permission = AudioPermission.resolve(hasUsageDescription: hasUsageDescription(), probe: probeResult)
        log.info("permission probe done")
        if isVisible { mixer.refresh() }
    }

    func setDefault(uid: String, direction: AudioDirection) {
        system.setDefaultDevice(uid: uid, direction: direction)
    }

    private func didHandle(_ event: AudioSystemEvent) {
        refreshDevices()
        guard isVisible || mixer.hasLiveTaps else { return }
        mixer.refresh()
    }

    private func refreshAll() {
        refreshDevices()
        mixer.refresh()
    }

    private func refreshDevices() {
        let list = system.devices()
        if list != devices { devices = list }
        defaultOutput = system.defaultDeviceUID(.output)
        defaultInput = system.defaultDeviceUID(.input)
    }
}
