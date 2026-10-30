import Foundation

enum MixerEngineError: Error, Equatable {
    case tapCreationFailed(status: Int32)
    case aggregateCreationFailed(status: Int32)
    case ioProcFailed(status: Int32)
    case startFailed(status: Int32)
    case unavailable
    /// Audio capture is not authorised (or not yet requested): no tap may be created.
    case permissionNotGranted
    /// The aggregate's input streams are not the layout the IOProc was written for.
    case unexpectedStreamLayout
}

/// Whether audio capture was granted. Written on the main thread by the feature model after the user
/// clicked the permission button; read by the mixer model and, as a last guard, by the engine.
final class CaptureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    init(ready: Bool = false) { self.ready = ready }

    var isReady: Bool {
        get { lock.lock(); defer { lock.unlock() }; return ready }
        set { lock.lock(); defer { lock.unlock() }; ready = newValue }
    }
}

/// Per-app gain behind a seam: the real one drives Core Audio taps, tests use a fake.
/// Called on the main thread only.
protocol MixerEngine: AnyObject {
    /// Begin controlling `app` (a bundle id): tap `processes`, mute their direct output,
    /// play them through `outputDeviceUID` at `gain`. Replaces a tap already live for `app`.
    func start(app: String, processes: [UInt32], outputDeviceUID: String, gain: Float) throws
    func setGain(_ gain: Float, app: String)
    func stop(app: String)
    func stopAll()
    var liveApps: Set<String> { get }
}
