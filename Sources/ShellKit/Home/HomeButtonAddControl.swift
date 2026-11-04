import IslandUI
import SwiftUI

/// "Ajouter un bouton" of one side in the settings: opens the searchable picker in a popover and closes it once a
/// command is picked. Disabled while the side is full or no command is left to add.
struct HomeButtonAddControl: View {
    let side: HomeButtonSide
    let layout: HomeButtonLayout
    let catalog: [DockCommand]
    let availability: (DockCommand) -> DockAvailability
    let add: (String) -> Void

    @State private var picking = false

    var body: some View {
        let hasRoom = layout.hasRoom(on: side)
        let anyLeft = !HomeButtonPicker.candidates(catalog, layout: layout).isEmpty
        Button("Ajouter un bouton") { picking = true }
            .buttonStyle(IslandButtonStyle())
            .disabled(!hasRoom || !anyLeft)
            .help(hasRoom ? "Ajouter un bouton \(side.title.lowercased())"
                          : "Ce côté est plein (\(HomeButtonLayout.capacity(of: side)) boutons)")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                HomeButtonPicker(catalog: catalog, layout: layout, side: side, availability: availability) { id in
                    add(id)
                    // `layout` is the value from before this add: the side is full, or nothing is left, after it.
                    let willBeFull = layout.buttons(on: side).count + 1 >= HomeButtonLayout.capacity(of: side)
                    if willBeFull || HomeButtonPicker.candidates(catalog, layout: layout).count <= 1 { picking = false }
                }
            }
    }
}
