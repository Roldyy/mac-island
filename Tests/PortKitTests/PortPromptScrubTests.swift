import Foundation
import Testing

/// Mac Island never triggers a system permission prompt from ported code. The ported `request*` calls open
/// System Settings instead (patch 0013), and these source gates keep a re-import from bringing a prompt back.
@Suite struct PortPromptScrubTests {
    /// Prompts for the three permissions the `PermissionMonitor` owns (Accessibility, Input Monitoring, Screen
    /// Recording) and the private Input Monitoring request: banned everywhere in PortKit, code lines only.
    static let banned = [
        "kAXTrustedCheckOptionPrompt", "AXIsProcessTrustedWithOptions",
        "CGRequestScreenCaptureAccess", "CGRequestListenEventAccess", "CGRequestPostEventAccess",
        "IOHIDRequestAccess",
    ]

    /// The prompts of the other permissions. None of them is reachable from a bound feature yet; each belongs to a
    /// later lane, which replaces it with a pane opening or a read-only check and removes the entry here. A NEW
    /// site fails until someone reads it.
    static let knownOtherPromptSites: [String: Int] = [
        "Core/Permissions.swift": 3,  // requestCalendar, requestCamera, requestMicrophone (calendar, camera, mic lanes)
        "Services/Notifier.swift": 1,  // UNUserNotificationCenter.requestAuthorization (notifications lane)
        "Services/QuickTools/CameraPreviewService.swift": 1,  // AVCaptureDevice.requestAccess (camera lane)
        // Automation consent (`AppleScriptRunner.consentToAutomate`, the Apple Events prompt) and its definition.
        "Services/ShellSupport.swift": 1,
        "Services/Notch/NotchMusicService.swift": 1, "Services/Notch/NotchShuffleService.swift": 3,  // music lanes
        "Services/Uninstall/AppUninstaller.swift": 1, "Services/Cleaner/JunkCleaner.swift": 2,  // apps lane
        "Services/Finder/FinderCutPaste.swift": 3,  // Finder lane
    ]

    private static func isCode(_ line: Substring) -> Bool {
        !line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//")
    }

    @Test func noPromptApiForAccessibilityInputMonitoringOrScreenRecording() {
        var offenders: [String] = []
        for file in PortSourceScrubTests.files {
            for (index, line) in file.lines.enumerated() where Self.isCode(line) {
                if Self.banned.contains(where: { line.contains($0) }) { offenders.append("\(file.path):\(index + 1)") }
            }
        }
        #expect(offenders.isEmpty, "a system prompt in ported code: \(offenders)")
    }

    @Test func otherPromptSitesAreTheKnownOnes() {
        let markers = ["requestAccess(", "requestFullAccessToEvents", "requestAuthorization(", "consentToAutomate("]
        var found: [String: Int] = [:]
        for file in PortSourceScrubTests.files where !file.path.hasPrefix("Bridge/") {
            for line in file.lines where Self.isCode(line) && markers.contains(where: { line.contains($0) }) {
                found[file.path, default: 0] += 1
            }
        }
        #expect(found == Self.knownOtherPromptSites, "prompt sites changed: \(found)")
    }

    @Test func noPortedFileWritesAnAvailabilitySwitchItself() {
        // `shell.enabled.<id>` belongs to the FeatureRegistry: a write is a `PortHost.setEnabled` call.
        var offenders: [String] = []
        for file in PortSourceScrubTests.files where !file.path.hasPrefix("Bridge/") {
            for (index, line) in file.lines.enumerated() where Self.isCode(line) {
                if line.contains("availabilityKey"), line.contains(".set(") || line.contains("setValue") {
                    offenders.append("\(file.path):\(index + 1)")
                }
                if line.contains("\"shell.enabled.") && !line.contains("var availabilityKey") {
                    offenders.append("\(file.path):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "direct switch write: \(offenders)")
    }

    @Test func noPortedFileReadsTheStandardDomainForAPreferenceKey() {
        // Patch 0015: the ported code reads `PortHost.defaults`. Two global-domain reads and two hand-written
        // Compat files are the only `UserDefaults.standard` left.
        var found: [String: Int] = [:]
        for file in PortSourceScrubTests.files {
            for line in file.lines where Self.isCode(line) && line.contains("UserDefaults.standard") {
                found[file.path, default: 0] += 1
            }
        }
        let allowed: [String: Int] = [
            "Services/Audio/PreciseVolumeRollerService.swift": 1,  // com.apple.sound.beep.feedback (global domain)
            "Services/DockPreview/DockPreviewService.swift": 1,  // com.apple.dock domain
            "Compat/BlackHoleGlyph.swift": 1, "Compat/StatusItemController.swift": 1,  // menu bar icon, not bound
        ]
        #expect(found == allowed, "\(found)")
    }
}
