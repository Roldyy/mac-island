import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// The ported tap features and the permissions a grant must restart them for.
@Suite struct PortedPermissionTests {
    /// The ids the first feature wave binds (scroll, mouse, keyboard, shortcuts lanes).
    static let ids = [
        "scrollInverter", "scrollHorizontal", "smoothScroll", "linearScroll", "mouseAcceleration", "mouseNavigation",
        "mouseButtonShortcuts", "middleClick", "mouseClickDebounce", "focusFollowsMouse", "keyboardDebounce",
        "superKey", "quitWindowProtection", "textSnippets", "cleaningMode",
    ]

    static func descriptor(_ id: String, permissions: [FeaturePermission] = []) -> FeatureDescriptor {
        FeatureDescriptor(id: id, title: id, summary: id, systemImage: "gear", category: .input,
                          permissions: permissions, enabledByDefault: false)
    }

    @Test func theTableNamesExactlyTheFifteenWaveOneFeatures() {
        #expect(Set(MonitoredPermission.portedFeaturePermissions.keys) == Set(Self.ids))
        #expect(Self.ids.count == 15)
    }

    @Test func everyTapFeatureNeedsAccessibilityAndNoneNeedsInputMonitoring() {
        for id in Self.ids where id != "mouseAcceleration" {
            #expect(MonitoredPermission.portedFeaturePermissions[id] == [.accessibility], "\(id)")
        }
        #expect(MonitoredPermission.portedFeaturePermissions["mouseAcceleration"] == [],
                "a system setting, not a tap: nothing to grant")
        #expect(!MonitoredPermission.portedFeaturePermissions.values.contains { $0.contains(.inputMonitoring) },
                "every ported tap is an active tap: Accessibility, not Input Monitoring")
    }

    @Test func aDescriptorWithoutListedPermissionsStillRestartsOnAGrant() {
        #expect(MonitoredPermission.used(by: Self.descriptor("scrollInverter")) == [.accessibility])
        #expect(MonitoredPermission.used(by: Self.descriptor("mouseAcceleration")) == [])
        // Unknown ids are untouched, and the existing rows keep their answers.
        #expect(MonitoredPermission.used(by: Self.descriptor("somethingElse")) == [])
        let finder = ShellDescriptors.all.first { $0.id == "finder" }!
        #expect(MonitoredPermission.used(by: finder) == [.accessibility, .inputMonitoring])
    }

    @Test func noPortedIdCollidesWithAnExistingModule() {
        let existing = Set(ShellDescriptors.all.map(\.id))
        #expect(existing.isDisjoint(with: Self.ids))
    }
}
