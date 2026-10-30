import CoreAudio
import Foundation

/// One CoreAudio process object that has output running.
struct PlayingProcess: Equatable {
    var pid: Int32
    var bundleID: String?
}

/// Which apps are making sound. A browser plays through helper processes with their own pid, so a
/// process is attributed to the app that owns it (same pid, a parent in the pid tree, or an app
/// bundle id that prefixes the helper's own).
enum AudioActivity {
    struct Attribution: Equatable {
        /// Pids of apps (from `appPIDs`) that own at least one process running output.
        var appPIDs: Set<Int32> = []
        /// A process runs output that no known app owns (a system XPC service such as a web engine's
        /// audio process): the caller must then assume any app may be the source.
        var hasUnattributed = false
    }

    static let maxDepth = 32

    /// - `appPIDs`: running apps by pid with their bundle id (the apps that may be quit).
    /// - `knownPIDs`: every running application, agents included; audio from one of those is never
    ///   "unattributed" (a menu-bar helper playing sound is not a mystery).
    static func attribute(playing: [PlayingProcess], apps: [Int32: String],
                          knownPIDs: Set<Int32>, parentOf: (Int32) -> Int32?) -> Attribution {
        var result = Attribution()
        for process in playing {
            if let owner = owner(of: process, apps: apps, parentOf: parentOf) {
                result.appPIDs.insert(owner)
            } else if !knownPIDs.contains(process.pid) {
                result.hasUnattributed = true
            }
        }
        return result
    }

    private static func owner(of process: PlayingProcess, apps: [Int32: String],
                              parentOf: (Int32) -> Int32?) -> Int32? {
        if apps[process.pid] != nil { return process.pid }
        var seen: Set<Int32> = [process.pid]
        var current = process.pid
        for _ in 0..<maxDepth {
            guard let parent = parentOf(current), parent > 1, seen.insert(parent).inserted else { break }
            if apps[parent] != nil { return parent }
            current = parent
        }
        guard let bundle = process.bundleID, !bundle.isEmpty else { return nil }
        // Longest bundle id that prefixes the helper's at a dot boundary.
        return apps.filter { bundle.hasPrefix($0.value + ".") }
            .max { $0.value.count < $1.value.count }?.key
    }

    static func playingProcesses() -> [PlayingProcess] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        var found: [PlayingProcess] = []
        for object in objects {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &runAddress, 0, nil, &runSize, &running) == noErr,
                  running != 0 else { continue }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }
            var bundle: String?
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var cf: Unmanaged<CFString>?
            var cfSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &cf) {
                AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &cfSize, $0)
            }
            if status == noErr, let cf { bundle = cf.takeRetainedValue() as String }
            found.append(PlayingProcess(pid: pid, bundleID: bundle))
        }
        return found
    }
}
