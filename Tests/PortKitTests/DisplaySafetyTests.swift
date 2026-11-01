import Foundation
import Testing
@testable import PortKit

/// Lane W2A: the pure parts of the display safety net. Fakes only: no display, gamma table or DDC channel is read or
/// written here. The DDC verdict table, the gate on DDC writes, the floor under a software dim, the launch journal
/// of a dim, brightness clamping and the brightness keys and shortcuts.
@MainActor
@Suite(.serialized) struct DisplaySafetyTests {
    // MARK: DDC probe results

    @Test func eachProbeOutcomeMapsToAVerdictAFrenchReasonAndTheRightChoices() {
        let key = "1:2:3|IOService:/display"
        let replied = DDCReports.report(.probed(.replied, pathKey: key, trusted: false))
        #expect(replied.verdict == .supported && replied.label == "pris en charge")
        #expect(replied.reason.contains("VCP 0x10") && !replied.canTrust && !replied.trusted)

        let silent = DDCReports.report(.probed(.writeOnly, pathKey: key, trusted: false))
        #expect(silent.verdict == .notSupported && silent.label == "non pris en charge")
        #expect(silent.canTrust, "a monitor that accepts commands can be used anyway, on request")
        #expect(silent.reason.contains("DDC/CI") && silent.reason.contains("logiciel"))

        let chosen = DDCReports.report(.probed(.writeOnly, pathKey: key, trusted: true))
        #expect(chosen.verdict == .supported && chosen.trusted && !chosen.canTrust)

        let dead = DDCReports.report(.probed(.dead, pathKey: key, trusted: false))
        #expect(dead.verdict == .notSupported && !dead.canTrust && dead.reason.contains("refuse"))
        let deadEvenIfTrusted = DDCReports.report(.probed(.dead, pathKey: key, trusted: true))
        #expect(deadEvenIfTrusted.verdict == .notSupported && !deadEvenIfTrusted.trusted)
    }

    @Test func aWriteOnlyMonitorWithNoPathKeyCannotBeTrusted() {
        #expect(!DDCReports.report(.probed(.writeOnly, pathKey: nil, trusted: false)).canTrust,
                "the choice is kept under the path key: without one it cannot be remembered")
    }

    @Test func theOtherSituationsAreReportedWithAReason() {
        let system = DDCReports.report(.systemRoute)
        #expect(system.verdict == .notApplicable && system.label == "réglage système")
        for situation in [DDCReports.Situation.symbolsMissing, .noChannel, .forcedSoftware(pathKey: "k")] {
            let report = DDCReports.report(situation)
            #expect(report.verdict == .notSupported, "\(situation)")
            #expect(!report.reason.isEmpty && !report.reason.contains("DDC is"), "French: \(report.reason)")
        }
        #expect(DDCReports.report(.forcedSoftware(pathKey: "k")).pathKey == "k")
    }

    @Test func aDDCValueIsOnlyEverWrittenAfterARepliedReadOrARequestedTrust() {
        #expect(DDCReports.allowsDDC(outcome: .replied, trusted: false))
        #expect(DDCReports.allowsDDC(outcome: .replied, trusted: true))
        #expect(!DDCReports.allowsDDC(outcome: .writeOnly, trusted: false))
        #expect(DDCReports.allowsDDC(outcome: .writeOnly, trusted: true))
        #expect(!DDCReports.allowsDDC(outcome: .dead, trusted: false))
        #expect(!DDCReports.allowsDDC(outcome: .dead, trusted: true), "a rejected channel is never written to")
    }

    @Test func theKeyboardLightProbeFailsClosedInFrench() {
        let yes = KeyboardLightProbe.summary(supported: true)
        let no = KeyboardLightProbe.summary(supported: false)
        #expect(yes.label == "pris en charge" && no.label == "non pris en charge")
        #expect(no.reason.contains("Rien n’est modifié"))
    }

    // MARK: The floor under a software dim

    @Test func aSoftwareDimNeverReachesBlack() {
        let floor = BrightnessSupport.softwareDimFloor
        #expect(floor > 0 && floor <= 0.1)
        #expect(BrightnessSupport.safeSoftwareDimLevel(0) == floor)
        #expect(BrightnessSupport.safeSoftwareDimLevel(-3) == floor)
        #expect(BrightnessSupport.safeSoftwareDimLevel(0.01) == floor)
        #expect(BrightnessSupport.safeSoftwareDimLevel(0.5) == 0.5)
        #expect(BrightnessSupport.softwareDimFactor(for: BrightnessSupport.safeSoftwareDimLevel(0)) > 0,
                "the factor written to the gamma table is never zero")
    }

    @Test func fullBrightnessAndNonsenseAreARestoreNotADim() {
        #expect(BrightnessSupport.safeSoftwareDimLevel(1) == 1)
        #expect(BrightnessSupport.safeSoftwareDimLevel(0.999) == 1)
        #expect(BrightnessSupport.safeSoftwareDimLevel(1.7) == 1)
        #expect(BrightnessSupport.safeSoftwareDimLevel(.nan) == 1)
        #expect(BrightnessSupport.safeSoftwareDimLevel(.infinity) == 1)
    }

    @Test func theUpstreamFactorContractIsUntouched() {
        // The ported FeatureCatalog checks pin these; the floor lives one level above.
        #expect(BrightnessSupport.softwareDimFactor(for: 0) == 0 && BrightnessSupport.softwareDimFactor(for: 1) == 1)
        #expect(BrightnessSupport.softwareDimFactor(for: -0.3) == 0 && BrightnessSupport.softwareDimFactor(for: 1.4) == 1)
    }

    // MARK: Journal and launch recovery (fake backend)

    @Test func aMarkedRunRestoresOnceAndClearsTheNote() {
        PortHostFixture.isolated { defaults in
            DisplayGammaJournal.write(dimmed: true, defaults: defaults)
            #expect(DisplayGammaJournal.isMarked(in: defaults))
            var restored = 0
            let acted = DisplayGammaJournal.recoverAtLaunch(defaults: defaults, restore: { restored += 1 })
            #expect(acted && restored == 1)
            #expect(!DisplayGammaJournal.isMarked(in: defaults), "cleared: the next launch does nothing")
            #expect(!DisplayGammaJournal.recoverAtLaunch(defaults: defaults, restore: { restored += 1 }))
            #expect(restored == 1)
        }
    }

    @Test func noNoteMeansNothingIsTouched() {
        PortHostFixture.isolated { defaults in
            var restored = 0
            #expect(!DisplayGammaJournal.recoverAtLaunch(defaults: defaults, restore: { restored += 1 }))
            #expect(restored == 0, "another tool's colour tint is never reset by a clean launch")
        }
    }

    @Test @MainActor func noteWritesOnTheMainThreadAndRepeatsAreFree() {
        PortHostFixture.isolated { defaults in
            DisplayGammaJournal.resetMemory()
            DisplayGammaJournal.note(dimmed: true)
            #expect(DisplayGammaJournal.isMarked(in: defaults))
            defaults.removeObject(forKey: DisplayGammaJournal.key)
            DisplayGammaJournal.note(dimmed: true)
            #expect(!DisplayGammaJournal.isMarked(in: defaults), "the same answer twice is not written twice")
            DisplayGammaJournal.note(dimmed: false)
            #expect(!DisplayGammaJournal.isMarked(in: defaults))
            DisplayGammaJournal.resetMemory()
        }
    }

    @Test @MainActor func launchRecoveryEntersEachStepOnlyForItsMarker() {
        PortHostFixture.isolated { defaults in
            var colorSync = 0
            var switchedOff = 0
            DisplayBrightnessLane.recoverAtLaunch(defaults: defaults, restoreColorSync: { colorSync += 1 },
                                                  restoreSwitchedOff: { switchedOff += 1 })
            #expect(colorSync == 0 && switchedOff == 0, "a clean Mac: nothing is entered, no service is built")

            DisplayGammaJournal.write(dimmed: true, defaults: defaults)
            defaults.set([724_044_033], forKey: DefaultsKey.displaysSwitchedOff)
            DisplayBrightnessLane.recoverAtLaunch(defaults: defaults, restoreColorSync: { colorSync += 1 },
                                                  restoreSwitchedOff: { switchedOff += 1 })
            #expect(colorSync == 1 && switchedOff == 1)
            #expect(!DisplayGammaJournal.isMarked(in: defaults))

            defaults.set([Int](), forKey: DefaultsKey.displaysSwitchedOff)
            DisplayBrightnessLane.recoverAtLaunch(defaults: defaults, restoreColorSync: { colorSync += 1 },
                                                  restoreSwitchedOff: { switchedOff += 1 })
            #expect(colorSync == 1 && switchedOff == 1, "an empty list is not a marker")
        }
    }

    @Test func theJournalKeyIsOurOwnAndNotAVorssaintKey() {
        #expect(DisplayGammaJournal.key == "macIslandDisplayGammaDimActive")
        #expect(!DisplayGammaJournal.key.hasPrefix("vorss"))
        #expect(DDCReports.trustedPathsKey == "brightnessDDCTrustedPaths")
    }

    // MARK: Brightness clamping

    @Test func steppedBrightnessAndDeviceValuesStayInRange() {
        #expect(BrightnessSupport.steppedBrightness(0.97, delta: 0.0625) == 1)
        #expect(BrightnessSupport.steppedBrightness(0.02, delta: -0.0625) == 0)
        #expect(BrightnessSupport.steppedBrightness(0.5, delta: 0.0625) == 0.5625)
        #expect(BrightnessSupport.deviceValue(for: 3, maximum: 100) == 100)
        #expect(BrightnessSupport.deviceValue(for: -1, maximum: 100) == 0)
        #expect(BrightnessSupport.deviceValue(for: 0.5, maximum: 0) == 50, "no reported range means the 0-100 scale")
        #expect(BrightnessSupport.easedBrightnessChange(to: .nan, from: 0.5) == nil)
        #expect(BrightnessSupport.easedBrightnessChange(to: 2, from: 0.5) == 0.5, "the target is clamped before the change")
    }

    // MARK: Brightness keys and shortcuts

    @Test func mediaKeysAreParsedAndEverythingElseIsLeftToTheSystem() {
        func data1(code: Int, state: Int, repeated: Bool = false) -> Int { (code << 16) | (state << 8) | (repeated ? 1 : 0) }
        let up = BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(code: 2, state: 10))
        let down = BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(code: 3, state: 10, repeated: true))
        #expect(up == .init(delta: BrightnessSupport.brightnessKeyStep, isKeyDown: true, isRepeat: false))
        #expect(down == .init(delta: -BrightnessSupport.brightnessKeyStep, isKeyDown: true, isRepeat: true))
        #expect(BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(code: 2, state: 11))?.isKeyDown == false)
        #expect(BrightnessSupport.brightnessKeyEvent(subtype: 7, data1: data1(code: 2, state: 10)) == nil)
        #expect(BrightnessSupport.brightnessKeyEvent(subtype: 8, data1: data1(code: 0, state: 10)) == nil, "volume is not ours")
        #expect(BrightnessSupport.isKeyboardLightPress(subtype: 8, data1: data1(code: 21, state: 10)))
        #expect(!BrightnessSupport.isKeyboardLightPress(subtype: 8, data1: data1(code: 21, state: 11)), "key-up is left alone")
    }

    @Test func functionKeysAreOnlyBrightnessWhenUnmodifiedAndTheSystemStillMapsThem() {
        func event(_ code: Int, mods: Bool = false, adjusts: Bool = true) -> BrightnessSupport.BrightnessKeyEvent? {
            BrightnessSupport.brightnessFunctionKeyEvent(keyCode: code, isKeyDown: true, isRepeat: false,
                                                         hasModifiers: mods, functionKeysAdjustBrightness: adjusts)
        }
        #expect(event(BrightnessSupport.BrightnessKeyCode.increase)?.delta == BrightnessSupport.brightnessKeyStep)
        #expect(event(BrightnessSupport.BrightnessKeyCode.decrease)?.delta == -BrightnessSupport.brightnessKeyStep)
        #expect(event(BrightnessSupport.BrightnessKeyCode.functionIncrease) != nil)
        #expect(event(BrightnessSupport.BrightnessKeyCode.functionIncrease, adjusts: false) == nil)
        #expect(event(BrightnessSupport.BrightnessKeyCode.increase, mods: true) == nil)
        #expect(event(0) == nil)
        #expect(BrightnessSupport.isBrightnessKeyCode(144) && BrightnessSupport.isBrightnessKeyCode(107))
        #expect(!BrightnessSupport.isBrightnessKeyCode(53))
    }

    @Test func theKeyStepNeverMovesFurtherThanTheChosenFraction() {
        typealias Step = BrightnessSupport.KeyStep
        #expect(Step.sanitized(nil) == .standard && Step.sanitized("garbage") == .standard && Step.sanitized("half") == .half)
        #expect(Step.half.limited(0.0625) == 0.03125 && Step.quarter.limited(-0.0625) == -0.015625)
        #expect(Step.standard.limited(0.0625) == 0.0625 && Step.quarter.limited(0.001) == 0.001)
    }

    @Test func theBrightnessShortcutsParseAndHaveDistinctDefaults() {
        let roles: [GlobalShortcutRole] = [.displayBrightnessDecrease, .displayBrightnessIncrease,
                                           .keyboardBrightnessDecrease, .keyboardBrightnessIncrease]
        var seen = Set<String>()
        for role in roles {
            let stored = role.defaultShortcut.storageValue
            #expect(GlobalShortcut(storageValue: stored) == role.defaultShortcut, "\(role) round-trips")
            #expect(seen.insert(stored).inserted, "\(role): its own default")
        }
        #expect(roles.map(\.isKeyboardBrightness) == [false, false, true, true])
        #expect(GlobalShortcut(storageValue: "shift+command:27") == GlobalShortcutRole.displayBrightnessDecrease.defaultShortcut)
        #expect(GlobalShortcut(storageValue: "option+command:24") == GlobalShortcutRole.keyboardBrightnessIncrease.defaultShortcut)
        #expect(GlobalShortcut(storageValue: "27") == nil, "no modifier, no separator: not a shortcut")
        #expect(GlobalShortcut(storageValue: "shift+bogus:27") == nil && GlobalShortcut(storageValue: "27") == nil)
    }
}
