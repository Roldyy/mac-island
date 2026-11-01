import CoreAudio
import Foundation
import IslandKit

/// An orange mic indicator while any app captures from the default input device. Event driven: a CoreAudio
/// listener on `kAudioDevicePropertyDeviceIsRunningSomewhere` (and on the default-device property, to follow a
/// change of microphone). It reads a flag; it never opens the device, so macOS asks for no permission.
@MainActor
public final class MicSampler: AmbientSampler {
    public let channel = AmbientChannel.mic

    private let center: AmbientCenter
    private let queue = DispatchQueue(label: "be.roldy.macisland.mic", qos: .utility)
    private var deviceListener: AudioListener?
    private var defaultListener: AudioListener?
    private var active = false

    public init(center: AmbientCenter) { self.center = center }

    public var isListening: Bool { active }

    public func start(settings: ClosedIslandSettings) {
        guard !active else { return }
        active = true
        defaultListener = AudioListener(
            object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultInputDevice, queue: queue
        ) { [weak self] in
            Task { @MainActor in self?.attach() }
        }
        attach()
    }

    public func stop() {
        active = false
        deviceListener?.remove()
        deviceListener = nil
        defaultListener?.remove()
        defaultListener = nil
    }

    private func attach() {
        guard active else { return }
        deviceListener?.remove()
        deviceListener = nil
        guard let device = AudioDevices.defaultDevice(input: true) else {
            center.withdraw(id: AmbientReadings.micID)
            return
        }
        deviceListener = AudioListener(object: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere, queue: queue) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        guard active, let device = AudioDevices.defaultDevice(input: true) else { return }
        if AudioDevices.isRunningSomewhere(device) { center.post(AmbientReadings.mic()) } else { center.withdraw(id: AmbientReadings.micID) }
    }
}
