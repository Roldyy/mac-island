import Foundation

/// Compact binary form of the per-file parse cache. JSON would be ten times the size and slow to decode
/// for the tens of thousands of records of a 13-week window; this decodes in a few milliseconds.
///
/// Layout (little endian): magic "MISU", schema version (u32), payload length (u64), payload checksum (u64),
/// then the payload: a string table (models, projects), then per file its path, size, mtime, committed offset,
/// fingerprint, malformed counters and records. A record is a timestamp (f64), four token counts (u32),
/// model and project indexes into the string table (u32) and the message id (u16 length, 0xFFFF = none).
/// Anything that does not parse, check out or match the version is rejected whole: a cache is never repaired.
enum UsageCacheCodec {
    static let version: UInt32 = 1
    private static let magic: [UInt8] = Array("MISU".utf8)
    private static let headerSize = 4 + 4 + 8 + 8
    private static let noID: UInt16 = 0xFFFF

    enum DecodeError: Error { case badHeader, badVersion, badChecksum, malformed }

    // MARK: encode

    /// `keepingSince` drops records older than the page's window: they can never be shown again.
    static func encode(_ entries: [String: UsageFileCache.Entry], keepingSince: Date? = nil) -> Data {
        var strings: [String: UInt32] = [:]
        var table: [String] = []
        func index(_ value: String) -> UInt32 {
            if let hit = strings[value] { return hit }
            let next = UInt32(table.count)
            strings[value] = next
            table.append(value)
            return next
        }
        var files = Writer()
        for path in entries.keys.sorted() {
            guard let entry = entries[path] else { continue }
            let committed = entry.parse.committed.records.filter { keepingSince == nil || $0.timestamp >= keepingSince! }
            let tail = entry.parse.tail.records.filter { keepingSince == nil || $0.timestamp >= keepingSince! }
            files.string(path)
            files.i64(Int64(entry.key.size))
            files.f64(entry.key.mtime.timeIntervalSinceReferenceDate)
            files.u64(entry.parse.committedOffset)
            files.u16(UInt16(min(entry.fingerprint.count, Int(UInt16.max))))
            files.bytes(entry.fingerprint.prefix(Int(UInt16.max)))
            files.u32(UInt32(clamping: entry.parse.committed.malformedLines))
            files.u32(UInt32(clamping: entry.parse.tail.malformedLines))
            files.u32(UInt32(committed.count))
            files.u32(UInt32(tail.count))
            for record in committed + tail {
                files.f64(record.timestamp.timeIntervalSinceReferenceDate)
                files.u32(UInt32(clamping: record.inputTokens))
                files.u32(UInt32(clamping: record.outputTokens))
                files.u32(UInt32(clamping: record.cacheCreationTokens))
                files.u32(UInt32(clamping: record.cacheReadTokens))
                files.u32(index(record.model))
                files.u32(index(record.project))
                if let id = record.messageID {
                    let utf8 = Array(id.utf8.prefix(Int(noID) - 1))
                    files.u16(UInt16(utf8.count))
                    files.bytes(utf8)
                } else {
                    files.u16(noID)
                }
            }
        }
        var payload = Writer()
        payload.u32(UInt32(table.count))
        for value in table { payload.string(value) }
        payload.u32(UInt32(entries.count))
        payload.bytes(files.data)

        var out = Writer()
        out.bytes(magic)
        out.u32(version)
        out.u64(UInt64(payload.data.count))
        out.u64(checksum(payload.data))
        out.bytes(payload.data)
        return out.data
    }

    // MARK: decode

    static func decode(_ data: Data) throws -> [String: UsageFileCache.Entry] {
        guard data.count >= headerSize else { throw DecodeError.badHeader }
        return try data.withUnsafeBytes { (all: UnsafeRawBufferPointer) in
            guard Array(all[0..<4]) == magic else { throw DecodeError.badHeader }
            guard all.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian == version else { throw DecodeError.badVersion }
            let length = all.loadUnaligned(fromByteOffset: 8, as: UInt64.self).littleEndian
            let expected = all.loadUnaligned(fromByteOffset: 16, as: UInt64.self).littleEndian
            guard length == UInt64(all.count - headerSize) else { throw DecodeError.malformed }
            let payload = UnsafeRawBufferPointer(rebasing: all[headerSize...])
            guard checksum(payload) == expected else { throw DecodeError.badChecksum }

            var reader = Reader(buffer: payload)
            var table: [String] = []
            let stringCount = Int(try reader.u32())
            guard stringCount <= payload.count else { throw DecodeError.malformed }
            table.reserveCapacity(stringCount)
            for _ in 0..<stringCount { table.append(try reader.string()) }
            let fileCount = Int(try reader.u32())
            guard fileCount <= payload.count else { throw DecodeError.malformed }
            var entries: [String: UsageFileCache.Entry] = [:]
            entries.reserveCapacity(fileCount)
            for _ in 0..<fileCount {
                let path = try reader.string()
                let size = Int(try reader.i64())
                let mtime = Date(timeIntervalSinceReferenceDate: try reader.f64())
                let offset = try reader.u64()
                let fingerprint = try reader.data(count: Int(try reader.u16()))
                var parse = ClaudeUsageParser.FileParse()
                parse.committedOffset = offset
                parse.committed.malformedLines = Int(try reader.u32())
                parse.tail.malformedLines = Int(try reader.u32())
                let committedCount = Int(try reader.u32())
                let tailCount = Int(try reader.u32())
                guard committedCount <= payload.count, tailCount <= payload.count else { throw DecodeError.malformed }
                parse.committed.records.reserveCapacity(committedCount)
                for position in 0..<(committedCount + tailCount) {
                    let stamp = Date(timeIntervalSinceReferenceDate: try reader.f64())
                    let input = Int(try reader.u32()), output = Int(try reader.u32())
                    let created = Int(try reader.u32()), read = Int(try reader.u32())
                    let model = Int(try reader.u32()), project = Int(try reader.u32())
                    guard model < table.count, project < table.count else { throw DecodeError.malformed }
                    let idLength = try reader.u16()
                    let id: String? = idLength == noID ? nil : try reader.string(count: Int(idLength))
                    let record = UsageRecord(messageID: id, model: table[model], timestamp: stamp, inputTokens: input,
                                             outputTokens: output, cacheCreationTokens: created, cacheReadTokens: read,
                                             project: table[project])
                    if position < committedCount { parse.committed.records.append(record) } else { parse.tail.records.append(record) }
                }
                entries[path] = UsageFileCache.Entry(key: .init(size: size, mtime: mtime), parse: parse, fingerprint: fingerprint)
            }
            guard reader.isAtEnd else { throw DecodeError.malformed }
            return entries
        }
    }

    // MARK: checksum

    /// Word-at-a-time multiply-xor hash: catches truncation and flipped bits, which is all a cache needs.
    private static func checksum(_ data: Data) -> UInt64 { data.withUnsafeBytes { checksum($0) } }

    private static func checksum(_ buffer: UnsafeRawBufferPointer) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        var offset = 0
        while offset + 8 <= buffer.count {
            hash = (hash ^ buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) &* 0x100000001b3
            hash ^= hash >> 29
            offset += 8
        }
        while offset < buffer.count {
            hash = (hash ^ UInt64(buffer[offset])) &* 0x100000001b3
            offset += 1
        }
        return hash
    }

    // MARK: byte streams

    private struct Writer {
        var data = Data()
        mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func i64(_ v: Int64) { u64(UInt64(bitPattern: v)) }
        mutating func f64(_ v: Double) { u64(v.bitPattern) }
        mutating func bytes<S: Sequence>(_ s: S) where S.Element == UInt8 { data.append(contentsOf: s) }
        mutating func string(_ s: String) {
            let utf8 = Array(s.utf8)
            u32(UInt32(utf8.count))
            data.append(contentsOf: utf8)
        }
    }

    private struct Reader {
        let buffer: UnsafeRawBufferPointer
        var position = 0
        init(buffer: UnsafeRawBufferPointer) { self.buffer = buffer }

        var isAtEnd: Bool { position == buffer.count }

        private mutating func take(_ count: Int) throws -> Int {
            guard count >= 0, count <= buffer.count - position else { throw DecodeError.malformed }
            defer { position += count }
            return position
        }
        mutating func u16() throws -> UInt16 { buffer.loadUnaligned(fromByteOffset: try take(2), as: UInt16.self).littleEndian }
        mutating func u32() throws -> UInt32 { buffer.loadUnaligned(fromByteOffset: try take(4), as: UInt32.self).littleEndian }
        mutating func u64() throws -> UInt64 { buffer.loadUnaligned(fromByteOffset: try take(8), as: UInt64.self).littleEndian }
        mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }
        mutating func f64() throws -> Double { Double(bitPattern: try u64()) }
        mutating func data(count: Int) throws -> Data {
            let start = try take(count)
            return Data(UnsafeRawBufferPointer(rebasing: buffer[start..<start + count]))
        }
        mutating func string(count: Int) throws -> String {
            let start = try take(count)
            return String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<start + count]), as: UTF8.self)
        }
        mutating func string() throws -> String { try string(count: Int(try u32())) }
    }
}
