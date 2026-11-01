import CryptoKit
import Foundation

/// Newest-first clipboard history, persisted under an injected directory.
/// Pure of AppKit: the directory and the clock are injected so tests use temp dirs.
/// Never logs content.
final class ClipboardHistoryStore {
    static let fileName = "ClipboardHistory.json"
    static let imagesFolder = "ClipboardImages"

    let directory: URL
    private let now: () -> Date
    private(set) var entries: [ClipboardEntry] = []
    /// Maximum number of UNPINNED entries. Pinned entries are never trimmed.
    var limit: Int {
        didSet { if trim() { save() } }
    }
    private(set) var lastSaveFailed = false

    init(directory: URL, limit: Int = 50, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.limit = max(1, limit)
        self.now = now
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    private var imagesURL: URL { directory.appendingPathComponent(Self.imagesFolder, isDirectory: true) }

    // MARK: - Loading

    private struct Lossy: Decodable {
        let entry: ClipboardEntry?
        init(from decoder: Decoder) throws { entry = try? ClipboardEntry(from: decoder) }
    }
    private struct Wrapped: Decodable { let entries: [Lossy] }

    /// Where the file as found is kept when loading it would lose something (see `keepOriginalBeforeRepair`).
    static let repairBackupName = "ClipboardHistory.before-repair.json"

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { entries = []; return }
        let decoder = JSONDecoder()
        let lossy = (try? decoder.decode([Lossy].self, from: data))
            ?? (try? decoder.decode(Wrapped.self, from: data))?.entries
        var seen = Set<String>()
        // Duplicate ids would break list identity: keep the first.
        entries = (lossy ?? []).compactMap(\.entry).filter { seen.insert($0.id).inserted }
        // The next save rewrites the file from `entries`: whatever did not decode would be gone for good.
        let lostSomething = lossy.map { entries.count != $0.count } ?? !data.isEmpty
        if lostSomething { keepOriginalBeforeRepair(data) }
        if trim() { save() }
    }

    /// The history file is the user's data. When it holds something this store cannot read (an unknown kind, a
    /// damaged entry, a file that is not JSON at all), the first save would overwrite it with the readable part.
    /// So the original bytes go to a sibling file first, owner-only, and an existing backup is never replaced: the
    /// first copy is the closest to what the user had. Nothing is ever deleted here.
    private func keepOriginalBeforeRepair(_ data: Data) {
        let backup = directory.appendingPathComponent(Self.repairBackupName)
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? PrivateFiles.writeAtomic(data, to: backup)
    }

    // MARK: - Adding

    @discardableResult
    func addText(_ text: String, source: String?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let top = entries.first, top.kind == .text, top.text == text { return false }
        insert(ClipboardEntry(kind: .text, text: text, sourceBundleID: source, copiedAt: now()))
        return true
    }

    @discardableResult
    func addFiles(_ paths: [String], source: String?) -> Bool {
        guard !paths.isEmpty else { return false }
        if let top = entries.first, top.kind == .files, top.filePaths == paths { return false }
        insert(ClipboardEntry(kind: .files, text: ClipboardEntry.fileLabel(for: paths), filePaths: paths, sourceBundleID: source, copiedAt: now()))
        return true
    }

    @discardableResult
    func addImage(png: Data, width: Int, height: Int, source: String?) -> Bool {
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if let top = entries.first, top.kind == .image, top.imageHash == hash { return false }
        let id = UUID().uuidString
        let file = "\(id).png"
        do {
            try PrivateFiles.ensureDirectory(directory)
            try PrivateFiles.ensureDirectory(imagesURL)
            try PrivateFiles.writeAtomic(png, to: imagesURL.appendingPathComponent(file))
        } catch {
            lastSaveFailed = true
            return false
        }
        insert(ClipboardEntry(id: id, kind: .image, sourceBundleID: source, copiedAt: now(),
                              imageFile: file, imageHash: hash, imageWidth: width, imageHeight: height))
        return true
    }

    private func insert(_ entry: ClipboardEntry) {
        entries.insert(entry, at: 0)
        trim()
        save()
    }

    // MARK: - Editing

    func togglePin(id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].pinned.toggle()
        // No trim here: unpinning must never delete an old entry (and its image file) as a side
        // effect. The next real insert trims normally.
        save()
    }

    func remove(id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        deleteImage(of: entries[i])
        entries.remove(at: i)
        save()
    }

    func clearAll(keepPinned: Bool) {
        let doomed = entries.filter { !(keepPinned && $0.pinned) }
        doomed.forEach(deleteImage(of:))
        entries.removeAll { e in doomed.contains { $0.id == e.id } }
        save()
    }

    /// Put an item back on top with a fresh date (after the user clicked it).
    func moveToFront(id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries.remove(at: i)
        e.copiedAt = now()
        entries.insert(e, at: 0)
        save()
    }

    // MARK: - Reading

    func imageURL(for entry: ClipboardEntry) -> URL? {
        guard entry.kind == .image, let f = entry.imageFile, ClipboardEntry.isSafeFileName(f) else { return nil }
        return imagesURL.appendingPathComponent(f)
    }

    /// Pinned first, then newest first; filtered by a case-insensitive query.
    func displayEntries(matching query: String) -> [ClipboardEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = q.isEmpty ? entries : entries.filter {
            $0.text.localizedCaseInsensitiveContains(q)
                || $0.filePaths.contains { $0.localizedCaseInsensitiveContains(q) }
        }
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    // MARK: - Internals

    @discardableResult
    private func trim() -> Bool {
        let unpinned = entries.indices.filter { !entries[$0].pinned }
        guard unpinned.count > limit else { return false }
        let doomed = Set(unpinned.suffix(unpinned.count - limit))   // oldest, entries are newest-first
        for i in doomed { deleteImage(of: entries[i]) }
        entries = entries.enumerated().filter { !doomed.contains($0.offset) }.map(\.element)
        return true
    }

    private func deleteImage(of entry: ClipboardEntry) {
        guard let url = imageURL(for: entry) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try PrivateFiles.writeAtomic(try enc.encode(entries), to: fileURL)
            lastSaveFailed = false
        } catch {
            lastSaveFailed = true
        }
    }
}
