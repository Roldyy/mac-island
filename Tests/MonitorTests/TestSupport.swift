import Foundation
@testable import MonitorFeature

/// A throwaway defaults suite whose persistent domain is removed when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = "monitor-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
}

/// Replays a script of CPU tick sets, repeating the last one.
final class FakeCPU: CPUSampling {
    var script: [[CPUTicks]?]
    private(set) var reads = 0
    init(_ script: [[CPUTicks]?]) { self.script = script }
    func ticks() -> [CPUTicks]? {
        defer { reads += 1 }
        return script[min(reads, script.count - 1)]
    }
}

final class FakeMemory: MemorySampling {
    var counts: MemoryCounts?
    var level: MemoryPressure = .normal
    private(set) var reads = 0
    init(usedPercent: Double) { counts = Self.make(usedPercent) }
    static func make(_ percent: Double) -> MemoryCounts {
        MemoryCounts(internalPages: UInt64(percent), purgeablePages: 0, wiredPages: 0, compressorPages: 0,
                     pageSize: 1, totalBytes: 100)
    }
    func read() -> MemoryCounts? { reads += 1; return counts }
    func pressure() -> MemoryPressure { level }
}

final class FakeThermal: ThermalSampling {
    var current: ThermalLevel = .nominal
    func level() -> ThermalLevel { current }
}

final class FakeProcesses: ProcessSampling {
    var raws: [ProcessRaw] = []
    private(set) var snapshots = 0
    func snapshot() -> [ProcessRaw] { snapshots += 1; return raws }
    func name(pid: Int32) -> String { "proc-\(pid)" }
}

final class FakeNotifier: NotificationDelivering {
    var hasBundle = true
    var status: NotificationAuthorization = .authorized
    var grantOnRequest = true
    private(set) var posted: [(String, String)] = []
    private(set) var requests = 0
    func authorizationStatus() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> Bool {
        requests += 1
        if grantOnRequest { status = .authorized } else { status = .denied }
        return grantOnRequest
    }
    func post(title: String, body: String) { posted.append((title, body)) }
}

final class Clock {
    var now = Date(timeIntervalSinceReferenceDate: 5_000_000)
    var uptimeNs: UInt64 = 1_000_000_000
    func advance(_ seconds: TimeInterval) {
        now.addTimeInterval(seconds)
        uptimeNs += UInt64(seconds * 1_000_000_000)
    }
}

func busy(_ cores: Int, user: UInt32, idle: UInt32) -> [CPUTicks] {
    Array(repeating: CPUTicks(user: user, system: 0, idle: idle, nice: 0), count: cores)
}
