import Foundation

/// Decides, key by key, what happens to a Vorssaint preference on import.
/// Observed behaviour only: the key names come from the user's own defaults domain,
/// no Vorssaint source is read or copied.
public enum VorssaintKeyMap {
    public enum Verdict: Equatable {
        case carry
        case skip
        case unknown
    }

    /// Never carried: looks like a secret, is bound to the old app's sandbox,
    /// belongs to its onboarding or update logic, or is outside the v1 scope.
    static let skippedExact: Set<String> = [
        "commandBarQueryHabitKey",
        "notchDownloadsFolderBookmark",  // security-scoped bookmarks do not transfer between apps
        "fanControlHelperVersion",
        "featureHubKeptFeatures",  // mouse and keyboard tweaks, not in v1
    ]
    static let skippedPrefixes = [
        "featureAvailable.",
        "whatsNew", "onboarding", "migration", "vorss",
        "SU", "NS", "AppleLanguages",
    ]

    static let carriedExact: Set<String> = [
        "appVolumes", "appVolumesArePositions",
        "autoQuitEnabled", "launchAtLoginWanted",
        "brightnessControlEnabled", "pastePlainEnabled", "pastePlainShortcut",
        "dockPreviewEnabled", "shelfEnabled", "shelfItems",
        "windowEdgeSnapEnabled", "windowMaximizeEnabled",
    ]
    static let carriedPrefixes = [
        "notch", "clipboard", "keepAwake", "monitor", "mixer",
        "audioPriority", "dockClick", "finder", "menuBar", "brightness",
    ]

    public static func verdict(for key: String) -> Verdict {
        if skippedExact.contains(key) { return .skip }
        if skippedPrefixes.contains(where: key.hasPrefix) { return .skip }
        if carriedExact.contains(key) { return .carry }
        if carriedPrefixes.contains(where: key.hasPrefix) { return .carry }
        return .unknown
    }
}
