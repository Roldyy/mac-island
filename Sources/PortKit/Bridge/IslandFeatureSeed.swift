// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// Some ported features check a SECOND switch of their own on top of the registry's (`shell.enabled.<id>`): an upstream
/// key (`notchMascotEnabled`, `notchLiveEqualizer`, `notchLockScreen`, `notchLyricsEnabled`...) that upstream registers
/// off, or that its first-launch migration forces off (`Defaults.migrateExistingNotchDefaults`). Upstream's own page was
/// the only place a person turned the feature on. In Mac Island the Fonctions switch is the opt-in, so a feature
/// switched on there while its second key still said off did nothing at all: no companion, no equalizer, no lyrics.
///
/// The rule, applied on every start of the feature (the registry's switch is ON by then): a gate key that is ABSENT from the
/// person's stored defaults is written ON. A key that is stored, true or false, is a choice and is never touched, so the
/// toggle on the feature's own page keeps winning across restarts. Idempotent: the second start finds the key stored.
enum IslandFeatureSeed {
    /// registry id -> the upstream keys that gate the feature.
    static let gateKeys: [String: [String]] = [
        "notchMascot": [DefaultsKey.notchMascotEnabled],
        "notchLiveEqualizer": [DefaultsKey.notchLiveEqualizer],
        "notchNotifications": [DefaultsKey.notchNotificationsEnabled],
        "notchAccessories": [DefaultsKey.notchAccessoriesEnabled],
        "notchLyrics": [DefaultsKey.notchLyricsEnabled],
        "notchQueue": [DefaultsKey.notchQueueEnabled],
        "notchDownloads": [DefaultsKey.notchDownloadsEnabled],
        "cameraPreview": [DefaultsKey.notchCameraEnabled],
        "lockscreen": [DefaultsKey.notchLockScreen],
    ]

    /// True when the person's own domain holds a value for the key (a registered default does not count). Tests replace it.
    nonisolated(unsafe) static var isStored: (UserDefaults, String) -> Bool = { defaults, key in
        defaults.persistentDomain(forName: PortHost.bundleID)?[key] != nil
    }

    @discardableResult
    static func seed(feature: String, in defaults: UserDefaults = PortHost.defaults) -> [String] {
        var written: [String] = []
        for key in gateKeys[feature] ?? [] where !isStored(defaults, key) {
            defaults.set(true, forKey: key)
            written.append(key)
        }
        return written
    }

    // MARK: One-shot repair

    static let repairMarker = "macIslandGateRepair.v1"

    /// The seven keys the first-launch migration forced off, and the value upstream's default profile gives each.
    static let forcedOff: [(key: String, defaultProfile: Bool)] = [
        (DefaultsKey.notchNotificationsEnabled, true), (DefaultsKey.notchCameraEnabled, true),
        (DefaultsKey.notchAccessoriesEnabled, true), (DefaultsKey.notchLyricsEnabled, true),
        (DefaultsKey.notchLiveEqualizer, false), (DefaultsKey.notchQueueEnabled, true),
        (DefaultsKey.notchDownloadsEnabled, true),
    ]

    /// Once per profile. A profile that was installed fresh before `IslandFirstLaunch` carries ALL seven keys stored off,
    /// together, which nobody does by hand; the repair puts them back to upstream's default profile. Any one of them stored
    /// ON (or missing) means the person has chosen: nothing is touched. The marker is written either way, so a later choice
    /// is never read as damage. Returns the keys it rewrote.
    @discardableResult
    static func repairForcedOffGates(in defaults: UserDefaults = PortHost.defaults) -> [String] {
        guard !defaults.bool(forKey: repairMarker) else { return [] }
        defaults.set(true, forKey: repairMarker)
        let allForced = forcedOff.allSatisfy { isStored(defaults, $0.key) && !defaults.bool(forKey: $0.key) }
        guard allForced else { return [] }
        for item in forcedOff { defaults.set(item.defaultProfile, forKey: item.key) }
        return forcedOff.filter(\.defaultProfile).map(\.key)
    }
}

/// First launch of the island. Upstream registers `notchEnabled` off; here the island is the app, so a first launch stores
/// it on. The write must come AFTER upstream's registration and migrations: `migrateExistingNotchDefaults` reads any saved
/// `notch*` key as "this island was configured before" and forces seven switches off. `fresh` is read before the
/// registration, because a registered default would hide that the key is absent.
public enum IslandFirstLaunch {
    public static func storeIslandOn(in defaults: UserDefaults, register: () -> Void) {
        let fresh = defaults.object(forKey: "notchEnabled") == nil
        register()
        if fresh { defaults.set(true, forKey: "notchEnabled") }
        IslandFeatureSeed.repairForcedOffGates(in: defaults)
    }
}
