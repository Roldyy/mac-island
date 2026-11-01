import Foundation
@testable import PortKit

/// The fakes of lane W4-D. Nothing here touches the real disk (beyond what a test creates itself), the real wallpaper,
/// a real process or the clock.

/// A file system on a dictionary. A path exists when it is a file, a directory or a link; removing a directory removes
/// everything under it, like `FileManager.removeItem`.
final class FakeMediaFileSystem: MediaFileSystem {
    var files: [String: Data] = [:]
    var directories: Set<String> = []
    var links: Set<String> = []
    var executables: Set<String> = []
    var modes: [String: Int] = [:]
    var removed: [String] = []
    var writes: [String] = []
    var failWrites = false

    struct Failure: Error {}

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path) || links.contains(path)
    }

    func isExecutableFile(atPath path: String) -> Bool { executables.contains(path) }
    func isDirectory(atPath path: String) -> Bool { directories.contains(path) }
    func isSymbolicLink(atPath path: String) -> Bool { links.contains(path) }

    func contentsOfDirectory(atPath path: String) -> [String]? {
        guard directories.contains(path) else { return nil }
        let prefix = path + "/"
        var names: Set<String> = []
        for entry in Set(files.keys).union(directories).union(links) where entry.hasPrefix(prefix) {
            let rest = entry.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first { names.insert(String(first)) }
        }
        return names.sorted()
    }

    func createPrivateDirectory(atPath path: String) throws {
        guard !fileExists(atPath: path) else { throw Failure() }
        directories.insert(path)
        modes[path] = 0o700
    }

    func setPrivatePermissions(atPath path: String) throws {
        guard fileExists(atPath: path) else { throw Failure() }
        modes[path] = 0o700
    }

    func permissions(atPath path: String) -> Int? { modes[path] }
    func readData(atPath path: String) -> Data? { files[path] }

    func writeAtomically(_ data: Data, toPath path: String) throws {
        if failWrites { throw Failure() }
        files[path] = data
        writes.append(path)
    }

    func removeItem(atPath path: String) throws {
        guard fileExists(atPath: path) else { throw Failure() }
        let prefix = path + "/"
        files = files.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
        directories = directories.filter { $0 != path && !$0.hasPrefix(prefix) }
        links = links.filter { $0 != path && !$0.hasPrefix(prefix) }
        removed.append(path)
    }
}

/// A program that runs for a scripted time on a fake clock. `exitsAfter` is the number of polls before it ends by
/// itself; `ignoresTerminate` keeps it alive until it is killed.
final class FakeProcessHandle: MediaProcessHandle {
    var running = true
    var status: Int32 = 0
    var ignoresTerminate = false
    var terminateCalls = 0
    var killCalls = 0
    var exitsAfter: Int?
    var polls = 0

    var isRunning: Bool {
        polls += 1
        if let exitsAfter, polls > exitsAfter { running = false }
        return running
    }

    var terminationStatus: Int32 { status }

    func terminate() {
        terminateCalls += 1
        if !ignoresTerminate { running = false }
    }

    func forceKill() {
        killCalls += 1
        running = false
    }
}

/// A clock that only moves when somebody sleeps.
final class FakeClock {
    var time: TimeInterval = 0
    var sleeps: [TimeInterval] = []

    var clock: MediaClock {
        MediaClock(now: { self.time }, sleep: { seconds in
            self.sleeps.append(seconds)
            self.time += seconds
        })
    }
}

/// Captures the commands it is asked to run and answers with a script. When asked, it also does what avconvert would:
/// writes a file at the `--output` path.
final class FakeMediaProcessRunner: MediaProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [MediaToolCommand] = []
    private var _limits: [MediaRunLimits] = []
    private var _outputFolderModes: [Int?] = []
    var outcome: MediaRunOutcome = .finished(status: 0, log: "")
    /// Written at `--output` before the outcome is returned.
    var outputBytes: Data? = Data("fake-encoded".utf8)
    /// Blocks until the cancel is seen, then answers `.cancelled` (a running converter).
    var blocksUntilCancelled = false
    private var _entered = false

    var commands: [MediaToolCommand] { lock.lock(); defer { lock.unlock() }; return _commands }
    var limits: [MediaRunLimits] { lock.lock(); defer { lock.unlock() }; return _limits }
    var outputFolderModes: [Int?] { lock.lock(); defer { lock.unlock() }; return _outputFolderModes }
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return _entered }

    func run(_ command: MediaToolCommand, limits: MediaRunLimits, isCancelled: @escaping () -> Bool,
             launch: (Process) throws -> Void, onTick: (TimeInterval) -> Void) throws -> MediaRunOutcome {
        lock.lock()
        _commands.append(command)
        _limits.append(limits)
        if let index = command.arguments.firstIndex(of: "--output"), index + 1 < command.arguments.count {
            let output = command.arguments[index + 1]
            _outputFolderModes.append(LiveMediaFileSystem().permissions(atPath: (output as NSString).deletingLastPathComponent))
        }
        _entered = true
        lock.unlock()
        if blocksUntilCancelled {
            while !isCancelled() { Thread.sleep(forTimeInterval: 0.01) }
            return .cancelled
        }
        if case .finished(let status, _) = outcome, status == 0, let outputBytes,
           let index = command.arguments.firstIndex(of: "--output") {
            try outputBytes.write(to: URL(fileURLWithPath: command.arguments[index + 1]))
        }
        return outcome
    }
}

/// Two screens, an image per screen, and a log of what was set.
final class FakeWallpaperDesktop: WallpaperDesktop {
    var images: [String: URL] = [:]
    var failingScreens: Set<String> = []
    var setCalls: [(id: String, url: URL)] = []

    struct Failure: Error {}

    func screenIDs() -> [String] { images.keys.sorted() }
    func currentImage(forScreen id: String) -> URL? { images[id] }

    func setImage(_ url: URL, forScreen id: String) throws {
        if failingScreens.contains(id) { throw Failure() }
        setCalls.append((id, url))
        images[id] = url
    }
}
