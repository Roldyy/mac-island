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
    static let skippedExactV2: Set<String> = [
        "commandBarQueryHabitKey",
        "notchDownloadsFolderBookmark",
        "fanControlHelperVersion",
    ]
    static let skippedPrefixesV2 = [
        "whatsNew", "onboarding", "migration", "vorss", "SU", "NS", "AppleLanguages",
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
                let target = Self.switchTargetPrefix + id
                guard Self.isValidSwitchID(id), Self.isBoolean(value) else {
                    plan.report.typeMismatchKeys.append(key)
                    continue
                }
                if destDefaults.object(forKey: target) != nil {
                    plan.report.alreadyPresentKeys.append(target)
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
}
