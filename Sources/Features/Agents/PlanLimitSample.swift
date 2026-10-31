import Foundation

/// The newest reading of the Claude app's `plan-usage-history.json`. Percentages are used shares.
///
/// INFERRED mapping (no documentation): `u.fh` = five-hour window, `u.sd` = seven-day window,
/// `u.xu` = extra usage. A value outside 0...100 is unknown, never clamped. The organisation id in
/// each sample is never read into this type.
struct PlanLimitSample: Equatable, Sendable {
    var date: Date
    var fiveHour: Int?
    var sevenDay: Int?
    var extraUsage: Int?

    /// Older than this and the numbers are shown dimmed.
    static let staleAfter: TimeInterval = 15 * 60

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(date) > Self.staleAfter }
    var hasAnyValue: Bool { fiveHour != nil || sevenDay != nil }
}

enum PlanLimitParser {
    /// `t` is epoch seconds or milliseconds: anything past 1e11 (year 5138 in seconds) is milliseconds.
    static func date(fromEpoch raw: Double) -> Date {
        Date(timeIntervalSince1970: raw >= 1e11 ? raw / 1000 : raw)
    }

    /// The sample with the greatest timestamp, or nil for a missing, malformed or empty file.
    static func latest(from data: Data) -> PlanLimitSample? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]] else { return nil }
        var best: PlanLimitSample?
        for raw in samples {
            guard let t = epoch(raw["t"]), t > 0 else { continue }
            let used = raw["u"] as? [String: Any] ?? [:]
            let sample = PlanLimitSample(date: date(fromEpoch: t), fiveHour: percent(used["fh"]),
                                         sevenDay: percent(used["sd"]), extraUsage: percent(used["xu"]))
            if let current = best, current.date >= sample.date { continue }
            best = sample
        }
        return best
    }

    private static func epoch(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        let d = number.doubleValue
        return d.isFinite ? d : nil
    }

    /// Whole numbers in 0...100 only.
    static func percent(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(number) else { return nil }
        let d = number.doubleValue
        guard d.isFinite, d == d.rounded(), (0...100).contains(d) else { return nil }
        return Int(d)
    }

    private static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}

/// Reads the file. The path is injected; the default is the Claude app's own folder.
struct PlanLimitSource: Sendable {
    var url: URL
    /// A real file is a few KB; refuse anything absurd rather than load it.
    static let maxBytes = 5_000_000

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")) {
        self.url = url
    }

    func load() -> PlanLimitSample? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= Self.maxBytes, let data = try? Data(contentsOf: url) else { return nil }
        return PlanLimitParser.latest(from: data)
    }
}
