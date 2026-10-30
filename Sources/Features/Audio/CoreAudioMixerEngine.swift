import CoreAudio
import Foundation
import os

/// Per-app volume with Core Audio process taps (macOS 14.2+), one tap + one private aggregate per app.
///
/// Signal path: app audio -> tap (CATapMuted: the app no longer reaches the hardware itself) ->
/// aggregate device {tap input, output device} -> IOProc multiplies by the gain -> output device.
///
/// Verified in the SDK headers on this machine: AudioHardwareCreateProcessTap /
/// AudioHardwareDestroyProcessTap (macOS 14.2), CATapDescription (muteBehavior, isPrivate, processes),
/// AudioHardwareCreateAggregateDevice with kAudioAggregateDeviceTapListKey, AudioDeviceCreateIOProcIDWithBlock.
///
/// Teardown order on every exit: AudioDeviceStop, DestroyIOProcID, DestroyAggregateDevice, DestroyProcessTap.
/// A crash cannot leave a *persistent* mute through our aggregate (header: a private aggregate "is not
/// persistent across launches of the process that created it"; the tap is private to this process).
/// Whether the HAL destroys the tap itself when the process dies is UNKNOWN from the headers.
final class CoreAudioMixerEngine: MixerEngine, @unchecked Sendable {
    private struct Entry {
        var tapID: AudioObjectID
        var aggregateID: AudioObjectID
        var procID: AudioDeviceIOProcID
        var processor: GainProcessor
    }

    private var entries: [String: Entry] = [:]
    private let log = Logger(subsystem: "be.roldy.macisland", category: "audio")

    deinit { stopAll() }

    var liveApps: Set<String> { Set(entries.keys) }

    func start(app: String, processes: [UInt32], outputDeviceUID: String, gain: Float) throws {
        stop(app: app)
        guard #available(macOS 14.2, *) else { throw MixerEngineError.unavailable }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "MacIsland mixer"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .muted

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw MixerEngineError.tapCreationFailed(status: status) }

        let aggregateUID = CoreAudioSystem.aggregatePrefix + UUID().uuidString
        let dictionary: [String: Any] = [
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceNameKey: "MacIsland mixer",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: 1,
            ]],
        ]
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(dictionary as CFDictionary, &aggregateID)
        guard status == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            throw MixerEngineError.aggregateCreationFailed(status: status)
        }

        let processor = GainProcessor(cell: GainCell(initial: gain))
        var procID: AudioDeviceIOProcID?
        // Block runs on the HAL IO thread (queue nil): only GainProcessor.render, which does no
        // allocation, locking, logging or Objective-C messaging.
        let block: AudioDeviceIOBlock = { _, input, _, output, _ in
            processor.render(input: input, output: output)
        }
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil, block)
        guard status == noErr, let procID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw MixerEngineError.ioProcFailed(status: status)
        }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw MixerEngineError.startFailed(status: status)
        }
        entries[app] = Entry(tapID: tapID, aggregateID: aggregateID, procID: procID, processor: processor)
        log.info("tap started, live \(self.entries.count)")
    }

    func setGain(_ gain: Float, app: String) {
        entries[app]?.processor.cell.value = gain
    }

    func stop(app: String) {
        guard let entry = entries.removeValue(forKey: app) else { return }
        teardown(entry)
        log.info("tap stopped, live \(self.entries.count)")
    }

    func stopAll() {
        let all = entries
        entries.removeAll()
        for entry in all.values { teardown(entry) }
    }

    private func teardown(_ entry: Entry) {
        AudioDeviceStop(entry.aggregateID, entry.procID)
        AudioDeviceDestroyIOProcID(entry.aggregateID, entry.procID)
        AudioHardwareDestroyAggregateDevice(entry.aggregateID)
        if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(entry.tapID) }
    }
}
