import Foundation

/// A parsed file: the profile, ready to preview, and how many of its colours came from the file itself.
struct TerminalColorProfileImport: Equatable {
    var profile: TerminalColorProfile
    var foundColors: Int
    static let totalColors = TerminalRawColors.ansiCount + 4
}

/// Turns the bytes of an UNTRUSTED file into a colour profile. It only parses: nothing in the file is executed,
/// no path or URL from its content is used, no network is touched. Everything fails closed.
enum TerminalColorProfileParser {
    static let maxFileBytes = 1_048_576
    static let supportedExtensions = ["terminal", "itermcolors"]

    static func parse(data: Data, fileName: String, now: Date = Date()) throws -> TerminalColorProfileImport {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw TerminalColorProfileError.unsupportedType }
        guard data.count <= maxFileBytes else { throw TerminalColorProfileError.fileTooLarge }
        guard !data.isEmpty,
              let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { throw TerminalColorProfileError.unreadable }
        guard let raw = ext == "terminal" ? TerminalAppProfileReader.read(root) : ITermColorsReader.read(root)
        else { throw TerminalColorProfileError.notAColorProfile }
        guard raw.validCount >= TerminalRawColors.minimumColors else {
            throw TerminalColorProfileError.tooFewColors(found: raw.validCount)
        }
        let base = (fileName as NSString).deletingPathExtension
        return TerminalColorProfileImport(profile: raw.resolved(fallbackName: base, now: now), foundColors: raw.validCount)
    }

    /// Reads at most the cap plus one byte, so a huge or endless file is refused without being loaded.
    static func read(url: URL, now: Date = Date()) throws -> TerminalColorProfileImport {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { throw TerminalColorProfileError.unsupportedType }
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw TerminalColorProfileError.unreadable }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxFileBytes + 1) else { throw TerminalColorProfileError.unreadable }
        return try parse(data: data, fileName: url.lastPathComponent, now: now)
    }
}
