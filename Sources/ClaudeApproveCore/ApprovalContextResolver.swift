import Darwin
import Foundation

extension ApprovalContext {
    /// Reads the file system for ONE request: the chat folder, the target path and (Bash) each word of the command read as a path.
    /// The words are only looked at, never run, never globbed.
    public static func resolve(toolName: String?, toolInput: Any?, cwd: String?, home: String) -> ApprovalContext {
        let input = (toolInput as? [String: Any]) ?? [:]
        var ctx = ApprovalContext(home: home)
        ctx.cwdReal = physicalPath(cwd ?? "") ?? ""

        // First of file_path / notebook_path / path that is a non-empty string.
        let target = ["file_path", "notebook_path", "path"].compactMap { input[$0] as? String }.first { !$0.isEmpty } ?? ""
        var expanded: String
        if target == "~" { expanded = home } else if target.hasPrefix("~/") { expanded = home + "/" + target.dropFirst(2) } else { expanded = target }
        // A relative target is read from the chat's folder: resolve it there, so a Grep over "." is seen as a folder.
        if !expanded.isEmpty, !expanded.hasPrefix("/"), !ctx.cwdReal.isEmpty { expanded = ctx.cwdReal + "/" + expanded }
        if expanded.hasPrefix("/") {
            var st = stat()
            if lstat(expanded, &st) == 0 {
                ctx.isLink = (st.st_mode & S_IFMT) == S_IFLNK
                var st2 = stat()
                ctx.isDir = stat(expanded, &st2) == 0 && (st2.st_mode & S_IFMT) == S_IFDIR
            }
            ctx.real = expanded == "/" ? "/" : resolvedFromParent(expanded) ?? ""
        }

        if toolName == "Bash", !ctx.cwdReal.isEmpty, let command = input["command"] as? String {
            let head = String(command.unicodeScalars.prefix(200))
            let words = ApprovalClassifier.words(head)
            var reals: [String] = []
            var count = 0
            for word in words {
                if word.hasPrefix("-") { continue }
                count += 1
                if count > 20 { break }
                let path = word.hasPrefix("/") ? word : ctx.cwdReal + "/" + word
                var st = stat()
                if lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK { ctx.wordLink = true }
                reals.append(resolvedFromParent(path) ?? path)
            }
            ctx.wordReals = reals
        }
        return ctx
    }

    /// `realpath` of an existing directory or file, nil when it does not exist.
    static func physicalPath(_ path: String) -> String? {
        guard !path.isEmpty, let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The parent directory resolved physically, plus the last component as written.
    static func resolvedFromParent(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let base = url.lastPathComponent
        guard let parent = physicalPath(url.deletingLastPathComponent().path) else { return nil }
        let trimmed = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return trimmed + "/" + base
    }
}
