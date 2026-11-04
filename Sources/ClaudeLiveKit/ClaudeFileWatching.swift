import Darwin
import Foundation

/// Tells the monitor that something under the watched paths changed. Never says what: the monitor re-reads.
public protocol ClaudeFileWatching: AnyObject, Sendable {
    /// Arms every path that exists and is not armed yet, drops the ones no longer listed. Idempotent: the
    /// monitor calls it again at each slow tick, which is how a folder that appears later gets armed.
    /// `onEvent` may be called from any thread.
    func watch(_ paths: [String], onEvent: @escaping @Sendable () -> Void)
    func stop()
}

/// `DispatchSource` file-system events on an `O_EVTONLY` descriptor (no read access, no lock on the file).
/// A directory source fires on entries added or removed; Claude Code also rewrites a session file in place,
/// which only a source on that file sees, so the monitor lists the session files as paths too.
public final class DispatchFileWatcher: ClaudeFileWatching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "be.roldy.macisland.claude-live-watch", qos: .utility)
    private let lock = NSLock()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var handler: (@Sendable () -> Void)?

    public init() {}

    public func watch(_ paths: [String], onEvent: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        handler = onEvent
        let wanted = Set(paths)
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in wanted where sources[path] == nil { arm(path) }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        for source in sources.values { source.cancel() }
        sources.removeAll()
        handler = nil
    }

    /// Caller holds the lock.
    private func arm(_ path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }   // not there yet: the next call tries again
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            // The descriptor now points at a dead inode: drop it, the next `watch` arms the new one.
            if !source.data.isDisjoint(with: [.delete, .rename]) { self.drop(path, source) }
            self.fire()
        }
        source.setCancelHandler { close(fd) }
        sources[path] = source
        source.resume()
    }

    private func drop(_ path: String, _ source: DispatchSourceFileSystemObject) {
        lock.lock()
        if sources[path] === source { sources[path] = nil }
        lock.unlock()
        source.cancel()
    }

    private func fire() {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?()
    }
}
