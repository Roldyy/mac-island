import Foundation

/// The migrated Vorssaint keys, read tolerantly, in the defaults suite `be.roldy.macisland`.
/// Real shapes seen on this machine (read-only inspection): `appVolumes` = dictionary of bundle id to
/// float; `appVolumesArePositions` = bool; `audioPriorityOutputUIDs` / `audioPriorityInputUIDs` = arrays
/// of strings; `audioPriorityDeviceNames` = dictionary UID to name string. Anything else reads as empty.
final class AudioSettings {
    static let suiteName = "be.roldy.macisland"

    private enum Key {
        static let volumes = "appVolumes"
        static let arePositions = "appVolumesArePositions"
        static let muted = "mixerMutedApps"          // ours: the old data has no mute key
        static let outputUIDs = "audioPriorityOutputUIDs"
        static let inputUIDs = "audioPriorityInputUIDs"
        static let names = "audioPriorityDeviceNames"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    static func standard() -> AudioSettings {
        AudioSettings(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
    }

    // MARK: Per-app volume

    /// Slider positions in 0...1. Old data stored as linear gains (flag false or absent) is converted.
    var appPositions: [String: Double] {
        guard let raw = defaults.dictionary(forKey: Key.volumes) else { return [:] }
        let isPosition = defaults.bool(forKey: Key.arePositions)
        var result: [String: Double] = [:]
        for (bundleID, value) in raw {
            guard let number = value as? NSNumber, !bundleID.isEmpty else { continue }
            let v = number.doubleValue
            guard v.isFinite else { continue }
            let clamped = min(max(v, 0), 1)
            result[bundleID] = isPosition ? clamped : VolumeCurve.position(forGain: Float(clamped))
        }
        return result
    }

    var mutedApps: Set<String> {
        Set((defaults.array(forKey: Key.muted) as? [String]) ?? [])
    }

    func setPosition(_ position: Double, for bundleID: String) {
        var all = appPositions // converts legacy gains first, so the flag below stays truthful
        all[bundleID] = min(max(position, 0), 1)
        defaults.set(all, forKey: Key.volumes)
        defaults.set(true, forKey: Key.arePositions)
    }

    func setMuted(_ muted: Bool, for bundleID: String) {
        var set = mutedApps
        if muted { set.insert(bundleID) } else { set.remove(bundleID) }
        defaults.set(set.sorted(), forKey: Key.muted)
    }

    // MARK: Device priority

    func priority(for direction: AudioDirection) -> [String] {
        let key = direction == .output ? Key.outputUIDs : Key.inputUIDs
        guard let raw = defaults.array(forKey: key) else { return [] }
        var seen = Set<String>()
        return raw.compactMap { $0 as? String }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func setPriority(_ uids: [String], for direction: AudioDirection) {
        var seen = Set<String>()
        let clean = uids.filter { !$0.isEmpty && seen.insert($0).inserted }
        defaults.set(clean, forKey: direction == .output ? Key.outputUIDs : Key.inputUIDs)
    }

    /// UID to last known display name, so an unplugged device still has a label in the editor.
    var deviceNames: [String: String] {
        (defaults.dictionary(forKey: Key.names) as? [String: String]) ?? [:]
    }

    func setDeviceName(_ name: String, for uid: String) {
        var all = deviceNames
        guard all[uid] != name else { return }
        all[uid] = name
        defaults.set(all, forKey: Key.names)
    }
}
