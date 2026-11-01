// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W1B (mouse). The lane owns this file.

import AppKit
import SwiftUI

/// What the registry does to each of the six mouse features: the upstream service's start and stop, plus the
/// capability probe of the one feature that uses a private framework. `live` is the real ported services; tests
/// pass fakes, so nothing here needs a tap, a HID device or a permission to be exercised.
struct InputMouseRuntime {
    struct Hooks {
        let start: @MainActor () -> Void
        let stop: @MainActor () -> Void
    }

    var hooks: [AppFeature: Hooks]
    /// Why three-finger middle click cannot work on this Mac (private MultitouchSupport missing), nil when it can.
    var middleClickUnavailableReason: () -> String?

    static let live = InputMouseRuntime(
        hooks: [
            // `stop()` puts every pointer value back through the recovery journal, then ends the guard child.
            .mouseAcceleration: Hooks(
                start: { MouseAccelerationService.shared.syncWithPreferences() },
                stop: { MouseAccelerationService.shared.stop() }),
            // `suspend()` tears the tap down at once; `stop()` of the button service may keep it alive to drain.
            .mouseNavigation: Hooks(
                start: { MouseNavigationService.shared.syncWithPreferences() },
                stop: { MouseNavigationService.shared.suspend() }),
            .mouseButtonShortcuts: Hooks(
                start: { MouseButtonShortcutService.shared.syncWithPreferences() },
                stop: { MouseButtonShortcutService.shared.suspend() }),
            .middleClick: Hooks(
                start: { MiddleClickService.shared.syncWithPreferences() },
                stop: { MiddleClickService.shared.suspend() }),
            .mouseClickDebounce: Hooks(
                start: { MouseClickDebounceService.shared.syncWithPreferences() },
                stop: { MouseClickDebounceService.shared.suspend() }),
            .focusFollowsMouse: Hooks(
                start: { FocusFollowsMouseService.shared.syncWithPreferences() },
                stop: { FocusFollowsMouseService.shared.stop() }),
        ],
        middleClickUnavailableReason: { Multitouch.unavailableReason })
}

/// Binds this lane's six ported features. Called once at launch by `PortLanes`, before the registry exists.
enum InputMouseLane {
    /// Upstream feature -> our Settings page id (`SettingsPageCatalog`).
    static let pageIDs: [AppFeature: String] = [
        .middleClick: "middleclick",
        .focusFollowsMouse: "focusfollows",
        .mouseAcceleration: "noaccel",
        .mouseNavigation: "sidebuttons",
        .mouseButtonShortcuts: "mouseshortcuts",
        .mouseClickDebounce: "clickfilter",
    ]

    static let features: [AppFeature] = [
        .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .middleClick, .mouseClickDebounce,
        .focusFollowsMouse,
    ]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: InputMouseRuntime) {
        for feature in features {
            guard let hooks = runtime.hooks[feature], let pageID = pageIDs[feature] else { continue }
            var start = hooks.start
            if feature == .middleClick {
                // Capability probe: a Mac whose MultitouchSupport is gone gets no start at all, and the page says why.
                let probe = runtime.middleClickUnavailableReason
                let inner = hooks.start
                start = { if probe() == nil { inner() } }
            }
            binding.bind(feature, page: PortFeaturePage(pageID: pageID) { page(for: feature) },
                         start: start, stop: hooks.stop)
        }
    }

    @MainActor private static func page(for feature: AppFeature) -> AnyView {
        switch feature {
        case .mouseAcceleration: AnyView(MouseAccelerationPage())
        case .mouseNavigation: AnyView(MouseNavigationPage())
        case .mouseButtonShortcuts: AnyView(MouseButtonShortcutsSection())
        case .middleClick: AnyView(MiddleClickPage())
        case .mouseClickDebounce: AnyView(MouseClickDebouncePage())
        case .focusFollowsMouse: AnyView(FocusFollowsMousePage())
        default: AnyView(EmptyView())
        }
    }
}

// MARK: - Pages (upstream cards of `MouseSettings`, one per Mac Island page)

private struct MouseAccelerationPage: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.mouseAccelerationDisabled) private var disabled = false

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "cursorarrow.motionlines", title: l10n.s.mouseAccelerationName,
                        caption: l10n.s.mouseAccelerationCaption) {
                Toggle(l10n.s.mouseAccelerationName, isOn: $disabled)
                    .labelsHidden()
                    .onChange(of: disabled) { _, _ in MouseAccelerationService.shared.syncWithPreferences() }
            }
        }
        .toggleStyle(.switch)
    }
}

private struct MouseNavigationPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MouseNavigationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.mouseNavigationEnabled) private var enabled = false

    var body: some View {
        SettingsCard(title: l10n.s.mouseNavigationSection) {
            SettingsRow(symbol: "arrowshape.turn.up.left", title: l10n.s.mouseNavigationEnable,
                        caption: l10n.s.mouseNavigationCaption) {
                Toggle(l10n.s.mouseNavigationEnable, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, on in
                        MouseNavigationService.shared.syncWithPreferences()
                        if on { permissions.requestAccessibility() }
                    }
            }
            if enabled, service.isRunning { ActiveBadge(text: l10n.s.mouseNavigationActiveNow) }
            if enabled { MouseExceptionsList(scope: .navigation) }
        }
        .toggleStyle(.switch)
    }
}

private struct MouseClickDebouncePage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.mouseClickDebounceEnabled) private var enabled = false
    @AppStorage(DefaultsKey.mouseClickDebounceWindowMs) private var window =
        Defaults.defaultMouseClickDebounceWindowMs

    private var text: MouseClickDebounceStrings { FeatureStrings.mouseClickDebounce(l10n.language) }

    private var windowBinding: Binding<Int> {
        Binding(
            get: { Defaults.sanitizedMouseClickDebounceWindow(window) },
            set: {
                window = Defaults.sanitizedMouseClickDebounceWindow($0)
                MouseClickDebounceService.shared.syncWithPreferences()
            })
    }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "cursorarrow.click.badge.clock", title: text.title, caption: text.caption) {
                Toggle(text.title, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, on in
                        MouseClickDebounceService.shared.syncWithPreferences()
                        if on { permissions.requestAccessibility() }
                    }
            }
            if enabled {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(value: windowBinding, in: Defaults.allowedMouseClickDebounceWindowRange, step: 1) {
                        HStack {
                            Text(text.windowLabel)
                            Spacer()
                            Text("\(Defaults.sanitizedMouseClickDebounceWindow(window)) ms")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(text.windowCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct FocusFollowsMousePage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.focusFollowsMouseEnabled) private var enabled = false
    @AppStorage(DefaultsKey.focusFollowsMouseRaise) private var raise = true
    @AppStorage(DefaultsKey.focusFollowsMouseWaitForStop) private var waitForStop = true
    @AppStorage(DefaultsKey.focusFollowsMouseDelay) private var delay =
        FocusFollowsMouseSupport.defaultDelayMilliseconds

    private var delayBinding: Binding<Double> {
        Binding(
            get: { Double(FocusFollowsMouseSupport.sanitizedDelay(delay)) },
            set: {
                delay = Int($0)
                FocusFollowsMouseService.shared.preferencesDidChange()
            })
    }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "macwindow.and.cursorarrow", title: l10n.s.focusFollowsMouseName,
                        caption: l10n.s.focusFollowsMouseCaption) {
                Toggle(l10n.s.focusFollowsMouseName, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, on in
                        FocusFollowsMouseService.shared.syncWithPreferences()
                        if on { permissions.requestAccessibility() }
                    }
            }
            if enabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(l10n.s.focusFollowsMouseDelay).frame(minWidth: 96, alignment: .leading)
                        Slider(value: delayBinding,
                               in: Double(FocusFollowsMouseSupport.delayRange.lowerBound)
                                   ... Double(FocusFollowsMouseSupport.delayRange.upperBound),
                               step: 50) { Text(l10n.s.focusFollowsMouseDelay) }
                            .labelsHidden()
                        Text("\(delay) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    Toggle(l10n.s.focusFollowsMouseRaise, isOn: $raise)
                    if !raise { Toggle(l10n.s.focusFollowsMouseWaitForStop, isOn: $waitForStop) }
                    MouseExceptionsList(scope: .focusFollowsMouse)
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct MiddleClickPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MiddleClickService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.middleClickEnabled) private var enabled = false
    @AppStorage(DefaultsKey.middleClickTapFingers) private var tapFingers = 0

    var body: some View {
        SettingsCard(title: l10n.s.middleClickSection) {
            if let reason = Multitouch.unavailableReason {
                Label("Indisponible : \(reason)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsRow(symbol: "hand.tap", title: l10n.s.middleClickEnable,
                        caption: l10n.s.middleClickEnableCaption) {
                Toggle(l10n.s.middleClickEnable, isOn: $enabled)
                    .labelsHidden()
                    .disabled(Multitouch.unavailableReason != nil)
                    .onChange(of: enabled) { _, on in
                        MiddleClickService.shared.syncWithPreferences()
                        if on { permissions.requestAccessibility() }
                    }
            }
            if enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.s.middleClickTapPicker).font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        chip(0, title: l10n.s.middleClickTapOff, symbol: "hand.raised.slash")
                        chip(3, title: l10n.s.middleClickTapThreeFingers, symbol: "hand.tap")
                        chip(4, title: l10n.s.middleClickTapFourFingers, symbol: "hand.tap")
                    }
                    Text(l10n.s.middleClickTapCaption)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if service.systemDragGestureConflict {
                        Text(l10n.s.middleClickDragConflict)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if service.touchDeviceMissing {
                        Text(l10n.s.middleClickNoTrackpad)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                MouseExceptionsList(scope: .middleClick)
            }
        }
        .toggleStyle(.switch)
        .onAppear { MiddleClickService.shared.refreshDragGestureConflict() }
    }

    private func chip(_ fingers: Int, title: String, symbol: String) -> some View {
        let selected = tapFingers == fingers
        return Button {
            tapFingers = fingers
            MiddleClickService.shared.syncWithPreferences()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ActiveBadge: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(PanelMetricColor.green(for: colorScheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(PanelMetricColor.green(for: colorScheme).opacity(0.12), in: Capsule())
    }
}
