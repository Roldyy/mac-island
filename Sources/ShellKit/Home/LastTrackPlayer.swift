import AppKit
import Foundation

/// The seam between "open the player" and NSWorkspace, so tests launch nothing.
@MainActor
public protocol PlayerLaunching {
    func applicationURL(bundleID: String) -> URL?
    func isRunning(bundleID: String) -> Bool
    func launch(appAt url: URL)
    func openWebPage(_ url: URL)
}

@MainActor
public struct WorkspacePlayerLauncher: PlayerLaunching {
    public nonisolated init() {}

    public func applicationURL(bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    public func launch(appAt url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    public func openWebPage(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Which player a card click opens.
public struct MusicPlayerTarget: Equatable, Sendable {
    public static let spotifyBundleID = "com.spotify.client"
    public static let musicBundleID = "com.apple.Music"
    public static let spotifyInstallURL = URL(string: "https://www.spotify.com/download")!

    public var bundleID: String
    /// Nil for a player this build does not know by name (the name then comes from the app bundle).
    public var name: String?

    /// The player that produced the last track when known, Spotify otherwise.
    public init(bundleID: String?) {
        switch bundleID {
        case Self.musicBundleID?: self.init(bundleID: Self.musicBundleID, name: "Musique")
        case let other? where !other.isEmpty && other != Self.spotifyBundleID: self.init(bundleID: other, name: nil)
        default: self.init(bundleID: Self.spotifyBundleID, name: "Spotify")
        }
    }

    private init(bundleID: String, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// What a click does, decided from what is installed. Pure apart from the injected launcher.
public enum PlayerOpenPlan: Equatable, Sendable {
    case launch(name: String, bundleID: String, appURL: URL)
    /// Spotify is not installed (and no other player applies): the download page.
    case installPage(url: URL)

    /// The player of the last track; when it is gone, Spotify; when that is missing too, the download page.
    @MainActor
    public static func resolve(playerBundleID: String?, launcher: any PlayerLaunching) -> PlayerOpenPlan {
        let target = MusicPlayerTarget(bundleID: playerBundleID)
        if let url = launcher.applicationURL(bundleID: target.bundleID) {
            return .launch(name: target.name ?? url.deletingPathExtension().lastPathComponent,
                           bundleID: target.bundleID, appURL: url)
        }
        if target.bundleID != MusicPlayerTarget.spotifyBundleID,
           let url = launcher.applicationURL(bundleID: MusicPlayerTarget.spotifyBundleID) {
            return .launch(name: "Spotify", bundleID: MusicPlayerTarget.spotifyBundleID, appURL: url)
        }
        return .installPage(url: MusicPlayerTarget.spotifyInstallURL)
    }

    /// Label of the idle card's call to action.
    public var title: String {
        switch self {
        case .launch(let name, _, _): "Ouvrir \(name)"
        case .installPage: "Ouvrir Spotify"
        }
    }

    public var help: String {
        switch self {
        case .launch(let name, _, _): "Ouvrir \(name)"
        case .installPage: "Spotify n’est pas installé : ouvrir la page d’installation"
        }
    }

    @MainActor
    public func perform(with launcher: any PlayerLaunching) {
        switch self {
        case .launch(_, _, let url): launcher.launch(appAt: url)
        case .installPage(let url): launcher.openWebPage(url)
        }
    }
}
