// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W2A (display). The lane owns this file.

import SwiftUI

// The three Settings pages of the display lane (our page ids `displays`, `extrabrightness`, `kbdlight`). Each is
// drawn from the ported cards and rows, without the title, scroll view and header the upstream Energy page
// carries (Mac Island's page scaffold has its own), and shows its controls even while the registry holds the
// feature off, so the switch and the settings stay reachable.

// MARK: - Page 25: Écrans

struct DisplaysPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @AppStorage(DefaultsKey.brightnessKeysEnabled) private var brightnessKeysEnabled = false
    @AppStorage(DefaultsKey.brightnessOSDEnabled) private var brightnessOSDEnabled = false
    @AppStorage(DefaultsKey.brightnessKeyStep)
    private var brightnessKeyStep = BrightnessSupport.KeyStep.standard.rawValue
    @State private var optionsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            displaysCard
            DisplayProbeCard()
        }
        .toggleStyle(.switch)
        .onAppear { brightness.refresh() }
    }

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }

    private var displaysCard: some View {
        SettingsCard {
            SettingsRow(symbol: "display.2", title: strings.enable, caption: strings.enableCaption) {
                Toggle(strings.enable, isOn: $brightnessEnabled)
                    .labelsHidden()
                    .onChange(of: brightnessEnabled) { _, _ in brightness.syncWithPreferences() }
            }
            if !PortShortcutOwnership.isRunning(.brightness) {
                Text("La fonction « Écrans » est coupée (interrupteur de la carte ci-dessus, interrupteur d’arrêt ou mode sans échec) : aucun écran n’est piloté.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if brightnessEnabled {
                Divider()
                if brightness.displays.isEmpty {
                    Text(strings.noDisplays)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(brightness.displays) { display in displayRow(display) }
                }
                if let failure = brightness.displayControlFailure {
                    Text(displayControlFailureText(failure, strings: strings))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(isExpanded: $optionsExpanded) {
                    optionRows.padding(.top, 10)
                } label: {
                    Text(FeatureStrings.recorder(l10n.language).moreOptions)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    private var optionRows: some View {
        VStack(alignment: .leading, spacing: 13) {
            SettingsRow(symbol: "cursorarrow.rays", title: strings.keysToggle, caption: strings.keysCaption) {
                Toggle(strings.keysToggle, isOn: $brightnessKeysEnabled)
                    .labelsHidden()
                    .onChange(of: brightnessKeysEnabled) { _, isOn in
                        if isOn { Permissions.shared.requestAccessibility() }
                        brightness.syncWithPreferences()
                    }
            }
            SettingsRow(symbol: "sun.min", title: strings.keyStep, caption: strings.keyStepCaption) {
                Picker(strings.keyStep, selection: keyStepBinding) {
                    Text(strings.keyStepStandard).tag(BrightnessSupport.KeyStep.standard)
                    Text(strings.keyStepHalf).tag(BrightnessSupport.KeyStep.half)
                    Text(strings.keyStepQuarter).tag(BrightnessSupport.KeyStep.quarter)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            DisplayBrightnessShortcutControls(showsSettingsRow: true)
            if brightness.brightnessOSDSupported {
                SettingsRow(symbol: "sun.max", title: strings.osdToggle, caption: strings.osdCaption) {
                    Toggle(strings.osdToggle, isOn: $brightnessOSDEnabled)
                        .labelsHidden()
                        .onChange(of: brightnessOSDEnabled) { _, isOn in
                            if isOn { Permissions.shared.requestAccessibility() }
                            brightness.syncWithPreferences()
                        }
                }
            }
            if brightnessKeysEnabled || brightnessOSDEnabled
                || BrightnessSupport.KeyStep.sanitized(brightnessKeyStep) != .standard,
               !permissions.accessibility {
                PermissionRow(kind: .accessibility)
            }
            Text(strings.externalCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A finer step answers the keys in place of the system, which takes the same permission as the other key
    /// options.
    private var keyStepBinding: Binding<BrightnessSupport.KeyStep> {
        Binding {
            BrightnessSupport.KeyStep.sanitized(brightnessKeyStep)
        } set: { step in
            brightnessKeyStep = step.rawValue
            if step != .standard { Permissions.shared.requestAccessibility() }
            brightness.syncWithPreferences()
        }
    }

    private func displayRow(_ display: BrightnessDisplay) -> some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(display.isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background((display.isActive ? Color.accentColor : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(display.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 80, alignment: .leading)
            if display.isActive, display.method != nil {
                Slider(value: Binding(get: { display.brightness },
                                      set: { brightness.setBrightness($0, for: display.id, showOSD: brightnessOSDEnabled) }),
                       in: 0...1)
                    .disabled(brightness.isDisplayPending(display.id))
                    .accessibilityLabel(display.name)
                Text("\(Int((display.brightness * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Spacer()
                if !display.isActive {
                    Text(strings.displayOff)
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            SoftwareDimmingButton(display: display)
            DisplayPowerButton(display: display)
        }
    }
}

// MARK: - DDC probe

/// The result of the read-only DDC probe, per display: "pris en charge" or "non pris en charge" and why, with
/// the two choices the person has (test again, use DDC anyway on a monitor that never answers).
struct DisplayProbeCard: View {
    @ObservedObject private var brightness = BrightnessService.shared

    private var shown: [BrightnessDisplay] {
        brightness.displays.filter { $0.isActive && $0.method != nil }
    }

    var body: some View {
        SettingsCard(title: "Compatibilité DDC des écrans") {
            Text("Le test lit la luminosité de chaque écran externe (VCP 0x10) et ne modifie rien. DDC n’écrit une luminosité que sur un écran qui a répondu. Les autres sont assombris par le logiciel, jamais en dessous de \(Int(BrightnessSupport.softwareDimFloor * 100)) % : l’écran ne devient jamais noir.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if shown.isEmpty {
                Text("Aucun écran à tester : activez le contrôle des écrans ci-dessus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { display in row(display) }
            HStack {
                Button("Relancer le test", systemImage: "arrow.clockwise") { brightness.reprobeDDC() }
                    .disabled(shown.isEmpty)
                Spacer()
            }
            Text("L’interrupteur d’arrêt de la page Fonctions coupe tout changement d’écran et remet les courbes d’origine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ display: BrightnessDisplay) -> some View {
        let report = brightness.ddcReports[display.id]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(display.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(report?.label ?? "test en cours")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(of: report))
            }
            if let report {
                Text(report.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if report.canTrust {
                    Button("Utiliser DDC quand même") { brightness.setUnconfirmedDDCTrusted(true, for: display.id) }
                        .controlSize(.small)
                }
                if report.trusted {
                    Button("Revenir à la gradation logicielle") { brightness.setUnconfirmedDDCTrusted(false, for: display.id) }
                        .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(of report: DDCReport?) -> Color {
        switch report?.verdict {
        case .supported: .green
        case .notSupported: .orange
        case .notApplicable, nil: .secondary
        }
    }
}

// MARK: - Page 26: Luminosité extra

struct ExtraBrightnessPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var extraBrightness = ExtraBrightnessService.shared
    @AppStorage(DefaultsKey.extraBrightnessEnabled) private var enabled = false
    @AppStorage(DefaultsKey.extraBrightnessLevel) private var level = 100

    var body: some View {
        SettingsCard {
            if extraBrightness.supported {
                SettingsRow(symbol: "sun.max.fill", title: l10n.s.extraBrightnessName,
                            caption: l10n.s.extraBrightnessCaption) {
                    Toggle(l10n.s.extraBrightnessName, isOn: $enabled)
                        .labelsHidden()
                        .onChange(of: enabled) { _, _ in extraBrightness.syncWithPreferences() }
                }
                if enabled {
                    HStack(spacing: 12) {
                        Text(l10n.s.extraBrightnessLevelLabel)
                        Slider(value: levelBinding, in: 10...100, step: 5)
                        Text("\(level)%")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            } else {
                SettingsRow(symbol: "sun.max.fill", title: l10n.s.extraBrightnessName,
                            caption: l10n.s.extraBrightnessUnsupported) { EmptyView() }
            }
            Text(extraBrightness.supported
                 ? "Écran XDR détecté : pris en charge. La luminosité extra n’écrit rien sur l’écran, elle disparaît avec l’app."
                 : "Aucun écran intégré XDR détecté : non pris en charge sur ce Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
        .onAppear { extraBrightness.syncWithPreferences() }
    }

    private var levelBinding: Binding<Double> {
        Binding(get: { Double(level) },
                set: { newValue in
                    level = Int(newValue)
                    extraBrightness.levelDidChange()
                })
    }
}

// MARK: - Page 63: Éclairage du clavier

struct KeyboardLightPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var brightness = BrightnessService.shared
    @AppStorage(DefaultsKey.keyboardBrightnessShortcutsEnabled) private var shortcutsEnabled = false

    private var strings: BrightnessFeatureStrings { FeatureStrings.brightness(l10n.language) }
    private var supported: Bool { BrightnessService.keyboardLightIsSupported }

    var body: some View {
        let summary = KeyboardLightProbe.summary(supported: supported)
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard {
                SettingsRow(symbol: "light.max", title: strings.keyboardLight, caption: strings.keyboardLightCaption) {
                    Text(summary.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(supported ? Color.green : Color.orange)
                }
                Text(summary.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if supported {
                    HStack(spacing: 12) {
                        Image(systemName: "light.min")
                        Slider(value: levelBinding, in: 0...1) { editing in
                            brightness.keyboardLightDragChanged(editing)
                        }
                        .disabled(brightness.keyboardLightLevel == nil)
                        .accessibilityLabel(strings.keyboardLight)
                        Image(systemName: "light.max")
                        Text("\(Int(((brightness.keyboardLightLevel ?? 0) * 100).rounded()))%")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            if supported {
                SettingsCard {
                    Toggle(strings.keyboardBrightnessShortcuts, isOn: $shortcutsEnabled)
                        .onChange(of: shortcutsEnabled) { _, _ in brightness.syncWithPreferences() }
                    if shortcutsEnabled {
                        ForEach([GlobalShortcutRole.keyboardBrightnessDecrease, .keyboardBrightnessIncrease]) { role in
                            ShortcutPreferenceRow(role: role, isEnabled: shortcutsEnabled, label: role.title(l10n.s),
                                                  includeInactiveConflicts: true) {
                                brightness.syncWithPreferences()
                            }
                        }
                        if brightness.keyboardBrightnessShortcutRegistrationFailed {
                            Text(l10n.s.shortcutUnavailable)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .onAppear { if supported { brightness.refreshKeyboardLight() } }
    }

    private var levelBinding: Binding<Double> {
        Binding(get: { Double(brightness.keyboardLightLevel ?? 0) },
                set: { brightness.setKeyboardLightLevel(Float($0)) })
    }
}
