import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W4B (recorder): `screenRecorder` bound through `PortFeatureBinding` with a fake runtime and a real
/// `FeatureRegistry`. No ScreenCaptureKit, no AVFoundation, no window, no hotkey, no permission prompt.
@MainActor
@Suite(.serialized) struct RecorderLaneTests {
    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let safety: SafetyRig
        let log: Log
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
        var control: FakeRecorderControl { safety.control }
    }

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true, screenRecording: true),
             switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let safety = SafetyRig()
        let log = Log()
        let runtime = RecorderLane.Runtime.make(
            control: safety.control, safety: safety.safety,
            recover: { log.events.append("recover") }, arm: { log.events.append("arm") },
            disarm: { log.events.append("disarm") }, syncCapture: { log.events.append("syncCapture") })
        RecorderLane.bind(into: binding, runtime: runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { registry.switches["screenRecorder"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, safety: safety, log: log, permissions: permissions,
                   cleanup: { safety.cleanup(); bench.cleanup(); marker.clear() })
    }

    func change(_ rig: Rig, to new: PortPermissionState) {
        let old = rig.permissions.value
        rig.permissions.value = new
        rig.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: old.accessibility, inputMonitoring: old.inputMonitoring,
                                    screenRecording: old.screenRecording),
            new: PermissionSnapshot(accessibility: new.accessibility, inputMonitoring: new.inputMonitoring,
                                    screenRecording: new.screenRecording)))
    }

    // MARK: Descriptor, permission and page tables

    @Test func theDescriptorIsFrenchOffByDefaultAndNamesEveryPermissionItCanUse() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            let safety = SafetyRig()
            defer { safety.cleanup() }
            RecorderLane.bind(into: binding, runtime: .make(control: safety.control, safety: safety.safety, recover: {}))
            #expect(binding.descriptors.map(\.id) == ["screenRecorder"])
            let d = binding.descriptors[0]
            #expect(d.category == .tools)
            #expect(d.permissions == [.screenRecording, .accessibility, .audioCapture, .microphone])
            #expect(d.risk == .touchesInput)
            #expect(!d.enabledByDefault && d.tabID == nil)
            #expect(!d.title.isEmpty && !d.summary.isEmpty)
            #expect(binding.availability("screenRecorder") == false, "bound: the registry's verdict, off until started")
        }
    }

    @Test func page15IsTheRecorderPageAndCarriesTheFeatureCard() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        let pages = r.binding.pages
        #expect(pages.count == 1)
        #expect(pages[0].pageID == "recording" && pages[0].featureID == "screenRecorder")
        let row = SettingsPageCatalog.page("recording")
        #expect(row?.title == "Enregistrement de l’écran")
        #expect(RecorderLane.pageID == "recording")
    }

    @Test func theLaneIsInTheLaneListAndTheRegistryIdIsTheUpstreamId() throws {
        #expect(AppFeature.screenRecorder.registryID == "screenRecorder")
        #expect(!PortFeatureIDs.isOwnedByExistingModule("screenRecorder"), "new to Mac Island: the binding adds the descriptor")
        let lanes = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"),
                               encoding: .utf8)
        #expect(lanes.contains("RecorderLane.bind(into:)"))
        #expect(RecorderLane.source == AppFeature.screenRecorder.registryID, "the island item belongs to the feature")
    }

    // MARK: Start and stop through the registry

    @Test func nothingStartsBeforeTheSwitchIsOn() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(r.log.events.isEmpty && r.control.syncs == 0 && r.control.observerCount == 0)
        #expect(r.binding.availability("screenRecorder") == false)
    }

    @Test func switchingOnRecoversArmsAndSyncsOnceAndOffStopsSavesAndDisarms() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["screenRecorder"] = true
        r.registry.switches["screenRecorder"] = true
        #expect(r.log.events == ["recover", "arm", "syncCapture"], "idempotent: one start, recovery before anything else")
        #expect(r.control.syncs == 1 && r.control.observerCount == 1, "the supervisor is armed")
        #expect(r.binding.availability("screenRecorder") == true)
        r.log.events.removeAll()
        r.registry.switches["screenRecorder"] = false
        #expect(r.control.stopReasons.count == 1, "a recording in progress is stopped (saved), never dropped")
        #expect(r.log.events == ["syncCapture", "disarm"])
        #expect(r.control.syncs == 2 && r.control.observerCount == 0, "the upstream sync closes the editors, the supervisor is gone")
        #expect(r.binding.availability("screenRecorder") == false)
        r.registry.switches["screenRecorder"] = false
        #expect(r.log.count("disarm") == 1, "a second off changes nothing")
    }

    @Test func theStopReasonOfASwitchOffSaysTheVideoIsSaved() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["screenRecorder"] = false
        let reason = r.control.stopReasons.first ?? nil
        #expect(reason?.hasPrefix("Enregistrement arrêté") == true && reason?.hasSuffix("La vidéo est enregistrée.") == true)
    }

    @Test func theKillSwitchStopsARunningRecordingCleanlyAndTakesEverySignDown() {
        let r = rig()
        defer { r.cleanup() }
        r.control.emit(RecorderState(isRecording: true, isPaused: false, elapsedSeconds: 42))
        #expect(r.safety.island.posted.last?.leading?.text == "Enregistrement 0:42")
        #expect(r.safety.hotkey.isRegistered && r.safety.status.shown.count == 1)
        r.registry.killSwitch = true
        #expect(r.control.stopReasons.count == 1, "the recorder is told to stop and save")
        #expect(r.control.state == RecorderState(), "and it is no longer recording")
        #expect(r.safety.island.withdrawn == ["screenRecorder.recording"], "the closed island shows nothing")
        #expect(r.safety.status.hides == 1 && !r.safety.hotkey.isRegistered, "nor the menu bar, nor the shortcut")
        #expect(r.binding.availability("screenRecorder") == false)
        r.registry.killSwitch = false
        #expect(r.log.events.filter { $0 == "recover" }.count == 2, "back on: the lane starts again, recovery first")
        #expect(r.control.observerCount == 1)
    }

    @Test func safeModeStopsARunningRecordingToo() {
        let r = rig()
        defer { r.cleanup() }
        r.control.emit(RecorderState(isRecording: true, isPaused: false, elapsedSeconds: 3))
        r.registry.safeMode = true
        #expect(r.control.stopReasons.count == 1 && r.control.state == RecorderState())
        #expect(r.safety.island.withdrawn.count == 1)
    }

    @Test func aMissingPermissionNeverStartsAndTheGrantStartsOnceTheRevokeStopsTheRecording() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        // The registry calls the stop of a feature that cannot run (idempotent, nothing to stop); it never starts it.
        func started() -> Bool { r.log.events.contains("recover") || r.log.events.contains("arm") }
        #expect(!started() && r.control.observerCount == 0, "Screen Recording and Accessibility are read, never asked")
        change(r, to: PortPermissionState(accessibility: true, screenRecording: false))
        #expect(!started() && r.control.observerCount == 0, "Accessibility alone is not enough")
        change(r, to: PortPermissionState(accessibility: true, screenRecording: true))
        #expect(Array(r.log.events.suffix(3)) == ["recover", "arm", "syncCapture"], "the grant starts it, recovery first")
        #expect(r.log.count("recover") == 1 && r.control.observerCount == 1)
        r.control.emit(RecorderState(isRecording: true, isPaused: false, elapsedSeconds: 7))
        let stops = r.control.stopReasons.count
        r.log.events.removeAll()
        change(r, to: PortPermissionState(accessibility: true, screenRecording: false))
        #expect(r.control.stopReasons.count == stops + 1 && r.control.state == RecorderState(), "a revoke ends the recording")
        #expect(r.log.events == ["syncCapture", "disarm"])
        #expect(r.control.observerCount == 0 && r.safety.island.withdrawn == ["screenRecorder.recording"])
    }

    @Test func theBindingNeverAsksForAPermissionItself() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        // The registry's state says what is missing; the click on "Autoriser" (feature card) does the asking.
        #expect(r.registry.state(for: "screenRecorder") == .needsPermission(.screenRecording)
                || r.registry.state(for: "screenRecorder") == .needsPermission(.accessibility))
    }

    // MARK: No prompt, no network (source contract)

    private func code(_ relative: String) throws -> [String] {
        let url = PortSourceScrubTests.portKit.appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
    }

    private func recorderFiles() -> [String] {
        PortSourceScrubTests.files.map(\.path).filter {
            $0.hasPrefix("Services/Recorder/") || $0.hasPrefix("UI/Recorder/") || $0 == "UI/Settings/ScreenRecorderSettings.swift"
        }
    }

    @Test func theLaneFileUsesNoPromptApiAndNoNetwork() throws {
        let banned = PortPromptScrubTests.banned + ["requestAccess(", "AVCaptureDevice", "requestMicrophone", "requestCamera",
                                                   "requestAuthorization(", "URLSession", "NSAppleScript", "consentToAutomate",
                                                   "probeTap", "AudioHardwareCreateProcessTap", "ByClick(isAvailable"]
        let clickRequests = try code("Bridge/Recorder.swift").filter { $0.contains("requestByClick") }
        #expect(clickRequests.isEmpty, "the mixer's click is the only door to the probe tap (MixerPermissionTests pins it)")
        for line in try code("Bridge/Recorder.swift") {
            for word in banned { #expect(!line.contains(word), "\(word) in: \(line)") }
        }
    }

    @Test func theRecorderServicesNeverAskForTheMicrophoneAndNeverBuildATapBeforeAClick() throws {
        for path in recorderFiles() where path.hasPrefix("Services/Recorder/") || path.hasPrefix("UI/Recorder/") {
            for line in try code(path) {
                #expect(!line.contains("requestMicrophone") && !line.contains("AVCaptureDevice.requestAccess"), "\(path)")
            }
        }
        let tap = try code("Services/Recorder/RecorderSystemAudioTap.swift").joined(separator: "\n")
        let makeRange = try #require(tap.range(of: "static func make(hearing pid: pid_t?) async"))
        let guardRange = try #require(tap.range(of: "guard MixerAudioCapture.allowsTaps else { return nil }"))
        let createRange = try #require(tap.range(of: "AudioHardwareCreateProcessTap"))
        #expect(makeRange.lowerBound < guardRange.lowerBound && guardRange.lowerBound < createRange.lowerBound,
                "no tap, and so no system prompt, before a click proved System Audio Recording")
    }

    @Test func theMicrophoneIsAskedOnlyByTheSettingsPageOnAClick() throws {
        let page = try code("UI/Settings/ScreenRecorderSettings.swift").joined(separator: "\n")
        #expect(page.contains("permissions.requestMicrophone()"), "the toggle and the row are the click")
        let service = try code("Services/Recorder/ScreenRecorderService.swift").joined(separator: "\n")
        #expect(service.contains("case .undetermined, .denied, .unknown:"), "a recording start never asks")
    }

    @Test func theOnlyHostInTheRecorderCodeIsTheUnreachableSharingOne() throws {
        for path in recorderFiles() {
            for line in try code(path) where line.contains("http://") || line.contains("https://") {
                #expect(line.contains(".invalid"), "\(path): \(line)")
            }
        }
        #expect(RecordingSharingSupport.productionEndpoint.host?.hasSuffix(".invalid") == true)
        #expect(RecordingShareService.isAvailable == false, "no upload exists")
    }

    @Test func theShareButtonsAreHiddenWhileSharingIsUnavailable() throws {
        let editor = try code("UI/Recorder/RecorderEditorView.swift").joined(separator: "\n")
        #expect(editor.contains("if sharingEnabled, RecordingShareService.isAvailable {"))
        let page = try code("UI/Settings/ScreenRecorderSettings.swift").joined(separator: "\n")
        #expect(page.contains("if RecordingShareService.isAvailable {"))
    }

    // MARK: Resources

    @Test func theResourceFilesCarryTheMicrophoneKeysAndTheBundleSignsWithThem() throws {
        let root = PortSourceScrubTests.repoRoot
        let info = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/Info.plist")))
        let mic = try #require(info["NSMicrophoneUsageDescription"] as? String)
        #expect(!mic.isEmpty && mic.contains("micro"), "French text that names the microphone")
        let audio = try #require(info["NSAudioCaptureUsageDescription"] as? String)
        #expect(!audio.contains("never records"), "the system-audio text no longer denies recording")
        let entitlements = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/MacIsland.entitlements")))
        #expect(entitlements["com.apple.security.device.audio-input"] as? Bool == true)
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true, "the other lanes' keys stay")
        let bundle = try String(contentsOf: root.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        #expect(bundle.contains("--entitlements Resources/MacIsland.entitlements"), "the app is signed with that file")
        #expect(bundle.contains("--options runtime"), "hardened runtime: the audio-input entitlement is required")
    }

    @Test func nothingElseIsGrantedByTheRecorderBlock() throws {
        let root = PortSourceScrubTests.repoRoot
        let entitlements = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Resources/MacIsland.entitlements")))
        let recorderKeys = entitlements.allKeys.compactMap { $0 as? String }.filter {
            $0.contains("audio-input") || $0.contains("screen") || $0.contains("device")
        }
        #expect(recorderKeys.contains("com.apple.security.device.audio-input"))
        #expect(!recorderKeys.contains { $0.contains("screen") }, "Screen Recording is a TCC grant, not an entitlement")
    }
}
