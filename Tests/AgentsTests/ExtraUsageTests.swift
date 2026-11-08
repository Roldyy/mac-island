import Foundation
import Testing
@testable import AgentsFeature

/// MIS_0120: the extra-usage ("crédit supplémentaire") gauge reads Claude Code's own cache in ~/.claude.json.
/// No network, no Keychain. The cache can be days old: age and staleness are part of the value.
struct ExtraUsageTests {
    static let now = Date(timeIntervalSince1970: 1_762_600_000)

    static func json(fetchedAgo: TimeInterval? = 3600, reached: Bool = false, enabled: Bool = true,
                     reason: String? = nil, rootReason: String? = nil, limit: Int = 5000, used: Int = 584) -> Data {
        let fetched = fetchedAgo.map { "\"fetchedAtMs\": \(Int((now.timeIntervalSince1970 - $0) * 1000))," } ?? ""
        let reasonJSON = reason.map { "\"\($0)\"" } ?? "null"
        let rootJSON = rootReason.map { ",\"cachedExtraUsageDisabledReason\": \"\($0)\"" } ?? ""
        return Data("""
        {"numStartups": 3, "cachedUsageUtilization": {\(fetched) "utilization": {"five_hour": {"utilization": 3},
        "extra_usage": {"is_enabled": \(enabled), "monthly_limit": \(limit), "used_credits": \(used),
        "utilization": 11.68, "currency": "EUR", "decimal_places": 2, "disabled_reason": \(reasonJSON),
        "user_disabled": false, "spend_limit_reached": \(reached), "credits_ever_enabled": true}}}\(rootJSON)}
        """.utf8)
    }

    @Test func amountsAreMinorUnitsDividedByTheDecimalPlaces() throws {
        let extra = try #require(ExtraUsageParser.parse(Self.json()))
        #expect(extra.limit == 50.0)
        #expect(extra.used == 5.84)
        #expect(extra.currency == "EUR")
        #expect(extra.isEnabled)
        #expect(!extra.limitReached)
        #expect(abs((extra.percent ?? 0) - 11.68) < 1e-9)
    }

    @Test func percentIsComputedWhenTheCacheOmitsIt() throws {
        let raw = String(decoding: Self.json(), as: UTF8.self).replacingOccurrences(of: "\"utilization\": 11.68,", with: "")
        let extra = try #require(ExtraUsageParser.parse(Data(raw.utf8)))
        #expect(abs((extra.percent ?? 0) - 11.68) < 1e-9)
    }

    @Test func aReachedLimitIsReportedAndShownAsFull() throws {
        let extra = try #require(ExtraUsageParser.parse(Self.json(reached: true, used: 5000)))
        #expect(extra.limitReached)
        #expect(extra.statusText == "Plafond atteint")
    }

    @Test func theRootReasonCountsOnlyWhenTheFeatureIsOff() throws {
        let on = try #require(ExtraUsageParser.parse(Self.json(rootReason: "org_spend_cap_reached")))
        #expect(on.disabledReason == nil)
        let off = try #require(ExtraUsageParser.parse(Self.json(enabled: false, rootReason: "org_spend_cap_reached")))
        #expect(off.disabledReason == "org_spend_cap_reached")
        #expect(off.statusText == "Plafond de l’organisation atteint")
    }

    @Test func stalenessAndAgeAreWordedInFrench() throws {
        let fresh = try #require(ExtraUsageParser.parse(Self.json(fetchedAgo: 3600)))
        #expect(!fresh.isStale(at: Self.now))
        #expect(fresh.ageText(at: Self.now) == "il y a 1 h")
        let old = try #require(ExtraUsageParser.parse(Self.json(fetchedAgo: 3 * 86_400)))
        #expect(old.isStale(at: Self.now))
        #expect(old.ageText(at: Self.now) == "il y a 3 j")
        let unknown = try #require(ExtraUsageParser.parse(Self.json(fetchedAgo: nil)))
        #expect(unknown.isStale(at: Self.now))
        #expect(unknown.ageText(at: Self.now) == "date inconnue")
        let minutes = try #require(ExtraUsageParser.parse(Self.json(fetchedAgo: 600)))
        #expect(minutes.ageText(at: Self.now) == "il y a 10 min")
    }

    @Test func missingOrBrokenFilesGiveNilAndNeverCrash() {
        #expect(ExtraUsageParser.parse(Data()) == nil)
        #expect(ExtraUsageParser.parse(Data("[1,2]".utf8)) == nil)
        #expect(ExtraUsageParser.parse(Data("{\"cachedUsageUtilization\": {}}".utf8)) == nil)
        #expect(ExtraUsageParser.parse(Data("{\"cachedUsageUtilization\": {\"utilization\": {\"extra_usage\": 3}}}".utf8)) == nil)
    }

    @Test func anAbsurdDecimalPlacesNeverTrapsTheApp() throws {
        for places in ["1e19", "-5", "99", "1e308"] {
            let raw = String(decoding: Self.json(), as: UTF8.self)
                .replacingOccurrences(of: "\"decimal_places\": 2", with: "\"decimal_places\": \(places)")
            #expect(ExtraUsageParser.parse(Data(raw.utf8)) != nil, "\(places)")
        }
    }

    @Test func theSourceReadsAFileAndRefusesAnAbsurdOne() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("extra-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("claude.json")
        try Self.json().write(to: file)
        #expect(ExtraUsageSource(url: file).load()?.limit == 50.0)
        #expect(ExtraUsageSource(url: dir.appendingPathComponent("absent.json")).load() == nil)
        #expect(ExtraUsageSource(url: file, maxBytes: 10).load() == nil)
    }
}
