import Combine
import Foundation
import Testing
@testable import PortKit

/// `Permissions.shared` after patch 0013/0016: it follows the host's `PermissionMonitor` reading, owns no timer
/// and no observer, and none of its `request*` calls prompts. Fakes only: no pane, no overlay, no probe.
@Suite(.serialized) @MainActor struct PortPermissionsTests {
    private func make(refreshOnInit: Bool = false)
        -> (permissions: Permissions, host: CurrentValueSubject<PortPermissionState, Never>, opened: Box<[URL]>, guides: Box<[String]>) {
        let host = CurrentValueSubject<PortPermissionState, Never>(PortPermissionState())
        let permissions = Permissions(hostState: host, refreshOnInit: refreshOnInit)
        let opened = Box<[URL]>([])
        let guides = Box<[String]>([])
        permissions.openURL = { url in opened.value.append(url); return true }
        permissions.showGuide = { kind in guides.value.append("\(kind)") }
        return (permissions, host, opened, guides)
    }

    @Test func followsTheHostReadingAndNothingElse() {
        let r = make()
        #expect(!r.permissions.accessibility && !r.permissions.screenRecording && !r.permissions.inputMonitoring)
        r.host.send(PortPermissionState(accessibility: true, inputMonitoring: false, screenRecording: false))
        #expect(r.permissions.accessibility && !r.permissions.screenRecording && !r.permissions.inputMonitoring)
        r.host.send(PortPermissionState(accessibility: true, inputMonitoring: true, screenRecording: true))
        #expect(r.permissions.screenRecording && r.permissions.inputMonitoring)
        r.host.send(PortPermissionState())
        #expect(!r.permissions.accessibility, "a revoke shows too")
    }

    @Test func startsFromTheCurrentReadingWithoutWaitingForAChange() {
        let host = CurrentValueSubject<PortPermissionState, Never>(PortPermissionState(accessibility: true))
        let permissions = Permissions(hostState: host, refreshOnInit: false)
        #expect(permissions.accessibility)
    }

    @Test func requestsOpenThePaneAndNeverPrompt() {
        let r = make()
        r.permissions.requestAccessibility()
        r.permissions.requestScreenRecording()
        r.permissions.requestInputMonitoring()
        let panes = r.opened.value.map(\.absoluteString)
        #expect(panes.count == 3)
        #expect(panes[0].hasSuffix("Privacy_Accessibility"), "\(panes)")
        #expect(panes[1].hasSuffix("Privacy_ScreenCapture"), "\(panes)")
        #expect(panes[2].hasSuffix("Privacy_ListenEvent"), "\(panes)")
        #expect(panes.allSatisfy { $0.hasPrefix("x-apple.systempreferences:") })
        #expect(r.guides.value.count == 2, "the guide card follows the two that have one")
    }

    @Test func noGuideCardOnceTheHostSaysGranted() {
        let r = make()
        r.host.send(PortPermissionState(accessibility: true, screenRecording: true))
        r.permissions.requestAccessibility()
        r.permissions.requestScreenRecording()
        #expect(r.guides.value.isEmpty)
        #expect(r.opened.value.count == 2, "the pane still opens")
    }

    @Test func aPermissionSurfaceOnlyTakesAFreshReading() {
        let r = make()
        r.permissions.setActivePermissionSurface(UUID(), visible: true)
        r.permissions.setActivePermissionSurface(UUID(), visible: false)
        #expect(r.opened.value.isEmpty && r.guides.value.isEmpty)
    }

    @Test func theSourceHoldsNoPromptNoTimerNoObserverForTheThreeMonitoredPermissions() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Core/Permissions.swift"),
                              encoding: .utf8)
        let code = text.split(separator: "\n").filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }.joined(separator: "\n")
        for banned in ["Timer(", "addObserver(", "AXIsProcessTrusted", "CGPreflight", "kAXTrustedCheckOptionPrompt",
                       "CGRequest", "didBecomeActive"] {
            #expect(!code.contains(banned), "Permissions.swift still has \(banned)")
        }
    }
}
