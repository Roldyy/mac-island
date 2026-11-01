// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Combine
import Foundation

/// Mac Island never updates itself from inside the ported code: no check, no download, no host.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var availableNotes: String?
    var autoCheckEnabled = false
    var includeBetaUpdates = false

    private init() {}

    func checkIfStale() {}

    func check(manual: Bool = false) {}
}

/// Release notes of the ported app: Mac Island has its own "Nouveautés" page, so these are always empty.
struct ReleaseNotes {
    let version: String
    let date: String?
    let sections: [ReleaseNoteSection]

    static var current: ReleaseNotes { ReleaseNotes(version: AppInfo.version, date: nil, sections: []) }
}

struct ReleaseNoteSection {
    let title: String
    let items: [ReleaseNoteItem]
}

enum ReleaseNoteItem {
    case paragraph(String)
    case bullet(String)
    case image(ReleaseNoteImage)
}

struct ReleaseNoteImage {
    let path: String
    let alt: String
}

/// Vorssaint's uninstaller reset TCC and deleted its own support folders. Mac Island has its own page for that.
enum SelfUninstall {
    static func clearPermissions(_ completion: @escaping (Bool) -> Void) { completion(false) }

    static func uninstallCompletely(_ completion: @escaping (String) -> Void) {
        completion("Cette action n’est pas disponible dans Mac Island.")
    }
}

/// Immutable-location check of the upstream installer (a running app on a read-only volume cannot log in at launch).
enum UpdateInstallerSupport {
    static func runsFromImmutableLocation(appPath: String, volumeIsReadOnly: (String) -> Bool) -> Bool {
        appPath.contains("/AppTranslocation/") || volumeIsReadOnly(appPath)
    }
}
