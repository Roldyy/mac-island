import Foundation

/// What the second import pass did, or would do. Names only: a value never goes into a report.
public struct MigrationV2Report: Equatable {
    /// Known keys written under their own name.
    public var carriedKeys: [String] = []
    /// `featureAvailable.<id>` turned into `shell.enabled.<id>` (the new key names).
    public var mappedSwitches: [String] = []
    /// Known keys left alone on purpose (onboarding, update markers, bookmarks, runtime state).
    public var skippedKeys: [String] = []
    /// Known keys whose value has another property-list type than the registered default.
    public var typeMismatchKeys: [String] = []
    /// Known keys, or switches, that our app already holds a value for. Never overwritten.
    public var alreadyPresentKeys: [String] = []
    /// Not a Vorssaint key we know: never written.
    public var unknownKeys: [String] = []
    public var backupURL: URL?
    public var alreadyDone = false
    public var nothingToMigrate = false

    public init() {}
}

extension VorssaintMigrator {
    public static let doneKeyV2 = "migration.vorssaint.v2.done"

    /// Kept out of the second pass. Same spirit as the first one: secrets, bookmarks bound to the old
    /// app's identity, onboarding and what's-new markers, system keys, and the old app's runtime state
    /// (`vorss*` holds crash-recovery notes about its own sleep and brightness changes).
    static let skippedExactV2: Set<String> = Set([
        "commandBarQueryHabitKey",
        "notchDownloadsFolderBookmark",
        "fanControlHelperVersion",
    ]).union(runtimeMarkerKeysV2)

    /// Crash and runtime markers that name a system change the old app applied and still owed back (or a
    /// security-scoped grant of its own identity). Carried here, a ported recovery step would "restore"
    /// state that this app never applied, or act on a stale grant. Each is machine state in upstream's own
    /// `SettingsBackup.machineStateKeys` (never exported there either). Only the ported services write
    /// them and none is bound yet, so removing them from our domain is safe (see `purgeRuntimeKeysV2`).
    /// `vorssDisabledSleep` / `vorssDimmedDisplaySavedBrightness` (pmset sleep, panel dimming) are
    /// already covered by the `vorss` prefix.
    static let runtimeMarkerKeysV2: Set<String> = [
        // Fans: hand-back owed to the helper, and a control to re-apply after launch.
        "fanControlRecoveryNeeded", "fanControlResume", "fanControlResumeConfiguration",
        // Keyboard mapping (hidutil) in place and the source to take back.
        "superKeyMappingApplied", "superKeyMappedSource",
        // Closed-lid mode that would re-run `pmset disablesleep` through the sudoers rule.
        "clamshellPreferred",
        // Security-scoped bookmark minted for the old app's identity.
        "wallpaperOwnBookmarks",
        // Native hotkeys switched off in the symbolic-hotkeys table, to give back.
        "systemShortcutsSuppressed", "switcherNativeHotkeysSuppressed",
        // Dock settings (autohide, Spaces arrangement) changed and owed back, Dock restart owed.
        "dockPreviewRestoreAutohide", "spacesOrderRestore", "spacesOrderRestartPending",
        // Bluetooth switched off for sleep and owed back.
        "bluetoothSleepRestorePending",
        // Microphone muted by lowering input volume: the volumes to put back, and who is muted.
        "micMuteActive", "micMuteSavedVolume", "micMuteSavedVolumes", "micMuteSavedChannelVolumes",
        "micMuteMutedDevices",
        // Displays switched off (and their fingerprints): a ported recovery would re-enable them.
        "displaysSwitchedOff", "displaysSwitchedOffFingerprints",
        // A start that did not finish: would make the ported code think this app crashed.
        "startupDidNotFinish",
    ]
    static let skippedPrefixesV2 = [
        "whatsNew", "onboarding", "migration", "vorss", "SU", "NS", "AppleLanguages",
    ]
    /// Upstream raw feature ids whose switch one of our own modules already owns under another id.
    /// Mirrors `PortFeatureIDs.existing` (PortKit); SettingsKit cannot depend on PortKit.
    static let upstreamToRegistryID: [String: String] = [
        "keepAwake": "keepawake", "clipboardHistory": "clipboard", "commandBar": "commandbar",
        "mixer": "audio", "fanControl": "fans",
        // The two Dock switches of upstream are one registry feature (`PortFeatureIDs.folded`): on when either was.
        "dockPreview": "dock", "dockClick": "dock",
    ]
    static let switchPrefix = "featureAvailable."
    static let switchTargetPrefix = "shell.enabled."

    static func isSkippedV2(_ key: String) -> Bool {
        skippedExactV2.contains(key) || skippedPrefixesV2.contains(where: key.hasPrefix)
    }

    /// A switch id is a Swift enum raw value; anything else would build a strange target key.
    static func isValidSwitchID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func isBoolean(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Whether `value` has the property-list type the registered default has. A key with no known
    /// kind is accepted as is.
    static func matches(_ kind: VorssaintValueKind?, _ value: Any) -> Bool {
        guard let kind else { return true }
        switch kind {
        case .bool:
            return isBoolean(value)
        case .int:
            guard !isBoolean(value), let number = value as? NSNumber else { return false }
            return !CFNumberIsFloatType(number)
        case .double:
            return !isBoolean(value) && value is NSNumber
        case .string:
            return value is String
        case .array:
            return value is [Any]
        }
    }

    private struct PlanV2 {
        var report = MigrationV2Report()
        var writes: [(key: String, value: Any)] = []
    }

    /// Decides everything without writing anything. Pure with respect to the destination.
    private func planV2() -> PlanV2 {
        var plan = PlanV2()
        for key in sourceDomain.keys.sorted() {
            guard let value = sourceDomain[key] else { continue }

            if key.hasPrefix(Self.switchPrefix) {
                let id = String(key.dropFirst(Self.switchPrefix.count))
                let target = Self.switchTargetPrefix + (Self.upstreamToRegistryID[id] ?? id)
                guard Self.isValidSwitchID(id), Self.isBoolean(value) else {
                    plan.report.typeMismatchKeys.append(key)
                    continue
                }
                if destDefaults.object(forKey: target) != nil {
                    plan.report.alreadyPresentKeys.append(target)
                } else if let pending = plan.writes.firstIndex(where: { $0.key == target }) {
                    // Two upstream switches fold into one registry switch (dockPreview + dockClick -> dock):
                    // it is on when either was on.
                    if (value as? NSNumber)?.boolValue == true { plan.writes[pending].value = value }
                } else {
                    plan.writes.append((target, value))
                    plan.report.mappedSwitches.append(target)
                }
                continue
            }

            guard VorssaintKnownKeys.all.contains(key) else {
                plan.report.unknownKeys.append(key)
                continue
            }
            if Self.isSkippedV2(key) {
                plan.report.skippedKeys.append(key)
                continue
            }
            if !Self.matches(VorssaintKnownKeys.kinds[key], value) {
                plan.report.typeMismatchKeys.append(key)
                continue
            }
            if destDefaults.object(forKey: key) != nil {
                plan.report.alreadyPresentKeys.append(key)
                continue
            }
            plan.writes.append((key, value))
            plan.report.carriedKeys.append(key)
        }
        return plan
    }

    /// Second pass, after `run()`: carries every known key that the first pass left behind.
    /// Backup first (preferences only), never overwrites a key already in the destination, runs once.
    public func runV2() throws -> MigrationV2Report {
        if destDefaults.bool(forKey: Self.doneKeyV2) {
            var done = MigrationV2Report()
            done.alreadyDone = true
            return done
        }
        if sourceDomain.isEmpty {
            var empty = MigrationV2Report()
            empty.nothingToMigrate = true
            return empty
        }

        var plan = planV2()
        if !plan.writes.isEmpty {
            var ignored: [String] = []
            plan.report.backupURL = try backup(
                supportExists: false, links: &ignored, folderPrefix: "vorssaint-v2")
            for (key, value) in plan.writes { destDefaults.set(value, forKey: key) }
        }
        destDefaults.set(true, forKey: Self.doneKeyV2)
        return plan.report
    }

    // MARK: - Purge of already-carried runtime markers

    public static let purgeRuntimeKeysDoneKey = "migration.v2.purgeRuntimeKeys.done"

    /// One-shot clean-up for a Mac where the first v2 pass (before these keys were skipped) already copied
    /// them. Removes exactly `runtimeMarkerKeysV2` from `defaults` (our domain, never the source) and
    /// returns how many were present. Counts only: no key name or value is returned or logged.
    @discardableResult
    public static func purgeRuntimeKeysV2(in defaults: UserDefaults) -> Int {
        guard !defaults.bool(forKey: purgeRuntimeKeysDoneKey) else { return 0 }
        var removed = 0
        for key in runtimeMarkerKeysV2 where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        defaults.set(true, forKey: purgeRuntimeKeysDoneKey)
        return removed
    }

    public static let switchIDRepairDoneKey = "migration.v2.switchIDRepair.done"

    /// Pass 2 first wrote `shell.enabled.<upstream id>` for the five features our own modules own under
    /// another id (`keepAwake` -> `keepawake`...). Moves such a value to the key the registry reads, only when
    /// that key is absent, and removes the stray one. Runs once; returns how many switches moved (count only).
    @discardableResult
    public static func repairSwitchIDsV2(in defaults: UserDefaults) -> Int {
        guard !defaults.bool(forKey: switchIDRepairDoneKey) else { return 0 }
        var moved = 0
        var movedTargets: Set<String> = []
        for (upstream, registry) in upstreamToRegistryID.sorted(by: { $0.key < $1.key }) {
            let stray = switchTargetPrefix + upstream
            let right = switchTargetPrefix + registry
            guard let value = defaults.object(forKey: stray) else { continue }
            if defaults.object(forKey: right) == nil, isBoolean(value) {
                defaults.set(value, forKey: right)
                movedTargets.insert(right)
                moved += 1
            } else if movedTargets.contains(right), isBoolean(value), (value as? NSNumber)?.boolValue == true {
                defaults.set(true, forKey: right)  // two strays fold into one switch (the Dock's): on when either was
            }
            defaults.removeObject(forKey: stray)
        }
        defaults.set(true, forKey: switchIDRepairDoneKey)
        return moved
    }
}
