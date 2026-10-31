import Darwin
import Foundation

/// One bounded read of a regular file. A symlink, a device, a FIFO or an oversized file gives nil.
enum SafeFileRead {
    static func data(atPath path: String, maxBytes: Int) -> Data? {
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= maxBytes else { return nil }
        // O_NOFOLLOW closes the swap-for-a-symlink window between lstat and open.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st2 = stat()
        guard fstat(fd, &st2) == 0, (st2.st_mode & S_IFMT) == S_IFREG, st2.st_size <= maxBytes else { return nil }
        return readCapped(fd: fd, limit: maxBytes, rejectOverflow: true)
    }

    /// Reads at most `limit` bytes. With `rejectOverflow`, more data than that gives nil instead of a prefix.
    static func readCapped(fd: Int32, limit: Int, rejectOverflow: Bool) -> Data? {
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
            if rejectOverflow { return nil }
            out.removeLast(out.count - limit)
        }
        return out
    }
}
