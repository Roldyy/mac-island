import IslandKit
import SwiftUI

public enum AgentsFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "agents", title: "Claude", systemImage: "sparkles") {
            AnyView(AgentsTabView())
        }
    }

    /// Tokens and cost of the chosen period for the closed island (the contract has no idle slot: the shell places this).
    @MainActor public static func idleView() -> AnyView {
        AnyView(AgentsIdleView())
    }

    @MainActor private static var resting: AgentsRestingController?

    /// Posts the focused plan limit to the closed island (ambient, id `agents.resting`) when the migrated
    /// `notchIdleContent` is "agents", refreshed every minute. Idempotent. The host calls it once at launch.
    @MainActor public static func startResting() {
        warmUp()   // the host already calls this at launch: the usage numbers are ready by the first hover
        guard resting == nil else { return }
        let controller = AgentsRestingController(
            settings: AgentsSettings(store: AppDefaults.make() ?? .standard), poster: ActivityCenter.shared)
        resting = controller
        controller.start()
    }

    /// Reads the usage logs once in the background (low priority, from the disk cache when there is one) and
    /// then polls only while the island shows the page or a Claude session is working. Idempotent.
    @MainActor public static func warmUp() {
        AgentsUsageModel.shared.startWarmup()
    }

    /// Stops the refresh and withdraws the activity.
    @MainActor public static func stopResting() {
        resting?.stop()
        resting = nil
    }
}
