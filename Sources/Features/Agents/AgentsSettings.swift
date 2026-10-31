import Foundation

/// Read/write side of the preferences store. UserDefaults in the app, an in-memory fake in tests.
protocol AgentsKeyValueStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: AgentsKeyValueStore {}

/// The page's preferences. Every key is a migrated one (old names kept) so Harold's settings carry over.
struct AgentsSettings {
    static let periodKey = "notchAgentsPeriod"
    static let cardOrderKey = "notchAgentsCardOrder"
    static let hiddenCardsKey = "notchAgentsHiddenCards"
    static let limitDisplayKey = "notchAgentsLimitDisplay"
    static let limitFocusKey = "notchAgentsLimitFocus"
    static let dailyBudgetKey = "notchAgentsDailyBudget"
    static let idleContentKey = "notchIdleContent"

    let store: any AgentsKeyValueStore

    init(store: any AgentsKeyValueStore) { self.store = store }

    /// An absent or unknown value means the month, the view this tab always had.
    var period: UsagePeriod {
        (store.object(forKey: Self.periodKey) as? String).flatMap(UsagePeriod.init(rawValue:)) ?? .month
    }

    func save(period: UsagePeriod) { store.set(period.rawValue, forKey: Self.periodKey) }

    var cardOrder: [AgentsCard] { AgentsCardLayout.order(from: store.object(forKey: Self.cardOrderKey)) }
    var hiddenCards: Set<AgentsCard> { AgentsCardLayout.hidden(from: store.object(forKey: Self.hiddenCardsKey)) }

    func save(cardOrder: [AgentsCard]) { store.set(cardOrder.map(\.rawValue), forKey: Self.cardOrderKey) }

    func save(hiddenCards: Set<AgentsCard>) {
        store.set(AgentsCard.allCases.filter(hiddenCards.contains).map(\.rawValue), forKey: Self.hiddenCardsKey)
    }

    var limitDisplay: AgentsLimitDisplay {
        (store.object(forKey: Self.limitDisplayKey) as? String).flatMap(AgentsLimitDisplay.init(rawValue:)) ?? .remaining
    }

    func save(limitDisplay: AgentsLimitDisplay) { store.set(limitDisplay.rawValue, forKey: Self.limitDisplayKey) }

    var limitFocus: AgentsLimitFocus {
        (store.object(forKey: Self.limitFocusKey) as? String).flatMap(AgentsLimitFocus.init(rawValue:)) ?? .mostUsed
    }

    func save(limitFocus: AgentsLimitFocus) { store.set(limitFocus.rawValue, forKey: Self.limitFocusKey) }

    /// USD of API value per day. nil = off (absent, zero, negative or not a number).
    var dailyBudget: Double? {
        guard let value = (store.object(forKey: Self.dailyBudgetKey) as? NSNumber)?.doubleValue,
              value.isFinite, value > 0 else { return nil }
        return value
    }

    func save(dailyBudget: Double?) {
        store.set(dailyBudget.flatMap { $0 > 0 ? $0 : nil } ?? 0, forKey: Self.dailyBudgetKey)
    }

    /// The closed island shows our limit only when the user picked "agents" as its resting content.
    var showsLimitWhenClosed: Bool { (store.object(forKey: Self.idleContentKey) as? String) == "agents" }
}
