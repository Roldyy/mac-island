import Foundation
import Observation
import os

/// Keeps the default output and input on the highest-priority available device.
/// The one listener that stays on while the tab is hidden.
@MainActor @Observable
final class DevicePriorityController {
    private(set) var isRunning = false
    private(set) var outputPriority: [String]
    private(set) var inputPriority: [String]

    /// Forwarded after the controller handled an event (the feature model shares the one HAL listener).
    @ObservationIgnored var onEvent: (@MainActor (AudioSystemEvent) -> Void)?

    @ObservationIgnored private let system: AudioSystem
    @ObservationIgnored private let settings: AudioSettings
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let manualGrace: TimeInterval
    @ObservationIgnored private var lastManualChange: [AudioDirection: Date] = [:]
    @ObservationIgnored private var pendingOwn: [AudioDirection: String] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "be.roldy.macisland", category: "audio")

    init(system: AudioSystem, settings: AudioSettings,
         now: @escaping () -> Date = Date.init, manualGrace: TimeInterval = 10) {
        self.system = system
        self.settings = settings
        self.now = now
        self.manualGrace = manualGrace
        outputPriority = settings.priority(for: .output)
        inputPriority = settings.priority(for: .input)
    }

    func priority(for direction: AudioDirection) -> [String] {
        direction == .output ? outputPriority : inputPriority
    }

    func setPriority(_ uids: [String], for direction: AudioDirection) {
        settings.setPriority(uids, for: direction)
        let stored = settings.priority(for: direction)
        if direction == .output { outputPriority = stored } else { inputPriority = stored }
        if isRunning { evaluate(direction) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        system.startListening { [weak self] event in self?.handle(event) }
        rememberNames()
        evaluate(.output)
        evaluate(.input)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        system.stopListening()
        pendingOwn.removeAll()
    }

    func handle(_ event: AudioSystemEvent) {
        guard isRunning else { return }
        switch event {
        case .devicesChanged:
            rememberNames()
            evaluate(.output)
            evaluate(.input)
        case .defaultChanged(let direction):
            if let own = pendingOwn[direction], own == system.defaultDeviceUID(direction) {
                pendingOwn[direction] = nil // the echo of our own change
            } else {
                // A change we did not make: the user (or macOS reacting to a plug). Do not fight it for a while.
                lastManualChange[direction] = now()
                evaluate(direction)
            }
        case .processesChanged:
            break
        }
        onEvent?(event)
    }

    private func evaluate(_ direction: AudioDirection) {
        let available = system.devices().filter { $0.supports(direction) }.map(\.uid)
        guard let target = DevicePriorityResolver.resolve(
            available: available, priority: priority(for: direction),
            current: system.defaultDeviceUID(direction),
            lastManualChange: lastManualChange[direction], now: now(), grace: manualGrace
        ) else { return }
        pendingOwn[direction] = target
        if system.setDefaultDevice(uid: target, direction: direction) {
            log.info("default \(direction.rawValue, privacy: .public) switched by priority")
        } else {
            pendingOwn[direction] = nil
            log.error("default \(direction.rawValue, privacy: .public) switch failed")
        }
    }

    private func rememberNames() {
        let listed = Set(outputPriority + inputPriority)
        for device in system.devices() where listed.contains(device.uid) {
            settings.setDeviceName(device.name, for: device.uid)
        }
    }
}
