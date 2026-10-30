import Foundation

enum CollisionNamer {
    /// "a.txt" -> "a 2.txt" -> "a 3.txt". Nil only after 10 000 attempts.
    static func unique(name: String, in folder: URL, exists: (URL) -> Bool) -> URL? {
        let first = folder.appendingPathComponent(name)
        if !exists(first) { return first }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        // ".hidden" has no extension: NSString already reports an empty one, the stem stays whole.
        for n in 2...10_000 {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            if !exists(candidate) { return candidate }
        }
        return nil
    }
}
