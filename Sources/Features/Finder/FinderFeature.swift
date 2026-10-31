import IslandKit
import SwiftUI

/// What `startCleaning()` did. Anything but `.started` / `.alreadyRunning` swallowed nothing.
public enum CleaningStartResult: Equatable, Sendable {
    case started, alreadyRunning, needsAccessibility, needsInputMonitoring, refused
}

public enum FinderFeature {
    /// Created on first use only, so building the tab list touches nothing (no tap, no permission).
    @MainActor static let shared = FinderModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "finder", title: "Finder", systemImage: "folder") {
            AnyView(FinderTabView(model: shared))
        }
    }

    /// Install the key tap if the toggles and permissions allow it. Idempotent. Never prompts.
    @MainActor public static func start() { shared.start() }

    /// Remove the key tap and forget any pending cut. Also ends cleaning mode. Idempotent.
    @MainActor public static func stop() {
        shared.stop()
        endCleaning()
    }

    // MARK: - Cleaning mode

    private static let cleaningActivityID = "finder.cleaning"
    @MainActor private static var cleaning: CleaningSession?

    @MainActor public static var isCleaning: Bool { cleaning?.isRunning ?? false }

    /// Swallows keyboard, mouse and scroll for at most 60 s. Ends on Escape held 3 s, on tap failure and
    /// on `endCleaning()`. Checks permissions first and never prompts; the countdown shows in the closed island.
    @MainActor @discardableResult
    public static func startCleaning() -> CleaningStartResult {
        if isCleaning { return .alreadyRunning }
        let session = CleaningSession(tap: CleaningEventTap())
        session.onTick = { remaining in
            ActivityCenter.shared.post(IslandActivity(
                id: cleaningActivityID, source: "finder", priority: .alert,
                leading: CompactItem(symbol: "sparkles", text: CleaningPolicy.label(remaining: remaining),
                                     status: .warning)))
        }
        session.onEnd = { reason in
            ActivityCenter.shared.withdraw(id: cleaningActivityID)
            cleaning = nil
            if reason != .quit {
                ActivityCenter.shared.post(IslandActivity(
                    id: cleaningActivityID, source: "finder", priority: .alert,
                    leading: CompactItem(symbol: "checkmark.circle.fill", text: "Nettoyage terminé",
                                         status: .success)),
                    expiresAfter: .seconds(3))
            }
        }
        cleaning = session
        switch session.start() {
        case nil: return .started
        case .needsAccessibility?: cleaning = nil; return .needsAccessibility
        case .needsInputMonitoring?: cleaning = nil; return .needsInputMonitoring
        case .refused?: cleaning = nil; return .refused
        }
    }

    /// Ends cleaning mode now (app quit, feature stopped, user action). Idempotent.
    @MainActor public static func endCleaning() { cleaning?.end(.quit) }
}
