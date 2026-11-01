import Foundation
import Testing
@testable import PortKit

/// The behaviour patches of the Vorssaint port (scripts/port/patches), one test each.
@Suite struct PortFoundationTests {
    @Test func interfaceIsFrench() {
        #expect(L10n.shared.language == .fr)
        L10n.shared.language = .de  // the setter keeps its shape but never leaves French
        #expect(L10n.shared.language == .fr)
        #expect(Strings.localized(.de).statusIdleTooltip == Strings.localized(.fr).statusIdleTooltip)
    }

    @Test func privateFileStoreLivesUnderMacIslandData() throws {
        let url = try #require(PrivateFileStore.containerURL)
        #expect(url.path.hasSuffix("/Application Support/be.roldy.macisland/Data"))
    }

    @Test func availabilityKeyIsTheRegistrySwitch() {
        for feature in AppFeature.allCases {
            #expect(feature.availabilityKey == "shell.enabled." + feature.registryID)
        }
    }

    @Test func appInfoCarriesNoVorssaintLink() {
        #expect(AppInfo.name == "Mac Island")
        for url in [AppInfo.repositoryURL, AppInfo.coffeeURL] {
            #expect(!url.absoluteString.lowercased().contains("vorssaint"))
        }
        #expect(!AppInfo.copyright.contains("Vorssaint"))
    }

    @Test func frenchAndEnglishTablesNameNoVorssaint() {
        let fr = Strings.localized(.fr)
        let en = Strings.localized(.enUS)
        for table in [fr, en] {
            #expect(!table.menuAbout.contains("Vorssaint"))
            #expect(!table.menuQuit.contains("Vorssaint"))
            #expect(!table.settingsTitle.contains("Vorssaint"))
            #expect(!table.statusIdleTooltip.contains("Vorssaint"))
        }
    }

    @Test func sharingNeverReachesAServer() {
        #expect(!ScreenshotSharingSupport.productionEndpoint.absoluteString.contains("vorssaint"))
        #expect(!RecordingSharingSupport.productionEndpoint.absoluteString.contains("vorssaint"))
        #expect(!ScreenshotShareService.isAvailable)
        #expect(!RecordingShareService.isAvailable)
    }

    @Test func fanIdentityIsMacIslands() {
        #expect(FanControlIdentifiers.teamID == "U3TUL63HHK")
        #expect(FanControlIdentifiers.helperID == "be.roldy.macisland.fanhelper")
    }
}
