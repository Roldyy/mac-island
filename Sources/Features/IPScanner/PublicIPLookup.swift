import Darwin
import Foundation

/// The public address is never fetched by itself. The user clicks a button that names this URL; one GET goes out.
public enum PublicIPLookup {
    public static let url = URL(string: "https://api.ipify.org")!
    public static let maxResponseBytes = 64

    /// The answer is shown only when it is exactly an IPv4 or IPv6 literal; anything else is dropped.
    public static func validated(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...45).contains(text.utf8.count) else { return nil }
        if IPv4Address(text) != nil { return text }
        var buffer = in6_addr()
        guard text.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) || $0 == 0x3A }),
              inet_pton(AF_INET6, text, &buffer) == 1 else { return nil }
        return text
    }
}
