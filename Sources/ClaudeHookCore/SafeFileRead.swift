import Darwin
import Foundation

/// One bounded read of a regular file. A symlink, a device, a FIFO, an oversized file, a file owned by
/// someone else or a hard-linked one gives nil.
public enum SafeFileRead {
    /// `uid` is injectable so tests can play "someone else owns it" without a second account.
    public static func data(atPath path: String, maxBytes: Int, uid: uid_t = getuid()) -> Data? {
        var st = stat()
        guard lstat(path, &st) == 0, isTrusted(st, uid: uid), st.st_size <= maxBytes else { return nil }
        // O_NOFOLLOW closes the swap-for-a-symlink window between lstat and open.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st2 = stat()
        guard fstat(fd, &st2) == 0, isTrusted(st2, uid: uid), st2.st_size <= maxBytes else { return nil }
        return readCapped(fd: fd, limit: maxBytes, rejectOverflow: true)
    }

    /// Regular file, ours, one link: a hard link to a file we do not control is refused.
    static func isTrusted(_ st: stat, uid: uid_t) -> Bool {
        (st.st_mode & S_IFMT) == S_IFREG && st.st_uid == uid && st.st_nlink == 1
    }

    /// A real directory (not a symlink to one) owned by `uid`.
    public static func isTrustedDirectory(atPath path: String, uid: uid_t = getuid()) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR && st.st_uid == uid
    }

    /// Reads at most `limit` bytes. With `rejectOverflow`, more data than that gives nil instead of a prefix.
    /// With `drainRest`, a longer input is still read to EOF (and discarded) so the writer is never left blocked.
    public static func readCapped(fd: Int32, limit: Int, rejectOverflow: Bool, drainRest: Bool = false) -> Data? {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let want = min(buf.count, limit + 1 - out.count)
            if want <= 0 { break }
            let n = read(fd, &buf, want)
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { break }
            out.append(buf, count: n)
        }
        if out.count > limit {
            if drainRest { drain(fd: fd, scratch: &buf) }
            if rejectOverflow { return nil }
            out.removeLast(out.count - limit)
        }
        return out
    }

    private static func drain(fd: Int32, scratch: inout [UInt8]) {
        while true {
            let n = read(fd, &scratch, scratch.count)
            if n < 0 { if errno == EINTR { continue }; return }
            if n == 0 { return }
        }
    }
}
