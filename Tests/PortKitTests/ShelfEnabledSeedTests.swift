import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Our old shelf read a missing `shelfEnabled` as ON; the ported service reads `bool(forKey:)` (OFF when absent).
@MainActor
@Suite struct ShelfEnabledSeedTests {
    @Test func anAbsentKeyBecomesOnOnce() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        #expect(bench.defaults.object(forKey: DefaultsKey.shelfEnabled) == nil)
        ShelfEnabledSeed.run(in: bench.defaults)
        #expect(bench.defaults.bool(forKey: DefaultsKey.shelfEnabled))
        #expect(bench.defaults.bool(forKey: ShelfEnabledSeed.seededKey))
    }

    @Test func aStoredChoiceIsNeverTouched() {
        let off = TestDefaults.make()
        defer { off.cleanup() }
        off.defaults.set(false, forKey: DefaultsKey.shelfEnabled)
        ShelfEnabledSeed.run(in: off.defaults)
        #expect(off.defaults.object(forKey: DefaultsKey.shelfEnabled) as? Bool == false, "a person who switched it off keeps it off")
    }

    @Test func switchingItOffLaterIsNotUndone() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        ShelfEnabledSeed.run(in: bench.defaults)
        bench.defaults.set(false, forKey: DefaultsKey.shelfEnabled)
        ShelfEnabledSeed.run(in: bench.defaults)
        #expect(bench.defaults.bool(forKey: DefaultsKey.shelfEnabled) == false)
    }

    @Test func prepareStoreFromAnEmptyDomainTurnsTheShelfOn() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        ShelfLane.prepareStore(defaults: bench.defaults, directory: nil)
        #expect(bench.defaults.bool(forKey: DefaultsKey.shelfEnabled), "the strip reads this key: absent meant 'désactivée'")
    }
}
