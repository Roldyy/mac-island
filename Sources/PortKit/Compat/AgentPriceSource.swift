// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// The remote price table of Vorssaint lived on a Vorssaint host. Mac Island never downloads one: the agent
/// usage code keeps working with the built-in prices (or none) and its refresh always reports "nothing new".
enum AgentPriceSource {
    static let refreshInterval: TimeInterval = 86_400
    static let retryInterval: TimeInterval = 6 * 3_600

    static func bundled() -> AgentPriceList? { nil }

    static func cached() -> (list: AgentPriceList, saved: Date)? { nil }

    static func save(_ data: Data) {}

    static func download(completion: @escaping ((data: Data, list: AgentPriceList)?) -> Void) {
        completion(nil)
    }
}
