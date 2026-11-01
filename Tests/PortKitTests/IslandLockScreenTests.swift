import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Wave 8D: the lock-screen island's session and private Space, the scroll gestures, the mascot's binding. Fakes only: no
/// WindowServer call, no panel, no sound, no event monitor.
@MainActor
@Suite(.serialized) struct IslandLockScreenTests {
    // MARK: Fakes

    final class FakeService: LockScreenServing {
        var events: [String] = []
        func sync(_ session: NotchSessionState) { events.append("sync:\(session.locked ? "locked" : "open")") }
        func playSound(locking: Bool) { events.append(locking ? "sound:lock" : "sound:unlock") }
        func close() { events.append("close") }
    }

    final class FakeCalls: OverlaySpaceCalls {
        var log: [String] = []
        var onCreate: (() -> Void)?
        var createResult: UInt64 = 77
        var levelWorks = true
        func create() -> UInt64 { onCreate?(); log.append("create"); return createResult }
        func setLevel(space: UInt64, level: Int32) -> Bool { log.append("level:\(level)"); return levelWorks }
        func show(space: UInt64) { log.append("show") }
        func hide(space: UInt64) { log.append("hide") }
        func add(windows: [Int], space: UInt64) { log.append("add:\(windows)") }
        func remove(windows: [Int], space: UInt64) { log.append("remove:\(windows)") }
        func destroy(space: UInt64) { log.append("destroy") }
    }

    final class MemoryJournal: OverlaySpaceJournaling {
        var entry: OverlaySpaceJournalEntry?
        var canWrite = true
        var trace: [String] = []
        func begin(level: Int32) -> Bool {
            trace.append("begin")
            guard canWrite else { return false }
            entry = OverlaySpaceJournalEntry(level: level, space: nil, startedAt: Date(timeIntervalSince1970: 0))
            return true
        }
        func record(space: UInt64) { trace.append("record"); entry?.space = space }
        func clear() { trace.append("clear"); entry = nil }
        func read() -> OverlaySpaceJournalEntry? { entry }
    }

    struct SpaceRig {
        let provider: SkyLightOverlaySpaceProvider
        let calls: FakeCalls
        let journal: MemoryJournal
        let defaults: UserDefaults
        let cleanup: () -> Void
    }

    func spaceRig(resolves: @escaping (String) -> Bool = { _ in true }, hasCalls: Bool = true) -> SpaceRig {
        let calls = FakeCalls()
        let journal = MemoryJournal()
        let bench = TestDefaults.make()
        let provider = SkyLightOverlaySpaceProvider(calls: hasCalls ? calls : nil, resolves: resolves, journal: journal,
                                                    defaults: { bench.defaults })
        return SpaceRig(provider: provider, calls: calls, journal: journal, defaults: bench.defaults, cleanup: bench.cleanup)
    }

    // MARK: Session reducer

    @Test func theSessionEventsMoveTheStateAsUpstreamDid() {
        var s = NotchSessionState()
        IslandLockSession.apply(.saverStarted, to: &s)
        #expect(s.screenSaverRunning)
        IslandLockSession.apply(.locked, to: &s)
        #expect(s.locked && s.showsLockScreen == false, "a screen saver keeps the scene down")
        IslandLockSession.apply(.saverStopped, to: &s)
        #expect(s.showsLockScreen)
        IslandLockSession.apply(.screensSleep, to: &s)
        #expect(s.displaysSleeping && !s.showsLockScreen)
        IslandLockSession.apply(.screensWake, to: &s)
        IslandLockSession.apply(.resignActive, to: &s)
        #expect(!s.onConsole && !s.showsLockScreen, "another user's session")
        IslandLockSession.apply(.becomeActive, to: &s)
        IslandLockSession.apply(.willSleep, to: &s)
        IslandLockSession.apply(.saverStarted, to: &s)
        IslandLockSession.apply(.didWake, to: &s)
        #expect(!s.sleeping && !s.screenSaverRunning, "waking ends a screen saver")
        IslandLockSession.apply(.saverStarted, to: &s)
        IslandLockSession.apply(.unlocked, to: &s)
        #expect(!s.locked && !s.screenSaverRunning, "no screen saver outlasts an unlock")
    }

    @Test func everyUpstreamNotificationIsListenedTo() {
        let names = IslandLockSession.names.map(\.name.rawValue)
        #expect(names.contains("com.apple.screenIsLocked") && names.contains("com.apple.screenIsUnlocked"))
        #expect(names.contains("com.apple.screensaver.didstart") && names.contains("com.apple.screensaver.didstop"))
        #expect(IslandLockSession.names.count == 10)
    }

    // MARK: Controller

    func controller(_ service: FakeService, sounds: Bool = true,
                    capability: OverlaySpaceCapability = .available) -> IslandLockScreenController {
        IslandLockScreenController(service: service, capability: { capability }, playsSounds: { sounds })
    }

    @Test func lockingAtTheMacPlaysTheSoundThenShowsTheScene() {
        let service = FakeService()
        let c = controller(service)
        c.start(initial: NotchSessionState(), observe: false)
        service.events.removeAll()
        c.handle(.locked)
        #expect(service.events == ["sound:lock", "sync:locked"])
        c.handle(.unlocked)
        #expect(service.events.suffix(2) == ["sound:unlock", "sync:open"])
    }

    @Test func noSoundWhenTheSoundsAreOffOrNobodyIsThere() {
        let off = FakeService()
        let a = controller(off, sounds: false)
        a.start(initial: NotchSessionState(), observe: false)
        a.handle(.locked)
        #expect(!off.events.contains("sound:lock"))
        let lid = FakeService()
        let b = controller(lid)
        b.start(initial: NotchSessionState(), observe: false)
        b.handle(.willSleep)
        b.handle(.locked)
        #expect(!lid.events.contains("sound:lock"), "a closed lid is not someone hearing it")
        let saver = FakeService()
        let c = controller(saver)
        c.start(initial: NotchSessionState(), observe: false)
        c.handle(.saverStarted)
        c.handle(.locked)
        #expect(!saver.events.contains("sound:lock"))
    }

    @Test func anUnavailableSpaceNeverReachesTheServiceButTheSoundStillPlays() {
        let service = FakeService()
        let c = controller(service, capability: .unavailable(.symbolsMissing(["CGSSpaceCreate"])))
        c.start(initial: NotchSessionState(), observe: false)
        c.handle(.locked)
        #expect(service.events.contains("sound:lock"))
        #expect(!service.events.contains { $0.hasPrefix("sync") }, "unavailable rather than crash: the scene is never asked")
        #expect(service.events.contains("close"))
    }

    @Test func stopClosesTheSceneAndLaterEventsAreIgnored() {
        let service = FakeService()
        let c = controller(service)
        c.start(initial: NotchSessionState(), observe: false)
        c.start(initial: NotchSessionState(), observe: false)
        #expect(service.events == ["sync:open"], "a second start does nothing")
        c.stop()
        #expect(service.events.last == "close" && !c.isRunning)
        service.events.removeAll()
        c.handle(.locked)
        c.stop()
        #expect(service.events.isEmpty)
    }

    // MARK: The private Space: probe, journal first, kill switch

    @Test func theProbeNamesTheMissingSymbolsAndTheLevelOnlyWhenAskedFor() {
        #expect(OverlaySpaceSymbols.missing(needsLevel: true, resolves: { _ in true }).isEmpty)
        let missing = OverlaySpaceSymbols.missing(needsLevel: true, resolves: { $0 != "CGSSpaceSetAbsoluteLevel" })
        #expect(missing == ["CGSSpaceSetAbsoluteLevel"])
        #expect(OverlaySpaceSymbols.missing(needsLevel: false, resolves: { $0 != "CGSSpaceSetAbsoluteLevel" }).isEmpty)
        let r = spaceRig(resolves: { $0 != "CGSSpaceCreate" })
        defer { r.cleanup() }
        #expect(r.provider.capability(needsLevel: false) == .unavailable(.symbolsMissing(["CGSSpaceCreate"])))
        #expect(r.provider.makeSpace(absoluteLevel: 400) == nil)
        #expect(r.calls.log.isEmpty && r.journal.trace.isEmpty, "nothing written, nothing called")
        let none = spaceRig(hasCalls: false)
        defer { none.cleanup() }
        #expect(none.provider.makeSpace(absoluteLevel: 400) == nil, "no calls table: unavailable, not a crash")
    }

    @Test func theJournalIsWrittenAndReadBackBeforeTheFirstPrivateCall() {
        let r = spaceRig()
        defer { r.cleanup() }
        var journalAtCreate: OverlaySpaceJournalEntry?
        r.calls.onCreate = { journalAtCreate = r.journal.entry }
        let space = r.provider.makeSpace(absoluteLevel: 400)
        #expect(space != nil)
        #expect(journalAtCreate?.level == 400 && journalAtCreate?.space == nil, "armed before CGSSpaceCreate ran")
        #expect(r.journal.trace == ["begin", "record"])
        #expect(r.calls.log == ["create", "level:400", "show"])
        #expect(r.journal.entry?.space == 77, "the id is recorded once it is known")
        space?.add(windowNumber: 5)
        space?.add(windowNumber: 5)
        space?.add(windowNumber: 0)
        space?.close()
        space?.close()
        #expect(r.calls.log == ["create", "level:400", "show", "add:[5]", "remove:[5]", "hide", "destroy"],
                "windows leave before the Space goes; closing twice does nothing")
        #expect(r.journal.entry == nil && r.journal.trace.last == "clear", "cleared only after the destroy")
    }

    @Test func noJournalMeansNoPrivateCall() {
        let r = spaceRig()
        defer { r.cleanup() }
        r.journal.canWrite = false
        #expect(r.provider.makeSpace(absoluteLevel: 400) == nil)
        #expect(r.calls.log.isEmpty)
    }

    @Test func aFailedLevelDestroysWhatWasMadeAndClearsTheJournal() {
        let r = spaceRig()
        defer { r.cleanup() }
        r.calls.levelWorks = false
        #expect(r.provider.makeSpace(absoluteLevel: 400) == nil)
        #expect(r.calls.log == ["create", "level:400", "destroy"])
        #expect(r.journal.entry == nil)
        let refused = spaceRig()
        defer { refused.cleanup() }
        refused.calls.createResult = 0
        #expect(refused.provider.makeSpace(absoluteLevel: 400) == nil)
        #expect(refused.journal.entry == nil && refused.calls.log == ["create"])
    }

    @Test func theDefaultLevelSpaceIsNotJournaledBecauseItIsNotTheLockScreen() {
        let r = spaceRig()
        defer { r.cleanup() }
        let space = r.provider.makeSpace(absoluteLevel: nil)
        #expect(space != nil && r.journal.trace.isEmpty)
        #expect(r.calls.log == ["create", "show"])
        space?.close()
        #expect(r.journal.trace.isEmpty)
    }

    @Test func theKillSwitchAndTheCrashLockKeepTheIslandDownUntilRetried() {
        let r = spaceRig()
        defer { r.cleanup() }
        r.defaults.set(true, forKey: OverlaySpaceGuard.killKey)
        #expect(r.provider.capability(needsLevel: true) == .unavailable(.killSwitch))
        #expect(r.provider.makeSpace(absoluteLevel: 400) == nil && r.calls.log.isEmpty && r.journal.trace.isEmpty)
        r.defaults.set(true, forKey: OverlaySpaceGuard.crashedKey)
        #expect(r.provider.capability(needsLevel: true) == .unavailable(.crashed), "the crash lock wins the explanation")
        OverlaySpaceGuard.reset(defaults: r.defaults)
        #expect(r.provider.capability(needsLevel: true) == .available)
        #expect(r.provider.makeSpace(absoluteLevel: 400) != nil)
    }

    @Test func aJournalLeftByADeadRunTripsTheCrashLockAndDestroysNothing() {
        let r = spaceRig()
        defer { r.cleanup() }
        let calls = r.calls
        #expect(OverlaySpaceGuard.recoverAtLaunch(journal: r.journal, defaults: r.defaults) == false, "no journal: no write")
        #expect(r.defaults.object(forKey: OverlaySpaceGuard.crashedKey) == nil)
        _ = r.journal.begin(level: 400)
        r.journal.record(space: 9)
        #expect(OverlaySpaceGuard.recoverAtLaunch(journal: r.journal, defaults: r.defaults))
        #expect(r.defaults.bool(forKey: OverlaySpaceGuard.crashedKey))
        #expect(r.journal.entry == nil, "the journal is consumed")
        #expect(calls.log.isEmpty, "a stored id could belong to somebody else by now: nothing is destroyed")
        #expect(r.provider.capability(needsLevel: true) == .unavailable(.crashed))
    }

    @Test func theFileJournalRoundTripsAndFailsClosedWithoutAFolder() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = FileOverlaySpaceJournal(url: dir.appendingPathComponent("overlay-space.json"),
                                           now: { Date(timeIntervalSince1970: 100) })
        #expect(file.read() == nil)
        #expect(file.begin(level: 400))
        #expect(file.read() == OverlaySpaceJournalEntry(level: 400, space: nil, startedAt: Date(timeIntervalSince1970: 100)))
        file.record(space: 12)
        #expect(file.read()?.space == 12)
        file.clear()
        #expect(file.read() == nil)
        #expect(FileOverlaySpaceJournal(url: nil).begin(level: 400) == false, "no container: no private call")
    }

    @Test func theSettingsViewSpeaksFrenchForEveryState() {
        let states: [OverlaySpaceCapability] = [.available, .unavailable(.crashed), .unavailable(.killSwitch),
                                                .unavailable(.symbolsMissing([])), .unavailable(.symbolsMissing(["a", "b"]))]
        let texts = states.map(IslandLockScreenSettingsView.statusText)
        #expect(Set(texts).count == texts.count)
        #expect(texts.allSatisfy { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("bient") })
    }

    // MARK: Gestures

    let frame = CGRect(x: 0, y: 0, width: 300, height: 40)
    func sample(x: Double = 0, y: Double = 0, t: TimeInterval, began: Bool = false, at point: CGPoint = CGPoint(x: 10, y: 10),
                plain: Bool = true) -> IslandScrollSample {
        IslandScrollSample(deltaX: x, deltaY: y, precise: true, inverted: true, timestamp: t, began: began, ended: false,
                           momentum: false, hasPhase: true, location: point, plainModifiers: plain)
    }

    func context(expanded: Bool = false, music: Bool = false, header: Bool = false) -> IslandGestureContext {
        IslandGestureContext(frame: frame, expanded: expanded, overHeader: header, musicSurface: music)
    }

    @Test func aDownwardSwipeOpensAnUpwardOneClosesAndSidewaysSkipsOnlyOnMusic() {
        var engine = IslandGestureEngine()
        #expect(engine.handle(sample(y: 10, t: 1, began: true), context: context()) == nil)
        #expect(engine.handle(sample(y: 10, t: 1.01), context: context()) == .open)
        var closing = IslandGestureEngine()
        #expect(closing.handle(sample(y: -10, t: 2, began: true), context: context(expanded: true, header: true)) == nil)
        #expect(closing.handle(sample(y: -10, t: 2.01), context: context(expanded: true, header: true)) == .close)
        var next = IslandGestureEngine()
        #expect(next.handle(sample(x: -25, t: 3, began: true), context: context(music: true)) == nil)
        #expect(next.handle(sample(x: -25, t: 3.01), context: context(music: true)) == .nextTrack)
        var plain = IslandGestureEngine()
        _ = plain.handle(sample(x: -25, t: 4, began: true), context: context())
        #expect(plain.handle(sample(x: -25, t: 4.01), context: context()) == nil, "no music surface: no track gesture")
    }

    @Test func aPointerOutsideTheIslandOrAModifierOrNoContextDoesNothing() {
        var engine = IslandGestureEngine()
        _ = engine.handle(sample(y: 10, t: 1, began: true), context: context())
        #expect(engine.handle(sample(y: 10, t: 1.01, at: CGPoint(x: 900, y: 10)), context: context()) == nil)
        #expect(engine.handle(sample(y: 30, t: 1.02, plain: false), context: context()) == nil)
        #expect(engine.handle(sample(y: 30, t: 1.03), context: nil) == nil)
    }

    @Test func theMonitorNeedsBothHostHooksAndNeverStartsOnItsOwn() {
        let monitor = IslandGestureMonitor()
        #expect(!monitor.isRunning)
        var performed: [NotchGestureSupport.Action] = []
        IslandGestures.context = nil
        IslandGestures.perform = nil
        defer { IslandGestures.context = nil; IslandGestures.perform = nil }
        monitor.receive(sample(y: 10, t: 1, began: true))
        monitor.receive(sample(y: 10, t: 1.01))
        #expect(performed.isEmpty)
        IslandGestures.context = { IslandGestureContext(frame: CGRect(x: 0, y: 0, width: 300, height: 40), expanded: false,
                                                        overHeader: false, musicSurface: false) }
        IslandGestures.perform = { performed.append($0) }
        monitor.receive(sample(y: 10, t: 2, began: true))
        monitor.receive(sample(y: 10, t: 2.01))
        #expect(performed == [.open])
    }

    // MARK: Binding

    final class Log { var events: [String] = [] }

    func runtime(_ log: Log) -> IslandLockScreenLane.Runtime {
        IslandLockScreenLane.Runtime(
            startLock: { log.events.append("lock.start") }, stopLock: { log.events.append("lock.stop") },
            startGestures: { log.events.append("gest.start") }, stopGestures: { log.events.append("gest.stop") },
            startMascot: { log.events.append("mascot.start") }, stopMascot: { log.events.append("mascot.stop") })
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig() -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        IslandLockScreenLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    @Test func threeNewFeaturesAllOffAndTheLockScreenOneIsOurOwnDescriptor() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["lockscreen", "notchGestures", "notchMascot"])
        let lock = r.registry.descriptor("lockscreen")
        #expect(lock?.title == "Île sur l’écran verrouillé" && lock?.category == .island)
        #expect(lock?.risk == .touchesSystem && lock?.enabledByDefault == false)
        #expect(r.binding.descriptors.allSatisfy { !$0.enabledByDefault && !$0.title.isEmpty && !$0.summary.isEmpty })
        #expect(r.log.events.isEmpty)
        #expect(r.registry.state(for: "lockscreen") == .off)
    }

    @Test func eachFeatureStartsOnItsSwitchStopsOnOffAndTheKillSwitchStopsAll() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["lockscreen"] = true
        r.registry.switches["notchGestures"] = true
        r.registry.switches["notchMascot"] = true
        #expect(r.log.events == ["lock.start", "gest.start", "mascot.start"])
        r.registry.killSwitch = true
        #expect(Set(r.log.events.suffix(3)) == ["lock.stop", "gest.stop", "mascot.stop"])
        #expect(r.binding.availability("lockscreen") == false)
        r.registry.killSwitch = false
        #expect(r.log.events.filter { $0.hasSuffix(".start") }.count == 6)
        r.registry.safeMode = true
        #expect(r.binding.availability("lockscreen") == false, "safe mode stops the island features too")
    }

    @Test func aCustomDescriptorCannotShadowAnUpstreamFeatureOrBeBoundTwice() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let upstream = FeatureDescriptor(id: "notchTimer", title: "t", summary: "s", systemImage: "x", category: .island)
        #expect(binding.bind(custom: upstream, start: {}, stop: {}) == false, "an AppFeature's id goes through bind()")
        #expect(binding.bind(custom: IslandLockScreenLane.descriptor, start: {}, stop: {}))
        #expect(binding.bind(custom: IslandLockScreenLane.descriptor, start: {}, stop: {}) == false)
        #expect(binding.availability("lockscreen") == false && binding.availability("nope") == nil)
    }

    @Test func theRecoveryReadsTheJournalOncePerLaunch() {
        let journal = MemoryJournal()
        _ = journal.begin(level: 400)
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        IslandLockScreenLane.recoverAtLaunch(journal: journal, defaults: bench.defaults)
        // The first call of the process may already have been used by another test binding the live lane; either way the
        // second call must not read the journal again.
        let after = journal.trace.count
        IslandLockScreenLane.recoverAtLaunch(journal: journal, defaults: bench.defaults)
        #expect(journal.trace.count == after)
    }

    // MARK: The gate and the sources of truth

    @Test func theLockScreenSupportAnswersYesOnlyWhileTheLaneHostsAndTheKeyIsOn() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: DefaultsKey.notchLockScreen)
        bench.defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        #expect(NotchLockScreenSupport.isEnabled(in: bench.defaults) == false)
        let host = IslandActivityHost.shared
        host.acquire(IslandLockScreenLane.lockScreenID)
        let hosted = NotchLockScreenSupport.isEnabled(in: bench.defaults) && NotchLockScreenSupport.playsSounds(in: bench.defaults)
        host.release(IslandLockScreenLane.lockScreenID)
        #expect(hosted)
        bench.defaults.set(false, forKey: DefaultsKey.notchLockScreen)
        host.acquire(IslandLockScreenLane.lockScreenID)
        let keyOff = NotchLockScreenSupport.isEnabled(in: bench.defaults)
        host.release(IslandLockScreenLane.lockScreenID)
        #expect(keyOff == false, "the person's own tick still decides")
    }

    @Test func theMascotViewIsEmptyUntilTheFeatureHoldsItsHost() {
        #expect(IslandActivityHost.shared.holds("notchMascot") == false)
        #expect(IslandPortTabs.companion().title == "Compagnon")
    }

    // MARK: Source contracts (the patches are applied in the tree)

    func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func thePrivateSymbolsLiveInOneBridgeFileAndTheOverlaySpaceHasNone() throws {
        let overlay = try source("Sources/PortKit/Services/Notch/NotchOverlaySpace.swift")
        #expect(!overlay.contains("dlsym") && !overlay.contains("CGSSpace"), "the ported class only asks the provider")
        for file in ["IslandActivityHost", "IslandDownloads", "IslandLockScreen"] {
            let text = try source("Sources/PortKit/Bridge/\(file).swift")
            #expect(!text.contains("dlsym(") && !text.contains("dlopen(") && !text.contains("@_silgen_name"), "\(file)")
        }
        let privateFile = try source("Sources/PortKit/Bridge/PrivateOverlaySpace.swift")
        #expect(privateFile.contains("dlsym("))
        let allow = try source("scripts/port/private-api-allowlist.txt")
        #expect(allow.contains("Bridge/PrivateOverlaySpace.swift") && !allow.contains("NotchOverlaySpace.swift"))
    }

    @Test func everyPatchOfTheLaneMatchesTheTreeAndTouchesOnlyItsOwnFiles() throws {
        let names = ["1650-island-hosted-support-checks", "1651-island-downloads-and-file-tools-hosted",
                     "1652-island-camera-mirror-hosted", "1653-notch-overlay-space-provider-seam"]
        for name in names {
            let patch = try source("scripts/port/patches/\(name).patch")
            let added = patch.split(separator: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }
                .map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let paths = patch.split(separator: "\n").filter { $0.hasPrefix("+++ b/") }.map { String($0.dropFirst(6)) }
            #expect(!paths.isEmpty && !added.isEmpty, "\(name)")
            var text = ""
            for path in paths { text += try source("Sources/PortKit/\(path)") }
            for line in added { #expect(text.contains(line), "\(name): \(line)") }
        }
    }
}
