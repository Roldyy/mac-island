import CoreGraphics
import Observation

struct PreviewItem: Identifiable {
    let id: Int // index in the AX window list
    let title: String
    var thumbnail: CGImage?
    let isMinimized: Bool
}

@MainActor @Observable
final class PreviewModel {
    var appName = ""
    var items: [PreviewItem] = []
    var needsScreenRecording = false
    @ObservationIgnored var onRaise: (Int) -> Void = { _ in }
    @ObservationIgnored var onRequestScreenRecording: () -> Void = {}

    /// Drops every image: called when the panel hides.
    func clear() {
        items = []
        appName = ""
    }
}
