import Foundation

/// Pure parser for Claude Code `~/.claude/projects/**/*.jsonl` lines.
enum ClaudeUsageParser {
    struct Result {
        var records: [UsageRecord] = []
        var malformedLines = 0
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
                cacheReadTokens: usage.cache_read_input_tokens ?? 0))
        }
    }
}
