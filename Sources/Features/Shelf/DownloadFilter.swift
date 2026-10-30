import Foundation

enum DownloadFilter {
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "opdownload", "tmp"]

    /// True for partial downloads and hidden files (.DS_Store, .localized, dot files).
    static func isPartialOrHidden(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix(".") else { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }
}
