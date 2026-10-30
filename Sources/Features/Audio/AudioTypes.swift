import Foundation

enum AudioDirection: String, Sendable, CaseIterable {
    case output
    case input
}

/// One physical or virtual device, identified by its stable UID (never by AudioObjectID).
struct AudioDeviceInfo: Equatable, Identifiable, Sendable {
    var uid: String
    var name: String
    var hasOutput: Bool
    var hasInput: Bool
    var id: String { uid }

    func supports(_ direction: AudioDirection) -> Bool {
        direction == .output ? hasOutput : hasInput
    }
}

/// A Core Audio process object (one pid) known to the HAL.
struct AudioProcess: Equatable, Sendable {
    var objectID: UInt32
    var pid: Int32
    var bundleID: String
    var name: String
    var isRunningOutput: Bool
}

enum AudioSystemEvent: Equatable, Sendable {
    case devicesChanged
    case defaultChanged(AudioDirection)
    case processesChanged
}

/// Everything the feature needs from the HAL, so the logic runs against a fake.
/// All calls and the listener callback happen on the main thread.
protocol AudioSystem: AnyObject {
    func devices() -> [AudioDeviceInfo]
    func defaultDeviceUID(_ direction: AudioDirection) -> String?
    @discardableResult func setDefaultDevice(uid: String, direction: AudioDirection) -> Bool
    func processes() -> [AudioProcess]
    func startListening(_ handler: @escaping @MainActor (AudioSystemEvent) -> Void)
    func stopListening()
}
