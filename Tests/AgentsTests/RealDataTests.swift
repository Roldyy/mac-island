import Darwin
import Foundation
import Testing
@testable import AgentsFeature

/// Pipeline check on this Mac's real Claude Code logs. Skipped unless `MIS_REAL_DATA=1`. Prints counts,
/// totals and timings only: never a project name, a path or any message content.
@Suite struct RealDataTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["MIS_REAL_DATA"] == "1" }

    private static func peakMemoryMB() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576   // bytes on macOS
    }

    @Test(.enabled(if: RealDataTests.enabled)) func realLogsProduceASaneSnapshot() {
        let calendar = UsageFormat.calendar
        let now = Date()
        let since = UsageSnapshot.windowStart(now: now, calendar: calendar)
        // A temp store: the real run never touches the installed app's own cache file.
        let store = UsageCacheStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-real-\(UUID().uuidString)").appendingPathComponent("usage-cache.bin"))
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let source = ClaudeUsageSource(store: store)

        let t0 = Date()
        var firstReport: TimeInterval?
        var reports = 0
        let first = source.load(modifiedSince: since, shouldContinue: { true }) { _ in
            reports += 1
            if firstReport == nil { firstReport = Date().timeIntervalSince(t0) }
        }
        let parseSeconds = Date().timeIntervalSince(t0)
        let t1 = Date()
        let second = source.load(modifiedSince: since)
        let cachedSeconds = Date().timeIntervalSince(t1)

        // Relaunch: empty memory, cache on disk. Time to the first state (decode only), then to the end state.
        let relaunched = ClaudeUsageSource(store: store)
        let t3 = Date()
        var diskFirst: TimeInterval?
        var diskSnapshot: TimeInterval?
        let third = relaunched.load(modifiedSince: since, shouldContinue: { true }) { progress in
            guard diskFirst == nil else { return }
            diskFirst = Date().timeIntervalSince(t3)
            _ = UsageSnapshot.build(progress.result.records, now: now, calendar: calendar)
            diskSnapshot = Date().timeIntervalSince(t3)
        }
        let diskSeconds = Date().timeIntervalSince(t3)
        let storeBytes = (try? FileManager.default.attributesOfItem(atPath: store.url.path)[.size] as? Int) ?? 0

        let t2 = Date()
        let snapshot = UsageSnapshot.build(first.records, now: now, calendar: calendar)
        let buildSeconds = Date().timeIntervalSince(t2)

        let today = snapshot.summary(for: .today), week = snapshot.summary(for: .week), month = snapshot.summary(for: .month)
        let other = first.records.filter { ModelFamily(model: $0.model) == .other }.count
        let sample = PlanLimitSource().load()
        let state = LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: now)
        let heat = snapshot.heatmap.columns.flatMap { $0 }
        var lines: [String] = []
        lines.append("files=\(first.fileCount) parsedFirst=\(first.parsedFileCount) parsedSecond=\(second.parsedFileCount) dirMissing=\(first.directoryMissing)")
        lines.append("malformedLines=\(first.malformedLines) unreadableFiles=\(first.unreadableFiles) records=\(first.records.count) recordsSecond=\(second.records.count)")
        lines.append(String(format: "cold=%.2fs (first report %.2fs, %d reports) warmFromDisk: records at %.0f ms, first snapshot at %.0f ms, done %.2fs (parsed %d) memory=%.3fs",
                            parseSeconds, firstReport ?? -1, reports, (diskFirst ?? -1) * 1000, (diskSnapshot ?? -1) * 1000, diskSeconds,
                            third.parsedFileCount, cachedSeconds))
        lines.append(String(format: "build=%.0f ms cacheFile=%.1f MB peakRSS=%.0f MB", buildSeconds * 1000, Double(storeBytes) / 1_048_576, Self.peakMemoryMB()))
        lines.append("tokens today=\(today.totalTokens) week=\(week.totalTokens) month=\(month.totalTokens)")
        lines.append(String(format: "cost today=%.2f week=%.2f month=%.2f estimated=%@ cacheSavings=%.2f", today.totalCost, week.totalCost, month.totalCost, "\(month.costIsEstimated)", month.cacheSavings))
        lines.append("models=\(month.perModel.count) projects=\(month.perProject.count) recordsOfUnknownModel=\(other) perDayBars=\(month.perDay.count)")
        if let block = snapshot.block {
            lines.append("block open: tokens=\(block.tokens) lengthH=\(block.end.timeIntervalSince(block.start) / 3600) elapsedMin=\(Int(now.timeIntervalSince(block.start) / 60)) leftMin=\(Int(block.remaining(at: now) / 60))")
        } else {
            lines.append("block: none (last activity older than 5 h or no record)")
        }
        lines.append("heatmap activeDays=\(heat.filter { $0.tokens > 0 }.count) futureCells=\(heat.filter(\.isFuture).count) peak=\(snapshot.heatmap.peak)")
        lines.append("planFile sample=\(sample != nil) fiveHour=\(sample?.fiveHour.map(String.init) ?? "nil") sevenDay=\(sample?.sevenDay.map(String.init) ?? "nil") ageMin=\(sample.map { Int(now.timeIntervalSince($0.date) / 60) } ?? -1) stale=\(sample?.isStale(at: now) ?? false)")
        lines.append("limits source=\(state.source) rows=\(state.rows.map { "\($0.kind.rawValue):\($0.usedPercent.map(String.init) ?? "nil")" })")
        lines.append("plan=\(PlanTierSource.load()?.name ?? "unknown")")
        print("MIS_REAL_DATA\n" + lines.joined(separator: "\n"))

        #expect(first.records.count > 0, "no usage record found")
        #expect(month.totalTokens >= week.totalTokens && week.totalTokens >= today.totalTokens, "periods not nested")
        #expect(second.records.count >= first.records.count, "cached pass lost records")
        #expect(third.records.count >= first.records.count, "disk-cached pass lost records")
        #expect(third.parsedFileCount <= 5, "a relaunch re-read more than the files that changed meanwhile")  // a live log may grow between passes
    }
}
