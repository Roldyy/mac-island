import Foundation

/// Watches a folder with a DispatchSource and publishes snapshots on the main queue.
/// All state lives on one serial queue. Never logs file names.
final class DownloadsMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "be.roldy.macisland.downloads")
    private let directory: URL
    private let limit: @Sendable () -> Int
    private let onSnapshot: @Sendable (DownloadsSnapshot) -> Void
    private var tracker: DownloadTracker
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private var started = false

    init(directory: URL, settle: TimeInterval = 2, limit: @escaping @Sendable () -> Int,
         onSnapshot: @escaping @Sendable (DownloadsSnapshot) -> Void) {
        self.directory = directory
        self.tracker = DownloadTracker(settle: settle)
        self.limit = limit
        self.onSnapshot = onSnapshot
    }

    /// Idempotent.
    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            scan()
            attach()
        }
    }

    func refresh() { queue.async { [self] in scan() } }

    func stop() {
        queue.async { [self] in
            source?.cancel(); source = nil
            debounce?.cancel(); debounce = nil
            started = false
        }
    }

    private func attach() {
        guard source == nil else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }  // denied or missing: the snapshot already says so
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleScan(after: 0.4) }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleScan(after delay: TimeInterval) {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scan() }
        debounce = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scan() {
        let snap = DownloadsLister.list(directory: directory, limit: limit(), now: Date(), tracker: &tracker)
        if snap.state == .ok { attach() }
        let publish = onSnapshot
        DispatchQueue.main.async { publish(snap) }
        if snap.hasPending { scheduleScan(after: tracker.settle + 0.5) }
    }
}
