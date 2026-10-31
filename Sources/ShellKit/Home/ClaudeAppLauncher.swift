import AppKit
import Foundation

/// Launches the Claude desktop app. Existence is checked every time, so installing or removing the app is
/// noticed without a restart; the two closures are injectable so tests touch neither disk nor NSWorkspace.
@MainActor
public struct ClaudeAppLauncher {
    public static let defaultURL = URL(fileURLWithPath: "/Applications/Claude.app")
    public static let missingReason = "Claude.app est introuvable dans /Applications"

    public var appURL: URL
    public var exists: (URL) -> Bool
    public var open: (URL) -> Void

    public init(
        appURL: URL = ClaudeAppLauncher.defaultURL,
        exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        open: @escaping (URL) -> Void = { url in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    ) {
        self.appURL = appURL
        self.exists = exists
        self.open = open
    }

    public var isAvailable: Bool { exists(appURL) }

    /// Why the button is off, nil when it works.
    public var unavailableReason: String? { isAvailable ? nil : Self.missingReason }

    /// True when the launch was requested. Nothing happens when the app is missing.
    @discardableResult
    public func launch() -> Bool {
        guard isAvailable else { return false }
        open(appURL)
        return true
    }
}
