import IslandKit
import Testing
@testable import ShellKit

/// The "Autoriser" click for System Audio Recording goes to the handler the app plugs in (the mixer's probe tap), and
/// to nothing else: ShellKit itself never creates a tap. Only the hooked path is exercised here, because the
/// unhooked one opens System Settings.
@MainActor
@Suite(.serialized) struct AudioCaptureRequestTests {
    @Test func theClickGoesToTheHandlerAndOpensNothingItself() {
        let saved = UserPermissionRequest.audioCaptureRequest
        defer { UserPermissionRequest.audioCaptureRequest = saved }
        var calls = 0
        UserPermissionRequest.audioCaptureRequest = { calls += 1 }
        UserPermissionRequest.request(FeaturePermission.audioCapture)
        #expect(calls == 1)
    }

    @Test func audioCaptureIsNotOneOfTheThreeMonitoredPermissions() {
        // No read-only probe exists for it, so the monitor never polls it and the registry never gates on it.
        #expect(MonitoredPermission(.audioCapture) == nil)
        let probe = PermissionProbe(accessibility: { false }, screenRecording: { false }, automation: { _ in nil })
        let descriptor = FeatureDescriptor(id: "x", title: "x", summary: "x", systemImage: "x", category: .sound,
                                           permissions: [.audioCapture])
        #expect(SystemCapabilities.capability(for: descriptor, probe: probe) == .available)
    }
}
