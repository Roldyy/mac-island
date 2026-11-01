import Foundation
import os

/// Permanent breadcrumb for the plain-paste flow: steps and states only, NEVER clipboard content.
/// Read it with: log show --last 2m --predicate 'process == "MacIsland" AND category == "paste"'
/// (`notice` level, so it shows without `--info`).
enum PasteLog {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "be.roldy.macisland", category: "paste")
}
