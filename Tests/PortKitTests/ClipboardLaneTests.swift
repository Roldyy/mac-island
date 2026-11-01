import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W5A. The history store stays OURS (`ClipboardLane` explains why); these tests pin the three things that
/// decision rests on, and the lane's one binding: the stopper that finally reaches our recorder. Fakes only: a
/// recording runtime, a temporary defaults suite, a temporary crash marker. Nothing here touches the real
/// pasteboard, the real history folder or the `ClipboardHistoryService` singleton.
@MainActor
@Suite(.serialized) struct ClipboardLaneTests {
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        var events: [String] { lock.lock(); defer { lock.unlock() }; return stored }
        func add(_ event: String) { lock.lock(); stored.append(event); lock.unlock() }
    }

    func runtime(_ log: Log) -> ClipboardLane.Runtime {
        ClipboardLane.Runtime(stopModule: { log.add("stop") })
    }

    /// The app delegate's wiring: the bound starters, then OUR starter for `clipboard` over them.
    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig(on: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        ClipboardLane.bind(into: binding, runtime: runtime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, withdraw: { _ in })
        registry.switches["clipboard"] = on
        registry.launch(
            starters: binding.starters.merging(["clipboard": { log.add("our start") }]) { _, ours in ours },
            stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Binding

    @Test func theLaneAdoptsTheStopperAndAddsNothingToTheFeatureList() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        ClipboardLane.bind(into: binding, runtime: runtime(Log()))
        #expect(binding.descriptors.isEmpty, "the registry already holds OUR descriptor `clipboard`")
        #expect(binding.pages.isEmpty, "no ported page: the declarative pages of ShellKit are the bodies")
        #expect(Set(binding.starters.keys) == ["clipboard"] && Set(binding.stoppers.keys) == ["clipboard"])
        #expect(PortFeatureIDs.registryID(forUpstream: "clipboardHistory") == "clipboard")
    }

    @Test func oneImplementation_plainPasteAndTheHistoryAreNeverBoundAsPortedFeatures() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        ClipboardLane.bind(into: binding, runtime: runtime(Log()))
        #expect(!binding.descriptors.contains { $0.id == "pastePlain" || $0.id == "clipboardHistory" })
        #expect(binding.starters["pastePlain"] == nil, "the plain-paste hotkey is owned by Features/Clipboard")
        // Binding the URL cleaner is the foundation lane's job and stays so: this lane does not rebind it.
        #expect(binding.starters["urlCleaner"] == nil)
    }

    @Test func registryOffKillSwitchStopOurRecorderAndOurStarterStillWins() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.log.events == ["our start"], "the delegate's starter runs, the bound no-op start does not replace it")
        r.registry.switches["clipboard"] = false
        #expect(r.log.events.last == "stop", "switching the feature off reaches the recorder")
        r.registry.switches["clipboard"] = true
        #expect(r.log.events.suffix(1) == ["our start"])
        r.registry.killSwitch = true
        #expect(r.log.events.last == "stop", "the kill switch stops monitoring")
        r.registry.killSwitch = false
        #expect(r.log.events.last == "our start")
    }

    @Test func theBoundIdIsNotStartedForThePortedSideSoItsServicesStayDown() {
        let r = rig()
        defer { r.cleanup() }
        // Our starter replaced the bound one, so the binding never saw a start: `AppFeature.clipboardHistory
        // .isAvailable` reads false on the ported side (the services that gate on it stay down).
        #expect(r.binding.availability("clipboard") == false)
        #expect(PortClipboard.portedStoreOwnsHistory == false)
    }

    @Test func liveStopperPostsTheNameOurModelListensTo() {
        let center = NotificationCenter.default
        let got = Box(0)
        let token = center.addObserver(forName: PortClipboard.stopNotification, object: nil, queue: nil) { _ in
            got.value += 1
        }
        defer { center.removeObserver(token) }
        ClipboardLane.Runtime.live.stopModule()
        #expect(got.value == 1)
    }

    // MARK: Cross-target contracts (read from the sources)

    @Test func theNotificationNameIsTheSameStringOnBothSides() throws {
        let bridge = try Self.source("Sources/PortKit/Bridge/Clipboard.swift")
        let module = try Self.source("Sources/Features/Clipboard/ClipboardFeature.swift")
        let name = "be.roldy.macisland.clipboard.stop"
        #expect(bridge.contains("Notification.Name(\"\(name)\")"))
        #expect(module.contains("Notification.Name(\"\(name)\")"))
        #expect(PortClipboard.stopNotification.rawValue == name)
    }

    @Test func theAppDelegateKeepsOurStarterBecauseTheBoundOneIsANoOp() throws {
        let delegate = try Self.source("Sources/MacIsland/AppDelegate.swift")
        #expect(delegate.contains("\"clipboard\": { ClipboardFeature.start() }"),
                "without it nothing starts the history: the lane's start is a no-op by design")
        #expect(delegate.contains("ClipboardFeature.tab()"), "the island tab stays")
    }

    @Test func thePortedHistoryServiceCannotRecordWriteOrSweepWhileOursIsTheStore() throws {
        let text = try Self.source("Sources/PortKit/Services/Clipboard/ClipboardHistoryService.swift")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func body(after signature: String) -> [String] {
            guard let i = lines.firstIndex(where: { $0.contains(signature) }) else { return [] }
            return Array(lines[(i + 1)...].prefix(6))
        }
        let guardLine = "guard PortClipboard.portedStoreOwnsHistory else { return }"
        #expect(body(after: "private func start() {").contains { $0.contains(guardLine) }, "no second watcher")
        #expect(body(after: "private func persist() {").contains { $0.contains(guardLine) }, "no write of our file")
        let cleanup = lines.drop { !$0.contains("static func cleanup(keeping") }.prefix(24)
        let guardIndex = cleanup.firstIndex { $0.contains(guardLine) }
        let deleteIndex = cleanup.firstIndex { $0.contains("removeItem(at: file)") }
        #expect(guardIndex != nil && deleteIndex != nil, "no sweep of our ClipboardImages folder")
        #expect((guardIndex ?? Int.max) < (deleteIndex ?? Int.min), "the guard comes before the deletion")
        #expect(PortClipboard.portedStoreOwnsHistory == false)
    }

    // MARK: The evidence for KEEP: the ported decoder against the file OUR store writes

    /// The file as our store writes it (`ClipboardEntry.encode`): `pinned` as a Bool, ids as strings.
    static func ourFile(extraEntry: String = "") -> Data {
        Data("""
        [
          {"id":"AAAAAAAA-0000-0000-0000-000000000001","kind":"text","text":"synthetic pinned","filePaths":[],
           "sourceBundleID":"com.example.a","copiedAt":814980691.5,"pinned":true},
          {"id":"AAAAAAAA-0000-0000-0000-000000000002","kind":"image","text":"","filePaths":[],
           "copiedAt":814980600.0,"imageFile":"AAAAAAAA-0000-0000-0000-000000000002.png","imageHash":"abc",
           "imageWidth":10,"imageHeight":20,"pinned":false}\(extraEntry)
        ]
        """.utf8)
    }

    @Test func theNeighbourFormatReadsOurFileButForgetsEveryPin() throws {
        let decoded = try JSONDecoder().decode([ClipboardHistoryEntry].self, from: Self.ourFile())
        #expect(decoded.count == 2, "text and image entries do decode")
        #expect(decoded[0].text == "synthetic pinned")
        #expect(decoded[0].isPinned == false,
                "our `pinned: true` is not what it reads (`pinnedAt`): replacing our store without a patch loses pins")
        #expect(decoded[1].imageFile == "AAAAAAAA-0000-0000-0000-000000000002.png")
    }

    @Test func theNeighbourFormatLosesTheWholeHistoryOnOneEntryItCannotRead() {
        // An id that is not a UUID is valid for our store and fatal for the ported decoder: all or nothing.
        let odd = ",{\"id\":\"not-a-uuid\",\"kind\":\"text\",\"text\":\"x\",\"filePaths\":[],\"copiedAt\":1.0}"
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([ClipboardHistoryEntry].self, from: Self.ourFile(extraEntry: odd))
        }
    }

    @Test func theNeighbourFormatKeepsOnlyOneConcealedMarker() {
        #expect(ClipboardHistorySensitiveText.isConcealed(["org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardHistorySensitiveText.isConcealed(["org.nspasteboard.TransientType"]),
                "ours refuses transient too: a store swap would start recording those")
        #expect(!ClipboardHistorySensitiveText.isConcealed(["org.nspasteboard.AutoGeneratedType"]))
    }

    // MARK: Descriptor and permission tables of the three upstream ids

    @Test func theThreeUpstreamFeaturesNeedOnlyWhatTheyUse() {
        #expect(PortFeatureBinding.descriptor(for: .clipboardHistory).permissions.isEmpty)
        #expect(PortFeatureBinding.descriptor(for: .urlCleaner).permissions.isEmpty)
        #expect(PortFeatureBinding.descriptor(for: .pastePlain).permissions == [.accessibility])
        #expect(PortFeatureBinding.risk(of: .clipboardHistory) == .safe)
        #expect(PortFeatureBinding.risk(of: .urlCleaner) == .safe)
        #expect(PortFeatureBinding.risk(of: .pastePlain) == .touchesInput)
        #expect(PortFeatureBinding.category(of: AppFeature.clipboardHistory.group) == .files)
    }

    // MARK: Helpers

    static func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }
}
