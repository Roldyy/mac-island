import Foundation
import Testing
@testable import ShellKit

/// The two-click rule of a confirming action, as pure functions of (action, armed, now).
@MainActor
@Suite struct StatusChipConfirmationTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func quit() -> StatusChipAction { StatusChipAction(id: "quit", title: "Quitter", isDestructive: true) {} }
    private func copy() -> StatusChipAction { StatusChipAction(id: "copy", title: "Copier") {} }

    @Test func aPlainActionRunsOnTheFirstClick() {
        #expect(StatusChipConfirmation.decide(copy(), armed: nil, now: t0) == .perform)
    }

    @Test func aDestructiveActionNeedsASecondClick() {
        #expect(quit().needsConfirmation)
        #expect(StatusChipConfirmation.decide(quit(), armed: nil, now: t0) == .arm)
        let armed = StatusChipConfirmation.Armed(actionID: "quit", at: t0)
        #expect(StatusChipConfirmation.decide(quit(), armed: armed, now: t0.addingTimeInterval(1)) == .perform)
    }

    @Test func anActionThatAsksIsConfirmedEvenWhenNotDestructive() {
        let ask = StatusChipAction(id: "share", title: "Partager", requiresConfirmation: true) {}
        #expect(!ask.isDestructive && ask.needsConfirmation)
        #expect(StatusChipConfirmation.decide(ask, armed: nil, now: t0) == .arm)
    }

    @Test func theConfirmationExpiresAfterThreeSeconds() {
        #expect(StatusChipConfirmation.window == 3)
        let armed = StatusChipConfirmation.Armed(actionID: "quit", at: t0)
        #expect(StatusChipConfirmation.isArmed(armed, for: "quit", now: t0.addingTimeInterval(2.99)))
        #expect(!StatusChipConfirmation.isArmed(armed, for: "quit", now: t0.addingTimeInterval(3)))
        #expect(StatusChipConfirmation.decide(quit(), armed: armed, now: t0.addingTimeInterval(3.5)) == .arm)
    }

    @Test func aConfirmationIsForOneActionOnly() {
        let armed = StatusChipConfirmation.Armed(actionID: "other", at: t0)
        #expect(!StatusChipConfirmation.isArmed(armed, for: "quit", now: t0))
        #expect(StatusChipConfirmation.decide(quit(), armed: armed, now: t0) == .arm)
        #expect(!StatusChipConfirmation.isArmed(nil, for: "quit", now: t0))
    }

    @Test func aClockThatWentBackwardsNeverConfirms() {
        let armed = StatusChipConfirmation.Armed(actionID: "quit", at: t0)
        #expect(!StatusChipConfirmation.isArmed(armed, for: "quit", now: t0.addingTimeInterval(-1)))
    }
}
