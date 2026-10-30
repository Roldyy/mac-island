import AppKit
import CoreAudio
import Foundation

/// The real HAL. Listeners are blocks on the main queue, so the handler runs on the main thread.
final class CoreAudioSystem: AudioSystem {
    /// Our private aggregates never show up as selectable devices.
    static let aggregatePrefix = "be.roldy.macisland.mixer."

    private struct Registration {
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }
    private var registrations: [Registration] = []

    deinit { stopListening() }

    func devices() -> [AudioDeviceInfo] {
        HAL.ids(HAL.system, kAudioHardwarePropertyDevices).compactMap { id in
            guard let uid = HAL.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(Self.aggregatePrefix) else { return nil }
            let hasOut = HAL.dataSize(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) > 0
            let hasIn = HAL.dataSize(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput) > 0
            guard hasOut || hasIn else { return nil }
            return AudioDeviceInfo(uid: uid, name: HAL.string(id, kAudioObjectPropertyName) ?? uid,
                                   hasOutput: hasOut, hasInput: hasIn)
        }
    }

    func defaultDeviceUID(_ direction: AudioDirection) -> String? {
        let selector = direction == .output ? kAudioHardwarePropertyDefaultOutputDevice
                                            : kAudioHardwarePropertyDefaultInputDevice
        guard let id = HAL.uint32(HAL.system, selector), id != kAudioObjectUnknown else { return nil }
        return HAL.string(id, kAudioDevicePropertyDeviceUID)
    }

    @discardableResult
    func setDefaultDevice(uid: String, direction: AudioDirection) -> Bool {
        guard let id = HAL.ids(HAL.system, kAudioHardwarePropertyDevices).first(where: {
            HAL.string($0, kAudioDevicePropertyDeviceUID) == uid
        }) else { return false }
        let selector = direction == .output ? kAudioHardwarePropertyDefaultOutputDevice
                                            : kAudioHardwarePropertyDefaultInputDevice
        return HAL.setUInt32(HAL.system, selector, id)
    }

    func processes() -> [AudioProcess] {
        HAL.ids(HAL.system, kAudioHardwarePropertyProcessObjectList).compactMap { id in
            guard let pid = HAL.int32(id, kAudioProcessPropertyPID),
                  let bundle = HAL.string(id, kAudioProcessPropertyBundleID), !bundle.isEmpty else { return nil }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundle
            let running = (HAL.uint32(id, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0
            return AudioProcess(objectID: id, pid: pid, bundleID: bundle, name: name, isRunningOutput: running)
        }
    }

    func startListening(_ handler: @escaping @MainActor (AudioSystemEvent) -> Void) {
        stopListening()
        let table: [(AudioObjectPropertySelector, AudioSystemEvent)] = [
            (kAudioHardwarePropertyDevices, .devicesChanged),
            (kAudioHardwarePropertyDefaultOutputDevice, .defaultChanged(.output)),
            (kAudioHardwarePropertyDefaultInputDevice, .defaultChanged(.input)),
            (kAudioHardwarePropertyProcessObjectList, .processesChanged),
        ]
        for (selector, event) in table {
            var address = HAL.address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in
                MainActor.assumeIsolated { handler(event) } // delivered on DispatchQueue.main
            }
            if AudioObjectAddPropertyListenerBlock(HAL.system, &address, DispatchQueue.main, block) == noErr {
                registrations.append(Registration(address: address, block: block))
            }
        }
    }

    func stopListening() {
        for var r in registrations {
            AudioObjectRemovePropertyListenerBlock(HAL.system, &r.address, DispatchQueue.main, r.block)
        }
        registrations.removeAll()
    }
}
