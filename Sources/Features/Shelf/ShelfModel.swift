import AppKit
import Foundation
import Observation

enum ShelfSegment: String, CaseIterable, Identifiable {
    case shelf = "Étagère"
    case downloads = "Téléchargements"
    var id: String { rawValue }
}

@MainActor @Observable
final class ShelfModel {
    var segment: ShelfSegment = .shelf
    private(set) var items: [ShelfItem] = []
    private(set) var downloads: DownloadsSnapshot = .init(state: .ok, items: [], hasPending: false)
    var isDropTargeted = false

    let settings: ShelfSettings
    private let store: ShelfStore
    private var monitor: DownloadsMonitor?
    private let downloadsDirectory: URL
    private var started = false

    var shelfEnabled: Bool { settings.shelfEnabled }
    var downloadsEnabled: Bool { settings.downloadsEnabled }

    init(settings: ShelfSettings = ShelfSettings(), dataDirectory: URL,
         downloadsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)) {
        self.settings = settings
        self.store = ShelfStore(directory: dataDirectory)
        self.downloadsDirectory = downloadsDirectory
    }

    /// Idempotent. Loads the shelf and starts the Downloads watcher (first read may show the
    /// system permission prompt once).
    func start() {
        guard !started else { return }
        started = true
        items = settings.loadItems(store: store)
        guard settings.downloadsEnabled else { return }
        let limit = settings.downloadsLimit
        let monitor = DownloadsMonitor(directory: downloadsDirectory, limit: { limit }) { [weak self] snap in
            Task { @MainActor in self?.downloads = snap }
        }
        self.monitor = monitor
        monitor.start()
    }

    // MARK: Shelf

    func add(_ urls: [URL]) {
        guard settings.shelfEnabled else { return }
        let next = ShelfItems.add(urls, to: items, now: Date()) { try? $0.bookmarkData() }
        guard next != items else { return }
        items = next
        persist()
    }

    func remove(_ item: ShelfItem) {
        items = ShelfItems.remove(item.id, from: items)
        persist()
    }

    func clear() {
        items = []
        persist()
    }

    private func persist() { try? store.save(items) }

    /// Drop of file URLs. Returns whether any provider was accepted.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard settings.shelfEnabled else { return false }
        let id = "public.file-url"
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(id) }
        for provider in matching {
            provider.loadItem(forTypeIdentifier: id, options: nil) { [weak self] item, _ in
                guard let url = ShelfDropDecoder.fileURL(from: item) else { return }
                Task { @MainActor in self?.add([url]) }
            }
        }
        return !matching.isEmpty
    }

    // MARK: Actions on a file

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        let url = item.resolvedURL() ?? URL(fileURLWithPath: item.path)
        return NSItemProvider(object: url as NSURL)
    }

    func dragProvider(path: String) -> NSItemProvider {
        NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
    }

    func reveal(path: String) {
        guard ShelfFileCheck.exists(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func icon(forPath path: String) -> NSImage {
        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 32, height: 32)
        return img
    }

    func refreshDownloads() { monitor?.refresh() }
}
