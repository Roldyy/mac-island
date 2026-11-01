import Foundation
import IslandKit
import ShellKit
import Testing
@testable import PortKit

/// The one table between upstream feature ids and registry ids, and the availability key built from it.
@MainActor
@Suite struct PortFeatureIDsTests {
    @Test func theTableMapsUpstreamIdsToTheRegistryIdsOfOurModules() {
        #expect(PortFeatureIDs.registryID(forUpstream: "shelf") == "shelf")
        #expect(PortFeatureIDs.registryID(forUpstream: "keepAwake") == "keepawake")
        #expect(PortFeatureIDs.registryID(forUpstream: "clipboardHistory") == "clipboard")
        #expect(PortFeatureIDs.registryID(forUpstream: "commandBar") == "commandbar")
        #expect(PortFeatureIDs.registryID(forUpstream: "mixer") == "audio")
        #expect(PortFeatureIDs.registryID(forUpstream: "fanControl") == "fans")
    }

    @Test func aFeatureNewToMacIslandKeepsItsUpstreamId() {
        for feature in AppFeature.allCases where !PortFeatureIDs.isOwnedByExistingModule(feature.rawValue) {
            #expect(feature.registryID == feature.rawValue)
        }
    }

    @Test @MainActor func everyMappedIdIsARealRegistryIdAndOnlyOneUpstreamFeatureOwnsIt() {
        let registryIDs = Set(ShellDescriptors.all.map(\.id))
        let targets = Array(PortFeatureIDs.existing.values)
        #expect(Set(targets).count == targets.count, "two upstream features on one switch")
        for (upstream, target) in PortFeatureIDs.existing {
            #expect(AppFeature(rawValue: upstream) != nil, "\(upstream) is not an upstream feature")
            #expect(registryIDs.contains(target), "\(target) is not a registry id")
        }
    }

    @Test func theAvailabilityKeyIsTheRegistrysKey() {
        #expect(AppFeature.keepAwake.availabilityKey == "shell.enabled.keepawake")
        #expect(AppFeature.shelf.availabilityKey == "shell.enabled.shelf")
        #expect(AppFeature.scrollInverter.availabilityKey == "shell.enabled.scrollInverter")
        #expect(AppFeature.urlCleaner.availabilityKey == "shell.enabled.urlCleaner")
    }

    @Test func isAvailableAsksTheHostForTheHostsDefaultsOnly() {
        PortHostFixture.isolated { defaults in
            PortHost.availability = { $0 == "scrollInverter" ? false : ($0 == "urlCleaner" ? true : nil) }
            defaults.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
            #expect(AppFeature.scrollInverter.isAvailable(in: defaults) == false, "the host's verdict wins over a stored switch")
            #expect(AppFeature.urlCleaner.isAvailable(in: defaults) == true, "available through the host alone")
            #expect(AppFeature.smoothScroll.isAvailable(in: defaults) == false, "nobody bound it: the stored key, unset")
            defaults.set(true, forKey: AppFeature.smoothScroll.availabilityKey)
            #expect(AppFeature.smoothScroll.isAvailable(in: defaults) == true, "an unbound feature keeps reading its key")
            #expect(AppFeature.scrollInverter.isAvailable == false, "the property reads the host's defaults too")

            // A defaults object that is not the host's (a unit test of a pure helper) is read as it is.
            let other = UserDefaults(suiteName: "mis-test-" + UUID().uuidString)!
            other.set(true, forKey: AppFeature.scrollInverter.availabilityKey)
            #expect(AppFeature.scrollInverter.isAvailable(in: other))
        }
    }

    @Test func activeFeaturesFollowTheHostToo() {
        PortHostFixture.isolated { defaults in
            // The permission portal lists a feature only while it is available: through the host, a feature the
            // registry stopped (kill switch) leaves the list although its own switch is still on.
            defaults.set(true, forKey: DefaultsKey.scrollInverterEnabled)
            PortHost.availability = { $0 == "scrollInverter" ? true : nil }
            #expect(AppFeature.activeFeatures(using: .accessibility, defaults: defaults).contains(.scrollInverter))
            PortHost.availability = { $0 == "scrollInverter" ? false : nil }
            #expect(!AppFeature.activeFeatures(using: .accessibility, defaults: defaults).contains(.scrollInverter))
        }
    }
}
