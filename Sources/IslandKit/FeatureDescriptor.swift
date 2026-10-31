import Foundation

// FROZEN W0 contract (types only). Lane L2 writes `FeatureRegistry` and the hub in ShellKit.
// Nobody else edits this file. Wave W1 adds a `<Name>Descriptor.swift` to each feature module.

public enum FeatureCategory: String, CaseIterable, Sendable {
    case daily, claude, input, display, sound, windows, capture, island, monitor, files, tools, apps, media
}

/// What the feature needs from the system, so the hub can show a status and a "grant" button.
public enum FeaturePermission: String, CaseIterable, Sendable {
    case accessibility, screenRecording, automation, audioCapture, camera, microphone,
         notifications, calendar, bluetooth, fullDiskAccess, helperDaemon
}

public enum FeatureCapability: Equatable, Sendable {
    case available
    case needsPermission(FeaturePermission)
    case unavailable(reason: String)
}

public enum FeatureRisk: Int, Comparable, Sendable {
    case safe = 0, touchesInput, touchesSystem, privileged
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct FeatureDescriptor: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let systemImage: String
    public let category: FeatureCategory
    public let permissions: [FeaturePermission]
    public let risk: FeatureRisk
    /// On after a first launch, before the user touches the hub.
    public let enabledByDefault: Bool
    /// Tab id this feature adds to the island, if any.
    public let tabID: String?

    public init(id: String, title: String, summary: String, systemImage: String,
                category: FeatureCategory, permissions: [FeaturePermission] = [],
                risk: FeatureRisk = .safe, enabledByDefault: Bool = true, tabID: String? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.category = category
        self.permissions = permissions
        self.risk = risk
        self.enabledByDefault = enabledByDefault
        self.tabID = tabID
    }
}
