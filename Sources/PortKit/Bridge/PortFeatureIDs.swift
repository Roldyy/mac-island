// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// The one table between upstream `AppFeature` raw ids and the ids of Mac Island's `FeatureRegistry`.
///
/// A ported feature has no entry here when it is new to Mac Island: its registry id is its upstream raw id
/// (`scrollInverter`, `urlCleaner`...), so a migrated `featureAvailable.<id>` (copied to `shell.enabled.<id>`
/// by the migrator) lands on the very switch the registry reads. An entry exists when one of our own feature
/// modules already owns the switch under another name: the ported code then reads and writes THAT switch.
/// One upstream feature per registry id: where upstream splits one of our features in two (finderCutPaste and
/// finderRename into `finder`, dockPreview and dockClick into `dock`...) no row is added until a lane decides
/// how the two switches fold into one.
enum PortFeatureIDs {
    /// upstream raw id -> registry id of an existing module.
    static let existing: [String: String] = [
        "shelf": "shelf",
        "keepAwake": "keepawake",
        "clipboardHistory": "clipboard",
        "commandBar": "commandbar",
        "mixer": "audio",
        "fanControl": "fans",
    ]

    static func registryID(forUpstream raw: String) -> String { existing[raw] ?? raw }

    /// True when one of our modules already owns the switch, so `PortFeatureBinding` must not add a descriptor.
    static func isOwnedByExistingModule(_ raw: String) -> Bool { existing[raw] != nil }
}

extension AppFeature {
    /// The id of this feature in `FeatureRegistry`, and the suffix of its `shell.enabled.<id>` key.
    var registryID: String { PortFeatureIDs.registryID(forUpstream: rawValue) }
}
