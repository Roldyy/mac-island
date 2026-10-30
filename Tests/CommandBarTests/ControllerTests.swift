import Foundation
import Testing
@testable import CommandBarFeature

@MainActor
private final class FakeRegistrar: HotkeyRegistering {
    var registered: [HotkeySpec] = []
    var unregisterCalls = 0
    var nextStatus: Int32 = 0
    var trigger: (@MainActor () -> Void)?
    func register(_ spec: HotkeySpec, onTrigger: @escaping @MainActor () -> Void) -> Int32 {
        registered.append(spec)
        trigger = onTrigger
        return nextStatus
    }
    func unregister() { unregisterCalls += 1 }
}

@MainActor
private final class FakePresenter: CommandBarPresenting {
    var isVisible = false
    var shows = 0, hides = 0
    func show() { isVisible = true; shows += 1 }
    func hide() { isVisible = false; hides += 1 }
}

@Suite final class ControllerTests {
    let bag = DefaultsBag()

    @MainActor private func make(defaults: UserDefaults? = nil)
        -> (CommandBarController, FakeRegistrar, FakePresenter, CommandBarSettings, HabitStore) {
        let reg = FakeRegistrar(), pres = FakePresenter()
        let settings = CommandBarSettings(defaults: defaults ?? bag.makeDefaults())
        let habits = HabitStore(directory: makeTempDir())
        return (CommandBarController(settings: settings, registrar: reg, presenter: pres, habits: habits),
                reg, pres, settings, habits)
    }

    @Test @MainActor func startIsIdempotentAndRegistersOnce() {
        let (c, reg, _, _, _) = make()
        c.start(); c.start(); c.start()
        #expect(reg.registered == [.default])
        #expect(c.status == .active("\u{2325}Space"))
    }

    @Test @MainActor func stopIsIdempotentAndHidesPanel() {
        let (c, reg, pres, _, _) = make()
        c.stop()                                   // never started: nothing to undo
        #expect(reg.unregisterCalls == 0)
        c.start()
        pres.show()
        c.stop(); c.stop()
        #expect(reg.unregisterCalls == 1)
        #expect(!pres.isVisible)
        #expect(c.status == .off)
        c.start()                                  // can restart
        #expect(reg.registered.count == 2)
    }

    @Test @MainActor func disabledSettingMeansNoRegistration() {
        let d = bag.makeDefaults()
        let (c, reg, _, s, _) = make(defaults: d)
        s.enabled = false
        c.start()
        #expect(reg.registered.isEmpty)
        #expect(c.status == .off)
    }

    @Test @MainActor func conflictIsReportedAndNotActive() {
        let (c, reg, _, _, _) = make()
        reg.nextStatus = -9878
        c.start()
        #expect(c.status == .conflict)
        #expect(c.status.message == "d\u{00E9}j\u{00E0} utilis\u{00E9}")
    }

    @Test @MainActor func hotkeyTriggerTogglesPanel() {
        let (c, reg, pres, _, _) = make()
        c.start()
        reg.trigger?()
        #expect(pres.isVisible && pres.shows == 1)
        reg.trigger?()
        #expect(!pres.isVisible && pres.hides == 1)
    }

    @Test @MainActor func applyHotkeyValidatesPersistsAndReRegisters() {
        let d = bag.makeDefaults()
        let (c, reg, _, _, _) = make(defaults: d)
        c.start()
        #expect(!c.applyHotkey("nonsense"))
        #expect(reg.registered.count == 1)
        #expect(c.applyHotkey("option+command:9"))
        #expect(reg.registered.last?.stored == "option+command:9")
        #expect(reg.unregisterCalls == 1)
        #expect(CommandBarSettings(defaults: d).hotkey.stored == "option+command:9")
    }

    @Test @MainActor func disablingHabitsClearsThem() {
        let (c, _, _, s, habits) = make()
        habits.record("app:/x")
        s.habitsEnabled = false
        c.applyHabits()
        #expect(habits.weight("app:/x", now: Date()) == 0)
        #expect(!FileManager.default.fileExists(atPath: habits.fileURL.path))
    }

    @Test @MainActor func clearHabitsKeepsTheSwitch() {
        let (c, _, _, s, habits) = make()
        habits.record("app:/x")
        c.clearHabits()
        #expect(habits.weight("app:/x", now: Date()) == 0)
        #expect(s.habitsEnabled)
    }

    @Test @MainActor func applyEnabledStartsAndStops() {
        let (c, reg, _, s, _) = make()
        c.start()
        s.enabled = false
        c.applyEnabled()
        #expect(c.status == .off)
        s.enabled = true
        c.applyEnabled()
        #expect(reg.registered.count == 2)
    }
}
