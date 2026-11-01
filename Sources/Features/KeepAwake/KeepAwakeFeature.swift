import IslandKit
import SwiftUI

/// Keep Awake as the island shell sees it. The sessions, the timers, the automation, the mouse jiggle and the
/// closed-lid mode all run in the ported `KeepAwakeManager` (one implementation, bound by PortKit's Energy lane);
/// this module keeps the Éveil tab, the observable state the closed island's cup follows, and the two-minute hold
/// the island itself takes while it is in use.
public enum KeepAwakeFeature {
    @MainActor static var backend: any KeepAwakeBackend = PortKeepAwakeBackend()
    @MainActor static var state = KeepAwakeState(backend: backend)
    @MainActor static var hold = IslandActivityHold()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "keepawake", title: "Éveil", systemImage: "cup.and.saucer") {
            AnyView(KeepAwakeView(state: state, backend: backend))
        }
    }

    /// True while a keep-awake session runs, whether a click or an automation started it.
    @MainActor public static var isActive: Bool { state.isActive }

    /// Quick-access button and global shortcut: stops the session when one runs, otherwise starts the last pick
    /// (the default duration, no limit when none is saved).
    @MainActor public static func toggle() { backend.toggle() }

    /// Call when the island opens or is used; honours `notchKeepAwakeActivity`.
    @MainActor public static func noteIslandActivity() { hold.note() }

    /// Tests swap the backend and the hold; the app never does.
    @MainActor static func configure(backend: any KeepAwakeBackend, hold: IslandActivityHold? = nil) {
        self.backend = backend
        self.state = KeepAwakeState(backend: backend)
        self.hold = hold ?? IslandActivityHold()
    }
}
