import Darwin
import Foundation

/// Lists the descendants of a pid and recognises a Claude Code process among them.
/// Only executable names and argv basenames are read; full command lines are never kept or logged.
enum ProcessTree {
    // MARK: Pure matching

    /// `name` is the kernel process name, `argvBasenames` the basenames of argv[0] and argv[1] (when known).
    /// Claude is either a binary titled `claude`, or `node` running a script called `claude`.
    static func isClaude(name: String, argvBasenames: [String]) -> Bool {
        if name == "claude" { return true }
        if argvBasenames.first == "claude" { return true }
        if name == "node" || argvBasenames.first == "node" {
            return argvBasenames.dropFirst().first == "claude"
        }
        return false
    }

    /// Extracts the basenames of the first two argv entries from a `KERN_PROCARGS2` buffer:
    /// `int32 argc`, executable path, NUL padding, then the argv strings. Everything else is dropped.
    static func argvBasenames(fromProcArgs data: [UInt8], limit: Int = 2) -> [String] {
        guard data.count > MemoryLayout<Int32>.size else { return [] }
        let argc = data.prefix(4).withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var i = 4
        while i < data.count, data[i] != 0 { i += 1 }  // executable path
        while i < data.count, data[i] == 0 { i += 1 }  // padding
        var result: [String] = []
        var remaining = min(argc, limit)
        while remaining > 0, i < data.count {
            var j = i
            while j < data.count, data[j] != 0 { j += 1 }
            let arg = String(decoding: data[i..<j], as: UTF8.self)
            result.append(arg.split(separator: "/").last.map(String.init) ?? arg)
            i = j + 1
            remaining -= 1
        }
        return result
    }

    // MARK: System queries

    /// All descendants of `pid` (children, grandchildren, ...), excluding `pid` itself.
    static func descendants(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue = [pid]
        var seen: Set<pid_t> = [pid]
        while let current = queue.popLast(), result.count < 512 {
            for child in children(of: current) where seen.insert(child).inserted {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    /// True when a descendant of `pid` is Claude Code.
    static func containsClaude(below pid: pid_t) -> Bool {
        for child in descendants(of: pid) {
            let procName = name(of: child)
            if procName == "claude" { return true }
            if isClaude(name: procName, argvBasenames: argvBasenames(of: child)) { return true }
        }
        return false
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let capacity = 256
        var buffer = [pid_t](repeating: 0, count: capacity)
        let bytes = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(pid), &buffer, Int32(capacity * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        let count = min(capacity, Int(bytes) / MemoryLayout<pid_t>.size)
        return buffer.prefix(count).filter { $0 > 0 }
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(cString: buffer)
    }

    static func argvBasenames(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // The buffer also holds the environment: it is parsed for argv only and dropped, never stored.
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        return argvBasenames(fromProcArgs: Array(buffer.prefix(size)))
    }
}
