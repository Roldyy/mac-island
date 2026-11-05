import Testing
@testable import IslandKit

@Suite struct StalePasteGuardTests {
    @Test func freshAndSameAppIsNotStale() {
        let g = StalePasteGuard(requestedAt: 10, frontPID: 5)
        #expect(!g.isStale(now: 10.5, frontPID: 5))
    }

    @Test func olderThanTheLimitIsStale() {
        let g = StalePasteGuard(requestedAt: 10, frontPID: 5)
        #expect(g.isStale(now: 10 + StalePasteGuard.maxAge + 0.01, frontPID: 5))
        #expect(!g.isStale(now: 10 + StalePasteGuard.maxAge, frontPID: 5))
    }

    @Test func aSlowButLegitimatePasteIsNotStale() {
        let g = StalePasteGuard(requestedAt: 10, frontPID: 5)
        #expect(StalePasteGuard.maxAge == 8)
        #expect(!g.isStale(now: 15, frontPID: 5))
    }

    @Test func anotherFrontAppIsStale() {
        let g = StalePasteGuard(requestedAt: 10, frontPID: 5)
        #expect(g.isStale(now: 10.1, frontPID: 6))
        #expect(g.isStale(now: 10.1, frontPID: nil))
    }
}
