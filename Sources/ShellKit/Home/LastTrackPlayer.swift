import AppKit
import Foundation
import IslandKit

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

    /// One resolver for every click (`MusicPlayerResolver`): the player playing now, the chosen player, the last
    /// track's player, the blocker's replacement, Spotify, then the download page. Apple Music never comes out while
    /// the Music blocker is on or Spotify is the chosen player.
    @MainActor
    public static func resolve(playerBundleID: String?, playing: String? = nil,
                               settings: MusicPlayerSettings = MusicPlayerSettings(),
                               launcher: any PlayerLaunching) -> PlayerOpenPlan {
        let outcome = MusicPlayerResolver.resolve(playing: playing, last: playerBundleID, settings: settings) {
            launcher.applicationURL(bundleID: $0) != nil
        }
        switch outcome {
        case .open(let bundleID):
            guard let url = launcher.applicationURL(bundleID: bundleID) else { return .installPage(url: MusicPlayerTarget.spotifyInstallURL) }
            return .launch(name: MusicPlayerTarget(bundleID: bundleID).name ?? url.deletingPathExtension().lastPathComponent,
                           bundleID: bundleID, appURL: url)
        case .installPage(let url):
            return .installPage(url: url)
        }
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
