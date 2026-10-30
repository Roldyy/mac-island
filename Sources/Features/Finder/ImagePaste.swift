import AppKit
import Foundation

enum ImagePaste {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

    static func fileName(date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Image \(f.string(from: date)).png"
    }

    /// A real PNG, or nil. TIFF (what most apps put on the pasteboard) is converted.
    static func pngData(png: Data?, tiff: Data?) -> Data? {
        if let png, png.starts(with: pngSignature) { return png }
        guard let tiff, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func save(png: Data, in folder: URL, date: Date, timeZone: TimeZone,
                     inspector: FileInspecting) throws {
        guard inspector.isReadableWritableDirectory(folder) else { throw MoveRefusal.destinationUnavailable }
        let name = fileName(date: date, timeZone: timeZone)
        guard let target = CollisionNamer.unique(name: name, in: folder, exists: inspector.exists) else {
            throw MoveRefusal.destinationUnavailable
        }
        try png.write(to: target, options: .withoutOverwriting)
    }
}
