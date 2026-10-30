import IslandKit
import SwiftUI

public enum KeepAwakeFeature {
    @MainActor static let controller = KeepAwakeController()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "keepawake", title: "Éveil", systemImage: "cup.and.saucer") {
            AnyView(KeepAwakeView(controller: controller, settings: KeepAwakeSettings()))
        }
    }

    /// True while a user-started keep-awake session runs.
    @MainActor public static var isActive: Bool { controller.isActive }

    /// Call when the island opens or is used; honours `notchKeepAwakeActivity`.
    @MainActor public static func noteIslandActivity() { controller.noteIslandActivity() }
}
