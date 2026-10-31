import CoreAudio
import CoreGraphics
import Darwin
import Foundation

/// A 0...1 level the Home sliders can read and write. Closures so tests inject a fake.
public struct LevelBackend: Sendable {
    public var read: @Sendable () -> Double?
    public var write: @Sendable (Double) -> Bool
    /// Short French line shown when the level cannot be read or set.
    public var unavailableReason: String

    public init(read: @escaping @Sendable () -> Double?, write: @escaping @Sendable (Double) -> Bool,
                unavailableReason: String) {
        self.read = read
        self.write = write
        self.unavailableReason = unavailableReason
    }

    /// A slider that exists on screen but cannot act: dimmed, with the reason.
    public static func unsupported(_ reason: String) -> LevelBackend {
        LevelBackend(read: { nil }, write: { _ in false }, unavailableReason: reason)
    }
}

/// Output volume of the default CoreAudio device. No permission, no prompt.
public enum SystemVolume {
    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`: the level the volume keys move.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663  // 'vmvc'

    public static let backend = LevelBackend(
        read: { read() }, write: { write($0) }, unavailableReason: "Volume indisponible sur cette sortie")

    private static func defaultOutput() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func address(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: virtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    static func read() -> Double? {
        guard let device = defaultOutput() else { return nil }
        var address = address(kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
        return Double(min(max(value, 0), 1))
    }

    static func write(_ level: Double) -> Bool {
        guard let device = defaultOutput() else { return false }
        var address = address(kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(min(max(level, 0), 1))
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}

/// Brightness of the built-in display through the private DisplayServices framework, loaded at runtime
/// like the Display feature does (symbols resolved with dlsym; any miss means "indisponible").
public enum SystemBrightness {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let functions: (get: GetFn?, set: SetFn?) = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return (nil, nil)
        }
        return (dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) },
                dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) })
    }()

    public static let backend = LevelBackend(
        read: { read() }, write: { write($0) }, unavailableReason: "Pas d'écran intégré réglable")

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func read() -> Double? {
        guard let get = functions.get, let id = builtInDisplay() else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0, value.isFinite else { return nil }
        return Double(min(1, max(0, value)))
    }

    static func write(_ level: Double) -> Bool {
        guard let set = functions.set, let id = builtInDisplay() else { return false }
        return set(id, Float(min(1, max(0, level)))) == 0
    }
}
