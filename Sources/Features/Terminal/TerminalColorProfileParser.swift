import Darwin
import Foundation

/// A parsed file: the profile, ready to preview, and how many of its colours came from the file itself.
struct TerminalColorProfileImport: Equatable, Sendable {
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
    /// The file is opened without blocking (a named pipe would otherwise hang the open), then `fstat` on the
    /// descriptor itself must say "regular file": a directory, pipe, socket or device is refused before any read.
    /// A symlink is followed (the open panel hands over resolved paths) and judged by what it points to.
    /// Blocking work: call it off the main thread.
    static func read(url: URL, now: Date = Date()) throws -> TerminalColorProfileImport {
        guard supportedExtensions.contains(url.pathExtension.lowercased()) else { throw TerminalColorProfileError.unsupportedType }
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw TerminalColorProfileError.unreadable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw TerminalColorProfileError.unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw TerminalColorProfileError.notARegularFile }
        guard info.st_size <= off_t(maxFileBytes) else { throw TerminalColorProfileError.fileTooLarge }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= maxFileBytes {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, min($0.count, maxFileBytes + 1 - data.count)) }
            if count < 0 {
                if errno == EINTR { continue }
                throw TerminalColorProfileError.unreadable
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return try parse(data: data, fileName: url.lastPathComponent, now: now)
    }
}
