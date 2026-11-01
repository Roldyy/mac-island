import Foundation
import Testing
@testable import PortKit

/// Patch 0010: the ported "never touch this app" checks recognise Mac Island's own identifiers, not only the
/// old app's.
@Suite struct OwnBundleProtectionTests {
    static let ownIDs = ["be.roldy.macisland", "be.roldy.macisland.fanhelper", "be.roldy.macisland.claudehook",
                         "be.roldy.macisland.dev"]

    @Test func cleanerNeverTreatsOurIdentifiersAsJunkOwners() {
        for id in Self.ownIDs { #expect(CleanerSupport.isProtectedBundleID(id), "\(id)") }
        // Team-prefixed group containers wrap the id the same way.
        #expect(CleanerSupport.isProtectedBundleID("U3TUL63HHK.be.roldy.macisland"))
        #expect(CleanerSupport.isProtectedBundleID("com.vorssaint.utils"))
        #expect(!CleanerSupport.isProtectedBundleID("be.roldy.otherapp"))
    }

    @Test func uninstallerRefusesOurOwnCopy() {
        for id in Self.ownIDs { #expect(UninstallerSupport.verifiedBundleID(id) == nil, "\(id)") }
        #expect(UninstallerSupport.verifiedBundleID("com.vorssaint.utils") == nil)
        #expect(UninstallerSupport.verifiedBundleID("com.example.someapp") == "com.example.someapp")
    }

    @Test func cleanerHidesOurCacheFolders() {
        #expect(CleanerPolicy.isExcludedCacheEntry("be.roldy.macisland"))
        #expect(CleanerPolicy.isExcludedCacheEntry("be.roldy.macisland.fanhelper"))
        #expect(CleanerPolicy.isExcludedCacheEntry("com.vorssaint.utils"))
    }

    @Test func dockClickNeverTargetsUs() {
        for id in Self.ownIDs { #expect(DockClickSupport.isOwnBundleIdentifier(id), "\(id)") }
        #expect(DockClickSupport.isOwnBundleIdentifier("com.vorssaint.utils"))
        #expect(!DockClickSupport.isOwnBundleIdentifier("com.apple.finder"))
        #expect(!DockClickSupport.isOwnBundleIdentifier(nil))
    }
}
