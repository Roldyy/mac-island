import ClaudeLiveKit
import Foundation

/// Pure parser for Claude Code `~/.claude/projects/**/*.jsonl` lines.
/// JSONL fields read (names only): type, timestamp, cwd, message.id, message.model, message.usage.
/// {input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}.
enum ClaudeUsageParser {
    struct Result: Sendable {
        var records: [UsageRecord] = []
        var malformedLines = 0

        mutating func append(_ other: Result) {
            records.append(contentsOf: other.records)
            malformedLines += other.malformedLines
        }
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
                var cache_creation_input_tokens: Int?
                var cache_read_input_tokens: Int?
            }
            var id: String?
            var model: String?
            var usage: Usage?
        }
        var type: String?
        var timestamp: String?
        var cwd: String?
        var message: Message?
    }

    static func parse(lines: [String]) -> Result {
        var result = Result()
        let parser = LineParser()
        for line in lines { parser.consume(Data(line.utf8), into: &result) }
        return result
    }

    static func parse(data: Data) -> Result {
        var result = Result()
        let parser = LineParser()
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            parser.consume(Data(slice), into: &result)
        }
        return result
    }

    /// Streams a file from `offset`. `committed` holds only newline-terminated lines (safe to cache and to
    /// resume from `committedOffset`); `tail` is a last line without newline, parsed but never cached. A tail
    /// still being written counts as malformed until its newline lands (transient, the counter is only a hint).
    struct FileParse: Sendable {
        var committed = Result()
        var tail = Result()
        var committedOffset: UInt64 = 0
    }

    /// Most records one file keeps in memory. A real log holds a few thousand messages; the cap only stops a
    /// pathological file from growing the arrays without bound. Records past it are counted in `malformedLines`.
    static let maxRecordsPerFile = 250_000

    static func parse(file url: URL, from offset: UInt64 = 0, maxRecords: Int = maxRecordsPerFile) throws -> FileParse {
        var out = FileParse()
        // Streams: a message id repeated once per content block is folded into one record as the lines arrive,
        // so the array never holds the repeats (they were the bulk of a transient copy per big file).
        let parser = LineParser(deduplicating: true, maxRecords: maxRecords)
        let outcome = try JSONLStream.read(url: url, from: offset) { parser.consume($0, into: &out.committed) }
        out.committed.malformedLines += outcome.oversizedLines
        out.committedOffset = outcome.committedOffset
        if let tail = outcome.tail {
            var scratch = Result()
            LineParser(deduplicating: false, maxRecords: maxRecords).consume(tail, into: &scratch)
            out.tail = scratch
        }
        return out
    }

    /// Model and project names repeat across every record: one shared string each instead of a heap copy per
    /// record. Bounded, so a hostile log of unique names cannot grow it.
    private final class Interner: @unchecked Sendable {
        static let shared = Interner()
        private let lock = NSLock()
        private var table: [String: String] = [:]
        func intern(_ value: String) -> String {
            lock.withLock {
                if let known = table[value] { return known }
                if table.count < 512 { table[value] = value }
                return value
            }
        }
    }

    private final class LineParser {
        private let deduplicating: Bool
        private let maxRecords: Int
        /// message id -> index in the result being filled (streaming mode only, one result per parser).
        private var index: [String: Int] = [:]

        init(deduplicating: Bool = false, maxRecords: Int = ClaudeUsageParser.maxRecordsPerFile) {
            self.deduplicating = deduplicating
            self.maxRecords = maxRecords
        }

        private let withFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private let plain = ISO8601DateFormatter()
        private let decoder = JSONDecoder()
        private let usageMarker = Data("\"usage\"".utf8)

        func consume(_ raw: Data, into result: inout Result) {
            guard let first = raw.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D }) else { return }
            // Cheap path: lines without usage are never decoded, only checked for truncation.
            if raw.range(of: usageMarker) == nil {
                let last = raw.last(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D })
                if first != UInt8(ascii: "{") || last != UInt8(ascii: "}") { result.malformedLines += 1 }
                return
            }
            guard let line = try? decoder.decode(Line.self, from: raw) else {
                result.malformedLines += 1
                return
            }
            guard line.type == "assistant", let usage = line.message?.usage else { return }
            guard let stamp = line.timestamp,
                  let date = withFraction.date(from: stamp) ?? plain.date(from: stamp) else {
                result.malformedLines += 1
                return
            }
            let record = UsageRecord(
                messageID: line.message?.id,
                model: Interner.shared.intern(line.message?.model ?? "unknown"),
                timestamp: date,
                inputTokens: usage.input_tokens ?? 0,
                outputTokens: usage.output_tokens ?? 0,
                cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
                cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                project: Interner.shared.intern(line.cwd.map(ClaudeText.folderName(fromCwd:)) ?? ""))
            guard deduplicating else { result.records.append(record); return }
            // Same rule as `UsageRecord.deduplicated`: the largest output per id wins, first position kept.
            if let id = record.messageID, let at = index[id] {
                if record.outputTokens > result.records[at].outputTokens { result.records[at] = record }
            } else if result.records.count >= maxRecords {
                result.malformedLines += 1
            } else {
                if let id = record.messageID { index[id] = result.records.count }
                result.records.append(record)
            }
        }
    }
}
