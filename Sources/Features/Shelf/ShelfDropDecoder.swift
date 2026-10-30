import Foundation

/// Turns what `NSItemProvider.loadItem` returns for a file-url drop into a file URL.
enum ShelfDropDecoder {
    static func fileURL(from item: NSSecureCoding?) -> URL? {
        let url: URL?
        switch item {
        case let data as Data: url = URL(dataRepresentation: data, relativeTo: nil)
        case let nsurl as NSURL: url = nsurl as URL
        default: url = nil
        }
        guard let url, url.isFileURL else { return nil }
        return url
    }
}
