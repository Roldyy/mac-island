import AppKit
import ClaudeLiveKit
import Foundation
import IslandUI
import SwiftUI
import Testing
@testable import AgentsFeature

/// Renders the real page to PNGs in `NSTemporaryDirectory()/mac-island-agents/` so a person (or an agent
/// with an image reader) can look at it. The asserts only check that something non-trivial was drawn.
@MainActor @Suite struct PageSnapshotTests {
    // Content box of the island section: 720 pt panel minus 14 pt margins each side. The height is the
    // 420 pt panel minus the notch band, header, section picker and quick-access bar (about 256 pt).
    static let panelWidth: CGFloat = 720
    static let viewportHeight: CGFloat = 256

    nonisolated static var calendar: Calendar { UsageFormat.calendar }

    nonisolated static var now: Date {
        DateComponents(calendar: calendar, year: 2026, month: 10, day: 31, hour: 15, minute: 20).date ?? Date()
    }

    // MARK: synthetic data

    struct Lcg {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    nonisolated static func records(now: Date) -> [UsageRecord] {
        let models = ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"]
        let projects = ["odoo-erp", "site-golf", "mac-island", "api-gateway", "docs"]
        var rng = Lcg(state: 42)
        var out: [UsageRecord] = []
        let today = calendar.startOfDay(for: now)
        for back in 0..<40 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            if (weekday == 1 || weekday == 7) && rng.next() < 0.6 { continue }   // quiet weekends
            if back % 11 == 5 { continue }
            let count = 8 + Int(rng.next() * 30)
            for _ in 0..<count {
                let hour = 9 + Int(rng.next() * 9)
                let minute = Int(rng.next() * 59)
                guard let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), t <= now else { continue }
                let model = models[rng.next() < 0.45 ? 0 : (rng.next() < 0.7 ? 1 : 2)]
                out.append(UsageRecord(
                    messageID: nil, model: model, timestamp: t,
                    inputTokens: 200 + Int(rng.next() * 3_000), outputTokens: 800 + Int(rng.next() * 6_000),
                    cacheCreationTokens: Int(rng.next() * 25_000), cacheReadTokens: 60_000 + Int(rng.next() * 260_000),
                    project: projects[Int(rng.next() * 4.99)]))
            }
        }
        // Two bursts today, the last one 15 minutes ago, so a 5 h block is open (14:00 to 19:00).
        for minutesAgo in [95, 60, 15] {
            out.append(UsageRecord(messageID: nil, model: "claude-opus-4-5", timestamp: now.addingTimeInterval(Double(-minutesAgo) * 60),
                                   inputTokens: 900, outputTokens: 4_000, cacheCreationTokens: 12_000,
                                   cacheReadTokens: 180_000, project: "mac-island"))
        }
        return out
    }

    nonisolated static func liveSessions() -> [ClaudeSession] {
        [ClaudeSession(id: "1", pid: 101, state: .working, folderName: "mac-island", entrypoint: "claude-vscode",
                       updatedAt: now.addingTimeInterval(-4 * 60)),
         ClaudeSession(id: "2", pid: 102, state: .idle, folderName: "odoo-erp", entrypoint: "cli",
                       updatedAt: now.addingTimeInterval(-37 * 60))]
    }

    static func model(limits: PlanLimitSample?? = .some(PlanLimitSample(date: now.addingTimeInterval(-90), fiveHour: 3, sevenDay: 58)),
                      loaded: Bool = true, empty: Bool = false) -> AgentsUsageModel {
        let model = AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [],
                                     calendar: calendar, clock: { now })
        guard loaded else { return model }
        let records = empty ? [] : records(now: now)
        let snapshot = UsageSnapshot.build(records, now: now, calendar: calendar)
        let state = LimitsState.resolve(sample: limits ?? nil, block: snapshot.block,
                                        weekTokens: snapshot.week.tokens, now: now)
        model.preload(snapshot: snapshot, limits: state, plan: .max5x, status: empty ? .empty : .ready)
        return model
    }

    static func live(_ sessions: [ClaudeSession] = liveSessions()) -> AgentsLiveModel {
        let live = AgentsLiveModel()
        live.previewSessions = sessions
        return live
    }

    // MARK: rendering

    static var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mac-island-agents", isDirectory: true)
    }

    /// The island backdrop: solid black under the glass cards, dark appearance, 14 pt side margins.
    @discardableResult
    static func render<V: View>(_ content: V, name: String, height: CGFloat?) -> URL? {
        let framed = content
            .frame(width: panelWidth - 28, height: height)
            .padding(.horizontal, 14)
            .background(Color(white: 0.04))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? png.write(to: url)
        return url
    }

    static func viewport<V: View>(_ page: V, scrolledBy offset: CGFloat = 0) -> some View {
        page.frame(width: panelWidth - 28, alignment: .top).fixedSize(horizontal: false, vertical: true)
            .offset(y: -offset)
            .frame(width: panelWidth - 28, height: viewportHeight, alignment: .top)
            .clipped()
    }

    @Test func rendersFullPageAndViewport() {
        let model = Self.model(), live = Self.live()
        let page = AgentsPage(model: model, live: live, isLive: false)
        #expect(Self.render(page.page, name: "full-month", height: nil) != nil)
        // ImageRenderer cannot draw a ScrollView, so the viewport is the page clipped to the section height.
        #expect(Self.render(Self.viewport(page.page), name: "viewport-month", height: Self.viewportHeight) != nil)
        #expect(Self.render(Self.viewport(page.page, scrolledBy: 250), name: "viewport-month-scrolled",
                            height: Self.viewportHeight) != nil)
        model.period = .today
        #expect(Self.render(AgentsPage(model: model, live: live, isLive: false).page, name: "full-today", height: nil) != nil)
    }

    @Test func rendersTheOtherStates() {
        let live = Self.live()
        #expect(Self.render(Self.viewport(AgentsPage(model: Self.model(loaded: false), live: live, isLive: false).page),
                            name: "state-loading", height: Self.viewportHeight) != nil)
        #expect(Self.render(Self.viewport(AgentsPage(model: Self.model(limits: .some(nil), empty: true), live: Self.live([]),
                                                     isLive: false).page),
                            name: "state-empty", height: Self.viewportHeight) != nil)
        #expect(Self.render(AgentsPage(model: Self.model(limits: .some(nil)), live: live, isLive: false).page,
                            name: "state-estimated-full", height: nil) != nil)
        let stale = PlanLimitSample(date: Self.now.addingTimeInterval(-7.5 * 3600), fiveHour: 3, sevenDay: 58)
        #expect(Self.render(Self.viewport(AgentsPage(model: Self.model(limits: .some(stale)), live: live, isLive: false).page),
                            name: "state-stale-sample", height: Self.viewportHeight) != nil)
        #expect(Self.render(AgentsPage(model: Self.model(), live: live, showsSettings: true, isLive: false).page,
                            name: "state-settings", height: nil) != nil)
    }
}
