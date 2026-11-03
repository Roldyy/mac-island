import Foundation

/// One installed app and what it declares it can open.
public struct AppProfile: Identifiable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let url: URL
    public let declared: DeclaredTypes

    public var id: String { bundleID }

    public init(bundleID: String, name: String, url: URL, declared: DeclaredTypes) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.declared = declared
    }
}

/// A content type an app currently opens by default, with what the user needs to recognise it.
public struct HandledType: Identifiable, Equatable, Sendable {
    /// Lower-case UTI.
    public let id: String
    public let summary: String
    /// A few example extensions ("txt", "md").
    public let extensions: [String]
    public let isProtected: Bool

    public init(id: String, summary: String, extensions: [String], isProtected: Bool) {
        self.id = id
        self.summary = summary
        self.extensions = extensions
        self.isProtected = isProtected
    }

    /// ".txt, .md" or "" when the type has no extension.
    public var extensionsText: String { extensions.map { "." + $0 }.joined(separator: ", ") }
}

/// An app that is the default handler of at least one type.
public struct ReplaceableApp: Identifiable, Equatable, Sendable {
    public let profile: AppProfile
    public let handled: [HandledType]

    public var id: String { profile.bundleID }
    public var count: Int { handled.count }
    public var unprotectedCount: Int { handled.filter { !$0.isProtected }.count }
}

/// The outcome of one scan.
public struct ScanResult: Equatable, Sendable {
    public var apps: [AppProfile]
    /// Lower-case type -> bundle id of its default handler.
    public var defaults: [String: String]
    public var replaceable: [ReplaceableApp]

    public static let empty = ScanResult(apps: [], defaults: [:], replaceable: [])

    public func app(_ bundleID: String) -> AppProfile? { apps.first { $0.bundleID == bundleID } }
    public func name(of bundleID: String?) -> String? { bundleID.flatMap { app($0)?.name } }
}
