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

    static func parse(file url: URL, from offset: UInt64 = 0) throws -> FileParse {
        var out = FileParse()
        let parser = LineParser()
        let outcome = try JSONLStream.read(url: url, from: offset) { parser.consume($0, into: &out.committed) }
        out.committed.malformedLines += outcome.oversizedLines
        out.committedOffset = outcome.committedOffset
        if let tail = outcome.tail {
            var scratch = Result()
            parser.consume(tail, into: &scratch)
            out.tail = scratch
        }
        return out
    }

    private final class LineParser {
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
            result.records.append(UsageRecord(
                messageID: line.message?.id,
                model: line.message?.model ?? "unknown",
                timestamp: date,
                inputTokens: usage.input_tokens ?? 0,
                outputTokens: usage.output_tokens ?? 0,
                cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
                cacheReadTokens: usage.cache_read_input_tokens ?? 0,
                project: line.cwd.map(ClaudeText.folderName(fromCwd:)) ?? ""))
        }
    }
}
