import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct CrashMarkerTests {
    func tempMarker() -> CrashMarker {
        // A nested folder that does not exist yet: begin() must create it.
        CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)")
            .appendingPathComponent("start.marker"))
    }

    func cleanup(_ marker: CrashMarker) {
        try? FileManager.default.removeItem(at: marker.url.deletingLastPathComponent())
    }

    @Test func beginWritesARealFileThatAFreshInstanceReads() throws {
        let marker = tempMarker(); defer { cleanup(marker) }
        marker.begin("dock")
        #expect(FileManager.default.fileExists(atPath: marker.url.path))
        #expect(try String(contentsOf: marker.url, encoding: .utf8) == "dock")
        // A relaunch is a new value pointing at the same file.
        #expect(CrashMarker(url: marker.url).pending() == "dock")
    }

    @Test func clearRemovesTheFileAndAMissingFileIsNotPending() {
        let marker = tempMarker(); defer { cleanup(marker) }
        #expect(marker.pending() == nil)
        marker.begin("dock")
        marker.clear()
        #expect(marker.pending() == nil)
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
    }

    @Test func aSecondBeginReplacesTheFirst() {
        let marker = tempMarker(); defer { cleanup(marker) }
        marker.begin("a-long-feature-id")
        marker.begin("dock")
        #expect(marker.pending() == "dock")
    }

    @Test func crashedStartIsChargedToItsFeatureOnTheNextLaunchThroughTheFile() {
        let marker = tempMarker(); defer { cleanup(marker) }
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        func launch() -> FeatureRegistry {
            FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
        }
        // Launch 1 dies inside dock's start(): the file is on disk, defaults never saw a thing.
        var registry = launch()
        registry.beginStart("dock")
        #expect(FileManager.default.fileExists(atPath: marker.url.path))
        registry = launch()
        #expect(registry.state(for: "dock") == .active, "one crash is not enough")
        #expect(marker.pending() == nil, "read once, then cleared")
        registry.beginStart("dock")  // launch 2 dies the same way
        registry = launch()
        #expect(registry.state(for: "dock") == .quarantined)
    }

    @Test func endStartDeletesTheFile() {
        let marker = tempMarker(); defer { cleanup(marker) }
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
        registry.beginStart("dock")
        registry.endStart("dock")
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
    }
}
