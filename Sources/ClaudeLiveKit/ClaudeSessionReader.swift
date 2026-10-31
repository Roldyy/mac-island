import Foundation

/// Reads `~/.claude/sessions/<pid>.json`. The format is undocumented and written by another program, so
/// everything here is defensive: strict file names, bounded size, whitelisted fields, verified liveness.
/// A file that fails any check is skipped; nothing here throws or crashes.
public struct ClaudeSessionReader: Sendable {
    public static let maxFileBytes = 16 * 1024

    public let directory: URL
    public let clock: @Sendable () -> Date
    public let probe: any ProcessLivenessProbe

    public init(directory: URL, clock: @escaping @Sendable () -> Date = { Date() },
                probe: any ProcessLivenessProbe = SystemProcessProbe()) {
        self.directory = directory
        self.clock = clock
        self.probe = probe
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// Live sessions, sorted by pid for a stable order.
    public func read() -> [ClaudeSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        let now = clock()
        return names.compactMap { Self.pid(fromFileName: $0) == nil ? nil : session(named: $0, now: now) }
            .sorted { $0.pid < $1.pid }
    }

    /// `^\d{1,7}\.json$` with ASCII digits, nonzero pid. Anything else (`x.key`, `../x.json`) is nil.
    static func pid(fromFileName name: String) -> Int32? {
        guard name.hasSuffix(".json") else { return nil }
        let stem = name.dropLast(5)
        guard stem.utf8.count <= 7, ClaudeText.isASCIIDigits(stem), let pid = Int32(stem), pid > 0 else { return nil }
        return pid
    }

    private func session(named name: String, now: Date) -> ClaudeSession? {
        guard let pid = Self.pid(fromFileName: name),
              let data = SafeFileRead.data(atPath: directory.appendingPathComponent(name).path,
                                           maxBytes: Self.maxFileBytes),
              let raw = Self.parse(data) else { return nil }
        // Pid reuse: the file must describe the process that is running under this pid right now.
        guard let actualStart = probe.startTime(ofPID: pid), ProcStart.matches(raw.procStart, actual: actualStart) else {
            return nil
        }
        let updated = raw.updatedAt.map { min($0, now) }
        return ClaudeSession(id: raw.sessionID ?? String(pid), pid: pid, state: raw.state,
                             folderName: raw.folderName, entrypoint: raw.entrypoint, updatedAt: updated)
    }

    struct Raw {
        var state: ClaudeSession.State
        var folderName: String
        var entrypoint: String?
        var procStart: String
        var sessionID: String?
        var updatedAt: Date?
    }

    /// Whitelist parse: only the keys below are ever read. Prompt-ish or path-ish extras are never touched.
    static func parse(_ data: Data) -> Raw? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let procStart = object["procStart"] as? String else { return nil }
        let state: ClaudeSession.State = switch object["status"] as? String {
        case "busy": .working
        case "waiting": .waiting
        case "idle": .idle
        default: .unknown          // a status we do not know is never shown as idle
        }
        let folder = (object["cwd"] as? String).map(ClaudeText.folderName(fromCwd:)) ?? ""
        let millis = (object["updatedAt"] as? NSNumber)?.doubleValue
        return Raw(state: state, folderName: folder,
                   entrypoint: (object["entrypoint"] as? String).flatMap(ClaudeText.entrypoint),
                   procStart: procStart,
                   sessionID: (object["sessionId"] as? String).flatMap(ClaudeText.sanitizedID),
                   updatedAt: millis.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil })
    }
}
