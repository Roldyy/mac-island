import Foundation

/// Result of the helper's read-only self-test: what the SMC exposes for fan control on this Mac.
public struct FanSelfTestReport: Codable, Equatable, Sendable {
    public struct KeyInfo: Codable, Equatable, Sendable {
        public var name: String
        public var type: String
        public var size: Int
        public var attributes: Int
        public var value: Double?
    }

    public var fanCount: Int?
    public var fans: [FanReading]
    public var keys: [KeyInfo]
    public var maxTemperatureCelsius: Double?
    public var thermalPressure: ThermalPressure
    public var errors: [String]
}

/// Builds the self-test report through an `SMCReader` only. It has no writer to call.
public enum FanSelfTest {
    public static func run(reader: SMCReader, thermal: ThermalSnapshot) -> FanSelfTestReport {
        var errors: [String] = []
        let count: Int?
        do { count = try FanReadService.fanCount(reader) } catch {
            count = nil
            errors.append("FNum: \(error)")
        }
        let fans = (try? FanReadService.readings(reader)) ?? []
        var names = [FanSMCKeys.fanCount, FanSMCKeys.unlock]
        for fan in 0..<(count ?? 0) {
            names += [FanSMCKeys.mode(fan), FanSMCKeys.target(fan), FanSMCKeys.minimum(fan),
                      FanSMCKeys.maximum(fan), FanSMCKeys.actual(fan)].compactMap { $0 }
        }
        var keys: [FanSelfTestReport.KeyInfo] = []
        for key in names {
            do {
                let v = try reader.read(key)
                keys.append(.init(name: key.description, type: v.info.type.description, size: Int(v.info.size),
                                  attributes: Int(v.info.attributes), value: v.number))
            } catch {
                errors.append("\(key): \(error)")
            }
        }
        return FanSelfTestReport(fanCount: count, fans: fans, keys: keys,
                                 maxTemperatureCelsius: thermal.maxCelsius, thermalPressure: thermal.pressure,
                                 errors: errors)
    }
}
