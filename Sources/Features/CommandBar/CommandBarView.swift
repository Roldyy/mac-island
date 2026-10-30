import SwiftUI

struct CommandBarView: View {
    @Bindable var model: CommandBarModel
    let onClose: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityHidden(true)
                TextField("Rechercher une app, un fichier, un calcul\u{2026}", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .focused($fieldFocused)
                    .accessibilityLabel("Recherche")
                    .accessibilityHint("Fl\u{00E8}ches pour choisir, Entr\u{00E9}e pour ouvrir, Commande Entr\u{00E9}e pour afficher dans le Finder, \u{00C9}chap pour fermer")
                    .onKeyPress(.downArrow) { model.move(1); return .handled }
                    .onKeyPress(.upArrow) { model.move(-1); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                    .onKeyPress(keys: [.return]) { press in
                        let reveal = press.modifiers.contains(.command)
                        Task { if await model.submit(reveal: reveal) { onClose() } }
                        return .handled
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            if !model.results.isEmpty {
                Divider().overlay(.white.opacity(0.12))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                                Button {
                                    model.selectedIndex = index
                                    if model.activate(reveal: false) { onClose() }
                                } label: {
                                    ResultRow(result: result, selected: index == model.selectedIndex)
                                }
                                .buttonStyle(.plain)
                                .focusEffectDisabled()
                                .id(result.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selectedIndex) {
                        if model.results.indices.contains(model.selectedIndex) {
                            proxy.scrollTo(model.results[model.selectedIndex].id)
                        }
                    }
                }
                .accessibilityLabel("R\u{00E9}sultats")
                .accessibilityValue("\(model.results.count) r\u{00E9}sultats")
            }
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.14)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .task { fieldFocused = true }
        .task(id: model.query) {
            // Debounce typing; a newer keystroke cancels this one before it searches.
            if !model.query.isEmpty { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            await model.refresh()
        }
    }
}

private struct ResultRow: View {
    let result: BarResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(selected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var symbol: String {
        switch result.kind {
        case .app: "app"
        case .file: "doc"
        case .command: "command"
        case .calculator: "equal.square"
        case .web: "globe"
        }
    }
}
