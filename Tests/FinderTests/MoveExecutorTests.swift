import Foundation
import Testing
@testable import FinderFeature

final class FakeMover: FileMoving, @unchecked Sendable {
    private let lock = NSLock()
    var failing: Set<String> = []
    private(set) var calls: [(URL, URL)] = []
    func move(from: URL, to: URL) throws {
        lock.lock(); defer { lock.unlock() }
        calls.append((from, to))
        if failing.contains(from.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
    }
}

@Suite struct MoveExecutorTests {
    let fs = SystemFileInspector()

    func plan(_ items: [URL], _ dest: URL) throws -> MovePlan {
        try MovePlanner.plan(items: items, destination: dest, inspector: fs).get()
    }

    @Test func realMoveRemovesSource() throws {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("s/a.txt"), "hello")
        let dest = mkdir(root.appendingPathComponent("d"))
        let r = MoveExecutor.run(try plan([f], dest), inspector: fs, mover: FileManagerMover())
        #expect(r == MoveReport(moved: 1, failedSources: [], skipped: 0))
        #expect(!FileManager.default.fileExists(atPath: f.path))
        #expect(try String(contentsOf: dest.appendingPathComponent("a.txt")) == "hello")
    }
    @Test func neverOverwritesAndNamesUniquely() throws {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("s/a.txt"), "new")
        let dest = mkdir(root.appendingPathComponent("d"))
        touch(dest.appendingPathComponent("a.txt"), "old")
        touch(dest.appendingPathComponent("a 2.txt"), "old2")
        let r = MoveExecutor.run(try plan([f], dest), inspector: fs, mover: FileManagerMover())
        #expect(r.moved == 1)
        #expect(try String(contentsOf: dest.appendingPathComponent("a.txt")) == "old")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 2.txt")) == "old2")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 3.txt")) == "new")
    }
    @Test func sameNamesFromTwoFoldersBothLand() throws {
        let root = makeTempDir()
        let a = touch(root.appendingPathComponent("s1/a.txt"), "1")
        let b = touch(root.appendingPathComponent("s2/a.txt"), "2")
        let dest = mkdir(root.appendingPathComponent("d"))
        let r = MoveExecutor.run(try plan([a, b], dest), inspector: fs, mover: FileManagerMover())
        #expect(r.moved == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
        #expect(names == ["a 2.txt", "a.txt"])
    }
    @Test func symlinkMovesAsLinkNotTarget() throws {
        let root = makeTempDir()
        let target = touch(root.appendingPathComponent("t/real.txt"), "payload")
        let link = root.appendingPathComponent("s/lnk")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let dest = mkdir(root.appendingPathComponent("d"))
        let r = MoveExecutor.run(try plan([link], dest), inspector: fs, mover: FileManagerMover())
        #expect(r.moved == 1)
        let moved = dest.appendingPathComponent("lnk")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: moved.path)) == target.path)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }
    @Test func partialFailureIsReported() throws {
        let root = makeTempDir()
        let a = touch(root.appendingPathComponent("s/ok.txt"))
        let b = touch(root.appendingPathComponent("s/bad.txt"))
        let dest = mkdir(root.appendingPathComponent("d"))
        let mover = FakeMover(); mover.failing = ["bad.txt"]
        let r = MoveExecutor.run(try plan([a, b], dest), inspector: fs, mover: mover)
        #expect(r.moved == 1)
        #expect(r.failedSources == [b])
        #expect(r.isPartial)
    }
    @Test func missingSourceFailsWithoutThrowing() throws {
        let root = makeTempDir()
        let ghost = root.appendingPathComponent("s/ghost.txt")
        let dest = mkdir(root.appendingPathComponent("d"))
        let r = MoveExecutor.run(try plan([ghost], dest), inspector: fs, mover: FileManagerMover())
        #expect(r.moved == 0)
        #expect(r.failedSources == [ghost])
    }
    @Test func collisionNamer() {
        let dir = URL(fileURLWithPath: "/d")
        let taken: Set<String> = ["/d/a.txt", "/d/a 2.txt", "/d/.hidden", "/d/noext"]
        let ex: (URL) -> Bool = { taken.contains($0.path) }
        #expect(CollisionNamer.unique(name: "a.txt", in: dir, exists: ex)?.lastPathComponent == "a 3.txt")
        #expect(CollisionNamer.unique(name: "b.txt", in: dir, exists: ex)?.lastPathComponent == "b.txt")
        #expect(CollisionNamer.unique(name: ".hidden", in: dir, exists: ex)?.lastPathComponent == ".hidden 2")
        #expect(CollisionNamer.unique(name: "noext", in: dir, exists: ex)?.lastPathComponent == "noext 2")
        #expect(CollisionNamer.unique(name: "x", in: dir, exists: { _ in true }) == nil)
    }
}
