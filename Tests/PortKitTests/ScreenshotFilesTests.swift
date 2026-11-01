import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PortKit

/// Lane W4-A: what a capture leaves behind (names, folders, private temp files, the clipboard) and the source-level
/// gates of the lane (no prompt API, no network, no logging of pixels, no shortcut on the system's own keys). Only
/// temporary folders and a uniquely named pasteboard are touched, never the person's Desktop, clipboard or screen.
@MainActor
@Suite(.serialized) struct ScreenshotFilesTests {
    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-shot-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func permissions(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private var strings: ScreenshotFeatureStrings { FeatureStrings.screenshot(L10n.shared.language) }

    // MARK: File naming

    @Test func theDefaultNameIsFrenchDatedAndNeverOverwritesAnything() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 1; parts.hour = 9; parts.minute = 5; parts.second = 7
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        let name = ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: date)
        #expect(name == "\(strings.fileNamePrefix) 2026-11-01 at 09.05.07.png")
        #expect(!strings.fileNamePrefix.contains("Vorssaint") && !strings.fileNamePrefix.isEmpty)
        #expect(ScreenshotSupport.uniqueFileName(name) { _ in false } == name)
        let taken: Set<String> = [name, name.replacingOccurrences(of: ".png", with: " 2.png")]
        #expect(ScreenshotSupport.uniqueFileName(name) { taken.contains($0) }
                    == name.replacingOccurrences(of: ".png", with: " 3.png"))
    }

    @Test func aPatternExpandsDateTokensAndTheNumberAndNeverNestsFolders() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 3; parts.day = 4; parts.hour = 5; parts.minute = 6; parts.second = 7
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        #expect(ScreenshotSupport.expandFileNamePattern("shot %y-%mo-%d %##", date: date, number: 7) == "shot 26-03-04 07")
        #expect(!ScreenshotSupport.expandFileNamePattern("a/b:c", date: date, number: 0).contains("/"))
        #expect(!ScreenshotSupport.expandFileNamePattern("a/b:c", date: date, number: 0).contains(":"))
        // The dated subfolder can never climb out of the chosen folder.
        #expect(ScreenshotSupport.expandSaveSubfolder("../../etc/%y", date: date) == "etc/26")
        #expect(ScreenshotSupport.expandSaveSubfolder("./../", date: date) == "")
        #expect(ScreenshotSupport.expandSaveSubfolder("", date: date) == "")
    }

    // MARK: Folder and fallback

    @Test func aMissingChosenFolderFallsBackToTheDesktopAndIsNeverCreated() throws {
        try PortHostFixture.isolated { defaults in
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("mis-shot-absent-\(UUID().uuidString)", isDirectory: true)
            defaults.set(missing.path, forKey: DefaultsKey.screenshotSaveFolder)
            defaults.set("", forKey: DefaultsKey.screenshotSaveSubfolder)
            defaults.set("", forKey: DefaultsKey.screenshotFileNamePattern)
            let (url, consumed) = ScreenshotService.saveDestination(strings: strings)
            let desktop = try #require(ScreenshotSaveFallback.desktop)
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == desktop.standardizedFileURL.path)
            #expect(consumed == nil)
            #expect(!FileManager.default.fileExists(atPath: missing.path), "the chosen folder is never created")
        }
    }

    @Test func anExistingChosenFolderIsUsedWithADatedSubfolderCreatedInsideIt() throws {
        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        try PortHostFixture.isolated { defaults in
            defaults.set(base.path, forKey: DefaultsKey.screenshotSaveFolder)
            defaults.set("", forKey: DefaultsKey.screenshotSaveSubfolder)
            defaults.set("", forKey: DefaultsKey.screenshotFileNamePattern)
            let plain = ScreenshotService.saveDestination(strings: strings).url
            #expect(plain.deletingLastPathComponent().standardizedFileURL.path == base.standardizedFileURL.path)
            #expect(plain.pathExtension == "png")

            defaults.set("../escape/%y", forKey: DefaultsKey.screenshotSaveSubfolder)
            let nested = ScreenshotService.saveDestination(strings: strings).url
            let folder = nested.deletingLastPathComponent().standardizedFileURL
            #expect(folder.path.hasPrefix(base.standardizedFileURL.path + "/"), "inside the chosen folder: \(folder.path)")
            #expect(!folder.path.contains(".."))
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)

            // A name that is taken gets a number, the capture before it is untouched.
            defaults.set("", forKey: DefaultsKey.screenshotSaveSubfolder)
            defaults.set("fixed", forKey: DefaultsKey.screenshotFileNamePattern)
            try Data([1]).write(to: base.appendingPathComponent("fixed.png"))
            #expect(ScreenshotService.saveDestination(strings: strings).url.lastPathComponent == "fixed 2.png")
        }
    }

    @Test func aFolderThatRefusesTheWriteFallsBackToTheDesktopWithAFreshName() throws {
        let desktop = URL(fileURLWithPath: "/virtual/Desktop", isDirectory: true)
        let refused = URL(fileURLWithPath: "/virtual/readonly/shot.png")
        var written: [URL] = []
        let landed = try ScreenshotSaveFallback.write(
            Data([1, 2, 3]), to: refused, fallbackFolder: desktop,
            write: { _, url in
                if url.path.hasPrefix("/virtual/readonly") { throw CocoaError(.fileWriteNoPermission) }
                written.append(url)
            },
            exists: { $0.lastPathComponent == "shot.png" })
        #expect(landed.path == "/virtual/Desktop/shot 2.png", "never overwrites what is on the Desktop")
        #expect(written == [landed])
    }

    @Test func aWriteThatFailsEverywhereThrowsAndTheDesktopIsNotTriedTwice() {
        let folder = URL(fileURLWithPath: "/virtual/Desktop", isDirectory: true)
        var attempts = 0
        #expect(throws: CocoaError.self) {
            try ScreenshotSaveFallback.write(Data([1]), to: folder.appendingPathComponent("a.png"),
                                             fallbackFolder: folder,
                                             write: { _, _ in attempts += 1; throw CocoaError(.fileWriteNoPermission) })
        }
        #expect(attempts == 1, "the destination already is the fallback: no second try")
        #expect(throws: CocoaError.self) {
            try ScreenshotSaveFallback.write(Data([1]), to: URL(fileURLWithPath: "/virtual/x/a.png"),
                                             fallbackFolder: folder,
                                             write: { _, _ in attempts += 1; throw CocoaError(.fileWriteNoPermission) })
        }
        #expect(attempts == 3, "one try on the folder, one on the Desktop, then the error")
    }

    @Test func aGoodWriteTouchesNothingElse() throws {
        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let target = base.appendingPathComponent("ok.png")
        let landed = try ScreenshotSaveFallback.write(Data([9, 9]), to: target, fallbackFolder: nil)
        #expect(landed == target)
        #expect(try Data(contentsOf: target) == Data([9, 9]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == ["ok.png"])
    }

    // MARK: Private temp files

    @Test func theDragFolderIsPrivateAndItsFileToo() throws {
        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let file = try ScreenshotSupport.temporaryDragFile(data: Data([1, 2]), name: "../evil/name.png", directory: base)
        #expect(file.lastPathComponent == "name.png", "a path in the name never leaves the folder")
        #expect(permissions(of: file.deletingLastPathComponent()) == 0o700)
        #expect(permissions(of: file) == 0o600)
        #expect(file.deletingLastPathComponent().lastPathComponent.hasPrefix("ScreenshotDrag-"))
    }

    @Test func theCleanupRemovesOnlyTheDragFoldersOfThisTool() throws {
        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let mine = try ScreenshotSupport.temporaryDragFile(data: Data([1]), name: "a.png", directory: base)
            .deletingLastPathComponent()
        let notMine = base.appendingPathComponent("ScreenshotDrag-not-a-uuid", isDirectory: true)
        let other = base.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: notMine, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        ScreenshotSupport.removeTemporaryDragDirectories(directory: base)
        #expect(!FileManager.default.fileExists(atPath: mine.path))
        #expect(FileManager.default.fileExists(atPath: notMine.path), "a name that is not ours is left alone")
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func theCopiedFilesFolderIsPrivateToo() throws {
        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let folder = base.appendingPathComponent("Copied Screenshots", isDirectory: true)
        let file = try ScreenshotSupport.copiedFile(data: Data([1]), name: "c.png", directory: folder)
        #expect(permissions(of: folder) == 0o700 && permissions(of: file) == 0o600)
    }

    @Test func theLastCaptureStoreAndTheRecentStoreAreRestrictedInSource() throws {
        let service = try source("Services/QuickTools/ScreenshotService.swift")
        #expect(service.contains("ScreenshotPrivateFiles.restrict(folder: fileURL.deletingLastPathComponent())"))
        #expect(service.contains("ScreenshotPrivateFiles.restrict(file: fileURL)"))
        let recent = try source("Services/QuickTools/RecentCaptureStore.swift")
        #expect(recent.contains("0o700") && recent.contains("0o600"))
        #expect(ScreenshotPrivateFiles.folderPermissions == 0o700 && ScreenshotPrivateFiles.filePermissions == 0o600)
    }

    // MARK: Clipboard

    @Test func theClipboardGetsOneItemWithTheFileTheImageAndItsTiffAndNothingStale() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("be.roldy.macisland.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("stale text", forType: .string)

        let base = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("shot.png")
        try Data([0x89]).write(to: file)
        let payload = ScreenshotEditorController.ClipboardPayload(png: Data([1, 2, 3]), tiff: Data([4, 5, 6]))
        #expect(ScreenshotEditorController.copyFile(file, payload: payload, pasteboard: board))

        #expect(board.pasteboardItems?.count == 1, "one item: an app pastes the image or the file, never half of each")
        let item = try #require(board.pasteboardItems?.first)
        #expect(Set(item.types).isSuperset(of: [.fileURL, .png, .tiff]))
        #expect(item.data(forType: .png) == Data([1, 2, 3]) && item.data(forType: .tiff) == Data([4, 5, 6]))
        #expect(item.string(forType: .fileURL) == file.absoluteString)
        #expect(board.string(forType: .string) == nil, "the previous content is cleared, not mixed in")

        // The payload-only copy (an edited image with no file) keeps the same types minus the file.
        #expect(ScreenshotEditorController.copyClipboardPayload(payload, pasteboard: board))
        let bare = try #require(board.pasteboardItems?.first)
        #expect(Set(bare.types).isSuperset(of: [.png, .tiff]) && !bare.types.contains(.fileURL))
    }

    @Test func aFileCopyWithoutAPayloadStillCarriesTheFile() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("be.roldy.macisland.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let url = URL(fileURLWithPath: "/tmp/never-read.png")
        #expect(ScreenshotEditorController.copyFile(url, payload: nil, pasteboard: board))
        #expect(board.pasteboardItems?.first?.types.contains(.fileURL) == true)
        #expect(board.pasteboardItems?.first?.data(forType: .png) == nil)
    }

    @Test func noCaptureCodeTouchesTheGeneralPasteboardOutsideTheTwoWriters() throws {
        // The two writers default to `.general` (the app's real clipboard); everything else in the capture code
        // goes through them, so a test or a new call site never clears the clipboard behind the person's back.
        for path in ["Services/QuickTools/ScreenshotService.swift", "Services/QuickTools/ScreenshotQuickPreviewController.swift",
                     "Services/QuickTools/ScreenshotPinController.swift"] {
            let text = try source(path)
            #expect(!text.contains("NSPasteboard.general.clearContents"), "\(path)")
        }
    }

    // MARK: Shortcuts

    @Test func noCaptureShortcutDefaultSitsOnTheSystemsOwnKeys() {
        let systemKeys: Set<Int64> = [Int64(kVK_ANSI_3), Int64(kVK_ANSI_4), Int64(kVK_ANSI_5)]
        let roles: [GlobalShortcutRole] = [.screenshot, .screenshotFullScreen, .screenshotLastCapture, .screenshotUpload,
                                           .recentCaptures, .screenshotClipboard, .screenRecorder, .screenOCR, .colorPicker]
        for role in roles {
            let shortcut = role.defaultShortcut
            if systemKeys.contains(shortcut.keyCode) {
                #expect(shortcut.modifiers != [.command, .shift], "\(role): shift-command on 3, 4 or 5 is macOS's")
                #expect(shortcut.modifiers != [.command, .shift, .control], "\(role): control variants copy to the clipboard")
            }
            #expect(shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control), "\(role)")
        }
        #expect(GlobalShortcut.screenshotDefault.modifiers == [.control, .option, .command])
        #expect(GlobalShortcut.screenshotFullScreenDefault.modifiers == [.control, .option, .command])
    }

    @Test func everyCaptureShortcutIsOffUntilTheUserTurnsItOn() {
        PortHostFixture.isolated { defaults in
            Defaults.register(in: defaults)
            for key in [DefaultsKey.screenshotShortcutEnabled, DefaultsKey.screenshotFullScreenShortcutEnabled,
                        DefaultsKey.screenshotLastCaptureShortcutEnabled, DefaultsKey.screenshotClipboardShortcutEnabled,
                        DefaultsKey.screenshotUploadShortcutEnabled, DefaultsKey.recentCapturesShortcutEnabled] {
                #expect(defaults.bool(forKey: key) == false, "\(key)")
            }
        }
    }

    // MARK: No share, no network, no prompt, no log

    @Test func theShareServiceIsAStubAndEverySurfaceThatOffersALinkIsHidden() async throws {
        #expect(ScreenshotSharingSupport.serviceAvailable == false)
        #expect(ScreenshotShareService.isAvailable == false)
        #expect(ScreenshotSharingSupport.productionEndpoint.host?.hasSuffix(".invalid") == true)
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.screenshotUploadShortcutEnabled)
            defaults.set(true, forKey: DefaultsKey.screenshotSharingEnabled)
            #expect(ScreenshotSharingSupport.uploadShortcutEnabled(in: defaults) == false,
                    "the upload hotkey is never registered, whatever a migrated key says")
            #expect(ScreenshotSharingSupport.retainsLatestCapture(in: defaults) == false)
        }
        await #expect(throws: ScreenshotShareError.self) {
            _ = try await ScreenshotShareService.shared.createLink(pngData: Data([1]), duration: .oneHour)
        }
        let preview = try source("Services/QuickTools/ScreenshotQuickPreviewController.swift")
        #expect(preview.contains("if ScreenshotSharingSupport.serviceAvailable, sharingEnabled, model.sharedRecord == nil"))
        #expect(preview.contains("guard ScreenshotSharingSupport.serviceAvailable, !closed, !model.sharing"))
        let editorView = try source("UI/Screenshot/ScreenshotEditorView.swift")
        #expect(editorView.contains("if ScreenshotSharingSupport.serviceAvailable, sharingEnabled {"))
        let settings = try source("UI/Settings/ScreenshotSettings.swift")
        #expect(settings.contains("if ScreenshotSharingSupport.serviceAvailable {"))
        #expect(settings.contains("Les liens temporaires ne sont pas disponibles dans Mac Island"), "the page says why, in French")
    }

    @Test func theShelfEntriesStayOffUntilTheShelfIsHosted() throws {
        #expect(ScreenshotShelfBridge.isHosted == false)
        #expect(ScreenshotShelfBridge.unavailableReason.contains("étagère"), "the page says why, in French")
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: DefaultsKey.screenshotAddToShelf)
            defaults.set(true, forKey: DefaultsKey.shelfEnabled)
            PortHost.availability = { _ in true }
            #expect(ScreenshotSupport.addsCapturesToShelf(in: defaults) == false,
                    "a migrated key can never send a capture to a store nobody looks at")
        }
        let editorView = try source("UI/Screenshot/ScreenshotEditorView.swift")
        #expect(editorView.contains("if ScreenshotShelfBridge.isHosted, shelfEnabled, shelfAvailable {"))
        let settings = try source("UI/Settings/ScreenshotSettings.swift")
        #expect(settings.contains("ScreenshotShelfBridge.isHosted && shelfEnabled && shelfAvailable"))
    }

    /// The files this lane owns or patches.
    private static let surface: [String] = [
        "Bridge/Screenshot.swift",
        "Services/QuickTools/ScreenshotCanvasSupport.swift", "Services/QuickTools/ScreenshotCaptureEngine.swift",
        "Services/QuickTools/ScreenshotCapturePolicy.swift", "Services/QuickTools/ScreenshotEditorController.swift",
        "Services/QuickTools/ScreenshotImageLayerRendering.swift", "Services/QuickTools/ScreenshotPinController.swift",
        "Services/QuickTools/ScreenshotQuickPreviewController.swift", "Services/QuickTools/ScreenshotRenderer.swift",
        "Services/QuickTools/ScreenshotScrollingCapture.swift", "Services/QuickTools/ScreenshotSelectionController.swift",
        "Services/QuickTools/ScreenshotService.swift", "Services/QuickTools/ScreenshotSupport.swift",
        "Services/QuickTools/ScreenCaptureService.swift", "Services/QuickTools/RecentCaptureService.swift",
        "Services/QuickTools/RecentCaptureStore.swift", "Services/QuickTools/QuickToolHUD.swift",
        "Services/QuickTools/QuickToolHotkey.swift", "Services/QuickTools/WindowActivationPolicy.swift",
        "UI/Screenshot/ScreenshotBackdropPopover.swift", "UI/Screenshot/ScreenshotCanvasExpansionPreview.swift",
        "UI/Screenshot/ScreenshotEditorView.swift", "UI/Screenshot/ScreenshotToolOrderControls.swift",
        "UI/Screenshot/ScreenshotWatermarkPopover.swift", "UI/MenuPanel/PanelRecentCapturesView.swift",
        "UI/Settings/ScreenshotSettings.swift", "UI/Settings/ScreenCaptureSettings.swift",
        "UI/Settings/ScreenCaptureToolPicker.swift",
    ]

    private func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func theLaneFilesExist() throws {
        for path in Self.surface { _ = try source(path) }
    }

    @Test func noPromptApiIsCalledByTheCaptureCode() throws {
        let forbidden = ["CGRequestScreenCaptureAccess", "AXIsProcessTrustedWithOptions", "kAXTrustedCheckOptionPrompt",
                         "requestAccess(", "SCContentSharingPicker", "authorizationStatus"]
        for path in Self.surface {
            let text = try source(path)
            for word in forbidden { #expect(!text.contains(word), "\(path) uses \(word)") }
        }
    }

    @Test func screenCaptureKitIsReachedThroughTheOneGatedDoorOnly() throws {
        let engine = try source("Services/QuickTools/ScreenshotCaptureEngine.swift")
        #expect(engine.components(separatedBy: "SCShareableContent.excludingDesktopWindows(").count - 1 == 1,
                "one direct call, inside `shareableContent()`")
        #expect(engine.contains("guard Permissions.shared.screenRecording else { throw CocoaError(.userCancelled) }"))
        for path in Self.surface where path != "Services/QuickTools/ScreenshotCaptureEngine.swift" {
            let text = try source(path)
            #expect(!text.contains("SCShareableContent.excludingDesktopWindows("), "\(path)")
            #expect(!text.contains("SCScreenshotManager"), "\(path)")
        }
        // Every entry that reads the screen checks the grant first.
        let service = try source("Services/QuickTools/ScreenshotService.swift")
        #expect(service.contains("guard Permissions.shared.screenRecording else {"))
        let chooser = try source("Services/QuickTools/ScreenCaptureService.swift")
        #expect(chooser.contains("guard Permissions.shared.screenRecording else {"))
    }

    @Test func theRequestPathOnlyOpensTheSettingsPane() throws {
        let permissions = try source("Core/Permissions.swift")
        let start = try #require(permissions.range(of: "func requestScreenRecording()"))
        let body = permissions[start.lowerBound...].prefix(400)
        #expect(body.contains("openScreenRecordingSettings()") && !body.contains("CGRequestScreenCaptureAccess"))
    }

    @Test func theCaptureCodeReachesNoNetworkAndNoVorssaintHost() throws {
        let forbidden = ["URLSession", "URLRequest(", "NWConnection", "NSURLConnection", "vorssaint.com", "screenshots.vorssaint"]
        for path in Self.surface {
            let text = try source(path)
            for word in forbidden { #expect(!text.contains(word), "\(path) uses \(word)") }
        }
        let sharing = try source("Services/QuickTools/ScreenshotSharingSupport.swift")
        #expect(sharing.contains("sharing.unavailable.invalid"))
    }

    @Test func noPictureOrPathIsEverLogged() throws {
        for path in Self.surface {
            let text = try source(path)
            for word in ["NSLog(", "print(", "os_log(", "Logger(", "debugPrint(", "dump("] {
                #expect(!text.contains(word), "\(path) logs with \(word)")
            }
        }
    }
}
