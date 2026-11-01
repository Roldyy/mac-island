import Foundation
import IslandKit
import Testing
@testable import PortKit

/// System Audio Recording: the probe reads a stored status and never asks, the one ask is the click path, and no
/// per-app tap (the thing that makes macOS prompt) is built before the click proved the grant.
@MainActor
@Suite(.serialized) struct MixerPermissionTests {
    // MARK: State table

    @Test func theStateIsAFunctionOfTheBundleAndTheStoredStatus() {
        typealias C = MixerAudioCapture
        #expect(C.state(evidence: nil, hasUsageDescription: false) == .needsBundledApp)
        #expect(C.state(evidence: 0, hasUsageDescription: false) == .needsBundledApp, "no description: the system cannot ask")
        #expect(C.state(evidence: nil, hasUsageDescription: true) == .notAsked)
        #expect(C.state(evidence: 0, hasUsageDescription: true) == .granted)
        #expect(C.state(evidence: -1, hasUsageDescription: true) == .denied(-1))
        #expect(C.state(evidence: 560_947_818, hasUsageDescription: true) == .denied(560_947_818))
        #expect(C.state(evidence: Int.max, hasUsageDescription: true) == .notAsked, "an unreadable status is never a grant")
    }

    @Test func onlyAProvenGrantAllowsTapsAndEveryOtherStateNamesTheExactMissingPermission() {
        let states: [MixerAudioCaptureState] = [.needsBundledApp, .notAsked, .granted, .denied(-1)]
        #expect(states.filter(\.allowsTaps) == [.granted])
        for state in states where state != .granted {
            #expect(state.missingPermission == "Enregistrement audio du système", "\(state)")
            let reason = state.reason ?? ""
            #expect(!reason.isEmpty && reason.hasPrefix("Volume par app"), "French reason for \(state)")
        }
        #expect(MixerAudioCaptureState.granted.missingPermission == nil && MixerAudioCaptureState.granted.reason == nil)
        #expect(MixerAudioCaptureState.notAsked.canRequest && MixerAudioCaptureState.denied(1).canRequest)
        #expect(!MixerAudioCaptureState.granted.canRequest && !MixerAudioCaptureState.needsBundledApp.canRequest)
        #expect(MixerAudioCaptureState.denied(-1).reason?.contains("code -1") == true)
    }

    @Test func readingTheStateAsksNothing() {
        PortHostFixture.isolated { defaults in
            #expect(MixerAudioCapture.currentState(defaults: defaults, hasUsageDescription: true) == .notAsked)
            defaults.set(0, forKey: MixerAudioCapture.evidenceKey)
            #expect(MixerAudioCapture.currentState(defaults: defaults, hasUsageDescription: true) == .granted)
            #expect(MixerAudioCapture.currentState(defaults: defaults, hasUsageDescription: false) == .needsBundledApp)
            // The test process has no bundle: nothing here ever reaches `AudioHardwareCreateProcessTap`.
            #expect(MixerAudioCapture.hasUsageDescription == false)
            #expect(MixerAudioCapture.allowsTaps == false, "the gate the mixer reads is closed without a click")
        }
    }

    // MARK: The click path

    @Test func theClickAsksOnceWithTheMixerOnAndStoresTheOutcome() {
        PortHostFixture.isolated { defaults in
            var probes = 0
            var panes = 0
            var grants = 0
            let state = MixerAudioCapture.requestByClick(
                defaults: defaults, hasUsageDescription: true, isAvailable: { true },
                probe: { probes += 1; return 0 }, openPane: { panes += 1 }, didGrant: { grants += 1 })
            #expect(state == .granted && probes == 1 && panes == 0 && grants == 1)
            #expect(defaults.object(forKey: MixerAudioCapture.evidenceKey) as? Int == 0)
            #expect(MixerAudioCapture.currentState(defaults: defaults, hasUsageDescription: true).allowsTaps)
        }
    }

    @Test func aRefusedProbeOpensThePaneAndKeepsTapsClosed() {
        PortHostFixture.isolated { defaults in
            var panes = 0
            var grants = 0
            let state = MixerAudioCapture.requestByClick(
                defaults: defaults, hasUsageDescription: true, isAvailable: { true },
                probe: { -50 }, openPane: { panes += 1 }, didGrant: { grants += 1 })
            #expect(state == .denied(-50) && panes == 1 && grants == 0)
            #expect(!MixerAudioCapture.currentState(defaults: defaults, hasUsageDescription: true).allowsTaps)
        }
    }

    @Test func nothingIsAskedWhileTheMixerIsSwitchedOffOrTheBundleCannotAsk() {
        PortHostFixture.isolated { defaults in
            var probes = 0
            let off = MixerAudioCapture.requestByClick(
                defaults: defaults, hasUsageDescription: true, isAvailable: { false },
                probe: { probes += 1; return 0 }, openPane: {}, didGrant: {})
            #expect(off == .notAsked && probes == 0, "behind the feature switch")
            let unbundled = MixerAudioCapture.requestByClick(
                defaults: defaults, hasUsageDescription: false, isAvailable: { true },
                probe: { probes += 1; return 0 }, openPane: {}, didGrant: {})
            #expect(unbundled == .needsBundledApp && probes == 0, "swift run: the system cannot prompt")
            #expect(defaults.object(forKey: MixerAudioCapture.evidenceKey) == nil, "no status written without a probe")
        }
    }

    // MARK: Source gates

    private static func sites(of marker: String) -> [String] {
        var found: [String] = []
        for file in PortSourceScrubTests.files {
            let code = file.lines.filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
            if code.contains(where: { $0.contains(marker) }) { found.append(file.path) }
        }
        return found.sorted()
    }

    @Test func processTapsAreCreatedOnlyByTheKnownFiles() {
        #expect(Self.sites(of: "AudioHardwareCreateProcessTap") == [
            "Bridge/Mixer.swift",  // the probe tap, click path only
            "Services/Audio/AppVolumeMixer.swift",  // per-app engines, behind the click gate (patch 0450)
            "Services/Notch/NotchAudioLevelService.swift",  // island lane, not bound
            "Services/Recorder/RecorderSystemAudioTap.swift",  // recorder lane, not bound
        ])
    }

    @Test func theProbeTapIsReachableFromTheClickPathOnly() {
        #expect(Self.sites(of: "probeTap") == ["Bridge/Mixer.swift"], "only the bridge names the probe")
        #expect(Self.sites(of: "requestByClick") == [
            "Bridge/IslandMusic.swift",  // the equalizer's own click, the one that proves the grant (patch 1601)
            "Bridge/Mixer.swift", "UI/MenuPanel/MixerSection.swift",
        ])
        let lines = PortSourceScrubTests.files.first { $0.path == "Bridge/Mixer.swift" }?.lines ?? []
        // `probeTap` is the definition's name and the default of `requestByClick`'s `probe` parameter, nothing else.
        let uses = lines.filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") && $0.contains("probeTap") }.count
        #expect(uses == 2, "a third use of the probe is a prompt outside the click")
    }

    @Test func theMixerBuildsNoTapBeforeTheGate() throws {
        let url = PortSourceScrubTests.portKit.appendingPathComponent("Services/Audio/AppVolumeMixer.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let gate = try #require(text.range(of: "guard MixerAudioCapture.allowsTaps"))
        let device = try #require(text.range(of: "let engine = TapGainEngine("))
        let airPlay = try #require(text.range(of: "let engine = AirPlayGainEngine("))
        #expect(gate.lowerBound < device.lowerBound && gate.lowerBound < airPlay.lowerBound,
                "both engine kinds are built after the gate")
        #expect(text.components(separatedBy: "TapGainEngine(objects:").count - 1 == 1, "one build site for device taps")
    }

    @Test func noMixerFileUsesAPromptApiOfTheOtherPermissions() {
        for path in ["Bridge/Mixer.swift", "Services/Audio/AppVolumeMixer.swift", "Services/Audio/AudioPriorityService.swift",
                     "Services/Audio/SoundOutputSwitcher.swift", "Services/Audio/AudioInputDeviceManager.swift",
                     "UI/MenuPanel/MixerSection.swift", "UI/MenuPanel/AudioPrioritySection.swift"] {
            let file = PortSourceScrubTests.files.first { $0.path == path }
            #expect(file != nil, "\(path)")
            for line in file?.lines ?? [] where !line.drop(while: { $0 == " " }).hasPrefix("//") {
                for banned in PortPromptScrubTests.banned + ["requestAccess(", "requestAuthorization(", "requestMicrophone"] {
                    #expect(!line.contains(banned), "\(path): \(banned)")
                }
            }
        }
    }
}
