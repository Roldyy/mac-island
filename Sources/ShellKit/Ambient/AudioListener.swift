import CoreAudio
import Foundation

/// One CoreAudio property listener: installed once, removed exactly once. The block runs on a private queue
/// and only hops to the main actor through `onChange`, so a listener never does work of its own.
final class AudioListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private var block: AudioObjectPropertyListenerBlock?

    /// Nil when the object does not have the property (some outputs have no volume control).
    init?(object: AudioObjectID, selector: AudioObjectPropertySelector,
          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
          queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        self.object = object
        self.queue = queue
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        self.address = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        guard AudioObjectAddPropertyListenerBlock(object, &self.address, queue, block) == noErr else { return nil }
        self.block = block
    }

    func remove() {
        guard let block else { return }
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        self.block = nil
    }

    deinit { remove() }
}

enum AudioDevices {
    static func defaultDevice(input: Bool) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// Some app is capturing from this device right now (any process, not only ours).
    static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Output volume 0...1: the main element, or the mean of the first two channels when the device has none.
    static func volume(_ device: AudioObjectID) -> Double? {
        var values: [Double] = []
        for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { values.append(Double(value)) }
            if element == kAudioObjectPropertyElementMain, !values.isEmpty { break }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func isMuted(_ device: AudioObjectID) -> Bool {
        for element in [kAudioObjectPropertyElementMain, 1] as [AudioObjectPropertyElement] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr { return muted != 0 }
        }
        return false
    }
}
