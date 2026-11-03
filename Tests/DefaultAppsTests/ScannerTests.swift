import Foundation
import Testing
@testable import DefaultAppsFeature

@Suite struct ScannerTests {
    func scan(_ ls: FakeLaunchServices = Fixture.world()) -> ScanResult {
        DefaultAppsScanner(launchServices: ls, catalog: FakeCatalog()).scan()
    }

    @Test func listsTheAppsThatAreTheCurrentDefaultOfSomethingMostTypesFirst() {
        let result = scan()
        #expect(result.replaceable.map(\.profile.bundleID) == [Fixture.textEdit, Fixture.preview])
        #expect(result.apps.count == 4)
    }

    @Test func showsEveryTypeAnAppHandlesWithExamplesAndACount() throws {
        let textEdit = try #require(scan().replaceable.first)
        #expect(textEdit.count == 6 && textEdit.unprotectedCount == 5)
        let markdown = try #require(textEdit.handled.first { $0.id == "net.daringfireball.markdown" })
        #expect(markdown.summary == "Markdown" && markdown.extensions == ["md", "markdown"] && markdown.extensionsText == ".md, .markdown")
        #expect(textEdit.handled.first { $0.id == "public.folder" }?.isProtected == true)
    }

    @Test func aTypeNobodyOpensIsNotListedUnderAnyApp() {
        let result = scan()
        #expect(result.defaults["public.text"] == nil)
        #expect(!result.replaceable.flatMap(\.handled).contains { $0.id == "public.text" })
    }

    @Test func anAppWithoutABundleIdOrADuplicateIsIgnored() {
        let ls = Fixture.world()
        ls.apps.append((URL(fileURLWithPath: "/Applications/NoID.app"), ["CFBundleName": "NoID"]))
        ls.install(Fixture.sublime, name: "Sublime Copy", path: "/Applications/Copy.app")
        let result = scan(ls)
        #expect(result.apps.count == 4)
        #expect(result.app(Fixture.sublime)?.name == "Sublime Text", "the first one found wins")
    }

    @Test func theNameFallsBackToTheBundleFileName() {
        let ls = FakeLaunchServices()
        ls.apps.append((URL(fileURLWithPath: "/Applications/Plain.app"), ["CFBundleIdentifier": "x.plain"]))
        #expect(scan(ls).app("x.plain")?.name == "Plain")
    }

    @Test func scanningNeverWrites() {
        let ls = Fixture.world()
        _ = scan(ls)
        #expect(ls.writes.isEmpty)
    }
}
