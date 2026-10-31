import Foundation

/// Read/write side of the preferences store. UserDefaults in the app, an in-memory fake in tests.
protocol AgentsKeyValueStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: AgentsKeyValueStore {}

/// `notchAgentsPeriod` is a migrated key (old name kept): the old app stored today / week / month.
struct AgentsSettings {
    static let periodKey = "notchAgentsPeriod"

    let store: any AgentsKeyValueStore

    init(store: any AgentsKeyValueStore) { self.store = store }

    /// An absent or unknown value means the month, the view this tab always had.
    var period: UsagePeriod {
        (store.object(forKey: Self.periodKey) as? String).flatMap(UsagePeriod.init(rawValue:)) ?? .month
    }

    func save(period: UsagePeriod) { store.set(period.rawValue, forKey: Self.periodKey) }
}
