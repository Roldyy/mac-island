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
                        AgentsSegmentedControl(items: AgentsLimitDisplay.allCases, selection: $model.limitDisplay,
                                               title: \.title, label: AgentsStrings.text("limitsAs"))
                    }
                    labeled(AgentsStrings.text("limitFocus")) {
                        AgentsSegmentedControl(items: AgentsLimitFocus.allCases, selection: $model.limitFocus,
                                               title: \.title, label: AgentsStrings.text("limitFocus"))
                    }
                    HStack(spacing: IslandSpacing.s) {
                        Text(AgentsStrings.text("budget")).font(.islandBody)
                            .foregroundStyle(IslandPalette.textPrimary.color)
                        Spacer(minLength: IslandSpacing.s)
                        Text(model.dailyBudget.map { UsageFormat.cost($0, estimated: false) } ?? AgentsStrings.text("off"))
                            .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color)
                            .frame(minWidth: 70, alignment: .trailing)
                        Button(AgentsStrings.lessBudget, systemImage: "minus") { stepBudget(by: -5) }
                            .labelStyle(.iconOnly).buttonStyle(.island)
                            .disabled(model.dailyBudget == nil)
                        Button(AgentsStrings.moreBudget, systemImage: "plus") { stepBudget(by: 5) }
                            .labelStyle(.iconOnly).buttonStyle(.island)
                    }
                }
            }
        }
    }

    /// Steps of 5, from 0 (= off) to 1000; the system Stepper cannot be drawn in a snapshot.
    private func stepBudget(by delta: Double) {
        let next = min(1000, max(0, (model.dailyBudget ?? 0) + delta))
        model.dailyBudget = next > 0 ? next : nil
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
