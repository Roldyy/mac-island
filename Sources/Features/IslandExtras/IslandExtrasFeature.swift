import IslandKit
import SwiftUI

/// Four small opt-in extras: the "Notes", "Couleurs" and "Batterie" tabs of the island and the "Réseau perdu /
/// rétabli" notice. All off by default; the registry descriptors live in `ShellDescriptors`.
///
/// `start` and `stop` are idempotent and read nothing, send nothing and never prompt. Only the notice does work in the
/// background (a path monitor, which `stop` cancels); the tabs read only while they are on screen.
public enum IslandExtrasFeature {
    public static let notesID = "notesTab"
    public static let colorsID = "colorsTab"
    public static let batteryID = "batteryTab"
    public static let networkNoticeID = "networkNotice"

    /// Created on first use, so building the tab list creates nothing and reads no file.
    @MainActor static let notes = NotesModel()
    @MainActor static let colours = ColoursModel(defaults: AppDefaults.make() ?? .standard)
    @MainActor static let networkNotice = NetworkNoticeMonitor()

    @MainActor public static func notesTab() -> IslandTab {
        IslandTab(id: notesID, title: "Notes", systemImage: "note.text") { AnyView(NotesTabView(model: notes)) }
    }

    @MainActor public static func colorsTab() -> IslandTab {
        IslandTab(id: colorsID, title: "Couleurs", systemImage: "eyedropper") { AnyView(ColoursTabView(model: colours)) }
    }

    @MainActor public static func batteryTab() -> IslandTab {
        IslandTab(id: batteryID, title: "Batterie", systemImage: "battery.100percent") { AnyView(BatteryTabView()) }
    }

    @MainActor public static func tabs() -> [IslandTab] { [notesTab(), colorsTab(), batteryTab()] }

    /// Arms the feature `id` (a feature id of `ShellDescriptors`). Only the network notice has anything to arm.
    @MainActor public static func start(_ id: String) {
        if id == networkNoticeID { networkNotice.start() }
    }

    /// Disarms it. For the notice: cancels the path monitor.
    @MainActor public static func stop(_ id: String) {
        if id == networkNoticeID { networkNotice.stop() }
    }

    @MainActor public static func isRunning(_ id: String) -> Bool {
        id == networkNoticeID && networkNotice.isRunning
    }
}
