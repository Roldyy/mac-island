import Foundation

/// What an app says it can open: content types (lower-case UTIs) and URL schemes (lower-case).
public struct DeclaredTypes: Equatable, Sendable {
    public var contentTypes: Set<String>
    public var schemes: Set<String>

    public init(contentTypes: Set<String> = [], schemes: Set<String> = []) {
        self.contentTypes = contentTypes
        self.schemes = schemes
    }
}

/// Reads CFBundleDocumentTypes (LSItemContentTypes and CFBundleTypeExtensions, the extensions resolved through the
/// catalog) and CFBundleURLTypes out of an Info.plist. An Info.plist is untrusted input: every list is capped and
/// every string is validated before it is kept.
public enum DeclaredTypesExtractor {
    static let maxEntries = 500
    static let maxTypes = 2000
    /// Per document-type entry (a 4 MB plist can hold 100 000 identifiers in one entry).
    static let maxTypesPerEntry = 100
    /// Raw elements looked at per list, valid or not.
    static let maxRawPerList = 300
    /// Catalog lookups (extension to type) for one Info.plist, hits or misses.
    static let maxLookups = 3000
    static let maxSchemes = 200
    static let maxSchemesPerEntry = 20
    static let maxIdentifierLength = 255

    public static func extract(from plist: [String: Any], catalog: ContentTypeCataloging) -> DeclaredTypes {
        var result = DeclaredTypes()
        var lookups = 0
        let documentTypes = (plist["CFBundleDocumentTypes"] as? [Any] ?? []).prefix(maxEntries)
        for case let entry as [String: Any] in documentTypes {
            // An entry that says "None" (role or rank) is the app declining to be a handler.
            if (entry["CFBundleTypeRole"] as? String) == "None" || (entry["LSHandlerRank"] as? String) == "None" { continue }
            // Every cap is applied BEFORE anything accumulates: nothing past it is cleaned, looked up or kept.
            var fromEntry = 0
            for id in strings(entry["LSItemContentTypes"]) {
                guard fromEntry < maxTypesPerEntry, result.contentTypes.count < maxTypes else { break }
                if let clean = cleanIdentifier(id) { fromEntry += 1; result.contentTypes.insert(clean) }
            }
            for raw in strings(entry["CFBundleTypeExtensions"]) {
                guard fromEntry < maxTypesPerEntry, result.contentTypes.count < maxTypes, lookups < maxLookups else { break }
                lookups += 1
                guard let ext = cleanExtension(raw), let id = catalog.identifier(forExtension: ext),
                      let clean = cleanIdentifier(id) else { continue }
                fromEntry += 1
                result.contentTypes.insert(clean)
            }
            if result.contentTypes.count >= maxTypes { break }
        }
        for case let entry as [String: Any] in (plist["CFBundleURLTypes"] as? [Any] ?? []).prefix(maxEntries) {
            var fromEntry = 0
            for raw in strings(entry["CFBundleURLSchemes"]) {
                guard fromEntry < maxSchemesPerEntry, result.schemes.count < maxSchemes else { break }
                if let scheme = cleanScheme(raw) { fromEntry += 1; result.schemes.insert(scheme) }
            }
            if result.schemes.count >= maxSchemes { break }
        }
        return result
    }

    /// A plist value that should be a list of strings; a lone string is accepted, anything else is dropped. Only the
    /// first `maxRawPerList` elements are ever looked at.
    private static func strings(_ value: Any?) -> [String] {
        if let list = value as? [Any] { return list.prefix(maxRawPerList).compactMap { $0 as? String } }
        if let one = value as? String { return [one] }
        return []
    }

    /// Reverse-DNS style identifier: letters, digits, dot, dash, underscore. Lower-cased.
    static func cleanIdentifier(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !id.isEmpty, id.utf8.count <= maxIdentifierLength, !id.hasPrefix("dyn."),
              id.unicodeScalars.allSatisfy({ ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || ".-_".unicodeScalars.contains($0)) })
        else { return nil }
        return id
    }

    /// "*" and anything that is not a plain extension is dropped; a leading dot is stripped.
    static func cleanExtension(_ raw: String) -> String? {
        var ext = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        guard !ext.isEmpty, ext.utf8.count <= 32,
              ext.unicodeScalars.allSatisfy({ $0.value < 128 && (CharacterSet.alphanumerics.contains($0) || "-_+".unicodeScalars.contains($0)) })
        else { return nil }
        return ext
    }

    /// RFC 3986 scheme: a letter, then letters, digits, plus, dot, dash. At most 32 characters.
    public static func cleanScheme(_ raw: String) -> String? {
        let scheme = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard let first = scheme.unicodeScalars.first, scheme.utf8.count <= 32,
              first.value < 128, CharacterSet.letters.contains(first),
              scheme.unicodeScalars.allSatisfy({ $0.value < 128 && (CharacterSet.alphanumerics.contains($0) || "+.-".unicodeScalars.contains($0)) })
        else { return nil }
        return scheme
    }
}
