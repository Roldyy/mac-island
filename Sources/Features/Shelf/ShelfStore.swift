import Foundation

/// `Shelf.json` in an injected directory. Owner-only, atomic.
struct ShelfStore {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("Shelf.json") }
    var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    init(directory: URL) { self.directory = directory }

    func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([ShelfItem].self, from: data)) ?? []
    }

    func save(_ items: [ShelfItem]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try PrivateFiles.writeAtomic(try encoder.encode(items), to: fileURL)
    }
}

enum PrivateFiles {
    static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw CocoaError(.fileWriteFileExists)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func writeAtomic(_ data: Data, to url: URL) throws {
        try ensureDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
