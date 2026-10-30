import Foundation
import Testing
@testable import AudioFeature

@Suite struct DevicePriorityResolverTests {
    let now = Date(timeIntervalSince1970: 5_000)

    @Test func picksHighestPriorityAvailable() {
        #expect(DevicePriorityResolver.resolve(available: ["b", "c"], priority: ["a", "b", "c"], current: "c") == "b")
    }

    @Test func nilWhenCurrentIsAlreadyBest() {
        #expect(DevicePriorityResolver.resolve(available: ["a", "b"], priority: ["a", "b"], current: "a") == nil)
    }

    @Test func nilWhenNothingListedIsAvailable() {
        #expect(DevicePriorityResolver.resolve(available: ["x"], priority: ["a", "b"], current: "x") == nil)
    }

    @Test func nilWhenPriorityIsEmpty() {
        #expect(DevicePriorityResolver.resolve(available: ["a"], priority: [], current: nil) == nil)
    }

    @Test func listedDeviceBeatsUnlistedCurrent() {
        #expect(DevicePriorityResolver.resolve(available: ["x", "b"], priority: ["a", "b"], current: "x") == "b")
    }

    @Test func noCurrentSelectsBest() {
        #expect(DevicePriorityResolver.resolve(available: ["a"], priority: ["a"], current: nil) == "a")
    }

    @Test func duplicateInPriorityFirstWins() {
        #expect(DevicePriorityResolver.resolve(available: ["a", "b", "a"], priority: ["b", "a", "b"], current: "a") == "b")
    }

    @Test func manualChangeInsideGraceIsNotFought() {
        let manual = now.addingTimeInterval(-3)
        let r = DevicePriorityResolver.resolve(available: ["a", "b"], priority: ["a", "b"], current: "b",
                                               lastManualChange: manual, now: now, grace: 10)
        #expect(r == nil)
    }

    @Test func manualChangeOutsideGraceIsOverridden() {
        let manual = now.addingTimeInterval(-11)
        let r = DevicePriorityResolver.resolve(available: ["a", "b"], priority: ["a", "b"], current: "b",
                                               lastManualChange: manual, now: now, grace: 10)
        #expect(r == "a")
    }

    @Test func manualChangeNeverKeepsAnUnavailableDevice() {
        let manual = now.addingTimeInterval(-1)
        let r = DevicePriorityResolver.resolve(available: ["a"], priority: ["a", "b"], current: "b",
                                               lastManualChange: manual, now: now, grace: 10)
        #expect(r == "a")
    }
}
