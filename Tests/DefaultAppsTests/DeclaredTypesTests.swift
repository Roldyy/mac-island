import Foundation
import Testing
@testable import DefaultAppsFeature

@Suite struct DeclaredTypesTests {
    let catalog = FakeCatalog()

    @Test func readsContentTypesAndExtensionsFromTheDocumentTypes() {
        let declared = DeclaredTypesExtractor.extract(from: Fixture.textEditPlist(), catalog: catalog)
        // LSItemContentTypes as written, extensions resolved through the catalog ("*" dropped), a "None" role skipped.
        #expect(declared.contentTypes == ["public.plain-text", "public.rtf", "public.folder", "net.daringfireball.markdown"])
    }

    @Test func extensionsWithADotOrUpperCaseAreResolvedAndUnknownOnesDropped() {
        let plist: [String: Any] = ["CFBundleDocumentTypes": [["CFBundleTypeExtensions": [".MD", "TXT", "zzz", "", "a/b"]]]]
        #expect(DeclaredTypesExtractor.extract(from: plist, catalog: catalog).contentTypes == ["net.daringfireball.markdown", "public.plain-text"])
    }

    @Test func aLoneStringInsteadOfAListIsAccepted() {
        let plist: [String: Any] = ["CFBundleDocumentTypes": [["LSItemContentTypes": "Public.JSON"]]]
        #expect(DeclaredTypesExtractor.extract(from: plist, catalog: catalog).contentTypes == ["public.json"])
    }

    @Test func aHandlerRankOfNoneIsSkipped() {
        let plist: [String: Any] = ["CFBundleDocumentTypes": [["LSHandlerRank": "None", "LSItemContentTypes": ["public.json"]]]]
        #expect(DeclaredTypesExtractor.extract(from: plist, catalog: catalog).contentTypes.isEmpty)
    }

    @Test func readsUrlSchemesLowerCasedAndValidated() {
        let declared = DeclaredTypesExtractor.extract(from: Fixture.sublimePlist(), catalog: catalog)
        #expect(declared.schemes == ["subl", "http"])
        let junk: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["1bad", "ok-scheme", "has space", "x://y", String(repeating: "a", count: 40)]]]]
        #expect(DeclaredTypesExtractor.extract(from: junk, catalog: catalog).schemes == ["ok-scheme"])
    }

    @Test func malformedPlistValuesNeverCrashAndGiveNothing() {
        let plist: [String: Any] = ["CFBundleDocumentTypes": "oops", "CFBundleURLTypes": [1, 2, ["CFBundleURLSchemes": 5]]]
        #expect(DeclaredTypesExtractor.extract(from: plist, catalog: catalog) == DeclaredTypes())
        #expect(DeclaredTypesExtractor.extract(from: [:], catalog: catalog) == DeclaredTypes())
    }

    @Test func hostileSizesAreCapped() {
        let many = (0..<5000).map { ["LSItemContentTypes": ["x.t\($0)"]] }
        let declared = DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": many], catalog: catalog)
        #expect(declared.contentTypes.count <= DeclaredTypesExtractor.maxEntries)
        let long = String(repeating: "a", count: 300)
        #expect(DeclaredTypesExtractor.extract(from: ["CFBundleDocumentTypes": [["LSItemContentTypes": [long, "dyn.abc"]]]], catalog: catalog).contentTypes.isEmpty)
    }
}
