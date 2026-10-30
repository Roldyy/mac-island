import CoreAudio
import Foundation

/// Thin wrappers over the AudioObject property API. Main thread only; never used from the IOProc.
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result) == noErr else { return [] }
        return result
    }

    static func dataSize(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope) -> UInt32 {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var addr = address(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func int32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Int32? {
        var addr = address(selector)
        var value: Int32 = 0
        var size = UInt32(MemoryLayout<Int32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// CFString properties are returned retained (header: "the caller is responsible for releasing").
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &cf) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let cf else { return nil }
        return cf.takeRetainedValue() as String
    }

    @discardableResult
    static func setUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: UInt32) -> Bool {
        var addr = address(selector)
        var v = value
        return AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    /// Channel count of each stream of `object` in `scope` (kAudioDevicePropertyStreamConfiguration);
    /// nil when it cannot be read.
    static func streamChannels(_ object: AudioObjectID, scope: AudioObjectPropertyScope) -> [Int]? {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr else { return nil }
        guard size >= UInt32(MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size) else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw) == noErr else { return nil }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    /// The device object for a UID, or nil.
    static func deviceID(forUID uid: String) -> AudioObjectID? {
        ids(system, kAudioHardwarePropertyDevices).first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    /// Switch input streams of one IOProc on or off (kAudioDevicePropertyIOProcStreamUsage). The
    /// structure must list every input stream of the device.
    static func setInputStreamUsage(_ device: AudioObjectID, procID: AudioDeviceIOProcID,
                                    streamIsOn: [UInt32]) -> OSStatus {
        guard !streamIsOn.isEmpty else { return noErr }
        let header = MemoryLayout<AudioHardwareIOProcStreamUsage>.size
        let size = header + MemoryLayout<UInt32>.size * (streamIsOn.count - 1)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streamIsOn.count)
        let flags = (raw + MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!)
            .assumingMemoryBound(to: UInt32.self)
        for (k, on) in streamIsOn.enumerated() { flags[k] = on }
        var addr = address(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(size), raw)
    }
}
