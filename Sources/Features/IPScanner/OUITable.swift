import Foundation

/// MAC prefix to vendor name, from the small bundled table only (`OUIData`). No network, no file read.
public struct OUITable: Sendable {
    public static let privateAddressLabel = "Adresse privée (aléatoire)"

    private let vendors: [String: String]

    public var count: Int { vendors.count }

    /// Parses `Name|AABBCC AABBCC ...` lines. A malformed token or line is skipped; the first vendor to claim a prefix keeps it.
    public init(source: String) {
        var table: [String: String] = [:]
        for line in source.split(separator: "\n") {
            let halves = line.split(separator: "|", maxSplits: 1)
            guard halves.count == 2 else { continue }
            let name = halves[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            for token in halves[1].split(separator: " ") {
                let key = token.uppercased()
                guard key.utf8.count == 6, key.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) }),
                      table[key] == nil else { continue }
                table[key] = name
            }
        }
        vendors = table
    }

    public static let bundled = OUITable(source: OUIData.source)

    /// The vendor of a hardware address. A randomized (locally administered) address names nobody: it says so.
    public func vendor(of mac: MACAddress) -> String? {
        if mac.isLocallyAdministered { return Self.privateAddressLabel }
        return vendors[mac.ouiKey]
    }
}
