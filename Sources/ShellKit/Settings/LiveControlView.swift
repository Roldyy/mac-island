import IslandUI
import SwiftUI

/// A control that reads and writes its preference key. Holds its own value so a write never waits for a redraw.
struct LiveControlView: View {
    let label: String
    let hint: String?
    let control: LiveControl
    let store: LiveStore

    @State private var flag = false
    @State private var number = 0
    @State private var amount = 0.0
    @State private var shortcut = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            content
            if let hint {
                Text(hint).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder private var content: some View {
        switch control.kind {
        case .toggle, .stringFlag:
            Toggle(label, isOn: $flag)
                .toggleStyle(IslandToggleStyle())
                .onChange(of: flag) { if loaded { store.setBool(flag, control) } }
        case let .choice(options, _):
            row {
                Picker(label, selection: $number) {
                    ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: number) { if loaded { store.setInt(number, control) } }
            }
        case let .stepper(range, _, unit):
            row {
                Stepper(value: $number, in: range) {
                    Text(unit.isEmpty ? "\(number)" : "\(number) \(unit)").font(.islandValue)
                }
                .fixedSize()
                .onChange(of: number) { if loaded { store.setInt(number, control) } }
            }
        case let .slider(range, _, unit):
            row {
                HStack {
                    Slider(value: $amount, in: range).frame(width: 160)
                    Text("\(Int(amount)) \(unit)").font(.islandValue).frame(minWidth: 44, alignment: .trailing)
                }
                .onChange(of: amount) { if loaded { store.setDouble(amount, control) } }
            }
        case let .shortcut(fallback):
            row {
                ShortcutRecorderView(spec: ShortcutSpec.parse(shortcut), fallbackText: fallback) { new in
                    shortcut = new.stored
                    store.setShortcut(new.stored, control)
                }
            }
        }
    }

    private func row<T: View>(@ViewBuilder _ trailing: () -> T) -> some View {
        HStack {
            Text(label).font(.islandBody).foregroundStyle(IslandPalette.textPrimary.color)
            Spacer(minLength: IslandSpacing.s)
            trailing()
        }
        .frame(minHeight: IslandMetrics.controlHeight)
    }

    private func load() {
        flag = store.bool(control)
        number = store.int(control)
        amount = store.double(control)
        shortcut = store.shortcut(control)
        // Let the first onChange pass go by before writes start.
        Task { @MainActor in loaded = true }
    }
}
