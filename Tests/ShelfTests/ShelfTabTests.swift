import Foundation
import Testing
@testable import ShelfFeature

/// The island tab after lane W5B: the items are the ported shelf's, the model keeps only the segment and Downloads.
@Suite @MainActor struct ShelfTabTests {
    private func model(downloads: Bool = false) -> ShelfModel {
        let defaults = MemoryDefaults()
        defaults.set(downloads, forKey: "shelfDownloadsEnabled")  // never touch the real Downloads folder
        return ShelfModel(settings: ShelfSettings(defaults: defaults), downloadsDirectory: makeTempDir())
    }

    @Test func theTabKeepsItsIdentityTitleAndIcon() {
        let tab = ShelfFeature.tab()
        #expect(tab.id == "shelf" && tab.title == "Étagère" && tab.systemImage == "tray.and.arrow.down")
    }

    @Test func twoSegmentsShelfFirst() {
        #expect(ShelfSegment.allCases == [.shelf, .downloads])
        #expect(model().segment == .shelf)
    }

    @Test func downloadsOffStartsNoWatcherAndStartIsIdempotent() {
        let m = model(downloads: false)
        m.start()
        m.start()
        #expect(!m.downloadsEnabled)
        #expect(m.downloads.items.isEmpty)
        m.refreshDownloads()  // no monitor: a no-op, never a crash
    }

    @Test func revealOfAMissingPathDoesNothing() {
        // A path that does not exist is ignored (no Finder window, no crash).
        model().reveal(path: "/nonexistent/w5b/missing.txt")
        model().reveal(path: "")
    }

    @Test func dragProviderCarriesTheFileURLOnly() {
        let provider = model().dragProvider(path: "/tmp/w5b-x.txt")
        #expect(provider.hasItemConformingToTypeIdentifier("public.file-url"))
    }
}
