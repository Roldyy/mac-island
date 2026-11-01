import CoreMediaIO
import Foundation
import IslandKit

/// A green camera indicator while any app captures from a camera. Event driven: a CoreMediaIO listener on
/// `kCMIODevicePropertyDeviceIsRunningSomewhere` for every camera, and one on the device list to follow a camera
/// plugged in or out. It reads a flag; it never opens a camera, so macOS asks for no permission.
@MainActor
public final class CameraSampler: AmbientSampler {
    public let channel = AmbientChannel.camera

    private let center: AmbientCenter
    private let queue = DispatchQueue(label: "be.roldy.macisland.camera", qos: .utility)
    private var devices: [CMIOObjectID] = []
    private var listListener: CMIOObjectPropertyListenerBlock?
    private var deviceListener: CMIOObjectPropertyListenerBlock?
    private var active = false

    public init(center: AmbientCenter) { self.center = center }

    public var isListening: Bool { active }

    private static var devicesAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static var runningAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    public func start(settings: ClosedIslandSettings) {
        guard !active else { return }
        active = true
        let onList: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.rescan() }
        }
        let onRunning: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        listListener = onList
        deviceListener = onRunning
        var address = Self.devicesAddress
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, onList)
        rescan()
    }

    public func stop() {
        active = false
        detachDevices()
        if let listListener {
            var address = Self.devicesAddress
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue, listListener)
        }
        listListener = nil
        deviceListener = nil
    }

    private func detachDevices() {
        guard let deviceListener else { devices = []; return }
        for device in devices {
            var address = Self.runningAddress
            CMIOObjectRemovePropertyListenerBlock(device, &address, queue, deviceListener)
        }
        devices = []
    }

    private func rescan() {
        guard active, let deviceListener else { return }
        detachDevices()
        devices = Self.allDevices()
        for device in devices {
            var address = Self.runningAddress
            if CMIOObjectHasProperty(device, &address) {
                CMIOObjectAddPropertyListenerBlock(device, &address, queue, deviceListener)
            }
        }
        refresh()
    }

    private func refresh() {
        guard active else { return }
        if devices.contains(where: Self.isRunning) { center.post(AmbientReadings.camera()) } else { center.withdraw(id: AmbientReadings.cameraID) }
    }

    private static func allDevices() -> [CMIOObjectID] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &ids) == 0 else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isRunning(_ device: CMIOObjectID) -> Bool {
        var address = runningAddress
        guard CMIOObjectHasProperty(device, &address) else { return false }
        var running: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == 0 else { return false }
        return running != 0
    }
}
