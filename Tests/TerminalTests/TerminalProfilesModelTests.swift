import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TerminalFeature

@MainActor
private final class FakeSession: TerminalRestarting {
    var decision: TerminalRestartDecision = .restart
    var restarts = 0
    func restartDecision() -> TerminalRestartDecision { decision }
    func restartWithActiveProfile() { restarts += 1 }
}

private func profile(_ name: String, seed: Double = 0.1) -> TerminalColorProfile {
    TerminalColorProfile(
        id: UUID(), name: name,
        ansi: (0..<16).map { TerminalRGB(seed, Double($0) / 15, 0.5) },
        foreground: TerminalRGB(0.9, 0.9, 0.9), background: TerminalRGB(0, 0, 0.1),
        cursor: TerminalRGB(1, 1, 1), selection: TerminalRGB(0.2, 0.2, 0.6),
        fontName: nil, fontSize: nil, importedAt: Date(timeIntervalSince1970: 1_700_000_000))
}

private func scratchDefaults() -> UserDefaults {
    let suite = "terminal-profile-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Suite struct TerminalRestartDecisionTests {
    @Test func noSessionMeansColorsOnNextStart() {
        #expect(TerminalRestartDecision.decide(hasSession: false, shellPid: 10, foregroundGroup: 99, foregroundName: "vim") == .colorsOnNextStart)
    }

    @Test func shellAloneRestartsAtOnce() {
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: 10, foregroundName: "zsh") == .restart)
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: nil, foregroundName: nil) == .restart)
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: 0, foregroundName: nil) == .restart)
    }

    @Test func anotherForegroundProgramNeedsConfirmation() {
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: 77, foregroundName: "vim") == .confirm(process: "vim"))
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: 77, foregroundName: nil) == .confirm(process: "un programme"))
        #expect(TerminalRestartDecision.decide(hasSession: true, shellPid: 10, foregroundGroup: 77, foregroundName: "a\u{0}\u{202E}b") == .confirm(process: "ab"))
    }

    @Test func unusableDirectoryFallsBackToHome() {
        #expect(TerminalProcessInfo.usableDirectory("/nonexistent-\(UUID().uuidString)") == NSHomeDirectory())
        #expect(TerminalProcessInfo.usableDirectory("relative/path") == NSHomeDirectory())
        #expect(TerminalProcessInfo.usableDirectory("/tmp") == "/tmp")
    }

    @Test func ownShellDirectoryCanBeRead() {
        let path = TerminalProcessInfo.currentDirectory(of: getpid())
        #expect(path != nil && path!.hasPrefix("/"))
    }
}

@Suite struct TerminalProfileCodecTests {
    @Test func roundTripKeepsEverything() throws {
        var library = TerminalProfileLibrary()
        let one = profile("Un")
        let id = library.add(one)
        library.add(profile("Deux", seed: 0.7))
        library.activate(id)
        let data = try #require(TerminalProfileLibraryCodec.encode(library))
        let back = TerminalProfileLibraryCodec.decode(data)
        #expect(back == library)
        #expect(back.active?.name == "Un")
    }

    @Test func garbageOrOtherVersionDecodesToEmpty() throws {
        #expect(TerminalProfileLibraryCodec.decode(nil) == TerminalProfileLibrary())
        #expect(TerminalProfileLibraryCodec.decode(Data("{".utf8)) == TerminalProfileLibrary())
        #expect(TerminalProfileLibraryCodec.decode(Data(repeating: 0x20, count: TerminalProfileLibraryCodec.maxBytes + 1)) == TerminalProfileLibrary())
        var library = TerminalProfileLibrary()
        library.add(profile("A"))
        let data = try #require(TerminalProfileLibraryCodec.encode(library))
        let future = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        #expect(TerminalProfileLibraryCodec.decode(Data(future.utf8)) == TerminalProfileLibrary())
    }

    @Test func loadedProfilesAreSanitisedAndChecked() throws {
        var bad = profile("x\u{202E}y")
        bad.ansi.removeLast()  // 15 colours: dropped
        var library = TerminalProfileLibrary(profiles: [profile("ok\u{0}k"), bad])
        library.activate(library.profiles[0].id)
        let data = try #require(TerminalProfileLibraryCodec.encode(library))
        let back = TerminalProfileLibraryCodec.decode(data)
        #expect(back.profiles.count == 1)
        #expect(back.profiles[0].name == "okk")
    }

    @Test func nonFiniteComponentInStoredJSONFailsClosed() {
        let json = #"{"version":1,"profiles":[{"id":"\#(UUID().uuidString)","name":"n","ansi":[],"foreground":{"red":1e999,"green":0,"blue":0}}]}"#
        #expect(TerminalProfileLibraryCodec.decode(Data(json.utf8)) == TerminalProfileLibrary())
    }

    @Test func tenProfilesAtMostAndTheActiveOneSurvives() {
        var library = TerminalProfileLibrary()
        let first = library.add(profile("P0", seed: 0))
        library.activate(first)
        for index in 1...14 { library.add(profile("P\(index)", seed: Double(index) / 20)) }
        #expect(library.profiles.count == TerminalProfileLibrary.maxProfiles)
        #expect(library.active?.name == "P0")
        #expect(library.profiles.first?.name == "P14")
    }

    @Test func sameSchemeIsNotListedTwiceAndRenameDeleteWork() {
        var library = TerminalProfileLibrary()
        let a = library.add(profile("A"))
        let again = library.add(profile("Autre nom"))
        #expect(again == a && library.profiles.count == 1)
        library.rename(a, to: "  Nuit\u{0}  bleue ")
        #expect(library.profiles[0].name == "Nuit bleue")
        library.rename(a, to: "\u{0}")
        #expect(library.profiles[0].name == "Nuit bleue")
        library.activate(a)
        library.remove(a)
        #expect(library.profiles.isEmpty && library.activeID == nil)
        library.activate(UUID())
        #expect(library.activeID == nil)
    }

    @Test func storeWritesUnderTheDocumentedKey() throws {
        let defaults = scratchDefaults()
        let store = TerminalProfileStore(defaults: defaults)
        var library = TerminalProfileLibrary()
        library.activate(library.add(profile("Z")))
        store.save(library)
        #expect(defaults.data(forKey: "terminalColorProfile") != nil)
        #expect(store.activeProfile?.name == "Z")
        #expect(TerminalProfileStore(defaults: scratchDefaults()).activeProfile == nil)
    }
}

@MainActor
@Suite struct TerminalProfilesModelTests {
    private func make(_ decision: TerminalRestartDecision) -> (TerminalProfilesModel, FakeSession, TerminalProfileStore) {
        let session = FakeSession()
        session.decision = decision
        let store = TerminalProfileStore(defaults: scratchDefaults())
        return (TerminalProfilesModel(store: store, session: session), session, store)
    }

    private func imported(_ model: TerminalProfilesModel, name: String = "Nuit") throws {
        let dict: [String: Any] = Dictionary(uniqueKeysWithValues: (0..<16).map { i in
            ("Ansi \(i) Color", ["Red Component": Double(i) / 15, "Green Component": 0.5, "Blue Component": 0.2, "Color Space": "sRGB"] as [String: Any])
        })
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).itermcolors")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        model.importFile(at: url)
    }

    @Test func importThenApplyRestartsAndPersists() throws {
        let (model, session, store) = make(.restart)
        try imported(model)
        #expect(model.pending?.profile.name == "Nuit" && model.errorMessage == nil)
        #expect(store.load().profiles.isEmpty)  // preview only: nothing written yet
        model.applyPending()
        #expect(session.restarts == 1 && model.pending == nil)
        #expect(store.activeProfile?.name == "Nuit")
        #expect(model.statusMessage?.contains("redémarré") == true)
    }

    @Test func runningProgramAsksBeforeAnything() throws {
        let (model, session, store) = make(.confirm(process: "vim"))
        try imported(model)
        model.applyPending()
        #expect(session.restarts == 0 && store.load().profiles.isEmpty)
        #expect(model.confirmation?.process == "vim")
        model.cancelRestart()
        #expect(session.restarts == 0 && store.activeProfile == nil && model.confirmation == nil)
        model.applyPending()
        model.confirmRestart()
        #expect(session.restarts == 1 && store.activeProfile?.name == "Nuit")
    }

    @Test func noRunningShellOnlySaves() throws {
        let (model, session, store) = make(.colorsOnNextStart)
        try imported(model)
        model.applyPending()
        #expect(session.restarts == 0)
        #expect(store.activeProfile?.name == "Nuit")
        #expect(model.statusMessage?.contains("prochain démarrage") == true)
    }

    @Test func resetToDefaultClearsTheActiveProfileAndRestarts() throws {
        let (model, session, store) = make(.restart)
        try imported(model)
        model.applyPending()
        model.resetToDefault()
        #expect(store.activeProfile == nil && session.restarts == 2)
        #expect(store.load().profiles.count == 1)  // the profile stays in the list
        #expect(model.activeName == "Par défaut")
    }

    @Test func badFileShowsAFrenchErrorAndKeepsNothing() {
        let (model, _, _) = make(.restart)
        model.importFile(at: URL(fileURLWithPath: "/nonexistent/x.json"))
        #expect(model.pending == nil)
        #expect(model.errorMessage?.contains("Type de fichier") == true)
    }

    @Test func renameAndDeleteFromTheList() throws {
        let (model, session, store) = make(.restart)
        try imported(model)
        model.applyPending()
        let id = try #require(model.library.activeID)
        model.beginRename(id)
        model.renameText = "Mon profil"
        model.commitRename()
        #expect(store.load().profiles[0].name == "Mon profil")
        model.delete(id)
        #expect(store.load().profiles.isEmpty && store.activeProfile == nil)
        #expect(session.restarts == 1)  // deleting never restarts
    }
}

@MainActor
@Suite struct TerminalColorProfilePreviewTests {
    @Test func contentListsTheSixteenColorsAndTheFourSpecialOnes() {
        let content = TerminalColorProfilePreviewContent(profile("Aurore"), foundColors: 12)
        #expect(content.name == "Aurore")
        #expect(content.ansi.count == 16 && content.special.count == 4)
        #expect(content.ansi[0].label == "Noir (ANSI 0)" && content.ansi[9].label == "Rouge vif (ANSI 9)")
        #expect(content.special.map(\.label) == ["Texte", "Fond", "Curseur", "Sélection"])
        #expect(content.special[1].hex == "#00001A")
        #expect(content.ansi[0].accessibilityLabel == "Noir (ANSI 0) : #1A0080")
        #expect(content.summary.contains("12 couleurs lues sur 20"))
        #expect(Set(content.ansi.map(\.label)).count == 16)
    }

    @Test func fontLineAppearsOnlyWhenTheProfileHasAFont() {
        var withFont = profile("F")
        withFont.fontName = "Menlo-Regular"
        withFont.fontSize = 13
        #expect(TerminalColorProfilePreviewContent(withFont).fontLine?.contains("Menlo-Regular 13 pt") == true)
        #expect(TerminalColorProfilePreviewContent(profile("G")).fontLine == nil)
    }

    @Test func cardRendersWithARealSize() {
        let host = NSHostingView(rootView: TerminalColorProfilePreview(content: TerminalColorProfilePreviewContent(profile("Rendu"), foundColors: 20)))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 80 && host.fittingSize.width > 100)
    }

    @Test func settingsBodyBuildsWithoutStartingAShell() {
        let session = FakeSession()
        let model = TerminalProfilesModel(store: TerminalProfileStore(defaults: scratchDefaults()), session: session)
        let host = NSHostingView(rootView: TerminalSettingsBody(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 40 && session.restarts == 0)
    }
}
