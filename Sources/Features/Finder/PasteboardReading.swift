import AppKit

protocol PasteboardReading: Sendable {
    /// Bumps on every write to the pasteboard, whoever makes it.
    var changeCount: Int { get }
    var hasFileURLs: Bool { get }
    var hasImage: Bool { get }
    func pngData() -> Data?
}

struct SystemPasteboard: PasteboardReading, @unchecked Sendable {
    var pasteboard: NSPasteboard = .general

    var changeCount: Int { pasteboard.changeCount }
    var hasFileURLs: Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }
    var hasImage: Bool {
        let types = pasteboard.types ?? []
        return types.contains(.png) || types.contains(.tiff)
    }
    func pngData() -> Data? {
        ImagePaste.pngData(png: pasteboard.data(forType: .png), tiff: pasteboard.data(forType: .tiff))
    }
}
