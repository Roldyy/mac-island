import IslandUI
import SwiftUI

/// The sliders row of the island home: a switch for the keyboard backlight slider. Handed to
/// `IslandLayoutSettings` through its `extras` slot by the app delegate (that file belongs to another lane).
/// The switch stays visible on a Mac without a controllable backlight, disabled and saying why.
public struct HomeSlidersSettings: View {
    @Bindable var home: HomeModel

    public init(home: HomeModel) { self.home = home }

    public var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Curseurs", subtitle: "Volume et luminosité sont toujours là ; le clavier s’ajoute si le Mac en a un.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    Toggle("Curseur du rétroéclairage du clavier", isOn: $home.showsKeyboardLight)
                        .toggleStyle(IslandToggleStyle())
                        .disabled(!home.keyboardLight.isAvailable)
                    Text(caption)
                        .font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { home.keyboardLight.refresh() }
    }

    private var caption: String {
        home.keyboardLight.isAvailable
            ? "Glissez, faites défiler ou utilisez les flèches sur le curseur pour régler l’éclairage des touches."
            : home.keyboardLight.unavailableReason
    }
}
