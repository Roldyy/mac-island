import AppKit
import Foundation
import IslandKit
import OSLog

/// Everything the model reaches outside itself. The live value is the only place that touches LaunchServices; a
/// test builds its own with a fake that records writes and a throwaway defaults suite.
public struct DefaultAppsEnvironment {
    public var launchServices: any LaunchServicesFacading
    public var catalog: any ContentTypeCataloging
    public var defaults: UserDefaults
    public var now: @Sendable () -> Date
    /// Receives every log line (category `defaultapps`).
    public var log: @Sendable (String) -> Void

    public init(launchServices: any LaunchServicesFacading, catalog: any ContentTypeCataloging, defaults: UserDefaults,
                now: @escaping @Sendable () -> Date = { Date() }, log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.launchServices = launchServices
        self.catalog = catalog
        self.defaults = defaults
        self.now = now
        self.log = log
    }

    static let logger = Logger(subsystem: "be.roldy.macisland", category: "defaultapps")

    public static func live() -> DefaultAppsEnvironment {
        DefaultAppsEnvironment(
            launchServices: LiveLaunchServices(), catalog: LiveContentTypeCatalog(),
            defaults: AppDefaults.make() ?? .standard,
            log: { line in logger.info("\(line, privacy: .public)") })
    }
}
