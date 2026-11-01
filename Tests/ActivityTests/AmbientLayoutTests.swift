import Foundation
import IslandUI
import Testing
@testable import IslandKit

@Suite struct AmbientLayoutTests {
    private func item(_ id: String, _ priority: ActivityPriority = .ambient, urgent: Bool = false,
                      wing: AmbientWing? = nil, channel: String? = nil) -> AmbientIndicator {
        AmbientIndicator(id: id, channel: channel ?? id, symbol: "circle", text: id, priority: priority, isUrgent: urgent, wing: wing)
    }

    private func ids(_ items: [AmbientIndicator]) -> [String] { items.map(\.id) }

    /// Settings for ad-hoc channels: they are not user-facing, so they are always enabled.
    private func settings(perWing: Int = 2, rotates: Bool = true, order: [String] = []) -> ClosedIslandSettings {
        ClosedIslandSettings(order: order, rotates: rotates, maxPerWing: perWing)
    }

    // MARK: Priority and order

    @Test func higherPriorityComesFirstInItsWing() {
        let out = ClosedIslandLayout.resolve(
            [item("a", .ambient, wing: .trailing), item("m", .music, wing: .trailing)], settings: settings())
        #expect(ids(out.trailing) == ["m", "a"])
    }

    @Test func equalPriorityFollowsTheUserOrderThenId() {
        let low = AmbientIndicator(id: "x1", channel: AmbientChannel.network, symbol: "c", text: "1")
        let high = AmbientIndicator(id: "x2", channel: AmbientChannel.limits, symbol: "c", text: "1")
        let byDefault = ClosedIslandLayout.resolve([low, high], settings: settings())
        #expect(ids(byDefault.leading) == ["x2", "x1"])  // limits before network in the default order
        let swapped = ClosedIslandLayout.resolve(
            [low, high], settings: settings(order: [AmbientChannel.network, AmbientChannel.limits]))
        #expect(ids(swapped.leading) == ["x1", "x2"])
    }

    @Test func sameInputInAnyOrderGivesTheSameOutput() {
        let input = [item("a"), item("b"), item("c"), item("d", .music), item("e", urgent: true), item("f", .claudeWorking)]
        let reference = ClosedIslandLayout.resolve(input, settings: settings())
        for _ in 0..<20 {
            #expect(ClosedIslandLayout.resolve(input.shuffled(), settings: settings()) == reference)
        }
    }

    @Test func duplicateIdsCountOnce() {
        let out = ClosedIslandLayout.resolve([item("a", .ambient), item("a", .music)], settings: settings())
        #expect(out.all.count == 1)
        #expect(out.all.first?.priority == .music)  // the better ranked copy wins
    }

    // MARK: Urgent pinning

    @Test func urgentItemsPinFirstAndNeverRotate() {
        let input = [item("u", urgent: true, wing: .leading), item("a", wing: .leading), item("b", wing: .leading),
                     item("c", wing: .leading)]
        for step in 0..<6 {
            let out = ClosedIslandLayout.resolve(input, settings: settings(), step: step)
            #expect(out.leading.first?.id == "u")
            #expect(out.leading.count == 2)
        }
        // The one free slot cycles through a, b, c.
        let seen = (0..<3).map { ClosedIslandLayout.resolve(input, settings: settings(), step: $0).leading.last?.id }
        #expect(seen == ["a", "b", "c"])
    }

    @Test func liveClaudeAndAlertsPinWithoutBeingUrgent() {
        #expect(item("w", .claudeWorking).isPinned)
        #expect(item("x", .alert).isPinned)
        #expect(!item("m", .music).isPinned)
        #expect(!item("a", .ambient).isPinned)
        #expect(item("a", .ambient, urgent: true).isPinned)
    }

    @Test func morePinnedThanRoomKeepsTheBestRanked() {
        let input = [item("w1", .claudeWaiting, urgent: true), item("w2", .alert, urgent: true),
                     item("w3", .claudeWorking, urgent: true), item("w4", .claudeWorking)]
        let out = ClosedIslandLayout.resolve(input, settings: settings(perWing: 1))
        #expect(out.all.count == 2)
        #expect(Set(ids(out.all)) == ["w2", "w1"])
    }

    @Test func aWingFilledByPinnedItemsSendsTheOthersToTheOtherWing() {
        let input = [item("p1", .alert, urgent: true, wing: .leading), item("p2", .alert, urgent: true, wing: .leading),
                     item("a", wing: .leading)]
        let out = ClosedIslandLayout.resolve(input, settings: settings())
        #expect(ids(out.leading) == ["p1", "p2"])
        #expect(ids(out.trailing) == ["a"])
    }

    // MARK: Wing capacity

    @Test func neverMoreThanTwoPerWing() {
        let input = (0..<9).map { item("i\($0)") }
        let out = ClosedIslandLayout.resolve(input, settings: settings())
        #expect(out.leading.count <= 2)
        #expect(out.trailing.count <= 2)
    }

    @Test func onePerWingIsHonored() {
        let input = (0..<5).map { item("i\($0)") }
        let out = ClosedIslandLayout.resolve(input, settings: settings(perWing: 1))
        #expect(out.leading.count == 1)
        #expect(out.trailing.count == 1)
    }

    @Test func perWingIsClampedToOneOrTwo() {
        #expect(ClosedIslandSettings(maxPerWing: 0).maxPerWing == 1)
        #expect(ClosedIslandSettings(maxPerWing: 9).maxPerWing == 2)
    }

    @Test func itemsWithoutPreferenceBalanceTheWings() {
        let out = ClosedIslandLayout.resolve([item("a"), item("b"), item("c"), item("d")], settings: settings())
        #expect(out.leading.count == 2)
        #expect(out.trailing.count == 2)
        let two = ClosedIslandLayout.resolve([item("a"), item("b")], settings: settings())
        #expect(two.leading.count == 1 && two.trailing.count == 1)
    }

    @Test func aWingPreferenceIsKeptWhenThereIsRoom() {
        let out = ClosedIslandLayout.resolve([item("a", wing: .trailing), item("b", wing: .trailing)], settings: settings())
        #expect(ids(out.trailing) == ["a", "b"])
        #expect(out.leading.isEmpty)
    }

    // MARK: Rotation

    @Test func nothingRotatesWhileEverythingFits() {
        let out = ClosedIslandLayout.resolve([item("a", wing: .leading), item("b", wing: .trailing)], settings: settings(), step: 5)
        #expect(out.pageCount == 1 && out.step == 0 && !out.isRotating && out.nextStep == 0)
    }

    @Test func rotationVisitsEveryItemInOrderAndWraps() {
        let input = (1...5).map { item("t\($0)", wing: .trailing) }
        let pages = (0..<3).map { ClosedIslandLayout.resolve(input, settings: settings(), step: $0) }
        #expect(pages.map { ids($0.trailing) } == [["t1", "t2"], ["t3", "t4"], ["t5"]])
        #expect(pages.allSatisfy { $0.pageCount == 3 })
        #expect(pages.map(\.nextStep) == [1, 2, 0])
        #expect(ClosedIslandLayout.resolve(input, settings: settings(), step: 3).step == 0)  // wraps
        #expect(ClosedIslandLayout.resolve(input, settings: settings(), step: -1).step == 2)  // never negative
    }

    @Test func aStaticWingStaysWhileTheOtherRotates() {
        let input = [item("l", wing: .leading)] + (1...3).map { item("t\($0)", wing: .trailing) }
        for step in 0..<4 {
            let out = ClosedIslandLayout.resolve(input, settings: settings(perWing: 1), step: step)
            #expect(ids(out.leading) == ["l"])
            #expect(out.trailing.count == 1)
        }
    }

    @Test func rotationOffShowsTheFirstPageForever() {
        let input = (1...5).map { item("t\($0)", wing: .trailing) }
        for step in 0..<4 {
            let out = ClosedIslandLayout.resolve(input, settings: settings(rotates: false), step: step)
            #expect(ids(out.trailing) == ["t1", "t2"])
            #expect(out.pageCount == 1 && !out.isRotating)
        }
    }

    @Test func aWithdrawnItemShortensTheRotation() {
        var input = (1...3).map { item("t\($0)", wing: .trailing) }
        #expect(ClosedIslandLayout.resolve(input, settings: settings()).pageCount == 2)
        input.removeLast()
        #expect(ClosedIslandLayout.resolve(input, settings: settings(), step: 1).pageCount == 1)
    }

    // MARK: Disabled indicators

    @Test func disabledChannelsAreSkipped() {
        var s = settings()
        s.enabled.remove(AmbientChannel.battery)
        let battery = AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "b", text: "1")
        let limits = AmbientIndicator(id: "limits", channel: AmbientChannel.limits, symbol: "l", text: "1")
        let out = ClosedIslandLayout.resolve([battery, limits], settings: s)
        #expect(ids(out.all) == ["limits"])
    }

    @Test func aDisabledChannelDoesNotTakeARotationSlot() {
        var s = settings()
        s.enabled = [AmbientChannel.limits]
        let input = [
            AmbientIndicator(id: "limits", channel: AmbientChannel.limits, symbol: "l", text: "1", wing: .trailing),
            AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "b", text: "1", wing: .trailing),
            AmbientIndicator(id: "keepawake", channel: AmbientChannel.keepAwake, symbol: "k", text: "1", wing: .trailing),
        ]
        let out = ClosedIslandLayout.resolve(input, settings: s)
        #expect(ids(out.all) == ["limits"])
        #expect(out.pageCount == 1)
    }

    @Test func alertsAreNeverSwitchedOff() {
        var s = settings()
        s.enabled = []
        let alert = AmbientIndicator(id: "alert.0", channel: AmbientChannel.alert, symbol: "x", priority: .alert)
        #expect(ClosedIslandLayout.resolve([alert], settings: s).all.count == 1)
    }

    @Test func everythingOffLeavesTheIslandEmpty() {
        var s = settings()
        s.enabled = []
        let all = AmbientChannel.userChoices.map { AmbientIndicator(id: $0, channel: $0, symbol: "x") }
        #expect(ClosedIslandLayout.resolve(all, settings: s).isEmpty)
    }
}
