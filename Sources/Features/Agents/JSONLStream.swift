import Foundation

/// Reads a file line by line in fixed chunks: a 500 MB log never sits in memory whole.
enum JSONLStream {
    static let chunkSize = 1 << 20
    /// A line longer than this is dropped (it is not a usage line, and one line must not grow the buffer).
    static let maxLineBytes = 16 << 20

    struct Outcome {
        /// Offset just after the last newline-terminated line that was handed over.
        var committedOffset: UInt64
        /// A final line with no newline yet (possibly still being written), handed over separately.
        var tail: Data?
        var oversizedLines = 0
    }

    /// Calls `line` for every complete line from `offset`. Throws only when the file cannot be opened or read.
    static func read(url: URL, from offset: UInt64 = 0, line: (Data) -> Void) throws -> Outcome {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if offset > 0 { try handle.seek(toOffset: offset) }
        var carry = Data()
        var consumed = offset
        var skippingOversized = false
        var outcome = Outcome(committedOffset: offset)
        // One pool per chunk: `FileHandle.read` hands back autoreleased buffers, and without a drain a
        // 1.5 GB log folder was held in memory until the whole pass ended (measured on real data).
        var more = true
        while more {
            try autoreleasepool {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { more = false; return }
            carry.append(chunk)
            var lineStart = 0
            carry.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let base = buffer.baseAddress else { return }
                while lineStart < buffer.count,
                      let hit = memchr(base + lineStart, 0x0A, buffer.count - lineStart) {
                    let end = base.distance(to: UnsafeRawPointer(hit))
                    if skippingOversized {
                        skippingOversized = false
                    } else if end > lineStart {
                        line(Data(bytes: base + lineStart, count: end - lineStart))
                    }
                    lineStart = end + 1
                }
            }
            consumed += UInt64(lineStart)
            outcome.committedOffset = consumed
            carry = lineStart >= carry.count ? Data() : Data(carry[lineStart...])
            if carry.count > maxLineBytes {
                if !skippingOversized { outcome.oversizedLines += 1 }
                skippingOversized = true
                consumed += UInt64(carry.count)
                carry = Data()
                // The rest of that line is thrown away up to its newline; committedOffset catches up there.
                outcome.committedOffset = consumed
            }
            }
        }
        if !carry.isEmpty, !skippingOversized {
            outcome.tail = carry
            outcome.committedOffset = consumed
        }
        return outcome
    }
}
