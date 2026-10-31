import Foundation
@testable import ClaudeLiveKit

/// Synthetic data only: no real session content ever lands in the repo.
struct FakeProbe: ProcessLivenessProbe {
    var starts: [Int32: Date]
    func startTime(ofPID pid: Int32) -> Date? { starts[pid] }
}

final class TempDir {
    let url: URL
    init() {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-claude-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ name: String, _ text: String) -> URL {
        let file = url.appendingPathComponent(name)
        try? text.data(using: .utf8)?.write(to: file)
        return file
    }
}

enum Fixture {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let now = Date(timeIntervalSince1970: 1_800_000_600)

    /// Same shape as `ps -o lstart`: "Tue Oct 27 10:45:47 2026" in local time.
    static func procStart(_ date: Date = start) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f.string(from: date)
    }

    static func sessionJSON(status: String = "busy", cwd: String = "/Users/someone/projects/demo",
                            entrypoint: String = "cli", procStart: String = procStart(),
                            sessionId: String = "sess-1", updatedAtMillis: Double = 1_800_000_500_000) -> String {
        """
        {"pid": 1, "sessionId": "\(sessionId)", "cwd": "\(cwd)", "procStart": "\(procStart)",
         "entrypoint": "\(entrypoint)", "status": "\(status)", "updatedAt": \(updatedAtMillis),
         "name": "do not read me", "messagingSocketPath": "/private/should/not/be/read"}
        """
    }

    static func reader(_ dir: TempDir, alive: [Int32: Date] = [:]) -> ClaudeSessionReader {
        ClaudeSessionReader(directory: dir.url, clock: { now }, probe: FakeProbe(starts: alive))
    }
}
