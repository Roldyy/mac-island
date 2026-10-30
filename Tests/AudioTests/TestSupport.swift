import Foundation
@testable import AudioFeature

/// Synthetic data only: no real device or app names anywhere in these tests.
final class FakeAudioSystem: AudioSystem {
    var deviceList: [AudioDeviceInfo] = []
    var defaults: [AudioDirection: String] = [:]
    var processList: [AudioProcess] = []
    private(set) var setCalls: [(uid: String, direction: AudioDirection)] = []
    private(set) var processesCalls = 0
    private(set) var startListeningCount = 0
    private(set) var stopListeningCount = 0
    private var handler: (@MainActor (AudioSystemEvent) -> Void)?

    func devices() -> [AudioDeviceInfo] { deviceList }
    func defaultDeviceUID(_ direction: AudioDirection) -> String? { defaults[direction] }
    func processes() -> [AudioProcess] { processesCalls += 1; return processList }

    @discardableResult
    func setDefaultDevice(uid: String, direction: AudioDirection) -> Bool {
        setCalls.append((uid, direction))
        defaults[direction] = uid
        // The HAL calls the listener back for our own change too.
        MainActor.assumeIsolated { handler?(.defaultChanged(direction)) }
        return true
    }

    func startListening(_ handler: @escaping @MainActor (AudioSystemEvent) -> Void) {
        startListeningCount += 1
        self.handler = handler
    }

    func stopListening() {
        stopListeningCount += 1
        handler = nil
    }

    @MainActor func emit(_ event: AudioSystemEvent) { handler?(event) }
}

func out(_ uid: String) -> AudioDeviceInfo { AudioDeviceInfo(uid: uid, name: "name-\(uid)", hasOutput: true, hasInput: false) }
func inp(_ uid: String) -> AudioDeviceInfo { AudioDeviceInfo(uid: uid, name: "name-\(uid)", hasOutput: false, hasInput: true) }

final class FakeEngine: MixerEngine {
    struct StartCall: Equatable { var app: String; var processes: [UInt32]; var output: String; var gain: Float }
    private(set) var starts: [StartCall] = []
    private(set) var gains: [(app: String, gain: Float)] = []
    private(set) var stops: [String] = []
    private(set) var stopAllCount = 0
    var failStart = false
    private(set) var live: Set<String> = []

    var liveApps: Set<String> { live }

    func start(app: String, processes: [UInt32], outputDeviceUID: String, gain: Float) throws {
        if failStart { throw MixerEngineError.tapCreationFailed(status: -1) }
        starts.append(.init(app: app, processes: processes, output: outputDeviceUID, gain: gain))
        live.insert(app)
    }
    func setGain(_ gain: Float, app: String) { gains.append((app, gain)) }
    func stop(app: String) { stops.append(app); live.remove(app) }
    func stopAll() { stopAllCount += 1; live.removeAll() }
}

final class MutableClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

func proc(_ id: UInt32, pid: Int32, _ bundle: String, running: Bool = true) -> AudioProcess {
    AudioProcess(objectID: id, pid: pid, bundleID: bundle, name: "app-\(bundle)", isRunningOutput: running)
}

/// A throwaway defaults suite whose persistent domain, and plist file, are removed on deinit.
/// Hold it in a stored property of the suite (one instance per test) so it outlives the test body.
final class TempDefaults {
    let suite = "AudioTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: suite)! }

    deinit {
        defaults.removePersistentDomain(forName: suite)
        // cfprefsd may flush the plist after the removal: make sure no file stays behind.
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: file)
    }
}

/// A mutable boolean the model under test reads through a closure.
final class Flag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
