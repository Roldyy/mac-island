import Foundation

protocol FileInspecting: Sendable {
    /// lstat semantics: a broken symlink exists.
    func exists(_ url: URL) -> Bool
    func isSymlink(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
    func isReadableWritableDirectory(_ url: URL) -> Bool
    func resolved(_ url: URL) -> URL
}

struct SystemFileInspector: FileInspecting {
    func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }
    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
    func isReadableWritableDirectory(_ url: URL) -> Bool {
        isDirectory(url) && FileManager.default.isReadableFile(atPath: url.path)
            && FileManager.default.isWritableFile(atPath: url.path)
    }
    func resolved(_ url: URL) -> URL { url.resolvingSymlinksInPath() }
}
