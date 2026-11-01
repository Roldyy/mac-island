import CoreGraphics
import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// A fake keyboard backlight: counts reads and writes so "a read never writes" is checkable.
@MainActor
private final class FakeBacklight: KeyboardBacklighting {
    var level: Double?
    var accepts = true
    private(set) var reads = 0
    private(set) var writes: [Double] = []

    init(level: Double?) { self.level = level }

    func currentLevel() -> Double? { reads += 1; return level }
    func setLevel(_ level: Double) -> Bool {
        writes.append(level)
        guard accepts else { return false }
        self.level = level
        return true
    }
}

/// The keyboard backlight slider of the island home: value mapping, hidden when the Mac has none, clamp, no writes
/// while reading, and the island-settings switch.
@MainActor
@Suite struct HomeKeyboardLightTests {
    private func model(_ defaults: UserDefaults, _ device: FakeBacklight?) -> HomeModel {
        HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { 0.4 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.7 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: .keyboardBacklight(device))
    }

    @Test func threeSlidersWhenTheMacHasABacklight() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let home = model(b.defaults, FakeBacklight(level: 0.5))
        #expect(home.availableLevels.map(\.title) == ["Volume", "Luminosité", "Rétroéclairage du clavier"])
        #expect(home.keyboardLight.value == 0.5)
        #expect(home.keyboardLight.systemImage == "light.max")
    }

    @Test func hiddenNotBrokenWhenThereIsNoBacklight() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        for device in [nil, FakeBacklight(level: nil)] {
            let home = model(b.defaults, device)
            #expect(home.availableLevels.map(\.title) == ["Volume", "Luminosité"])
            #expect(!home.keyboardLight.isAvailable)
            home.keyboardLight.set(0.8)  // no crash, no effect
            #expect(home.keyboardLight.value == 0)
            #expect(home.unavailableLevelsHelp?.contains("Pas de rétroéclairage") == true)
        }
    }

    @Test func aReadNeverWrites() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let device = FakeBacklight(level: 0.3)
        let home = model(b.defaults, device)
        for _ in 0..<5 { home.refreshLevels() }
        #expect(device.reads >= 5)
        #expect(device.writes.isEmpty)
    }

    @Test func setMapsToTheDeviceAndClampsToTheUnitRange() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let device = FakeBacklight(level: 0.2)
        let level = model(b.defaults, device).keyboardLight
        level.set(0.75)
        level.set(1.7)
        level.set(-3)
        level.set(.nan)
        #expect(device.writes == [0.75, 1, 0, 0])
        #expect(level.value == 0)
    }

    @Test func aRefusedWriteGoesBackToTheDeviceValue() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let device = FakeBacklight(level: 0.4)
        device.accepts = false
        let level = model(b.defaults, device).keyboardLight
        level.set(0.9)
        #expect(level.value == 0.4)
    }

    @Test func theSettingsSwitchHidesTheSliderAndIsStored() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let home = model(b.defaults, FakeBacklight(level: 0.5))
        #expect(home.showsKeyboardLight)
        home.showsKeyboardLight = false
        #expect(home.availableLevels.map(\.title) == ["Volume", "Luminosité"])
        #expect(b.defaults.object(forKey: "notchHomeKeyboardLightSlider") as? Bool == false)
        #expect(home.unavailableLevelsHelp == nil)
        #expect(!model(b.defaults, FakeBacklight(level: 0.5)).showsKeyboardLight)
        home.showsKeyboardLight = true
        #expect(home.availableLevels.count == 3)
    }

    @Test func gesturesMapToLevels() {
        #expect(HomeLevelInput.level(forDragX: 50, width: 100) == 0.5)
        #expect(HomeLevelInput.level(forDragX: -20, width: 100) == 0)
        #expect(HomeLevelInput.level(forDragX: 500, width: 100) == 1)
        #expect(HomeLevelInput.level(forDragX: 10, width: 0) == 1)  // zero width never divides by zero
        #expect(abs(HomeLevelInput.level(from: 0.5, scrollDelta: 5, precise: false) - 0.6) < 1e-9)
        #expect(abs(HomeLevelInput.level(from: 0.5, scrollDelta: -100, precise: true) - 0.1) < 1e-9)
        #expect(HomeLevelInput.level(from: 0.95, scrollDelta: 50, precise: false) == 1)
        #expect(HomeLevelInput.level(from: 0.5, scrollDelta: .infinity, precise: true) == 0.5)
        #expect(HomeLevelInput.level(from: 0.5, keySteps: 1) == 0.5625)
        #expect(HomeLevelInput.level(from: 0.02, keySteps: -1) == 0)
    }
}
