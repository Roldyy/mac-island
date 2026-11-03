import Foundation

/// The types and schemes that are never replaced silently. They stay out of "Remplacer pour tous les types", are
/// listed apart, and only change when the user picks that very item AND confirms it.
public enum ProtectionPolicy {
    /// Types that are too broad (an app declaring them does not "open" them in a useful sense) or that belong to
    /// the system: folders, volumes, URLs, bundles, disk images, executables.
    static let protectedTypes: Set<String> = [
        "public.folder", "public.directory", "public.volume", "public.item", "public.data", "public.content",
        "public.composite-content", "public.url", "public.file-url", "public.url-name", "public.symlink",
        "public.executable", "public.unix-executable", "com.apple.application", "com.apple.application-bundle",
        "com.apple.package", "com.apple.bundle", "com.apple.alias-file", "com.apple.resolvable",
    ]
    static let protectedTypePrefixes = ["com.apple.finder", "com.apple.systempreferences", "com.apple.disk-image"]

    /// Too broad to count as "the app can open this": declaring one of these does not qualify a replacement.
    static let tooGenericToDeclare: Set<String> = ["public.item", "public.data", "public.content", "public.composite-content"]

    static let protectedSchemes: Set<String> = [
        "http", "https", "mailto", "file", "ftp", "tel", "sms", "facetime", "imessage", "webcal",
    ]
    static let protectedSchemePrefixes = ["x-apple"]

    public static func isProtected(contentType id: String) -> Bool {
        let id = id.lowercased()
        return protectedTypes.contains(id) || protectedTypePrefixes.contains { id.hasPrefix($0) }
    }

    public static func isProtected(scheme: String) -> Bool {
        let scheme = scheme.lowercased()
        return protectedSchemes.contains(scheme) || protectedSchemePrefixes.contains { scheme.hasPrefix($0) }
    }

    public static func isProtected(kind: ChangeKind, identifier: String) -> Bool {
        switch kind {
        case .contentType: isProtected(contentType: identifier)
        case .scheme: isProtected(scheme: identifier)
        }
    }
}
