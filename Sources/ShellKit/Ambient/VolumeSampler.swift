import CoreAudio
import Foundation
import IslandKit

/// The volume bar: when the system volume or mute changes, the pill shows a bar and the percentage for 1,5 s
/// as a pinned item, then goes back to what it showed. Event driven: CoreAudio listeners on the default output
/// device's volume and mute (and on the default-device property, which re-attaches them silently). Nothing runs
/// between two key presses. An output with no volume control (some HDMI and DisplayPort monitors) never fires.
///
/// Brightness has no public change notification (the display services that report it are private), so it is not
/// shown.
@MainActor
public final class VolumeSampler: AmbientSampler {
    public let channel = AmbientChannel.volume
    public static let hold: Duration = .milliseconds(1500)

    private let center: AmbientCenter
    private let sleep: @Sendable (Duration) async throws -> Void
    private let queue = DispatchQueue(label: "be.roldy.macisland.volume", qos: .utility)
    private var listeners: [AudioListener] = []
    private var defaultListener: AudioListener?
    private var hide: Task<Void, Never>?
    private var last: (percent: Int, muted: Bool)?
    private var active = false

    /// `read` gives the current level and mute of the default output; a test replaces it.
    private let read: @MainActor () -> (percent: Int, muted: Bool)?

    public init(center: AmbientCenter, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.center = center
        self.sleep = sleep
        self.read = {
            guard let device = AudioDevices.defaultDevice(input: false) else { return nil }
            return VolumeSampler.reading(device)
        }
    }

    init(center: AmbientCenter, sleep: @escaping @Sendable (Duration) async throws -> Void,
         read: @escaping @MainActor () -> (percent: Int, muted: Bool)?) {
        self.center = center
        self.sleep = sleep
        self.read = read
    }

    public var isListening: Bool { active }

    public func start(settings: ClosedIslandSettings) {
        guard !active else { return }
        active = true
        defaultListener = AudioListener(
            object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice, queue: queue
        ) { [weak self] in
            Task { @MainActor in self?.attach() }
        }
        attach()
    }

    public func stop() {
        active = false
        hide?.cancel()
        hide = nil
        detach()
        defaultListener?.remove()
        defaultListener = nil
        center.withdraw(id: AmbientReadings.volumeID)
    }

    private func detach() {
        for listener in listeners { listener.remove() }
        listeners = []
    }

    /// Listens to the current output device and takes its level as the baseline, without showing anything.
    private func attach() {
        guard active else { return }
        detach()
        guard let device = AudioDevices.defaultDevice(input: false) else { last = nil; return }
        let notify: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.changed() }
        }
        let main = kAudioObjectPropertyElementMain
        let targets: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioDevicePropertyVolumeScalar, main), (kAudioDevicePropertyVolumeScalar, 1), (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, main), (kAudioDevicePropertyMute, 1),
        ]
        for (selector, element) in targets {
            if let listener = AudioListener(object: device, selector: selector, scope: kAudioObjectPropertyScopeOutput,
                                            element: element, queue: queue, onChange: notify) {
                listeners.append(listener)
            }
        }
        last = read()
    }

    fileprivate static func reading(_ device: AudioObjectID) -> (percent: Int, muted: Bool)? {
        guard let level = AudioDevices.volume(device) else { return nil }
        return (Int((min(max(level, 0), 1) * 100).rounded()), AudioDevices.isMuted(device))
    }

    /// The baseline when the sampler attaches, without a bar: tests drive `changed()` after it.
    func baseline() { last = read() }

    func changed() {
        guard active, let now = read() else { return }
        // A stepped key press fires several callbacks for one change: only a different value shows the bar.
        guard last?.percent != now.percent || last?.muted != now.muted else { return }
        last = now
        center.post(AmbientReadings.volume(level: Double(now.percent) / 100, muted: now.muted))
        hide?.cancel()
        let sleep = self.sleep
        hide = Task { [weak self] in
            do { try await sleep(Self.hold) } catch { return }
            guard !Task.isCancelled else { return }
            self?.center.withdraw(id: AmbientReadings.volumeID)
        }
    }
}
