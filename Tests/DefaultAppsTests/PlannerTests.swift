import Foundation
import Testing
@testable import DefaultAppsFeature

@Suite struct PlannerTests {
    let planner = ReplacementPlanner(catalog: FakeCatalog())
    let ls = Fixture.world()
    var scan: ScanResult { DefaultAppsScanner(launchServices: ls, catalog: FakeCatalog()).scan() }

    func fixture() throws -> (scan: ScanResult, source: ReplaceableApp, sublime: AppProfile) {
        let scan = self.scan
        return (scan, try #require(scan.replaceable.first { $0.id == Fixture.textEdit }), try #require(scan.app(Fixture.sublime)))
    }

    @Test func replaceAllTakesEveryUnprotectedTypeTheReplacementCanOpen() throws {
        let f = try fixture()
        let preview = planner.preview(source: f.source, replacement: f.sublime, selection: .all, scan: f.scan)
        #expect(Set(preview.items.map(\.identifier)) == ["net.daringfireball.markdown", "public.json", "public.plain-text", "public.rtf", "public.swift-source"])
        #expect(preview.items.allSatisfy { $0.previousBundleID == Fixture.textEdit && $0.previousName == "TextEdit" && !$0.isProtected })
        #expect(preview.refused.map(\.identifier) == ["public.folder"] && preview.refused[0].reason == .protectedItem)
    }

    @Test func aSublimeThatDeclaresOnlyJsonOnlyTakesJson() throws {
        var f = try fixture()
        let narrow = AppProfile(bundleID: "x.narrow", name: "Narrow", url: URL(fileURLWithPath: "/Applications/Narrow.app"),
                                declared: DeclaredTypes(contentTypes: ["public.json"]))
        f.scan.apps.append(narrow)
        let preview = planner.preview(source: f.source, replacement: narrow, selection: .all, scan: f.scan)
        #expect(preview.items.map(\.identifier) == ["public.json"])
        #expect(preview.refused.filter { $0.reason == .replacementCannotOpen }.count == 4)
    }

    @Test func pickedTypesLimitThePreviewToThoseTypes() throws {
        let f = try fixture()
        let preview = planner.preview(source: f.source, replacement: f.sublime, selection: .picked(["public.json", "public.rtf"]), scan: f.scan)
        #expect(Set(preview.items.map(\.identifier)) == ["public.json", "public.rtf"] && preview.refused.isEmpty)
    }

    @Test func aProtectedTypeIsRefusedUnlessTheUserPickedItOnPurposeAndTheReplacementCanOpenIt() throws {
        let f = try fixture()
        let refused = planner.preview(source: f.source, replacement: f.sublime, selection: .picked(["public.folder"]), scan: f.scan)
        #expect(refused.items.isEmpty && refused.refused.first?.reason == .protectedItem)
        // Picked on purpose, but Sublime does not declare it (public.data is too generic to count): still refused.
        let picked = planner.preview(source: f.source, replacement: f.sublime, selection: .picked(["public.folder"]),
                                     explicitProtected: ["public.folder"], scan: f.scan)
        #expect(picked.items.isEmpty && picked.refused.first?.reason == .replacementCannotOpen)
        // An app that declares the folder type, picked on purpose: allowed, and marked explicit.
        let finderLike = AppProfile(bundleID: "x.fm", name: "FM", url: URL(fileURLWithPath: "/Applications/FM.app"),
                                    declared: DeclaredTypes(contentTypes: ["public.folder"]))
        let allowed = planner.preview(source: f.source, replacement: finderLike, selection: .picked(["public.folder"]),
                                      explicitProtected: ["public.folder"], scan: f.scan)
        #expect(allowed.items.first?.explicitlyPicked == true && allowed.items.first?.isProtected == true)
    }

    @Test func aReplacementThatAlreadyIsTheDefaultOrTheSameAppChangesNothing() throws {
        var f = try fixture()
        f.scan.defaults["public.json"] = Fixture.sublime
        let preview = planner.preview(source: f.source, replacement: f.sublime, selection: .picked(["public.json"]), scan: f.scan)
        #expect(preview.items.isEmpty && preview.refused.first?.reason == .alreadyDefault)
        let same = planner.preview(source: f.source, replacement: f.source.profile, selection: .all, scan: f.scan)
        #expect(same.items.isEmpty && same.refused.isEmpty)
    }

    @Test func aCatchAllDeclarationDoesNotQualifyAReplacement() {
        let greedy = AppProfile(bundleID: "x.greedy", name: "Greedy", url: URL(fileURLWithPath: "/Applications/G.app"),
                                declared: DeclaredTypes(contentTypes: ["public.data", "public.item", "public.content"]))
        #expect(!planner.canOpen(greedy, contentType: "public.json"))
        let viaParent = AppProfile(bundleID: "x.p", name: "P", url: URL(fileURLWithPath: "/Applications/P.app"),
                                   declared: DeclaredTypes(contentTypes: ["public.text"]))
        #expect(planner.canOpen(viaParent, contentType: "net.daringfireball.markdown"), "a conforming child is covered by its declared parent")
    }

    @Test func candidatesAreTheOtherAppsThatCanOpenSomethingBestCoverageFirst() throws {
        let f = try fixture()
        let candidates = planner.candidates(for: f.source, among: f.scan.apps)
        #expect(candidates.map(\.profile.bundleID) == [Fixture.sublime] && candidates[0].coverage == 5)
    }

    @Test func schemePreviewNeedsADeclaredSchemeAndConfirmationForTheSensitiveOnes() throws {
        let f = try fixture()
        let subl = planner.schemePreview(replacement: f.sublime, scheme: "subl", confirmedProtected: false, currentHandler: nil, currentName: nil)
        #expect(subl.items.map(\.identifier) == ["subl"] && subl.items[0].previousBundleID == nil)
        let http = planner.schemePreview(replacement: f.sublime, scheme: "http", confirmedProtected: false, currentHandler: Fixture.browser, currentName: "Browser")
        #expect(http.items.isEmpty && http.refused.first?.reason == .protectedItem)
        let confirmed = planner.schemePreview(replacement: f.sublime, scheme: "HTTP", confirmedProtected: true, currentHandler: Fixture.browser, currentName: "Browser")
        #expect(confirmed.items.first?.identifier == "http" && confirmed.items.first?.explicitlyPicked == true)
        let undeclared = planner.schemePreview(replacement: f.sublime, scheme: "mailto", confirmedProtected: true, currentHandler: nil, currentName: nil)
        #expect(undeclared.refused.first?.reason == .replacementCannotOpen)
        #expect(planner.schemePreview(replacement: f.sublime, scheme: "not a scheme", confirmedProtected: true, currentHandler: nil, currentName: nil).items.isEmpty)
    }

    @Test func theRefusalListNamesTheSystemCriticalTypesAndSchemes() {
        for id in ["public.folder", "public.url", "public.file-url", "com.apple.finder.alias", "com.apple.finder", "public.volume", "public.data"] {
            #expect(ProtectionPolicy.isProtected(contentType: id), Comment(rawValue: id))
        }
        for scheme in ["http", "https", "mailto", "HTTPS", "x-apple.systempreferences"] { #expect(ProtectionPolicy.isProtected(scheme: scheme)) }
        #expect(!ProtectionPolicy.isProtected(contentType: "public.json") && !ProtectionPolicy.isProtected(scheme: "subl"))
    }
}
