import IslandUI
import SwiftUI

/// A control that reads and writes its preference key. Holds its own value so a write never waits for a redraw.
struct LiveControlView: View {
    let label: String
    let hint: String?
    let control: LiveControl
    let store: LiveStore

    @State private var flag: Bool
    @State private var number: Int
    @State private var amount: Double
    @State private var shortcut: String
    @State private var text: String
    @State private var confirming = false
    /// A reference, so opening it never invalidates the view (a `@State` Bool would redraw every control once).
    @State private var gate = WriteGate()

    /// Writes start only after the first `onChange` pass has gone by.
    @MainActor final class WriteGate {
        var isOpen = false
    }

    /// The value is read once, here, for the kind of control this is: nothing has to be assigned after the
    /// view appeared, so a page of forty controls is drawn once instead of twice.
    init(label: String, hint: String?, control: LiveControl, store: LiveStore) {
        self.label = label
        self.hint = hint
        self.control = control
        self.store = store
        switch control.kind {
        case .toggle, .stringFlag:
            _flag = State(initialValue: store.bool(control)); _number = State(initialValue: 0)
            _amount = State(initialValue: 0); _shortcut = State(initialValue: "")
            _text = State(initialValue: "")
        case .choice, .stepper:
            _flag = State(initialValue: false); _number = State(initialValue: store.int(control))
            _amount = State(initialValue: 0); _shortcut = State(initialValue: "")
            _text = State(initialValue: "")
        case .slider:
            _flag = State(initialValue: false); _number = State(initialValue: 0)
            _amount = State(initialValue: store.double(control)); _shortcut = State(initialValue: "")
            _text = State(initialValue: "")
        case .shortcut:
            _flag = State(initialValue: false); _number = State(initialValue: 0)
            _amount = State(initialValue: 0); _shortcut = State(initialValue: store.shortcut(control))
            _text = State(initialValue: "")
        case .stringChoice:
            _flag = State(initialValue: false); _number = State(initialValue: 0)
            _amount = State(initialValue: 0); _shortcut = State(initialValue: "")
            _text = State(initialValue: store.string(control))
        case .action, .readout:
            _flag = State(initialValue: false); _number = State(initialValue: 0)
            _amount = State(initialValue: 0); _shortcut = State(initialValue: "")
            _text = State(initialValue: "")
        }
    }

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
                .onChange(of: flag) { if gate.isOpen { store.setBool(flag, control) } }
        case let .choice(options, _):
            row {
                Picker(label, selection: $number) {
                    ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: number) { if gate.isOpen { store.setInt(number, control) } }
            }
        case let .stepper(range, _, unit):
            row {
                Stepper(value: $number, in: range) {
                    Text(unit.isEmpty ? "\(number)" : "\(number) \(unit)").font(.islandValue)
                }
                .fixedSize()
                .onChange(of: number) { if gate.isOpen { store.setInt(number, control) } }
            }
        case let .slider(range, _, unit):
            row {
                HStack {
                    Slider(value: $amount, in: range).frame(width: 160)
                    Text("\(Int(amount)) \(unit)").font(.islandValue).frame(minWidth: 44, alignment: .trailing)
                }
                .onChange(of: amount) { if gate.isOpen { store.setDouble(amount, control) } }
            }
        case let .shortcut(fallback):
            row {
                ShortcutRecorderView(spec: ShortcutSpec.parse(shortcut), fallbackText: fallback) { new in
                    shortcut = new.stored
                    store.setShortcut(new.stored, control)
                }
            }
        case let .stringChoice(options, _):
            row {
                Picker(label, selection: $text) {
                    ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: text) { if gate.isOpen { store.setString(text, control) } }
            }
        case let .action(title, confirm):
            row { actionButtons(title: title, confirm: confirm) }
        case .readout:
            row {
                // Counts move while the page is open (a copy, a clear): read them again every second.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(SettingsActions.readout(control.key)).font(.islandValue)
                }
            }
        }
    }

    @ViewBuilder private func actionButtons(title: String, confirm: String?) -> some View {
        let available = SettingsActions.hasAction(control.key)
        if confirming, let confirm {
            HStack(spacing: IslandSpacing.xs) {
                Button(confirm) {
                    confirming = false
                    SettingsActions.run(control.key)
                }
                .buttonStyle(IslandButtonStyle(.destructive))
                Button("Annuler") { confirming = false }
                    .buttonStyle(IslandButtonStyle(.standard))
            }
        } else {
            Button(title) {
                if confirm != nil { confirming = true } else { SettingsActions.run(control.key) }
            }
            .buttonStyle(IslandButtonStyle(.standard))
            .disabled(!available)
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

    /// The value was read in `init`; this only re-reads it when the preference changed elsewhere in between
    /// (an equal value is not assigned, so nothing redraws).
    private func load() {
        switch control.kind {
        case .toggle, .stringFlag: let v = store.bool(control); if flag != v { flag = v }
        case .choice, .stepper: let v = store.int(control); if number != v { number = v }
        case .slider: let v = store.double(control); if amount != v { amount = v }
        case .shortcut: let v = store.shortcut(control); if shortcut != v { shortcut = v }
        case .stringChoice: let v = store.string(control); if text != v { text = v }
        case .action, .readout: break
        }
        // Let the first onChange pass go by before writes start.
        let gate = gate
        Task { @MainActor in gate.isOpen = true }
    }
}
