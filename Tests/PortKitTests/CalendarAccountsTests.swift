import AppKit
import EventKit
import Foundation
import Testing
@testable import PortKit

/// Google Calendar through the macOS account: every pure rule of the calendar lane. EventKit is reached through
/// `CalendarCatalogReading` only; no EKEventStore is ever created here.
struct CalendarAccountsTests {
    // MARK: Conference links

    @Test func everyAllowListedHostIsFoundInTheUrlLocationAndNotes() {
        let hosts = ["https://meet.google.com/abc-defg-hij", "https://us02web.zoom.us/j/123456789?pwd=x",
                     "https://teams.microsoft.com/l/meetup-join/19%3a", "https://acme.webex.com/meet/jo",
                     "https://acme.whereby.com/room"]
        for link in hosts {
            let url = URL(string: link)!
            #expect(CalendarConferenceLink.detect(url: url, location: nil, notes: nil) == url, "\(link)")
            #expect(CalendarConferenceLink.detect(url: nil, location: "Salle 3 - \(link)", notes: nil) == url, "\(link)")
            #expect(CalendarConferenceLink.detect(url: nil, location: nil, notes: "Rejoindre : \(link).\nMerci") == url, "\(link)")
        }
    }

    @Test func theUrlFieldBeatsTheLocationAndTheLocationBeatsTheNotes() {
        let a = URL(string: "https://meet.google.com/aaa-aaaa-aaa")!
        #expect(CalendarConferenceLink.detect(url: a, location: "https://zoom.us/j/1", notes: "https://whereby.com/x") == a)
        #expect(CalendarConferenceLink.detect(url: nil, location: "https://zoom.us/j/1", notes: "https://whereby.com/x")
                == URL(string: "https://zoom.us/j/1"))
    }

    @Test func lookalikeHostsAndForeignSchemesAreRefused() {
        let refused = ["https://meet.google.com.evil.io/abc", "https://evilzoom.us/j/1", "https://zoom.us.evil.io/j/1",
                       "http://meet.google.com/abc", "javascript:alert(1)", "file:///etc/passwd",
                       "https://meet.google.com@evil.io/x", "https://user:pw@zoom.us/j/1", "https://zoom.us:8443/j/1",
                       "https://meet.google.com\u{202E}.evil.io/x", "https://еvil.zoom.us.example/x",
                       "https://notmeet.google.com.example.org/"]
        for link in refused {
            #expect(CalendarConferenceLink.detect(url: URL(string: link), location: link, notes: link) == nil, "\(link)")
        }
    }

    @Test func aHugeInputIsBoundedAndAnOverlongLinkIsRefused() {
        let filler = String(repeating: "x", count: 5_000_000)
        #expect(CalendarConferenceLink.detect(url: nil, location: filler, notes: filler + " https://zoom.us/j/9") == nil,
                "a link past the scan window is not read")
        let long = "https://zoom.us/j/1?pwd=" + String(repeating: "a", count: 3_000)
        #expect(CalendarConferenceLink.detect(url: nil, location: long, notes: nil) == nil)
        let ok = CalendarConferenceLink.detect(url: nil, location: nil, notes: "intro " + "https://zoom.us/j/9")
        #expect(ok == URL(string: "https://zoom.us/j/9"))
    }

    @Test func validatedRechecksTheExactUrlBeforeItIsOpened() {
        #expect(CalendarConferenceLink.validated(URL(string: "https://meet.google.com/a")!) != nil)
        #expect(CalendarConferenceLink.validated(URL(string: "https://evil.io/meet.google.com")!) == nil)
        #expect(CalendarConferenceLink.validated(URL(string: "javascript:alert(1)")!) == nil)
    }

    // MARK: Untrusted text

    @Test func controlAndBidiCharactersAreStrippedAndLengthIsCapped() {
        #expect(CalendarText.clean("Reu\u{202E}nion\u{0007}\u{200B}!", limit: 50) == "Reunion!")
        #expect(CalendarText.clean("a\nb\tc\r\nd", limit: 50) == "a b c d")
        #expect(CalendarText.clean("  \u{2066}x\u{2069}  ", limit: 50) == "x")
        #expect(CalendarText.clean(nil, limit: 10) == "")
        let capped = CalendarText.clean(String(repeating: "ab", count: 10_000), limit: 20)
        #expect(capped.count == 20 && capped.hasSuffix("…"))
    }

    // MARK: Declined and cancelled

    private func raw(cancelled: Bool = false, declined: Bool = false, url: URL? = nil, notes: String? = nil) -> CalendarEventRaw {
        CalendarEventRaw(title: "Point", location: "Bureau", notes: notes, url: url, cancelled: cancelled, currentUserDeclined: declined)
    }

    @Test func cancelledAndDeclinedAreHiddenByDefault() {
        #expect(CalendarEventFacts.make(raw(), showDeclined: false) != nil)
        #expect(CalendarEventFacts.make(raw(cancelled: true), showDeclined: false) == nil)
        #expect(CalendarEventFacts.make(raw(declined: true), showDeclined: false) == nil)
    }

    @Test func theOptionShowsDeclinedButNeverCancelled() {
        let shown = CalendarEventFacts.make(raw(declined: true), showDeclined: true)
        #expect(shown?.declined == true)
        #expect(CalendarEventFacts.make(raw(cancelled: true, declined: true), showDeclined: true) == nil)
    }

    @Test func factsCarrySanitisedTextAndTheJoinLink() {
        let facts = CalendarEventFacts.make(
            CalendarEventRaw(title: "Sync\u{202E}", location: "Salle\n2", notes: "https://meet.google.com/abc-defg-hij",
                             url: nil, cancelled: false, currentUserDeclined: false), showDeclined: false)
        #expect(facts?.title == "Sync" && facts?.location == "Salle 2")
        #expect(facts?.joinURL == URL(string: "https://meet.google.com/abc-defg-hij"))
    }

    // MARK: Accounts

    struct FakeCatalog: CalendarCatalogReading {
        var items: [CalendarDescriptor]
        func calendarDescriptors() -> [CalendarDescriptor] { items }
    }

    private func descriptor(_ id: String, _ title: String, source: String, _ sourceTitle: String,
                            type: EKSourceType) -> CalendarDescriptor {
        CalendarDescriptor(id: id, title: title, color: .fallback, sourceID: source, sourceTitle: sourceTitle, sourceType: type)
    }

    private var everyAccount: FakeCatalog {
        FakeCatalog(items: [
            descriptor("i1", "Maison", source: "S-icloud", "iCloud", type: .calDAV),
            descriptor("g1", "harold@gmail.com", source: "S-google", "Gmail", type: .calDAV),
            descriptor("g2", "Équipe", source: "S-google", "Gmail", type: .calDAV),
            descriptor("x1", "Travail", source: "S-ex", "Exchange", type: .exchange),
            descriptor("l1", "Sur mon Mac", source: "S-local", "Sur mon Mac", type: .local),
            descriptor("s1", "Jours fériés", source: "S-sub", "Abonnements", type: .subscribed),
            descriptor("b1", "Anniversaires", source: "S-bday", "Anniversaires", type: .birthdays),
        ])
    }

    @Test func sourcesAreClassifiedByTypeAndTitle() {
        #expect(CalendarSourceKind.classify(type: .calDAV, title: "iCloud") == .iCloud)
        #expect(CalendarSourceKind.classify(type: .mobileMe, title: "iCloud") == .iCloud)
        #expect(CalendarSourceKind.classify(type: .calDAV, title: "Gmail") == .google)
        #expect(CalendarSourceKind.classify(type: .calDAV, title: "Google") == .google)
        #expect(CalendarSourceKind.classify(type: .calDAV, title: "Fastmail") == .calDAV)
        #expect(CalendarSourceKind.classify(type: .exchange, title: "Travail") == .exchange)
        #expect(CalendarSourceKind.classify(type: .local, title: "Sur mon Mac") == .local)
        #expect(CalendarSourceKind.classify(type: .subscribed, title: "x") == .subscribed)
        #expect(CalendarSourceKind.classify(type: .birthdays, title: "x") == .birthdays)
    }

    @Test func theCatalogListsEveryCalendarOfEverySourceGroupedByAccount() {
        let choices = CalendarCatalog.choices(from: everyAccount)
        #expect(choices.count == 7)
        let groups = NotchCalendarSupport.grouped(choices)
        #expect(groups.count == 6)
        let google = groups.first { $0.first?.sourceID == "S-google" }
        #expect(google?.map(\.title) == ["Équipe", "harold@gmail.com"])
        #expect(google?.first?.source == "Gmail" && google?.first?.kind == .google)
    }

    @Test func aCalendarSeenTwiceIsListedOnce() {
        let twice = FakeCatalog(items: [descriptor("g1", "A", source: "S", "Gmail", type: .calDAV),
                                        descriptor("g1", "A", source: "S", "Gmail", type: .calDAV)])
        #expect(CalendarCatalog.choices(from: twice).count == 1)
    }

    @Test func toutAndAucunActOnOneAccountOnly() {
        let choices = CalendarCatalog.choices(from: everyAccount)
        let google = choices.filter { $0.sourceID == "S-google" }
        var excluded: Set<String> = ["i1"]
        excluded = CalendarSelection.setAccount(google, shown: false, excluded: excluded)
        #expect(excluded == ["i1", "g1", "g2"])
        #expect(CalendarSelection.accountState(google, excluded: excluded) == .none)
        excluded = CalendarSelection.setAccount(google, shown: true, excluded: excluded)
        #expect(excluded == ["i1"])
        #expect(CalendarSelection.accountState(google, excluded: excluded) == .all)
        #expect(CalendarSelection.accountState(google, excluded: ["g2"]) == .some)
    }

    // MARK: Selection persisted by identifier

    @Test func theExistingSelectionIsKeptAndVanishedCalendarsAreDroppedQuietly() {
        let choices = CalendarCatalog.choices(from: everyAccount)
        let stored: Set<String> = ["g2", "gone-1", "x1", "gone-2"]
        #expect(CalendarSelection.pruned(stored, known: choices) == ["g2", "x1"])
        #expect(CalendarSelection.pruned(stored, known: []) == stored, "an empty catalog is a failed read, never a reason to forget")
        #expect(CalendarSelection.pruned(["g1"], known: choices) == ["g1"])
    }

    @Test func theSelectionStaysUnderTheCurrentKeyWithTheSameShape() {
        let suite = UserDefaults(suiteName: "calendar-accounts-\(UUID().uuidString)")!
        suite.set(["g2", "x1"], forKey: DefaultsKey.notchCalendarExcluded)
        #expect(NotchCalendarSupport.excludedCalendars(in: suite) == ["g2", "x1"])
        NotchCalendarSupport.setCalendar("g2", shown: true, in: suite)
        #expect(NotchCalendarSupport.excludedCalendars(in: suite) == ["x1"])
        CalendarSelection.store(["x1", "z"], in: suite)
        #expect(suite.stringArray(forKey: DefaultsKey.notchCalendarExcluded) == ["x1", "z"])
    }

    @Test func showDeclinedIsOffUnlessSetAndLivesUnderItsOwnKey() {
        let suite = UserDefaults(suiteName: "calendar-declined-\(UUID().uuidString)")!
        #expect(!CalendarEventFacts.showsDeclined(in: suite))
        suite.set(true, forKey: CalendarEventFacts.showDeclinedKey)
        #expect(CalendarEventFacts.showsDeclined(in: suite))
    }

    // MARK: Empty state for a Mac without a Google account

    @Test func theGoogleHintShowsOnlyWithoutAnyAccountBeyondLocalAndICloud() {
        let plain = CalendarCatalog.choices(from: FakeCatalog(items: [
            descriptor("i1", "Maison", source: "S-icloud", "iCloud", type: .calDAV),
            descriptor("l1", "Mac", source: "S-local", "Sur mon Mac", type: .local),
            descriptor("b1", "Anniversaires", source: "S-bday", "Anniversaires", type: .birthdays)]))
        #expect(CalendarAccountHint.needsGoogleAccount(plain))
        #expect(!CalendarAccountHint.needsGoogleAccount(CalendarCatalog.choices(from: everyAccount)))
        #expect(!CalendarAccountHint.needsGoogleAccount([]), "no read yet is not an empty Mac")
    }

    @Test func theSettingsLinkHasAFallback() {
        #expect(CalendarAccountHint.settingsURLs.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.internetaccounts"])
    }

    // MARK: Permission

    @Test func everyAuthorizationStatusMapsToACardState() {
        #expect(CalendarAccessState.map(.fullAccess) == .granted)
        #expect(CalendarAccessState.map(.notDetermined) == .notAsked)
        #expect(CalendarAccessState.map(.writeOnly) == .notAsked)
        #expect(CalendarAccessState.map(.denied) == .denied)
        #expect(CalendarAccessState.map(.restricted) == .denied)
    }

    // MARK: Refresh without polling

    @Test func theStoreChangedNotificationRefreshesAndStopRemovesIt() {
        let center = NotificationCenter(), workspace = NotificationCenter()
        var refreshes = 0
        let observer = CalendarRefreshObserver(center: center, workspaceCenter: workspace, queue: nil) { refreshes += 1 }
        observer.start()
        center.post(name: .EKEventStoreChanged, object: nil)
        #expect(refreshes == 1)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(refreshes == 2, "a wake refreshes too")
        observer.start()
        center.post(name: .EKEventStoreChanged, object: nil)
        #expect(refreshes == 3, "starting twice does not double the observers")
        observer.stop()
        center.post(name: .EKEventStoreChanged, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(refreshes == 3)
    }

    @Test func theSafetyNetIsSlowAndNothingPollsFast() throws {
        #expect(CalendarRefreshPolicy.safetyInterval >= 900)
        #expect(CalendarRefreshPolicy.storeNotifications.contains(.EKEventStoreChanged))
        #expect(CalendarRefreshPolicy.workspaceNotifications == [NSWorkspace.didWakeNotification])
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["Sources/PortKit/Services/Notch/NotchCalendarService.swift", "Sources/PortKit/Bridge/CalendarRefresh.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            #expect(!source.contains("scheduledTimer"), "\(file)")
            #expect(!source.contains("repeats: true"), "\(file)")
        }
    }

    @Test func theCardsSpeakFrenchByDefaultAndFormatTheirLabels() {
        let fr = CalendarAccountStrings.strings(.fr), en = CalendarAccountStrings.strings(.enUS)
        #expect(fr.accessRequired == "Accès calendrier requis" && fr.join == "Rejoindre" && fr.selectAll == "Tout"
                && fr.selectNone == "Aucun")
        #expect(en.join == "Join")
        #expect(String(format: fr.joinLabel, "Point") == "Rejoindre la visioconférence : Point")
        #expect(String(format: fr.selectAllLabel, "Gmail").contains("Gmail"))
    }

    // MARK: Sources of the lane

    @Test func noCalendarLaneFileAsksForAccessOutsideTheClickPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["CalendarConference", "CalendarAccounts", "CalendarRefresh"] {
            let source = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/\(file).swift"), encoding: .utf8)
            for forbidden in ["requestFullAccess", "requestAccess(", "requestCalendar(", "NSWorkspace.shared.open"] {
                #expect(!source.contains(forbidden), "\(file): \(forbidden)")
            }
        }
        let view = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/UI/Notch/NotchCalendarView.swift"), encoding: .utf8)
        #expect(!view.contains("onAppear { permissions.requestCalendar"), "never prompt at launch")
    }
}
