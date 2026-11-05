import Foundation

/// THE serial lane for every access to `NSPasteboard.general` (reads and writes alike).
///
/// NSPasteboard keeps a mutable type cache on its shared general instance. Two threads inside `types`,
/// `pasteboardItems`, `string(forType:)`, `clearContents()`... at once corrupt it (1.1.0 crash reports: SIGABRT in
/// `-[NSPasteboard _updateTypeCacheIfNeeded]`, array mutated during enumeration). So the whole app goes through this one
/// queue: the change hub, the clipboard watcher, auto clear, the URL cleaner, transient paste, every one-shot copy.
///
/// Rules: never `sync` it from the main thread (a pasteboard server that stops answering would freeze the app, and
/// `DispatchQueue.sync` onto a busy lane is exactly that); hand work with `async` and take the answer on main.
/// Other pasteboards (drag, find, `NSPasteboard(name:)`, app-private) have their own cache and stay off this lane.
/// Guard: `PasteboardLaneGuardTests` fails when a source file touches the general pasteboard elsewhere.
public final class GeneralPasteboardLane: @unchecked Sendable {
    public static let shared = GeneralPasteboardLane()
    public static let label = "Mac Island.Pasteboard.general"

    public let queue: DispatchQueue

    public init(label: String = GeneralPasteboardLane.label, queue: DispatchQueue? = nil) {
        self.queue = queue ?? DispatchQueue(label: label, qos: .utility)
    }

    /// Runs `work` on the lane, later. Returns at once.
    public func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` on the lane and hands its result to `completion` on the main queue.
    public func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }
}
