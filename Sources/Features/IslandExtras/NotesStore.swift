import Foundation

/// The one short note of the "Notes" tab, kept on this Mac only: `IslandNotes.json` in the app's data folder,
/// owner-only (0600, folder 0700). A missing, unreadable or corrupt file reads as an empty note; nothing is ever sent.
struct NotesStore: Sendable {
    static let fileName = "IslandNotes.json"
    static let maxLength = 20_000

    let directory: URL?

    /// `~/Library/Application Support/be.roldy.macisland/Data`: the folder the rest of the app keeps its private files in.
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    private struct Document: Codable { var text: String }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func load() -> String {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(Document.self, from: data) else { return "" }
        return String(document.text.prefix(Self.maxLength))
    }

    @discardableResult
    func save(_ text: String) -> Bool {
        guard let directory, let fileURL,
              let data = try? JSONEncoder().encode(Document(text: String(text.prefix(Self.maxLength)))) else { return false }
        let manager = FileManager.default
        guard (try? manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])) != nil,
              (try? data.write(to: fileURL, options: .atomic)) != nil else { return false }
        // `.atomic` swaps in a fresh file: the mode is set after every write, not once.
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return true
    }
}
