import IslandUI
import SwiftUI

/// The page's settings: which cards, in which order, how limits read. Shown in place of the cards
/// (a real sheet inside the island panel is not reliable), closed with "Fermer".
struct AgentsSettingsPanel: View {
    @Bindable var model: AgentsUsageModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            HStack {
                Text(AgentsStrings.text("cardsTitle"))
                    .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(AgentsStrings.closeLabel, action: close).buttonStyle(.island)
            }
            IslandCard {
                VStack(spacing: IslandSpacing.xs) {
                    ForEach(model.cardOrder) { card in cardRow(card) }
                }
            }
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    labeled(AgentsStrings.text("limitsAs")) {
                        Picker(AgentsStrings.text("limitsAs"), selection: $model.limitDisplay) {
                            ForEach(AgentsLimitDisplay.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    labeled(AgentsStrings.text("limitFocus")) {
                        Picker(AgentsStrings.text("limitFocus"), selection: $model.limitFocus) {
                            ForEach(AgentsLimitFocus.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    Stepper(value: budgetBinding, in: 0...1000, step: 5) {
                        HStack {
                            Text(AgentsStrings.text("budget")).font(.islandBody)
                                .foregroundStyle(IslandPalette.textPrimary.color)
                            Spacer(minLength: IslandSpacing.s)
                            Text(model.dailyBudget.map { UsageFormat.cost($0, estimated: false) } ?? AgentsStrings.text("off"))
                                .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color)
                        }
                    }
                }
            }
        }
    }

    /// 0 = off, so the stepper has a floor that means something.
    private var budgetBinding: Binding<Double> {
        Binding(get: { model.dailyBudget ?? 0 }, set: { model.dailyBudget = $0 > 0 ? $0 : nil })
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            Text(title).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            content()
        }
    }

    private func cardRow(_ card: AgentsCard) -> some View {
        let isShown = Binding(
            get: { !model.hiddenCards.contains(card) },
            set: { shown in
                if shown { model.hiddenCards.remove(card) } else { model.hiddenCards.insert(card) }
            })
        return HStack(spacing: IslandSpacing.xs) {
            Image(systemName: card.symbol).font(.islandBody).foregroundStyle(card.tint).frame(width: 20)
                .accessibilityHidden(true)
            Toggle(card.title, isOn: isShown).toggleStyle(IslandToggleStyle())
            Button(AgentsStrings.moveUp, systemImage: "chevron.up") { move(card, by: -1) }
                .labelStyle(.iconOnly).buttonStyle(.island)
                .disabled(model.cardOrder.first == card)
            Button(AgentsStrings.moveDown, systemImage: "chevron.down") { move(card, by: 1) }
                .labelStyle(.iconOnly).buttonStyle(.island)
                .disabled(model.cardOrder.last == card)
        }
    }

    private func move(_ card: AgentsCard, by offset: Int) {
        model.cardOrder = AgentsCardLayout.moved(card, by: offset, in: model.cardOrder)
    }
}
