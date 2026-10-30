import CoreGraphics
import Testing
@testable import DockFeature

@MainActor final class FakeMouseSource: MouseEventSource {
    var startCount = 0
    var stopCount = 0
    var isRunning = false
    var handler: ((MouseEvent) -> Void)?
    func start(_ handler: @escaping (MouseEvent) -> Void) {
        startCount += 1; isRunning = true; self.handler = handler
    }
    func stop() { stopCount += 1; isRunning = false; handler = nil }
}

@MainActor @Suite struct DockFeatureLifecycleTests {
    @Test func startAndStopAreIdempotent() {
        let source = FakeMouseSource()
        let c = DockCoordinator(source: source, click: nil, preview: nil)
        c.start(); c.start()
        #expect(source.startCount == 1 && c.isStarted)
        c.stop(); c.stop()
        #expect(source.stopCount == 1 && !c.isStarted)
        c.start()
        #expect(source.startCount == 2)
    }
    @Test func stopBeforeStartIsANoOp() {
        let source = FakeMouseSource()
        let c = DockCoordinator(source: source, click: nil, preview: nil)
        c.stop()
        #expect(source.stopCount == 0)
    }
}
