import Foundation
import Testing
@testable import KeepAwakeFeature

@Suite struct SessionPlanTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func unlimitedSessionNeverExpires() {
        let plan = SessionPlan(start: t0, duration: nil)
        #expect(plan.expiry == nil)
        #expect(plan.remaining(at: t0.addingTimeInterval(1e6)) == nil)
        #expect(!plan.isExpired(at: t0.addingTimeInterval(1e6)))
    }

    @Test func limitedSessionCountsDownAndExpires() {
        let plan = SessionPlan(start: t0, duration: 30 * 60)
        #expect(plan.expiry == t0.addingTimeInterval(1800))
        #expect(plan.remaining(at: t0.addingTimeInterval(600)) == 1200)
        #expect(!plan.isExpired(at: t0.addingTimeInterval(1799)))
        #expect(plan.isExpired(at: t0.addingTimeInterval(1800)))
        #expect(plan.remaining(at: t0.addingTimeInterval(9000)) == 0)
    }

    @Test func minutesZeroOrNegativeMeansUnlimited() {
        #expect(SessionPlan(start: t0, minutes: 0).duration == nil)
        #expect(SessionPlan(start: t0, minutes: -5).duration == nil)
        #expect(SessionPlan(start: t0, minutes: 60).duration == 3600)
    }

    @Test func countdownFormatting() {
        #expect(SessionPlan.format(remaining: 59) == "0:59")
        #expect(SessionPlan.format(remaining: 600) == "10:00")
        #expect(SessionPlan.format(remaining: 3725) == "1:02:05")
        #expect(SessionPlan.format(remaining: 0.4) == "0:01")
    }
}
