import IslandTestSupport
import Testing
@testable import ShellKit

/// "Activer Dynamic Island": the migrated `notchEnabled` key, on when absent, and the hook the app uses to hide the panel.
@MainActor
@Suite struct IslandEnabledTests {
    @Test func absentMeansOnAndTheChoiceIsStoredAndAnnounced() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let home = HomeModel(defaults: b.defaults)
        #expect(home.islandEnabled)
        var seen: [Bool] = []
        home.onIslandEnabledChange = { seen.append($0) }
        home.islandEnabled = false
        #expect(b.defaults.object(forKey: "notchEnabled") as? Bool == false)
        #expect(seen == [false])
        #expect(!HomeModel(defaults: b.defaults).islandEnabled)
    }
}
