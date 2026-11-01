import Foundation

struct ScratchPad: Identifiable, Equatable, Sendable, Codable {
    var id: String
    var name: String
    var text: String

    init(id: String = UUID().uuidString, name: String, text: String = "") {
        self.id = id; self.name = name; self.text = text
    }

    private enum CodingKeys: String, CodingKey { case id, name, text }

    /// Tolerant: missing fields get defaults, unknown keys are ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = ((try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil) ?? UUID().uuidString
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "Note"
        text = ((try? c.decodeIfPresent(String.self, forKey: .text)) ?? nil) ?? ""
    }
}

/// Multi-note scratchpad in `<dir>/Scratchpad.json`: {"pads":[{id,name,text}],"selectedID":"..."}.
final class ScratchpadStore {
    static let fileName = "Scratchpad.json"
    let directory: URL
    private(set) var pads: [ScratchPad] = []
    private(set) var selectedID: String = ""

    init(directory: URL) { self.directory = directory }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private struct Lossy: Decodable {
        let pad: ScratchPad?
        init(from decoder: Decoder) throws { pad = try? ScratchPad(from: decoder) }
    }
    private struct File: Decodable {
        let pads: [Lossy]?
        let selectedID: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            pads = try? c.decodeIfPresent([Lossy].self, forKey: .pads)
            selectedID = (try? c.decodeIfPresent(String.self, forKey: .selectedID)) ?? nil
        }
        enum Keys: String, CodingKey { case pads, selectedID }
    }
    private struct Out: Encodable { let pads: [ScratchPad]; let selectedID: String }

    /// When the file was last read or written by this store (nil: it did not exist). `Scratchpad.json` has another
    /// writer, the ported Scratchpad: a save over a file that changed since is refused.
    private var stamp: Date?

    private var fileStamp: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// True when someone else wrote the file after this store last read or wrote it.
    var changedOnDisk: Bool { fileStamp != stamp }

    func load() {
        stamp = fileStamp  // taken before the read: a write in between only makes the next save refuse, never lose
        var loaded: [ScratchPad] = []
        var selected: String?
        if let data = try? Data(contentsOf: fileURL), let f = try? JSONDecoder().decode(File.self, from: data) {
            var seen = Set<String>()
            loaded = (f.pads ?? []).compactMap(\.pad).filter { seen.insert($0.id).inserted }
            selected = f.selectedID
        }
        if loaded.isEmpty { loaded = [ScratchPad(name: "Note 1")] }
        pads = loaded
        selectedID = loaded.contains { $0.id == selected } ? selected! : loaded[0].id
    }

    func select(_ id: String) { if pads.contains(where: { $0.id == id }) { selectedID = id } }

    func updateText(_ text: String, for id: String) {
        guard let i = pads.firstIndex(where: { $0.id == id }), pads[i].text != text else { return }
        pads[i].text = text
    }

    func rename(_ id: String, to name: String) {
        guard let i = pads.firstIndex(where: { $0.id == id }) else { return }
        pads[i].name = name
    }

    @discardableResult
    func addPad(named name: String) -> ScratchPad {
        let pad = ScratchPad(name: name)
        pads.append(pad)
        selectedID = pad.id
        return pad
    }

    func removePad(id: String) {
        guard let i = pads.firstIndex(where: { $0.id == id }) else { return }
        pads.remove(at: i)
        if pads.isEmpty { pads = [ScratchPad(name: "Note 1")] }
        if !pads.contains(where: { $0.id == selectedID }) { selectedID = pads[min(i, pads.count - 1)].id }
    }

    /// Writes the pads unless the file changed on disk since the last load or save (the ported Scratchpad edited it:
    /// our copy is stale and rewriting the whole file would drop its edits). False when nothing was written because
    /// of that; the caller reloads.
    @discardableResult
    func save() -> Bool {
        guard !changedOnDisk else { return false }
        guard let data = try? JSONEncoder().encode(Out(pads: pads, selectedID: selectedID)) else { return true }
        try? PrivateFiles.writeAtomic(data, to: fileURL)
        stamp = fileStamp
        return true
    }
}
