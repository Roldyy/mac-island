import Foundation

/// Reads fans from any `SMCReader`. Pure over the protocol: no write path exists here.
public enum FanReadService {
    /// `FNum`, refused when outside 0...10 (keys only exist for one-digit indexes).
    public static func fanCount(_ reader: SMCReader) throws -> Int {
        guard let n = try reader.read(FanSMCKeys.fanCount).number,
              n == n.rounded(), (0...Double(FanSMCKeys.maxFanIndex + 1)).contains(n) else {
            throw SMCError.invalidResponse
        }
        return Int(n)
    }

    public static func readings(_ reader: SMCReader) throws -> [FanReading] {
        let count = try fanCount(reader)
        return (0..<count).map { fan in
            FanReading(index: fan,
                       actualRPM: number(reader, FanSMCKeys.actual(fan)),
                       minRPM: number(reader, FanSMCKeys.minimum(fan)),
                       maxRPM: number(reader, FanSMCKeys.maximum(fan)),
                       targetRPM: number(reader, FanSMCKeys.target(fan)),
                       mode: mode(reader, fan: fan))
        }
    }

    /// Min and max as read, unvalidated, for every fan where both keys read. The helper hands
    /// these to the policy so a bad SMC value is reported as `invalidLimits`.
    public static func rawLimits(_ reader: SMCReader) -> [Int: FanLimits] {
        guard let count = try? fanCount(reader) else { return [:] }
        var out: [Int: FanLimits] = [:]
        for fan in 0..<count {
            guard let lo = number(reader, FanSMCKeys.minimum(fan)),
                  let hi = number(reader, FanSMCKeys.maximum(fan)) else { continue }
            out[fan] = FanLimits(minRPM: lo, maxRPM: hi)
        }
        return out
    }

    /// Limits of every fan whose min and max pass `policy.validated`. A fan missing here cannot
    /// be driven manually.
    public static func limits(_ reader: SMCReader, policy: FanSafetyPolicy) -> [Int: FanLimits] {
        rawLimits(reader).compactMapValues { policy.validated($0) }
    }

    /// 0 automatic, 1 manual, anything else (or unreadable) unknown.
    public static func mode(_ reader: SMCReader, fan: Int) -> FanMode {
        switch number(reader, FanSMCKeys.mode(fan)) {
        case FanModeValue.automatic: .automatic
        case FanModeValue.manual: .manual
        default: .unknown
        }
    }

    static func number(_ reader: SMCReader, _ key: SMCKey?) -> Double? {
        guard let key else { return nil }
        return (try? reader.read(key))?.number
    }
}
