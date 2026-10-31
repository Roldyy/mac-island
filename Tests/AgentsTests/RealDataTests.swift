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
        let source = ClaudeUsageSource()

        let t0 = Date()
        let first = source.load(modifiedSince: since)
        let parseSeconds = Date().timeIntervalSince(t0)
        let t1 = Date()
        let second = source.load(modifiedSince: since)
        let cachedSeconds = Date().timeIntervalSince(t1)

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
        lines.append(String(format: "parseFirst=%.2fs parseCached=%.2fs build=%.2fs peakRSS=%.0f MB", parseSeconds, cachedSeconds, buildSeconds, Self.peakMemoryMB()))
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
        #expect(second.records.count >= first.records.count, "cached pass lost records")  // a live log may grow between passes
    }
}
