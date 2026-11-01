import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// The end-to-end proof of the foundation: the URL cleaner, bound through `PortFeatureBinding`, appears in the
/// Features hub with a real page, starts and stops with the registry, and obeys the kill switch. The service is the
/// real ported one (it needs no permission and reads only the pasteboard's change count); the registry, the defaults
/// and the permission state are fakes or temporary.
@MainActor
@Suite(.serialized) struct PortFoundationExampleTests {
    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
    }

    func rig(_ defaults: UserDefaults) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        FoundationExampleLane.bind(into: binding)
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: defaults,
                                       crashMarker: marker, withdraw: { _ in })
        binding.connectAvailability()
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry)
    }

    @Test func theFoundationLaneBindsTheUrlCleanerFirst() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        FoundationExampleLane.bind(into: binding)
        #expect(binding.descriptors.map(\.id) == ["urlCleaner"], "the foundation lane binds the cleaner and nothing else")
        #expect(binding.pages.map(\.pageID) == ["urlcleaner"])
        #expect(binding.pages.first?.featureID == "urlCleaner")
        #expect(SettingsPageCatalog.page("urlcleaner") != nil, "the page id is one of the catalog's")
    }

    @Test func itNeedsNoPermissionAndIsSafe() {
        let d = PortFeatureBinding.descriptor(for: .urlCleaner)
        #expect(d.permissions.isEmpty && d.risk == .safe && !d.enabledByDefault)
        #expect(MonitoredPermission.used(by: d).isEmpty)
        #expect(AppFeature.urlCleaner.permissions.isEmpty)
    }

    @Test func itStartsAndStopsWithTheRegistryAndObeysTheKillSwitch() {
        PortHostFixture.isolated { defaults in
            let service = URLCleanerService.shared
            service.stop()
            defer { service.stop() }
            defaults.set(true, forKey: DefaultsKey.urlCleanerEnabled)  // the page's own toggle
            let r = rig(defaults)

            #expect(r.registry.state(for: "urlCleaner") == .off, "off until the switch or a migrated value says on")
            #expect(!service.isRunning)

            r.registry.switches["urlCleaner"] = true
            #expect(service.isRunning, "start = the upstream service start")

            r.registry.switches["urlCleaner"] = false
            #expect(!service.isRunning, "stop = the upstream service stop")

            r.registry.switches["urlCleaner"] = true
            #expect(service.isRunning)
            r.registry.killSwitch = true
            #expect(!service.isRunning, "the kill switch calls the bound stop")

            // A toggle on the ported page re-syncs the service: with the registry holding it down, it stays down.
            service.syncWithPreferences()
            #expect(!service.isRunning, "isAvailable follows the registry, not a stored key")

            r.registry.killSwitch = false
            #expect(service.isRunning)
        }
    }

    @Test func theServiceStaysDownWhenItsOwnToggleIsOff() {
        PortHostFixture.isolated { defaults in
            let service = URLCleanerService.shared
            service.stop()
            defer { service.stop() }
            let r = rig(defaults)
            r.registry.switches["urlCleaner"] = true
            #expect(!service.isRunning, "the registry allows it, the page toggle (default off) does not")
            defaults.set(true, forKey: DefaultsKey.urlCleanerEnabled)
            service.syncWithPreferences()
            #expect(service.isRunning)
        }
    }

    @Test func theHubListsItUnderFilesWithItsFrenchSummary() {
        PortHostFixture.isolated { defaults in
            let r = rig(defaults)
            let sections = FeatureHub.sections(r.registry.descriptors, query: "")
            let files = sections.first { $0.category == .files }
            #expect(files?.features.contains { $0.id == "urlCleaner" } == true)
            #expect(FeatureHub.sections(r.registry.descriptors, query: "lien").flatMap(\.features).map(\.id).contains("urlCleaner"))
        }
    }

    @Test func theSettingsPageHasARealBodyWithItsSwitchCard() {
        PortHostFixture.isolated { defaults in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(defaults)
            let page = SettingsPageCatalog.page("urlcleaner")!
            #expect(page.isComingSoon, "the catalog row alone is still a stub")
            for ported in r.binding.pages {
                SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                            openPermission: { _ in }, ported.body)
            }
            #expect(!page.isComingSoon)
            #expect(SettingsPageBodies.hasBody(for: "urlcleaner"))

            let host = NSHostingView(rootView: SettingsPageScaffold(page: page) { EmptyView() })
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 900)
            host.layoutSubtreeIfNeeded()
            // Title, summary, the feature card and the ported form: far more than a title's worth of height.
            #expect(host.fittingSize.height > 250, "rendered \(host.fittingSize)")
        }
    }
}
