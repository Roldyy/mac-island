import Foundation
import Testing
@testable import FinderFeature

@Suite struct MovePlannerTests {
    let fs = SystemFileInspector()

    @Test func plansSimpleMove() throws {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("src/a.txt"))
        let dest = mkdir(root.appendingPathComponent("dst"))
        let plan = try MovePlanner.plan(items: [f], destination: dest, inspector: fs).get()
        #expect(plan.moves.count == 1)
        #expect(plan.skippedSameFolder == 0)
    }
    @Test func refusesNoItems() {
        let dest = mkdir(makeTempDir().appendingPathComponent("d"))
        #expect(throws: MoveRefusal.noItems) { try MovePlanner.plan(items: [], destination: dest, inspector: fs).get() }
    }
    @Test func refusesIntoItself() {
        let root = makeTempDir()
        let dir = mkdir(root.appendingPathComponent("a"))
        let inner = mkdir(dir.appendingPathComponent("inner"))
        #expect(throws: MoveRefusal.intoItself) { try MovePlanner.plan(items: [dir], destination: inner, inspector: fs).get() }
        #expect(throws: MoveRefusal.intoItself) { try MovePlanner.plan(items: [dir], destination: dir, inspector: fs).get() }
    }
    @Test func refusesIntoItselfThroughSymlinkedDestination() throws {
        let root = makeTempDir()
        let dir = mkdir(root.appendingPathComponent("a"))
        let inner = mkdir(dir.appendingPathComponent("inner"))
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: inner)
        #expect(throws: MoveRefusal.intoItself) { try MovePlanner.plan(items: [dir], destination: link, inspector: fs).get() }
    }
    @Test func symlinkItemMovesTheLinkEvenIfDestinationIsInsideItsTarget() throws {
        let root = makeTempDir()
        let target = mkdir(root.appendingPathComponent("target"))
        let inside = mkdir(target.appendingPathComponent("inside"))
        let link = root.appendingPathComponent("lnk")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let plan = try MovePlanner.plan(items: [link], destination: inside, inspector: fs).get()
        #expect(plan.moves.count == 1)
    }
    @Test func sameFolderIsNoOp() {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("a.txt"))
        #expect(throws: MoveRefusal.sameFolder) { try MovePlanner.plan(items: [f], destination: root, inspector: fs).get() }
    }
    @Test func sameFolderItemsAreSkippedOthersKept() throws {
        let root = makeTempDir()
        let here = touch(root.appendingPathComponent("here.txt"))
        let other = touch(root.appendingPathComponent("o/other.txt"))
        let plan = try MovePlanner.plan(items: [here, other], destination: root, inspector: fs).get()
        #expect(plan.moves.map(\.source) == [other])
        #expect(plan.skippedSameFolder == 1)
    }
    @Test func refusesMissingOrUnreadableOrFileDestination() {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("s/a.txt"))
        let missing = root.appendingPathComponent("nope")
        #expect(throws: MoveRefusal.destinationUnavailable) { try MovePlanner.plan(items: [f], destination: missing, inspector: fs).get() }
        let notDir = touch(root.appendingPathComponent("file.txt"))
        #expect(throws: MoveRefusal.destinationUnavailable) { try MovePlanner.plan(items: [f], destination: notDir, inspector: fs).get() }
        let locked = mkdir(root.appendingPathComponent("locked"))
        try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        #expect(throws: MoveRefusal.destinationUnavailable) { try MovePlanner.plan(items: [f], destination: locked, inspector: fs).get() }
    }
    @Test func capNeedsConfirmation() throws {
        let root = makeTempDir()
        let dest = mkdir(root.appendingPathComponent("d"))
        let items = (0...MovePlanner.maxItems).map { URL(fileURLWithPath: "/nonexistent/src/f\($0)") }
        #expect(throws: MoveRefusal.needsConfirmation(count: items.count)) {
            try MovePlanner.plan(items: items, destination: dest, inspector: fs).get()
        }
        let plan = try MovePlanner.plan(items: items, destination: dest, inspector: fs, confirmedLarge: true).get()
        #expect(plan.moves.count == items.count)
    }
    @Test func nestedSelectionDropsChild() throws {
        let root = makeTempDir()
        let dir = mkdir(root.appendingPathComponent("s/dir"))
        let child = touch(dir.appendingPathComponent("c.txt"))
        let dest = mkdir(root.appendingPathComponent("d"))
        let plan = try MovePlanner.plan(items: [dir, child], destination: dest, inspector: fs).get()
        #expect(plan.moves.map(\.source) == [dir])
    }
}
