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
    /// One resolution per item (bookmark first): availability, icon, reveal and drag all read this.
    private(set) var resolved: [UUID: URL] = [:]
    private(set) var downloads: DownloadsSnapshot = .init(state: .ok, items: [], hasPending: false)
    var isDropTargeted = false

    let settings: ShelfSettings
    private let store: ShelfStore
    var storeDirectoryForTests: URL { store.directory }
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
        refreshItems()
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
        let next = ShelfItems.add(urls, to: items, now: Date(), makeBookmark: ShelfItem.makeBookmark)
        guard next != items else { return }
        items = next
        persist()
        refreshItems()
    }

    /// Resolves every item once. A file the user moved keeps working: its path (and a stale
    /// bookmark) is rewritten to where the bookmark points now. Cheap enough for appear / activate.
    func refreshItems() {
        var next = items
        var urls: [UUID: URL] = [:]
        for (index, item) in items.enumerated() {
            guard let found = item.resolve() else { continue }
            urls[item.id] = found.url
            if found.item != item { next[index] = found.item }
        }
        if urls != resolved { resolved = urls }
        if next != items {
            items = next
            persist()
        }
    }

    func url(for item: ShelfItem) -> URL? { resolved[item.id] }
    func isAvailable(_ item: ShelfItem) -> Bool { resolved[item.id] != nil }

    func remove(_ item: ShelfItem) {
        items = ShelfItems.remove(item.id, from: items)
        resolved[item.id] = nil
        persist()
    }

    func clear() {
        items = []
        resolved = [:]
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
        let url = resolved[item.id] ?? URL(fileURLWithPath: item.path)
        return NSItemProvider(object: url as NSURL)
    }

    func dragProvider(path: String) -> NSItemProvider {
        NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
    }

    func reveal(_ item: ShelfItem) {
        guard let url = resolved[item.id] else { return }
        reveal(path: url.path)
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
