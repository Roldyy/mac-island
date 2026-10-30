import AppKit

protocol PasteboardReading {
    var hasFileURLs: Bool { get }
    var hasImage: Bool { get }
    func pngData() -> Data?
}

struct SystemPasteboard: PasteboardReading {
    var pasteboard: NSPasteboard = .general

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
