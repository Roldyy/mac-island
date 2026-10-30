import Foundation

enum MixerEngineError: Error, Equatable {
    case tapCreationFailed(status: Int32)
    case aggregateCreationFailed(status: Int32)
    case ioProcFailed(status: Int32)
    case startFailed(status: Int32)
    case unavailable
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
