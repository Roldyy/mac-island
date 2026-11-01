import Foundation
import Testing
@testable import PortKit

/// The ported commands the extra dock lists: metadata only. Nothing here runs a command or reads a service.
@MainActor
@Suite struct PortDockCommandsTests {
    @Test func idsAreUniquePrefixedAndMatchThePinnedList() {
        let commands = PortDockCommands.all()
        let ids = commands.map(\.id)
        #expect(ids == PortDockCommands.ids)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("port.") })
    }

    @Test func everyCommandHasAFrenchTitleASymbolAndKeywords() {
        for command in PortDockCommands.all() {
            #expect(!command.title.isEmpty && !command.systemImage.isEmpty, "\(command.id)")
            #expect(!command.keywords.isEmpty, "\(command.id)")
        }
    }

    @Test func commandsThatDiscardDataAskFirst() throws {
        let commands = Dictionary(uniqueKeysWithValues: PortDockCommands.all().map { ($0.id, $0) })
        let clear = try #require(commands["port.clipboard.clearUnpinned"])
        let stop = try #require(commands["port.timer.stop"])
        #expect(clear.confirmation?.isEmpty == false)
        #expect(stop.confirmation?.isEmpty == false)
        // Nothing else in the list is destructive: the non-destructive ones never nag.
        let asking = Set(commands.values.filter { $0.confirmation != nil }.map(\.id))
        #expect(asking == ["port.clipboard.clearUnpinned", "port.timer.stop"])
    }

    @Test func commandsThatActOnTheScreenOrAnotherAppCloseTheIslandFirst() throws {
        let commands = Dictionary(uniqueKeysWithValues: PortDockCommands.all().map { ($0.id, $0) })
        for id in ["port.capture.scrolling", "port.record", "port.ocr", "port.color", "port.pasteplain", "port.launcher"] {
            #expect(try #require(commands[id]).closesIsland, "\(id)")
        }
        for id in ["port.micmute", "port.timer.start", "port.clipboard.clearUnpinned"] {
            #expect(try #require(commands[id]).closesIsland == false, "\(id)")
        }
    }

    @Test func toggleCommandsReportTheirState() throws {
        let commands = Dictionary(uniqueKeysWithValues: PortDockCommands.all().map { ($0.id, $0) })
        for id in ["port.record", "port.micmute", "port.timer.start"] {
            #expect(try #require(commands[id]).isOn != nil, "\(id)")
        }
    }
}
