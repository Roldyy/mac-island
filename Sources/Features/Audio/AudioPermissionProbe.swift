import CoreAudio
import Foundation

/// Asks the system for audio capture by creating, then destroying, one harmless tap
/// (global, unmuted, private). Only ever called from a user click.
enum AudioPermissionProbe {
    static var hasUsageDescription: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String
        return !(value ?? "").isEmpty
    }

    /// OSStatus of the tap creation (0 = created). What status a denial returns is UNKNOWN.
    static func probe() -> Int32 {
        guard #available(macOS 14.2, *) else { return -1 }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "MacIsland permission probe"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        if status == noErr { AudioHardwareDestroyProcessTap(tapID) }
        return status
    }
}
