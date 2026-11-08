import Foundation
import Testing
@testable import PortKit

/// MIS_0120: the calendar page is never a silent blank. Every reason the list can be empty has its own state.
struct CalendarAgendaStateTests {
    @Test func eventsAlwaysWinOverEveryOtherSignal() {
        #expect(NotchCalendarSupport.agendaState(loading: false, eventCount: 3, serviceRunning: false,
                                                 readableCalendars: 0) == .events)
    }

    @Test func aStoppedServiceIsReportedAndNeverCalledEmpty() {
        #expect(NotchCalendarSupport.agendaState(loading: false, eventCount: 0, serviceRunning: false,
                                                 readableCalendars: nil) == .serviceOff)
    }

    @Test func aRunningServiceWithNoReadableCalendarSaysSo() {
        #expect(NotchCalendarSupport.agendaState(loading: false, eventCount: 0, serviceRunning: true,
                                                 readableCalendars: 0) == .noCalendars)
    }

    @Test func aRunningServiceWithCalendarsAndNoEventIsReallyEmpty() {
        #expect(NotchCalendarSupport.agendaState(loading: false, eventCount: 0, serviceRunning: true,
                                                 readableCalendars: 4) == .empty)
        // Calendars not counted yet: still a plain empty week, not an error.
        #expect(NotchCalendarSupport.agendaState(loading: false, eventCount: 0, serviceRunning: true,
                                                 readableCalendars: nil) == .empty)
    }

    @Test func loadingShowsTheSpinnerOnlyWhileNothingIsKnown() {
        #expect(NotchCalendarSupport.agendaState(loading: true, eventCount: 0, serviceRunning: true,
                                                 readableCalendars: nil) == .loading)
        #expect(NotchCalendarSupport.agendaState(loading: true, eventCount: 2, serviceRunning: true,
                                                 readableCalendars: 1) == .events)
    }

    @Test func anEmptyCatalogIsAnEarlyReadNotACalendarlessMac() {
        func choice(_ id: String) -> NotchCalendarChoice { NotchCalendarChoice(id: id, title: id, sourceID: "s", source: "s") }
        #expect(NotchCalendarSupport.readableCalendars(known: [], excluded: []) == nil)
        #expect(NotchCalendarSupport.readableCalendars(known: [choice("a"), choice("b")], excluded: ["a"]) == 1)
        #expect(NotchCalendarSupport.readableCalendars(known: [choice("a")], excluded: ["a"]) == 0)
    }

    @Test func aStoppedServiceThatTheTabCanRestartIsRestarted() {
        #expect(NotchCalendarSupport.shouldRestart(serviceRunning: false, enabled: true))
        #expect(!NotchCalendarSupport.shouldRestart(serviceRunning: true, enabled: true))
        #expect(!NotchCalendarSupport.shouldRestart(serviceRunning: false, enabled: false))
    }
}
