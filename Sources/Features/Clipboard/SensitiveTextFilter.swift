import Foundation

/// The opt-in guess behind "Ignorer le texte qui semble sensible". Pure: it reads one string and answers yes or no.
/// It never logs, stores or returns the text. It is a heuristic and says so on the page: an ordinary string that
/// looks like a secret can be skipped. What an app marks as concealed is refused elsewhere (`PasteboardFilter`) and
/// does not depend on this.
enum SensitiveTextFilter {
    /// A named credential field with a non-empty value: `password: x`, `API_KEY=x`, `"token": "x"`, `--secret x`,
    /// `Authorization: Bearer x`. A bare mention of the word ("the token expired") does not match.
    private static let credentialName = #"(?:password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|authorization)"#
    private static let credentialEnding = #"(?:[_-]?(?:access[_-]?)?key(?:[_-]?base)?|[_-]?confirmation|[_-]?\d{1,3})?"#
    private static let assignment = try? NSRegularExpression(
        pattern: #"(?<![\w-])(?:[\w-]*\#(credentialName)\#(credentialEnding)["']?[ \t]*[:=][ \t]*|--[\w-]*\#(credentialName)\#(credentialEnding)[ \t]+)["']?[^\s"'`,;{}\[\]]"#,
        options: [.caseInsensitive])

    /// Prefixes of tokens that identify themselves (cloud keys, source hosts, chat apps, payment keys).
    private static let tokenPrefixes = [
        "sk-", "sk_live_", "sk_test_", "pk_live_", "rk_live_", "ghp_", "gho_", "ghs_", "github_pat_", "glpat-",
        "xoxb-", "xoxp-", "xoxa-", "xoxs-", "AKIA", "ASIA", "AIza", "npm_", "SG.",
    ]

    static func looksSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("-----BEGIN") && trimmed.contains("PRIVATE KEY") { return true }
        if let assignment,
           assignment.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil { return true }
        // The rest is about one unbroken word: a sentence, a path with spaces or a long paragraph is not a secret.
        guard !trimmed.contains(where: \.isWhitespace) else { return isCardNumber(trimmed) }
        if isWebURL(trimmed) || isUUID(trimmed) { return false }
        if trimmed.count >= 16, tokenPrefixes.contains(where: trimmed.hasPrefix) { return true }
        if isJSONWebToken(trimmed) { return true }
        return looksLikeGeneratedSecret(trimmed)
    }

    /// Long, unbroken, with a letter, a digit and a symbol: what a generated password looks like.
    private static func looksLikeGeneratedSecret(_ word: String) -> Bool {
        guard word.count >= 20, word.count <= 160 else { return false }
        // A file path is long, unbroken and full of symbols, and nobody's password.
        if word.hasPrefix("/") || word.hasPrefix("~/") { return false }
        let hasLetter = word.contains { $0.isLetter }
        let hasDigit = word.contains { $0.isNumber }
        let hasSymbol = word.contains { !$0.isLetter && !$0.isNumber }
        return hasLetter && hasDigit && hasSymbol
    }

    /// Three base64url parts joined by dots, the first one starting like a JSON header.
    private static func isJSONWebToken(_ word: String) -> Bool {
        let parts = word.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].hasPrefix("eyJ") else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }

    /// 13 to 19 digits (spaces and dashes allowed) passing the Luhn check.
    private static func isCardNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard (13...19).contains(digits.count),
              text.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }) else { return false }
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard var value = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    private static func isWebURL(_ word: String) -> Bool {
        guard let url = URL(string: word), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return false }
        return true
    }

    /// Thirty-two hex digits in 8-4-4-4-12 groups: an identifier, nobody's secret.
    private static func isUUID(_ word: String) -> Bool {
        var value = word
        if value.hasPrefix("{"), value.hasSuffix("}") { value = String(value.dropFirst().dropLast()) }
        let groups = value.split(separator: "-", omittingEmptySubsequences: false)
        return groups.map(\.count) == [8, 4, 4, 4, 12] && groups.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }
}
