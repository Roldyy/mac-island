import Darwin
import Foundation
import Testing
@testable import AgentsFeature

/// Counts live malloc bytes (all zones) from a side thread while a block runs: the peak above the start.
private final class AllocationSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var peak = 0

    static func inUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// Peak growth of live bytes while `body` runs.
    static func peakGrowth(of body: () throws -> Void) rethrows -> Int {
        let sampler = AllocationSampler()
        let base = inUse()
        let thread = Thread {
            while sampler.lock.withLock({ sampler.running }) {
                let now = inUse() - base
                sampler.lock.withLock { sampler.peak = max(sampler.peak, now) }
                usleep(2_000)
            }
        }
        thread.start()
        defer { sampler.lock.withLock { sampler.running = false } }
        try body()
        return sampler.lock.withLock { max(sampler.peak, inUse() - base) }
    }
}

@Suite struct BoundedParsingTests {
    /// `distinct` messages, each repeated `repeats` times with a growing output (one line per content block).
    private func writeLog(distinct: Int, repeats: Int) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-usage-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var chunk = ""
        for message in 0..<distinct {
            for repeatIndex in 1...repeats {
                chunk += UsageParsingTests.line(id: "msg_synthetic_\(message)", model: "claude-synthetic-model-20260101",
                                                ts: "2026-10-05T10:00:00.000Z", output: repeatIndex * 10) + "\n"
            }
            if chunk.utf8.count > 1 << 20 { try handle.write(contentsOf: Data(chunk.utf8)); chunk = "" }
        }
        try handle.write(contentsOf: Data(chunk.utf8))
        return url
    }

    @Test func repeatedMessageIdsNeverInflateTheRecordArray() throws {
        let url = try writeLog(distinct: 5_000, repeats: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let parse = try ClaudeUsageParser.parse(file: url)
        #expect(parse.committed.records.count == 5_000, "one record per message id, kept while streaming")
        #expect(parse.committed.records.allSatisfy { $0.outputTokens == 40 }, "the largest output wins")
    }

    @Test func recordCountPerFileIsCapped() throws {
        let url = try writeLog(distinct: 3_000, repeats: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let parse = try ClaudeUsageParser.parse(file: url, maxRecords: 1_000)
        #expect(parse.committed.records.count == 1_000)
        #expect(parse.committed.malformedLines >= 2_000, "records past the cap are counted, not kept")
    }

    /// Process-wide malloc counters: exact only when nothing else allocates, so it is opt-in and run alone:
    /// `MIS_ALLOC_TEST=1 swift test --filter BoundedParsingTests`. The two tests above hold the same bound
    /// in the default run (one record per id, a record cap), without a counter.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MIS_ALLOC_TEST"] == "1"))
    func aLargeLogIsStreamedWithBoundedPeakAllocation() throws {
        // About 45 MB on disk: 30 000 messages, 4 lines each.
        let url = try writeLog(distinct: 30_000, repeats: 4)
        defer { try? FileManager.default.removeItem(at: url) }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 30 << 20)
        var count = 0
        // The malloc counters are process wide and other suites allocate meanwhile (the cache tests for a minute):
        // measure only in a quiet moment, up to 8 tries. A process that never goes quiet measures nothing; the
        // suite then has to be run alone (`--filter BoundedParsingTests`), where it is exact.
        var growth: Int?
        var measuredQuiet = false
        for _ in 0..<8 where growth == nil {
            let before = AllocationSampler.inUse()
            usleep(300_000)
            guard abs(AllocationSampler.inUse() - before) < 2 << 20 else { continue }
            let measured = try AllocationSampler.peakGrowth {
                count = try ClaudeUsageParser.parse(file: url).committed.records.count
            }
            measuredQuiet = true
            if measured < 25 << 20 { growth = measured }   // a noisy run is retried, a clean one is final
        }
        guard let growth else {
            if measuredQuiet { Issue.record("peak live allocation stayed above 25 MB in every quiet run") }
            return   // never quiet: nothing was measured, run this suite alone
        }
        #expect(count == 30_000)
        // The file must never sit in memory (45 MB) and the records of the repeats must not pile up: the 30 000
        // kept records (a few MB) plus one 1 MB chunk is the bound; 25 MB leaves room for the sampler's noise.
        #expect(growth < 25 << 20, "peak live allocation grew by \(growth >> 20) MB")
    }

    @Test func mergedCacheKeepsOneCopyOfARepeatedMessage() {
        let cache = UsageFileCache()
        func parse(_ id: String) -> ClaudeUsageParser.FileParse {
            var p = ClaudeUsageParser.FileParse()
            p.committed.records = [UsageRecord(messageID: id, model: "m", timestamp: Date(timeIntervalSince1970: 1),
                                               inputTokens: 1, outputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0)]
            return p
        }
        cache.store(parse("same"), path: "/a", key: .init(size: 1, mtime: .distantPast), fingerprint: Data())
        cache.store(parse("same"), path: "/b", key: .init(size: 1, mtime: .distantPast), fingerprint: Data())
        #expect(cache.merged().records.count == 1)
    }
}
