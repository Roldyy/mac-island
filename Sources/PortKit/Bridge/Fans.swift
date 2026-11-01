// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W6C (fans, UI and policy). The lane owns this file.

import AppKit
import FansFeature
import SwiftUI

/// Fan control: upstream's curves, presets and safety card over Mac Island's own root helper.
///
/// The helper, its XPC contract (`FanHelperContract`) and its installation stay in `Sources/Features/Fans` and
/// `Sources/FanShared`. The ported `FanControlService` is a shim over `FanControlBackend`, which drives the helper
/// through the Fans model. This lane adopts the `fans` registry switch (our module owns it), so the registry's
/// start and stop reach both the Ventilos monitoring and the policy, and kill switch, safe mode and crash
/// quarantine all end in automatic mode.
enum FansLane {
    struct Runtime {
        var start: @MainActor () -> Void
        var stop: @MainActor () -> Void

        /// The real thing. Order matters at stop: the policy hands the fans back first, then the Fans model
        /// disconnects (its own `stop` sends automatic again, which is idempotent).
        @MainActor static var live: Runtime {
            Runtime(
                start: {
                    FansFeature.start()
                    FanControlBackend.shared.start()
                },
                stop: {
                    FanControlBackend.shared.stop()
                    FansFeature.stop()
                })
        }
    }

    /// Our Settings page id (`SettingsPageCatalog`); its catalog row already carries the feature card.
    static let pageID = "fans"

    private static var didInstallLiveWiring = false

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installLiveWiring()
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.adopt(.fanControl, start: runtime.start, stop: runtime.stop)
    }

    /// What only the real app does: the page body, and the sleep, wake and quit hooks of the policy.
    @MainActor private static func installLiveWiring() {
        guard !didInstallLiveWiring else { return }
        didInstallLiveWiring = true
        PortBridge.register(pageID: pageID) { AnyView(FansPage().defaultAppStorage(PortHost.defaults)) }
        FanControlBackend.shared.installSystemObservers()
    }
}

// MARK: - Page: Contrôle des ventilateurs

/// The card (status, mode, manual level, curve editor, resume), the ready-made curves and the safety limits.
/// Everything here is live: nothing is greyed as coming soon.
struct FansPage: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = FanControlService.shared
    @AppStorage(DefaultsKey.fanControlMode) private var modeRaw = FanControlMode.system.rawValue
    @AppStorage(DefaultsKey.fanControlCoolingLevel) private var coolingLevel = FanControlPolicy.defaultCoolingLevel
    @AppStorage(DefaultsKey.fanControlCurves) private var curvesStorage = FanControlConfiguration.defaultCurvesStorage
    @AppStorage(DefaultsKey.fanControlResume) private var resume = false
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(FanControlEngine.ceilingKey) private var ceiling = FanControlEngine.defaultCeiling

    private var strings: FanControlFeatureStrings { FeatureStrings.fanControl(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !service.isRunning {
                Label("La fonction est éteinte : allumez-la ci-dessus pour piloter les ventilateurs.",
                      systemImage: "power")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Group {
                controlCard
                presetsCard
                safetyCard
            }
            .disabled(!service.isRunning)
            .opacity(service.isRunning ? 1 : 0.55)
        }
        .toggleStyle(.switch)
        .onAppear { service.panelDidAppear() }
        .onDisappear { service.panelDidDisappear() }
        .onChange(of: resume) { _, _ in service.resumePreferenceDidChange() }
    }

    // MARK: Control

    private var controlCard: some View {
        SettingsCard {
            FanControlCardContent(strings: strings,
                                  betaLabel: l10n.s.betaBadge,
                                  snapshot: service.snapshot,
                                  fallbackFanSpeeds: [],
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  mode: modeBinding,
                                  coolingLevel: $coolingLevel,
                                  curves: curvesBinding,
                                  resume: $resume,
                                  temperatureUnit: TemperatureUnit(rawValue: temperatureUnit) ?? .celsius,
                                  authorize: service.authorize,
                                  applyConfiguration: service.applyConfiguration,
                                  stopCooling: service.returnToSystem)
        }
    }

    // MARK: Presets

    private var presetsCard: some View {
        SettingsCard(title: "Courbes prêtes à l'emploi") {
            Text("Choisissez un préréglage : il remplit la courbe ci-dessus. Il ne s'applique qu'après « \(strings.applyCurve) ».")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(FanCurvePreset.allCases) { preset in
                    Button { choose(preset) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(preset.title, systemImage: preset.symbol).font(.subheadline.weight(.semibold))
                            Text(preset.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isWorking)
                    .accessibilityLabel("Préréglage \(preset.title)")
                    .accessibilityHint(preset.summary)
                }
            }
        }
    }

    private func choose(_ preset: FanCurvePreset) {
        guard let encoded = FanControlConfiguration.encodeCurves(preset.curves) else { return }
        curvesStorage = encoded
        modeRaw = FanControlMode.curve.rawValue
    }

    // MARK: Safety

    private var safetyCard: some View {
        SettingsCard(title: "Sécurité") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Limite de température")
                    Spacer()
                    Text("\(Int(FanControlEngine.sanitizedCeiling(ceiling))) °C")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: ceilingBinding, in: FanControlEngine.ceilingRange, step: 1)
                    .accessibilityLabel("Limite de température")
                    .accessibilityValue("\(Int(FanControlEngine.sanitizedCeiling(ceiling))) degrés")
                Text("Au-delà, Mac Island rend les ventilateurs à macOS. Le helper impose aussi son propre plafond à 95 °C.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Retour automatique").font(.subheadline.weight(.medium))
                ForEach(Self.handBackRules, id: \.self) { rule in
                    Label(rule, systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Every way the fans go back to macOS, as the policy and the helper enforce them.
    static let handBackRules = [
        "Quand vous arrêtez la fonction, ou avec l'interrupteur d'urgence et le mode sans échec.",
        "Quand Mac Island se ferme, et à la mise en veille du Mac.",
        "Si macOS signale une forte chaleur, ou si la limite ci-dessus est atteinte.",
        "Si l'app plante ou se fige : le helper reprend la main après 8 secondes sans signal.",
        "Si un capteur manque trois mesures de suite, ou si une commande est refusée.",
    ]

    // MARK: Bindings

    private var ceilingBinding: Binding<Double> {
        Binding(get: { FanControlEngine.sanitizedCeiling(ceiling) },
                set: { ceiling = FanControlEngine.sanitizedCeiling($0) })
    }

    private var modeBinding: Binding<FanControlMode> {
        Binding(get: { FanControlMode(rawValue: modeRaw) ?? .system }, set: { modeRaw = $0.rawValue })
    }

    private var curvesBinding: Binding<[FanControlCurve]> {
        Binding(
            get: { FanControlConfiguration.decodeCurves(curvesStorage) ?? [FanControlConfiguration.defaultCurve] },
            set: { curves in
                if let encoded = FanControlConfiguration.encodeCurves(curves) { curvesStorage = encoded }
            })
    }
}
