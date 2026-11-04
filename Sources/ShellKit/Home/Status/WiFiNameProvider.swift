import Foundation

/// The Wi-Fi name for the Network chip, behind the Location permission.
///
/// The permission is requested ONCE, the first time the chip is resolved while the Mac is on Wi-Fi (never at launch,
/// never on Ethernet), and never again whatever the answer: a refusal, an undetermined state or an empty name all
/// give `nil`, and the chip keeps its title "Wi-Fi" (no error text, no nag). The name is sanitised (see `sanitized`).
@MainActor
public final class WiFiNameProvider {
    /// The most characters of a name the chip shows.
    nonisolated public static let maxLength = 24

    private let reader: any SSIDReading
    private(set) var hasRequested = false

    public init(reader: any SSIDReading) { self.reader = reader }

    /// Starts listening for an authorization change (the user answers the prompt, or flips the switch in Settings).
    public func begin(onChange: @escaping @MainActor () -> Void) {
        reader.onAuthorizationChange = onChange
    }

    /// Stops listening. The request flag stays: one prompt per run, at most.
    public func end() { reader.onAuthorizationChange = nil }

    /// The name to show for this link: nil off Wi-Fi, while undetermined (after raising the prompt once), when
    /// denied, or when the system gives no name.
    public func name(forWiFi onWiFi: Bool) -> String? {
        guard onWiFi else { return nil }
        switch reader.authorization {
        case .notDetermined:
            if !hasRequested {
                hasRequested = true
                reader.requestAuthorization()
            }
            return nil
        case .denied:
            return nil
        case .authorized:
            return Self.sanitized(reader.readSSID())
        }
    }

    /// A network name is attacker-controlled text (anyone can name a hotspot). Controls, line breaks and invisible
    /// format characters (bidi overrides, zero-width) are dropped, spaces collapsed, then it is cut to `maxLength`
    /// characters with an ellipsis. Empty after cleaning gives nil.
    nonisolated public static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                continue
            case .spaceSeparator:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
