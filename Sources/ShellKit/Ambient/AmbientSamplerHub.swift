import AppKit
import Foundation
import IslandKit

/// Starts and stops the samplers from one rule: a sampler runs only while the closed strip is on screen (the
/// island is closed), the displays are awake and the user switched its channel on. Anything else, it is stopped
/// and holds no timer and no listener.
@MainActor
public final class AmbientSamplerHub {
    private let center: AmbientCenter
    private let samplers: [any AmbientSampler]
    private let workspace: NotificationCenter
    private var running: Set<String> = []
    private var demand: AmbientDemand
    private var screensAwake = true
    private var observers: [NSObjectProtocol] = []
    private var started = false

    public init(center: AmbientCenter, samplers: [any AmbientSampler],
                workspace: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
        self.samplers = samplers
        self.workspace = workspace
        self.demand = center.demand
    }

    deinit {
        for observer in observers { workspace.removeObserver(observer) }
    }

    /// Channels whose sampler is running right now.
    public var runningChannels: Set<String> { running }

    public func start() {
        guard !started else { return }
        started = true
        center.observeDemand { [weak self] demand in self?.apply(demand) }
        // Display sleep: no screen to draw on, no reason to sample. Wake picks up where the demand stands.
        for (name, awake) in [(NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true),
                              (NSWorkspace.willSleepNotification, false), (NSWorkspace.didWakeNotification, true)] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setScreensAwake(awake) }
            })
        }
    }

    public func stop() {
        started = false
        for sampler in samplers where running.contains(sampler.channel) { sampler.stop() }
        running.removeAll()
        for observer in observers { workspace.removeObserver(observer) }
        observers.removeAll()
    }

    public func setScreensAwake(_ awake: Bool) {
        guard awake != screensAwake else { return }
        screensAwake = awake
        reconcile()
    }

    func apply(_ new: AmbientDemand) {
        let settingsChanged = new.settings != demand.settings
        demand = new
        guard started else { return }
        reconcile()
        if settingsChanged {
            for sampler in samplers where running.contains(sampler.channel) { sampler.settingsChanged(new.settings) }
        }
    }

    private func reconcile() {
        guard started else { return }
        for sampler in samplers {
            let wanted = screensAwake && demand.wants(sampler.channel)
            let isRunning = running.contains(sampler.channel)
            if wanted, !isRunning {
                running.insert(sampler.channel)
                sampler.start(settings: demand.settings)
            } else if !wanted, isRunning {
                running.remove(sampler.channel)
                sampler.stop()
            }
        }
    }
}
