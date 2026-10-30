import Foundation

/// The temperature keys the thermal override watches.
///
/// The meaning of individual SMC temperature keys on the M4 Pro is UNKNOWN (Apple does not
/// document them). Read-only probe on this Mac: 309 `T*` float keys; `TVMR`/`TVMr` sit near
/// 117-120 C and look like limits rather than readings, so a max over every `T*` key would keep
/// the override on forever. The default watches the CPU-side prefixes `Tp`, `Te`, `TC` only,
/// drops implausible values (unpopulated sensors read 0 or -4), and the policy fails closed when
/// nothing plausible remains. `TCMz` was seen jumping 73 -> 98 C within a second under build load,
/// so manual mode will drop back to automatic under heavy load: by design, tune after real use.
public struct TemperatureSensors: Sendable {
    public static let defaultPrefixes = ["Tp", "Te", "TC"]

    public var keys: [SMCKey]

    public init(keys: [SMCKey]) { self.keys = keys }

    /// Keys from an SMC key list that start with one of `prefixes`, in input order.
    public static func discover(_ names: [SMCKey], prefixes: [String]) -> [SMCKey] {
        names.filter { key in prefixes.contains { key.description.hasPrefix($0) } }
    }

    /// Hottest plausible reading among `keys`; float and sp78 keys only. Nil when none.
    public func maxCelsius(_ reader: SMCReader, plausible: ClosedRange<Double>) -> Double? {
        keys.compactMap { key -> Double? in
            guard let v = try? reader.read(key), v.info.type == .flt || v.info.type == .sp78,
                  let n = v.number, plausible.contains(n) else { return nil }
            return n
        }.max()
    }
}
