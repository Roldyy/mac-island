// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import EventKit
import UserNotifications

/// Central place to read and open the TCC permissions the app uses.
/// Accessibility powers the scroll inverter and the switcher's event tap;
/// Screen Recording powers window titles and thumbnails in the switcher.
///
/// Mac Island: Accessibility, Input Monitoring and Screen Recording come from the host's `PermissionMonitor`
/// reading (`PortHost.permissionState`), so this class owns no timer and no observer for them, and no
/// `request*` call shows a system prompt: each one opens the matching System Settings pane.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    /// Input Monitoring, for the ported taps that listen to the keyboard. Read from the host like the others.
    @Published private(set) var inputMonitoring = false
    /// Optional — only used to make the uninstaller's scan more thorough by
    /// reaching protected locations. There is no API prompt for it; the user
    /// grants it in System Settings.
    @Published private(set) var fullDiskAccess = false
    /// Refreshed inside refresh() only (launch and activation); notifications
    /// have no cheap poll and the portal calls refresh() when it appears.
    @Published private(set) var notifications: NotificationPermissionState = .unknown
    /// Camera access for the preview mirror. The status read is free, so it
    /// rides the same refresh() moments as the rest.
    @Published private(set) var camera: CameraPermissionState = .unknown
    @Published private(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var requestingCalendar = false
    @Published private(set) var calendarRequestFailed = false
    private var calendarPermissionResolution: TimeInterval?

    var keepsCalendarPrompt: Bool {
        NotchSupport.keepsPermissionSurface(requesting: requestingCalendar,
                                            resolvedAt: calendarPermissionResolution,
                                            now: ProcessInfo.processInfo.systemUptime)
    }
    /// Optional microphone access, used only while a recording that asked for
    /// it is active.
    @Published private(set) var microphone: MicrophonePermissionState = .unknown

    enum NotificationPermissionState {
        case granted, denied, undetermined, unknown
    }

    enum CameraPermissionState {
        case granted, denied, undetermined, unknown
    }

    enum MicrophonePermissionState {
        case granted, denied, undetermined, unknown
    }

    private var hostObserver: AnyCancellable?
    private let hostState: CurrentValueSubject<PortPermissionState, Never>
    /// How a System Settings pane is opened (true when it opened), and how the guide card is floated. Swapped
    /// by tests, which must open no window.
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var showGuide: (PermissionKind) -> Void = { PermissionGuideOverlay.shared.show(for: $0) }

    private convenience init() {
        self.init(hostState: PortHost.permissionState, refreshOnInit: true)
    }

    /// `hostState` is where the host publishes its reading; `refreshOnInit` is false in tests, because
    /// `refresh()` probes Full Disk Access and the notification centre.
    init(hostState: CurrentValueSubject<PortPermissionState, Never>, refreshOnInit: Bool) {
        self.hostState = hostState
        apply(hostState.value)
        if refreshOnInit { refresh() }
        // The host pushes every reading of its `PermissionMonitor` (activation, the Accessibility notification
        // and its own poll), so a grant shows here without a timer or an observer of our own.
        // Full Disk Access is deliberately NOT polled here: it can only change
        // across a relaunch (a running process never gains or is meant to lose
        // it mid-session), and probing it touches protected paths, so polling it
        // would just be repeated denied accesses for no gain.
        hostObserver = hostState.sink { [weak self] state in self?.apply(state) }
    }

    /// Visible permission UI used to demand a faster poll; the host's monitor decides the cadence now, so
    /// showing the surface only takes a fresh reading.
    func setActivePermissionSurface(_ id: UUID, visible: Bool) {
        if visible { refreshActivePermissions() }
    }

    /// Full refresh including Full Disk Access. Runs at launch and on activation.
    func refresh() {
        refreshActivePermissions()
        refreshNotificationPermission()
        refreshCameraPermission()
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        refreshMicrophonePermission()
        // Checking Full Disk Access means asking the system about protected
        // folders, and every refused answer costs time. Doing that where the
        // app is starting up holds back the menu bar icon, so it moves off
        // and reports back.
        DispatchQueue.global(qos: .utility).async {
            let granted = Self.probeFullDiskAccess()
            DispatchQueue.main.async {
                if self.fullDiskAccess != granted { self.fullDiskAccess = granted }
            }
        }
    }

    private func refreshCameraPermission() {
        let state: CameraPermissionState
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.camera != state { self.camera = state }
        }
    }

    private func refreshMicrophonePermission() {
        let state: MicrophonePermissionState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: state = .granted
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .undetermined
        @unknown default: state = .unknown
        }
        DispatchQueue.main.async {
            if self.microphone != state { self.microphone = state }
        }
    }

    private func refreshNotificationPermission() {
        // Asking the system for the notification centre ends the process
        // outright when it cannot resolve this app, which is what happens
        // when the bundle is replaced or moved out from under a running copy.
        // An update does exactly that, so reporting nothing beats dying.
        guard Bundle.main.bundleIdentifier != nil,
              FileManager.default.fileExists(atPath: Bundle.main.bundlePath) else {
            if notifications != .unknown { notifications = .unknown }
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let state: NotificationPermissionState
            switch settings.authorizationStatus {
            case .authorized, .provisional: state = .granted
            case .denied: state = .denied
            case .notDetermined: state = .undetermined
            @unknown default: state = .unknown
            }
            DispatchQueue.main.async {
                if self?.notifications != state { self?.notifications = state }
            }
        }
    }

    /// Accessibility, Input Monitoring and Screen Recording: the host's latest reading, no system call.
    private func refreshActivePermissions() {
        apply(hostState.value)
    }

    private func apply(_ state: PortPermissionState) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.apply(state) }
            return
        }
        if accessibility != state.accessibility { accessibility = state.accessibility }
        if screenRecording != state.screenRecording { screenRecording = state.screenRecording }
        if inputMonitoring != state.inputMonitoring { inputMonitoring = state.inputMonitoring }
    }

    /// Protected directories safe to use both as access probes and as
    /// registration attempts. Request-only paths stay separate because every
    /// entry here must remain a reliable signal that access was granted.
    private static let fdaGatedDirectories = [
        "Library/Safari",
        "Library/Mail",
        "Library/Messages",
        "Library/Cookies",
        "Library/Suggestions",
        "Library/Application Support/MobileSync",
    ]

    /// Detects Full Disk Access without a prompt. Reading the TCC database is the
    /// classic signal, but that file is absent on some macOS versions (so a
    /// missing file would read as "no access" forever, even once granted). The
    /// dependable fallback is to list a protected directory that exists: that
    /// listing is denied without Full Disk Access and succeeds with it.
    private static func probeFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // Preferred when present: the TCC database is readable only with access.
        let tccDB = (home as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if let handle = FileHandle(forReadingAtPath: tccDB) {
            let ok = (try? handle.read(upToCount: 1)) != nil
            try? handle.close()
            if ok { return true }
        }

        // Works on every version: each of these is gated by Full Disk Access, so
        // a successful listing (even of an empty directory) means it is granted.
        let gatedDirs = fdaGatedDirectories.map { (home as NSString).appendingPathComponent($0) }
        return gatedDirs.contains { (try? fm.contentsOfDirectory(atPath: $0)) != nil }
    }

    /// Opens the Accessibility pane of System Settings (never the system prompt) and floats the little guide
    /// card for the round trip.
    func requestAccessibility() {
        openAccessibilitySettings()
        refreshActivePermissions()
        if !accessibility {
            showGuide(.accessibility)
        }
    }

    /// Opens the Screen Recording pane (never the system prompt) and floats the guide card, like the
    /// Accessibility path.
    func requestScreenRecording() {
        openScreenRecordingSettings()
        refreshActivePermissions()
        if !screenRecording {
            showGuide(.screenRecording)
        }
    }

    /// Opens the Input Monitoring pane. There is no read-only way to ask, and none is wanted.
    func requestInputMonitoring() {
        openInputMonitoringSettings()
    }

    /// Drops this app's entry from the list and asks again. The entry macOS
    /// keeps is bound to the app's code signature, so a copy signed
    /// differently (a local build, an update signed another way) finds the
    /// switch on and the permission gone; nothing short of removing the entry
    /// makes the system ask afresh. `tccutil` does that for the calling
    /// user's own entries with no privilege, and is the command Apple
    /// documents for the purpose.
    func startOver(_ kind: PermissionKind) {
        guard kind == .accessibility || kind == .screenRecording,
              let bundleID = Bundle.main.bundleIdentifier else { return }
        let service = kind == .accessibility ? "Accessibility" : "ScreenCapture"
        // Off the main thread through the bounded runner, like
        // `SelfUninstall.resetTCC`: a stuck tccutil must not hang the UI. The
        // hop back also lets the button's click finish before the card that
        // holds the button is rebuilt by the new request.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Shell.run("/usr/bin/tccutil", ["reset", service, bundleID])
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshActivePermissions()
                if kind == .accessibility { self.requestAccessibility() } else { self.requestScreenRecording() }
            }
        }
    }

    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    func openInputMonitoringSettings() {
        open(pane: "Privacy_ListenEvent")
    }

    func openFullDiskAccessSettings() {
        open(pane: "Privacy_AllFiles")
    }

    func openFilesAndFoldersSettings() {
        open(pane: "Privacy_FilesAndFolders")
    }

    /// Full Disk Access has no prompt API, and an app only shows up (toggled
    /// off) in its System Settings list once it has attempted to read a
    /// protected location. Touch likely protected paths to register the app,
    /// then open the pane after a short delay so tccd has recorded the denial
    /// before System Settings reads the list. If it still does not appear, the
    /// user can add the app with the list's "+" button.
    func requestFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            let fm = FileManager.default
            // The TCC database is the classic trigger when present. Some macOS
            // versions omit it, so the protected directories below are the
            // fallback registration attempts.
            let tccDB = (home as NSString)
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            _ = try? Data(contentsOf: URL(fileURLWithPath: tccDB), options: .mappedIfSafe)
            if let handle = FileHandle(forReadingAtPath: tccDB) {
                _ = try? handle.read(upToCount: 1)
                try? handle.close()
            }
            // Protected locations, harmless when absent. The TCC directory is
            // useful for registration but is not part of the access probe.
            let dirs = (["Library/Application Support/com.apple.TCC"] + Self.fdaGatedDirectories)
                .map { (home as NSString).appendingPathComponent($0) }
            for path in dirs { _ = try? fm.contentsOfDirectory(atPath: path) }

            // Let tccd persist the denial before the pane loads its list.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.openFullDiskAccessSettings()
            }
        }
    }

    /// Reading calendar events requires full access even though the app never writes them.
    func requestCalendar() {
        guard !requestingCalendar else { return }
        requestingCalendar = true
        calendarRequestFailed = false
        let store = EKEventStore()
        store.requestFullAccessToEvents { [weak self, store] _, error in
            _ = store
            DispatchQueue.main.async {
                self?.calendarPermissionResolution = ProcessInfo.processInfo.systemUptime
                self?.requestingCalendar = false
                let status = EKEventStore.authorizationStatus(for: .event)
                self?.calendarRequestFailed = NotchCalendarSupport.requestFailed(status: status, hasError: error != nil)
                self?.calendarAccess = status
            }
        }
    }

    func openCalendarSettings() {
        open(pane: "Privacy_Calendars")
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func requestMicrophone(completion: ((Bool) -> Void)? = nil) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphone = granted ? .granted : .denied
                completion?(granted)
            }
        }
    }

    func openCameraSettings() {
        open(pane: "Privacy_Camera")
    }

    func openMicrophoneSettings() {
        open(pane: "Privacy_Microphone")
    }

    func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        _ = openURL(url)
    }

    func openAutomationSettings() {
        open(pane: "Privacy_Automation")
    }

    func openAudioCaptureSettings() {
        open(pane: "Privacy_AudioCapture")
    }

    func openAppManagementSettings() {
        let pane = URL(string:
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles")!
        if openURL(pane) { return }

        // A general Privacy & Security page is still useful if a future macOS
        // version stops accepting the pane identifier.
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        _ = openURL(fallback)
    }

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        _ = openURL(url)
    }

    // MARK: - Automation (Apple Events)

    enum AutomationTarget: String, CaseIterable {
        case finder = "com.apple.finder"
        case terminal = "com.apple.Terminal"
    }

    enum AutomationStatus {
        case granted, denied, undetermined, notDeterminable
    }

    /// Never prompts (askUserIfNeeded false). A target that is not running
    /// cannot be checked and reads as notDeterminable. Call off the main
    /// thread; the check can block briefly.
    static func automationStatus(for target: AutomationTarget) -> AutomationStatus {
        var descriptor = AEAddressDesc()
        let bundleID = target.rawValue
        let created = bundleID.withCString { pointer in
            AECreateDesc(typeApplicationBundleID, pointer, bundleID.utf8.count, &descriptor)
        }
        guard created == noErr else { return .notDeterminable }
        defer { AEDisposeDesc(&descriptor) }
        switch AEDeterminePermissionToAutomateTarget(&descriptor, typeWildCard, typeWildCard, false) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .undetermined
        default: return .notDeterminable
        }
    }
}
