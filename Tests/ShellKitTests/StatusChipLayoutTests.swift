import Foundation
import Testing
@testable import ShellKit

@Suite struct StatusChipLayoutTests {
    @Test func theDefaultOrderIsNetworkLoadNextEvent() {
        #expect(StatusChipLayout.initial.kinds == [.network, .load, .nextEvent])
        #expect(StatusChipLayout.decode(nil) == .initial)
    }

    @Test func everyKindHasAFrenchTitleASummaryAndASymbol() {
        #expect(StatusChipKind.allCases.count == 9)
        for kind in StatusChipKind.allCases {
            #expect(!kind.title.isEmpty && !kind.summary.isEmpty && !kind.symbol.isEmpty, "\(kind)")
        }
        #expect(Set(StatusChipKind.allCases.map(\.title)).count == 9)
    }

    @Test func enableAppendsOnceAndDisableRemoves() {
        var layout = StatusChipLayout.initial
        let step21 = layout.enable(.disk)
        #expect(step21)
        #expect(layout.kinds == [.network, .load, .nextEvent, .disk])
        let step23 = layout.enable(.disk)
        #expect(!step23)
        layout.disable(.load)
        #expect(layout.kinds == [.network, .nextEvent, .disk])
        layout.setEnabled(.load, true)
        layout.setEnabled(.network, false)
        #expect(layout.kinds == [.nextEvent, .disk, .load])
        #expect(!layout.disabledKinds.contains(.load) && layout.disabledKinds.contains(.network))
    }

    @Test func moveBeforePutsTheChipJustBeforeTheTarget() {
        var layout = StatusChipLayout(kinds: [.network, .load, .nextEvent, .disk])
        let step34 = layout.move(.disk, before: .load)
        #expect(step34)
        #expect(layout.kinds == [.network, .disk, .load, .nextEvent])
        let step36 = layout.move(.network, before: nil)
        #expect(step36)
        #expect(layout.kinds == [.disk, .load, .nextEvent, .network])
        // Onto itself: nothing changes, and it still counts as done.
        let step39 = layout.move(.load, before: .load)
        #expect(step39)
        #expect(layout.kinds == [.disk, .load, .nextEvent, .network])
        // A chip that is not enabled, or a target that is not enabled, is refused.
        let step42 = layout.move(.timer, before: .load)
        #expect(!step42)
        let step43 = layout.move(.load, before: .timer)
        #expect(!step43)
        #expect(layout.kinds == [.disk, .load, .nextEvent, .network])
    }

    @Test func reorderSwapsWithTheNeighbourAndStopsAtTheEnds() {
        var layout = StatusChipLayout.initial
        let step49 = layout.reorder(.load, by: -1)
        #expect(step49)
        #expect(layout.kinds == [.load, .network, .nextEvent])
        let step51 = layout.reorder(.load, by: -1)
        #expect(!step51)
        let step52 = layout.reorder(.load, by: 1)
        #expect(step52)
        let step53 = layout.reorder(.nextEvent, by: 1)
        #expect(!step53)
        let step54 = layout.reorder(.timer, by: 1)
        #expect(!step54)
    }

    @Test func sanitizedKeepsTheFirstOfEachKind() {
        let layout = StatusChipLayout(kinds: [.load, .network, .load, .network, .disk])
        #expect(layout.sanitized().kinds == [.load, .network, .disk])
    }

    @Test func theStoredFormIsVersionedJSONAndRoundTrips() throws {
        let layout = StatusChipLayout(kinds: [.timer, .network, .batteryHealth])
        let data = try #require(layout.encoded())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["ids"] as? [String] == ["timer", "network", "batteryHealth"])
        #expect(StatusChipLayout.decode(data) == layout)
    }

    @Test func aStoredEmptyListStaysEmpty() throws {
        let data = try #require(StatusChipLayout(kinds: []).encoded())
        #expect(StatusChipLayout.decode(data).kinds.isEmpty)
    }

    @Test func aNewerVersionOrDamagedDataGivesTheDefaults() {
        let newer = Data(#"{"version":2,"ids":["disk"]}"#.utf8)
        #expect(StatusChipLayout.decode(newer) == .initial)
        #expect(StatusChipLayout.decode(Data("not json".utf8)) == .initial)
        #expect(StatusChipLayout.decode(Data(#"{"ids":["disk"]}"#.utf8)) == .initial)
    }

    @Test func anUnknownIdIsDroppedAndRepeatsAreCollapsed() {
        let data = Data(#"{"version":1,"ids":["disk","hologram","disk","timer"]}"#.utf8)
        #expect(StatusChipLayout.decode(data).kinds == [.disk, .timer])
    }

    @Test func theDragPayloadRoundTripsAndRefusesOtherText() {
        for kind in StatusChipKind.allCases {
            #expect(StatusChipLayout.dragKind(from: StatusChipLayout.dragPayload(kind)) == kind)
        }
        #expect(StatusChipLayout.dragKind(from: "network") == nil)
        #expect(StatusChipLayout.dragKind(from: "mis.extradock:network") == nil)
        #expect(StatusChipLayout.dragKind(from: "mis.statuschip:hologram") == nil)
    }
}
