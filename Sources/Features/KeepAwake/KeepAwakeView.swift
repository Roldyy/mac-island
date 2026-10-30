import SwiftUI

struct DurationChoice: Identifiable, Equatable {
    let label: String
    let minutes: Int // 0 = no limit
    var id: Int { minutes }
    static let all = [
        DurationChoice(label: "30 min", minutes: 30), DurationChoice(label: "1 h", minutes: 60),
        DurationChoice(label: "2 h", minutes: 120), DurationChoice(label: "4 h", minutes: 240),
        DurationChoice(label: "Sans limite", minutes: 0),
    ]
}

struct KeepAwakeView: View {
    let controller: KeepAwakeController
    let settings: KeepAwakeSettings
    @State private var selectedMinutes: Int

    init(controller: KeepAwakeController, settings: KeepAwakeSettings) {
        self.controller = controller
        self.settings = settings
        let stored = settings.defaultDurationMinutes
        _selectedMinutes = State(initialValue: DurationChoice.all.contains { $0.minutes == stored } ? stored : 0)
    }

    var body: some View {
        VStack(spacing: 10) {
            Toggle(isOn: Binding(get: { controller.isActive }, set: toggle)) {
                Label(controller.isActive ? "Mac éveillé" : "Laisser le Mac s'endormir",
                      systemImage: controller.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.title3.weight(.semibold))
            }
            .toggleStyle(.switch)

            countdown

            HStack(spacing: 6) {
                ForEach(DurationChoice.all) { choice in
                    Button(choice.label) { select(choice.minutes) }
                        .buttonStyle(.bordered)
                        .tint(choice.minutes == selectedMinutes ? .white : .gray)
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(jiggleLine).font(.caption).foregroundStyle(.secondary)
                if settings.clamshellPreferred {
                    Label("Écran fermé : nécessite les droits administrateur, indisponible ici",
                          systemImage: "laptopcomputer")
                        .font(.caption).foregroundStyle(.tertiary)
                        .accessibilityLabel("Mode écran fermé indisponible, nécessite les droits administrateur")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var countdown: some View {
        if let plan = controller.plan {
            if plan.duration == nil {
                Text("Sans limite").font(.callout).foregroundStyle(.secondary)
            } else {
                // Redraws once a second, and only while the view is on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionPlan.format(remaining: plan.remaining(at: context.date) ?? 0))
                        .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                }
            }
        } else {
            Text(" ").font(.system(size: 30))
        }
    }

    private var jiggleLine: String {
        switch controller.jiggleStatus {
        case .off:
            settings.mouseJiggleEnabled ? "Souris : actif quand l'éveil est activé" : "Souris : désactivée"
        case .needsAccessibility:
            "Souris : autorisez l'accessibilité dans Réglages Système"
        case let .waiting(minutes):
            "Souris : un petit mouvement après \(minutes) min d'inactivité"
        }
    }

    private func toggle(_ on: Bool) {
        if on { controller.start(duration: selectedMinutes > 0 ? TimeInterval(selectedMinutes) * 60 : nil) }
        else { controller.stop() }
    }

    private func select(_ minutes: Int) {
        selectedMinutes = minutes
        guard controller.isActive else { return }
        controller.stop()
        controller.start(duration: minutes > 0 ? TimeInterval(minutes) * 60 : nil)
    }
}
