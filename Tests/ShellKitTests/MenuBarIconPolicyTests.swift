import Foundation
import Testing
@testable import ShellKit

@MainActor
@Suite struct MenuBarIconPolicyTests {
    private func freshDefaults() -> UserDefaults {
        let name = "MenuBarIconPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func hiddenWhenTheKeyIsAbsent() {
        #expect(!MenuBarIconPolicy.isShown(defaults: freshDefaults()))
    }

    @Test func shownOnceSwitchedOnAndHiddenAgainWhenSwitchedOff() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: MenuBarIconPolicy.key)
        #expect(MenuBarIconPolicy.isShown(defaults: defaults))
        defaults.set(false, forKey: MenuBarIconPolicy.key)
        #expect(!MenuBarIconPolicy.isShown(defaults: defaults))
    }

    @Test func theKeyIsNotTheDeadUpstreamOne() {
        #expect(MenuBarIconPolicy.key == "menuBarIconShown")
    }

    @Test func visibleOnlyWhenTheUserAndTheMetricsBothAllow() {
        for user in [false, true] {
            for metrics in [false, true] {
                #expect(MenuBarIconPolicy.isVisible(userWantsIcon: user, metricsAllowIcon: metrics) == (user && metrics))
            }
        }
    }
}
