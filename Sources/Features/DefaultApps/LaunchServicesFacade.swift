import Foundation

/// What a change touches: a content type (UTI) or a URL scheme.
public enum ChangeKind: String, Codable, Sendable {
    case contentType, scheme
}

/// Content-type lookups (UTType). A protocol so a test never depends on what this Mac knows about a type.
public protocol ContentTypeCataloging: Sendable {
    /// The identifier of a file extension, nil when the system has none (dynamic types are dropped).
    func identifier(forExtension ext: String) -> String?
    /// Example extensions of a type, most preferred first.
    func extensions(forIdentifier id: String) -> [String]
    /// The human description ("Texte brut"), nil when unknown.
    func description(forIdentifier id: String) -> String?
    /// Whether `id` is `parent` or conforms to it.
    func conforms(_ id: String, to parent: String) -> Bool
}

/// Everything the feature asks LaunchServices. The live value is the ONLY place that reads the disk for apps or
/// writes a default handler; the tests use a fake that records every write, so no test ever changes the real Mac.
public protocol LaunchServicesFacading: Sendable {
    /// Every app bundle found in the standard application folders.
    func installedApplicationURLs() -> [URL]
    /// The app's Info.plist as a dictionary, nil when unreadable.
    func infoDictionary(at appURL: URL) -> [String: Any]?
    /// Bundle id of the app that opens this type now (lower-case id in, nil when none).
    func defaultHandlerBundleID(forContentType id: String) -> String?
    func defaultHandlerBundleID(forScheme scheme: String) -> String?
    func applicationURL(forBundleID id: String) -> URL?
    /// The two public writes. macOS may show its own confirmation sheet and the call returns once it is answered.
    func setDefault(appURL: URL, contentType id: String) async throws
    func setDefault(appURL: URL, scheme: String) async throws
}

/// A user's refusal of macOS's own sheet (or a timeout): the run stops instead of showing more sheets.
public struct LaunchServicesError: Error, Equatable, Sendable {
    public let message: String
    public let userCancelled: Bool
    /// macOS did not answer in time: the write may still land later, so the outcome is unknown (not "failed").
    public let timedOut: Bool
    public init(_ message: String, userCancelled: Bool = false, timedOut: Bool = false) {
        self.message = message
        self.userCancelled = userCancelled
        self.timedOut = timedOut
    }
}
