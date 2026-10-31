import AppKit
import IslandUI
import SwiftUI

/// Click, then press the new shortcut. Escape cancels. A shortcut needs ⌘, ⌥ or ⌃.
struct ShortcutRecorderView: View {
    let spec: ShortcutSpec?
    let fallbackText: String
    let onChange: (ShortcutSpec) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Appuyez sur le raccourci…" : (spec?.display ?? fallbackText))
                .font(.islandValue)
                .frame(minWidth: 120)
        }
        .buttonStyle(IslandButtonStyle(recording ? .prominent : .standard))
        .accessibilityLabel("Raccourci")
        .accessibilityValue(spec?.display ?? fallbackText)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // escape
                stop()
                return nil
            }
            if let new = ShortcutSpec.from(keyCode: event.keyCode, flags: event.modifierFlags) {
                onChange(new)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
