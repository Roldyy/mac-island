import PortKit
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
    let state: KeepAwakeState
    let backend: any KeepAwakeBackend
    @State private var selectedMinutes: Int

    init(state: KeepAwakeState, backend: any KeepAwakeBackend) {
        self.state = state
        self.backend = backend
        let stored = backend.defaultMinutes
        _selectedMinutes = State(initialValue: DurationChoice.all.contains { $0.minutes == stored } ? stored : 0)
    }

    var body: some View {
        let snapshot = state.snapshot
        VStack(spacing: 10) {
            Toggle(isOn: Binding(get: { snapshot.isActive }, set: toggle)) {
                Label(snapshot.isActive ? "Mac éveillé" : "Laisser le Mac s'endormir",
                      systemImage: snapshot.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.title3.weight(.semibold))
            }
            .toggleStyle(.switch)

            countdown(snapshot)

            HStack(spacing: 6) {
                ForEach(DurationChoice.all) { choice in
                    Button(choice.label) { select(choice.minutes) }
                        .buttonStyle(.bordered)
                        .tint(choice.minutes == selectedMinutes ? .white : .gray)
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let line = Self.statusLine(for: snapshot) {
                    Label(line, systemImage: snapshot.closedLidActive ? "laptopcomputer" : "bolt.badge.automatic")
                        .font(.caption)
                        .foregroundStyle(snapshot.closedLidActive ? .orange : .secondary)
                }
                Text("Automatisation, pointeur, capot fermé : Réglages, Garder éveillé.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private func countdown(_ snapshot: PortKeepAwake.Snapshot) -> some View {
        if snapshot.isActive {
            if let end = snapshot.endDate {
                // Redraws once a second, and only while the view is on screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SessionPlan.format(remaining: max(0, end.timeIntervalSince(context.date))))
                        .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                }
            } else {
                Text("Sans limite").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Text(" ").font(.system(size: 30))
        }
    }

    /// The one line under the chips: closed lid first, then an automatic start. Nil when nothing to say.
    static func statusLine(for snapshot: PortKeepAwake.Snapshot) -> String? {
        if snapshot.sleepRestoreNeeded { return "Veille désactivée : à rétablir dans Réglages" }
        if snapshot.closedLidActive { return "Mode capot fermé actif" }
        if snapshot.isActive, snapshot.isAutomatic { return "Démarré automatiquement" }
        return nil
    }

    private func toggle(_ on: Bool) {
        if on { backend.start(minutes: selectedMinutes) } else { backend.stop() }
    }

    private func select(_ minutes: Int) {
        selectedMinutes = minutes
        guard state.snapshot.isActive else { return }
        backend.start(minutes: minutes)
    }
}
