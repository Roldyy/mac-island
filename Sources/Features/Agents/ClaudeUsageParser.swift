import ClaudeLiveKit
import Foundation

/// Pure parser for Claude Code `~/.claude/projects/**/*.jsonl` lines.
/// JSONL fields read (names only): type, timestamp, cwd, message.id, message.model, message.usage.
/// {input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}.
enum ClaudeUsageParser {
    struct Result: Sendable {
        var records: [UsageRecord] = []
        var hooks: [HookRun] = []
        var malformedLines = 0

        mutating func append(_ other: Result) {
            records.append(contentsOf: other.records)
            hooks.append(contentsOf: other.hooks)
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
            /// Tool calls of the message. Lenient on purpose: `content` is a plain string on some lines and an item
            /// with an odd `input` must never turn the whole line into a malformed one.
            struct Item: Decodable {
                var type: String?
                var name: String?
                var command: String?
                private enum Keys: String, CodingKey { case type, name, input }
                private enum InputKeys: String, CodingKey { case command }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: Keys.self)
                    type = try? c.decode(String.self, forKey: .type)
                    name = try? c.decode(String.self, forKey: .name)
                    command = (try? c.nestedContainer(keyedBy: InputKeys.self, forKey: .input))
                        .flatMap { try? $0.decode(String.self, forKey: .command) }
                }
            }
            struct Content: Decodable {
                var items: [Item] = []
                init(from decoder: Decoder) throws {
                    items = (try? [Item](from: decoder)) ?? []
                }
            }
            var id: String?
            var model: String?
            var usage: Usage?
            var content: Content?
        }
        var type: String?
        var timestamp: String?
        var cwd: String?
        var message: Message?
        // Undocumented fields: a value that is not a string is ignored, never a malformed line (its tokens count).
        var attributionAgent: LenientString?
        var attributionSkill: LenientString?
        var attributionMcpServer: LenientString?
        var attributionPlugin: LenientString?
    }

    /// A hook run: an `attachment` line of type hook_success / hook_cancelled. Numbers are read as Double so an
    /// odd JSON number never fails the decode.
    private struct HookLine: Decodable {
        struct Attachment: Decodable {
            var type: String?
            var hookName: String?
            var hookEvent: String?
            var exitCode: Double?
            var durationMs: Double?
            var timeoutMs: Double?
        }
        var type: String?
        var timestamp: String?
        var uuid: String?
        var attachment: Attachment?
    }

    private struct LenientString: Decodable {
        var value: String?
        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    /// "cd \"/a b\" && FOO=1 gh pr list" -> "gh". Quote-aware: a path with a blank is one word. Wrappers (cd, env
    /// assignments, sudo, env, time, nohup, command, builtin) are skipped, a loop or condition (for, while, until,
    /// if) yields the command after its `do` / `then`, and a path keeps its last component. nil when nothing
    /// runnable is left.
    static func bashBinary(_ command: String) -> String? {
        let wrappers: Set<String> = ["sudo", "env", "time", "nohup", "command", "exec", "builtin"]
        let loops: Set<String> = ["for", "while", "until", "if", "elif", "select", "case"]
        let joiners: Set<String> = ["&&", ";", "||"]
        var words = shellWords(command)
        for _ in 0..<40 {
            guard let raw = words.first else { return nil }
            let first = raw.trimmingCharacters(in: CharacterSet(charactersIn: "({"))
            if first.isEmpty { words.removeFirst(); continue }
            words[0] = first
            if first == "cd" || first == "pushd" {
                guard let end = words.indices.dropFirst().first(where: { joiners.contains(words[$0]) || words[$0].hasSuffix(";") })
                else { return nil }
                words.removeSubrange(0...end)
            } else if loops.contains(first) {
                guard let end = words.firstIndex(where: { $0 == "do" || $0 == "then" }) else { return nil }
                words.removeSubrange(0...end)
            } else if ["do", "then", "else"].contains(first) {
                words.removeFirst()
            } else if first.contains("="), !first.hasPrefix("-"), !first.hasPrefix("/") {
                words.removeFirst()
            } else if wrappers.contains(first) {
                words.removeFirst()
                while let flag = words.first, flag.hasPrefix("-") { words.removeFirst() }
            } else {
                break
            }
        }
        guard let word = words.first?.trimmingCharacters(in: CharacterSet(charactersIn: "({;)&|")),
              let initial = word.first, initial.isLetter || initial.isNumber || initial == "." || initial == "/" || initial == "_"
        else { return nil }
        let name = word.split(separator: "/").last.map(String.init) ?? word
        // A word only: a quoted phrase, an escape or a variable is a piece of the command, never a binary name.
        guard !name.isEmpty, name.count <= 40,
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._+-".contains($0)) }) else { return nil }
        return name
    }

    /// Splits on blanks outside quotes; the quotes themselves are dropped.
    private static func shellWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var started = false
        for character in text {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                started = true
            } else if character == " " || character == "\t" || character == "\n" {
                if started || !current.isEmpty { words.append(current); current = ""; started = false }
            } else {
                current.append(character)
            }
        }
        if started || !current.isEmpty { words.append(current) }
        return words
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
        private let hookMarkers = [Data("\"hook_success\"".utf8), Data("\"hook_cancelled\"".utf8)]

        /// True when the line was a hook run. A line that merely quotes the marker (an assistant message talking
        /// about hooks) does not decode as one and goes on through the usage path untouched.
        private func consumeHook(_ raw: Data, into result: inout Result) -> Bool {
            guard hookMarkers.contains(where: { raw.range(of: $0) != nil }),
                  let line = try? decoder.decode(HookLine.self, from: raw), line.type == "attachment",
                  let attachment = line.attachment, let kind = attachment.type,
                  kind == "hook_success" || kind == "hook_cancelled",
                  let stamp = line.timestamp, let date = withFraction.date(from: stamp) ?? plain.date(from: stamp)
            else { return false }
            if result.hooks.count < maxRecords {
                let code = attachment.exitCode.flatMap { $0.isFinite ? Int(max(-1e6, min(1e6, $0))) : nil } ?? 0
                // A hook that timed out ran for the time it was allowed: the logged wait can be minutes longer.
                let shown = kind == "hook_cancelled" ? (attachment.timeoutMs ?? attachment.durationMs) : attachment.durationMs
                let duration = shown.flatMap { $0.isFinite ? Int(max(0, min(1e9, $0))) : nil } ?? 0
                result.hooks.append(HookRun(
                    name: Interner.shared.intern(attachment.hookName ?? "hook"),
                    event: Interner.shared.intern(attachment.hookEvent ?? ""),
                    durationMs: duration, failed: kind == "hook_cancelled" || code != 0,
                    timestamp: date, uuid: line.uuid))
            }
            return true
        }

        func consume(_ raw: Data, into result: inout Result) {
            guard let first = raw.first(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0D }) else { return }
            if consumeHook(raw, into: &result) { return }
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
                project: Interner.shared.intern(line.cwd.map(ClaudeText.folderName(fromCwd:)) ?? ""),
                attributionAgent: line.attributionAgent?.value.map(Interner.shared.intern),
                attributionSkill: line.attributionSkill?.value.map(Interner.shared.intern),
                attributionMcpServer: line.attributionMcpServer?.value.map(Interner.shared.intern),
                attributionPlugin: line.attributionPlugin?.value.map(Interner.shared.intern),
                cliBinaries: (line.message?.content?.items ?? []).compactMap {
                    $0.type == "tool_use" && $0.name == "Bash" ? $0.command.flatMap(ClaudeUsageParser.bashBinary) : nil
                }.map(Interner.shared.intern))
            guard deduplicating else { result.records.append(record); return }
            // Same rule as `UsageRecord.deduplicated`: the largest output per id wins, first position kept.
            if let id = record.messageID, let at = index[id] {
                // Each line of one message is a distinct content block: the Bash calls of all of them count.
                let binaries = result.records[at].cliBinaries + record.cliBinaries
                if record.outputTokens > result.records[at].outputTokens { result.records[at] = record }
                result.records[at].cliBinaries = binaries
            } else if result.records.count >= maxRecords {
                result.malformedLines += 1
            } else {
                if let id = record.messageID { index[id] = result.records.count }
                result.records.append(record)
            }
        }
    }
}
