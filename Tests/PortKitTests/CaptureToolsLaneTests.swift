import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W4C: copy text from screen (OCR), colour picker and camera preview, bound through a fake runtime and a real
/// `FeatureRegistry`. Nothing here touches Vision, the capture surface, a camera or a permission.
@MainActor
@Suite(.serialized) struct CaptureToolsLaneTests {
    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        /// What the app's permission monitor last reported: tests flip it before a grant.
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func runtime(_ log: Log) -> CaptureToolsLane.Runtime {
        CaptureToolsLane.Runtime(
            syncCaptureSurface: { log.events.append("surface") },
            resyncCaptureSurface: { log.events.append("resurface") },
            syncOCR: { log.events.append("ocr") },
            suspendOCR: { log.events.append("ocr.stop") },
            startCamera: { log.events.append("camera") },
            stopCamera: { log.events.append("camera.stop") },
            watchQuit: { log.events.append("watch") },
            unwatchQuit: { log.events.append("unwatch") })
    }

    /// The registry as the app builds it. `on` are the switches that are on at launch.
    func rig(on: Set<String> = [], screenRecording: Bool = true) -> Rig {
        let permissions = Box(PortPermissionState(screenRecording: screenRecording))
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let log = Log()
        CaptureToolsLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { permissions.value.screenRecording },
                                    automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        for id in on { registry.switches[id] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, permissions: permissions, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor, permission and page tables

    @Test func threeNewFeaturesWithFrenchTextOffByDefaultAndNothingStartedByBinding() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.map(\.id) == ["screenOCR", "colorPicker", "cameraPreview"])
        for descriptor in r.binding.descriptors {
            #expect(!descriptor.title.isEmpty && !descriptor.summary.isEmpty, "\(descriptor.id)")
            #expect(descriptor.category == .tools && descriptor.enabledByDefault == false && descriptor.tabID == nil)
            #expect(descriptor.risk == .safe, "\(descriptor.id): reads the screen or the camera, changes nothing")
            #expect(r.registry.state(for: descriptor.id) == .off)
            #expect(ShellDescriptors.all.filter { $0.id == descriptor.id }.isEmpty, "no second switch of ours")
        }
        #expect(r.binding.descriptors.first { $0.id == "screenOCR" }?.title == "Copier le texte à l’écran")
        #expect(r.binding.descriptors.first { $0.id == "colorPicker" }?.title == "Pipette de couleur")
        #expect(r.log.events.isEmpty, "binding starts nothing")
    }

    @Test func permissionTable() {
        let r = rig()
        defer { r.cleanup() }
        func permissions(_ id: String) -> [FeaturePermission] { r.binding.descriptors.first { $0.id == id }?.permissions ?? [] }
        #expect(permissions("screenOCR") == [.screenRecording], "OCR reads the screen")
        #expect(permissions("colorPicker").isEmpty, "the system sampler needs no permission")
        #expect(permissions("cameraPreview") == [.camera])
    }

    @Test func eachFeatureHasItsOwnPageAndTheCatalogRowsAreAlone() {
        let r = rig()
        defer { r.cleanup() }
        #expect(CaptureToolsLane.pageIDs == ["cameraPreview": "camera", "screenOCR": "ocr", "colorPicker": "colorpicker"])
        let pages = r.binding.pages
        #expect(pages.count == 3)
        for (feature, pageID) in CaptureToolsLane.pageIDs {
            let row = SettingsPageCatalog.page(pageID)
            #expect(row != nil && row?.featureID == nil, "\(pageID): the registry card is added by the page registration")
            #expect(SettingsLive.isEmpty(pageID: pageID), "\(pageID): the ported body draws the whole page")
            #expect(pages.contains { $0.pageID == pageID && $0.featureID == feature }, "\(pageID)")
        }
        #expect(SettingsPageCatalog.page("camera")?.title == "Aperçu de la caméra")
        #expect(SettingsPageCatalog.page("ocr")?.title == "Copier le texte à l’écran")
        #expect(SettingsPageCatalog.page("colorpicker")?.title == "Pipette de couleur")
    }

    @Test func theLaneIsInTheLaneListAndBindsOnlyItsOwnThreeFeaturesOnce() throws {
        let lanes = try Self.source("Sources/PortKit/Bridge/PortLanes.swift")
        #expect(lanes.contains("CaptureToolsLane.bind(into:)"))
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        CaptureToolsLane.bind(into: binding, runtime: runtime(Log()))
        CaptureToolsLane.bind(into: binding, runtime: runtime(Log()))
        #expect(binding.descriptors.count == 3, "a second bind adds nothing")
        #expect(PortFeatureIDs.registryID(forUpstream: "cameraPreview") == "cameraPreview", "new to Mac Island: its own id")
    }

    // MARK: Start, stop, kill switch

    @Test func ocrStartsOnceRegistersTheChooserAndOffReleasesIt() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["screenOCR"] = true
        r.registry.switches["screenOCR"] = true
        #expect(r.log.events == ["ocr", "surface"], "idempotent: one start")
        #expect(r.binding.availability("screenOCR") == true)
        r.log.events.removeAll()
        r.registry.switches["screenOCR"] = false
        #expect(r.log.events == ["ocr.stop", "resurface"], "recognition cancelled, QR panel closed, shortcut released")
        #expect(r.binding.availability("screenOCR") == false)
    }

    @Test func ocrIsHeldBackWithoutScreenRecordingAndNothingPromptsFromTheBinding() {
        let r = rig(on: ["screenOCR"], screenRecording: false)
        defer { r.cleanup() }
        #expect(r.registry.state(for: "screenOCR") == .needsPermission(.screenRecording))
        #expect(r.log.events.isEmpty, "never arms without the grant, never asks: the monitor restarts it")
        let none = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: false)
        let granted = PermissionSnapshot(accessibility: true, inputMonitoring: false, screenRecording: true)
        r.permissions.value = PortPermissionState(accessibility: true, screenRecording: true)
        r.registry.permissionsChanged(PermissionChange(old: none, new: granted))
        #expect(r.log.events == ["ocr.stop", "resurface", "ocr", "surface"], "the grant restarts it (stop, then one start)")
        #expect(r.binding.availability("screenOCR") == true)
    }

    @Test func colorPickerNeedsNoPermissionAndSharesTheChooserWithoutSuspendingIt() {
        let r = rig(on: ["colorPicker"], screenRecording: false)
        defer { r.cleanup() }
        #expect(r.log.events == ["surface"], "no permission needed: the system sampler is the fallback")
        r.log.events.removeAll()
        r.registry.switches["colorPicker"] = false
        #expect(r.log.events == ["resurface"], "re-synced (a sibling tool keeps its shortcut), never suspended")
    }

    @Test func cameraStartsWithItsSafetyAndOffClosesThePreviewBeforeAnythingElse() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["cameraPreview"] = true
        r.registry.switches["cameraPreview"] = true
        #expect(r.log.events == ["camera", "watch"], "idempotent: one start")
        r.log.events.removeAll()
        r.registry.switches["cameraPreview"] = false
        #expect(r.log.events == ["unwatch", "camera.stop"])
        #expect(r.binding.availability("cameraPreview") == false)
    }

    @Test func theKillSwitchStopsTheCameraSessionAndTheFeatureComesBack() {
        let r = rig(on: ["cameraPreview", "screenOCR", "colorPicker"])
        defer { r.cleanup() }
        #expect(r.log.count("camera") == 1)
        r.log.events.removeAll()
        r.registry.killSwitch = true
        #expect(r.log.count("camera.stop") == 1, "the kill switch closes the preview: the capture session is released")
        #expect(r.log.count("ocr.stop") == 1)
        #expect(r.binding.availability("cameraPreview") == false && r.binding.availability("screenOCR") == false)
        r.log.events.removeAll()
        r.registry.killSwitch = false
        #expect(r.log.count("camera") == 1 && r.log.count("ocr") == 1, "and it comes back when released")
    }

    @Test func safeModeStopsTheCameraToo() {
        let r = rig(on: ["cameraPreview"])
        defer { r.cleanup() }
        r.log.events.removeAll()
        r.registry.safeMode = true
        #expect(r.log.events == ["unwatch", "camera.stop"])
        #expect(r.binding.availability("cameraPreview") == false)
    }

    @Test func aToggleOnAPortedPageCannotRestartWhatTheRegistryStopped() {
        PortHostFixture.isolated { defaults in
            let r = rig()
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.cameraPreview.availabilityKey)  // a stale stored switch
            #expect(AppFeature.cameraPreview.isAvailable == false, "the registry verdict, not the stored key")
            r.registry.switches["cameraPreview"] = true
            #expect(AppFeature.cameraPreview.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.cameraPreview.isAvailable == false, "CameraPreviewService.show() refuses")
        }
    }

    // MARK: Source gates: nothing prompts outside a click

    static func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
    }

    @Test func theBridgeFileCallsNoPromptApi() throws {
        let lines = codeLines(try Self.source("Sources/PortKit/Bridge/CaptureTools.swift"))
        let banned = PortPromptScrubTests.banned + ["requestAccess(", "requestAuthorization(", "requestFullAccess",
                                                    "consentToAutomate(", "NSWorkspace.shared.open(", "CGWindowList"]
        for api in banned {
            #expect(!lines.contains { $0.contains(api) }, "\(api)")
        }
        // The only prompt the pages can reach is Permissions.requestCamera, from the "Autoriser" button.
        let asks = lines.filter { $0.contains("requestCamera()") }
        #expect(asks.count == 1 && asks[0].contains("Button(\"Autoriser\")"), "\(asks)")
    }

    @Test func theCameraPromptLivesOnlyInTheClickMethodNotInBeginCapture() throws {
        let text = try Self.source("Sources/PortKit/Services/QuickTools/CameraPreviewService.swift")
        let begin = try #require(text.range(of: "private func beginCapture()"))
        let click = try #require(text.range(of: "func requestAccessByClick()"))
        #expect(begin.lowerBound < click.lowerBound)
        let beginBody = String(text[begin.lowerBound..<click.lowerBound])
        #expect(!beginBody.contains("requestAccess("), "a shortcut, a menu entry or a launch never asks")
        #expect(beginBody.contains("state = .needsPermission"))
        let sites = codeLines(text).filter { $0.contains("requestAccess(") }
        #expect(sites.count == 1, "one prompt site, the click method: \(sites)")
        #expect(text.range(of: "requestAccess(")!.lowerBound > click.lowerBound)
        let view = try Self.source("Sources/PortKit/UI/CameraPreview/CameraPreviewView.swift")
        #expect(view.contains("service.requestAccessByClick()"), "the panel's own Autoriser button")
    }

    @Test func aQRLinkOpensOnlyFromTheOpenButtonNeverFromReturn() throws {
        let text = try Self.source("Sources/PortKit/Services/QuickTools/QRResultController.swift")
        let open = try #require(text.range(of: "Button(strings.qrResultOpen, action: open)"))
        let after = String(text[open.upperBound...].prefix(120))
        #expect(!after.contains(".keyboardShortcut"), "Return must not open a link")
        let sites = codeLines(text).filter { $0.contains("NSWorkspace.shared.open(") }
        #expect(sites.count == 1)
        let fn = try #require(text.range(of: "private func open(_ url: URL)"))
        #expect(text.range(of: "NSWorkspace.shared.open(")!.lowerBound > fn.lowerBound, "only inside the click action")
        #expect(text.contains("Text(payload)"), "the decoded text is shown first")
    }

    @Test func theCameraEntitlementAndItsFrenchReasonShipInTheBundle() throws {
        let info = try #require(NSDictionary(contentsOf: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Resources/Info.plist")) as? [String: Any])
        let reason = try #require(info["NSCameraUsageDescription"] as? String)
        #expect(reason.contains("caméra") && reason.contains("rien n’est enregistré"))
        let entitlements = try #require(NSDictionary(contentsOf: PortSourceScrubTests.repoRoot
            .appendingPathComponent("Resources/MacIsland.entitlements")) as? [String: Any])
        #expect(entitlements["com.apple.security.device.camera"] as? Bool == true, "hardened runtime refuses the camera without it")
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true, "the existing key is untouched")
        let bundle = try Self.source("scripts/bundle.sh")
        #expect(bundle.contains("--entitlements Resources/MacIsland.entitlements"), "the app is signed with this file")
    }
}
