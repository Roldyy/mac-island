import IslandKit
import IslandUI
import SwiftUI

/// What "Dynamic Island" can edit besides the indicators: the size of the open island, its look, the fit around the
/// hardware notch, the round buttons on each side and the shortcuts hidden from the grid. It drives OUR island only:
/// every control writes `HomeModel`, which persists under the key names the reference app used (`notchSize`,
/// `notchQuickAccessLayout`...) and which the island already observes, so a change shows at once.
///
/// Registered by the app delegate as the body of the `island` page (`SettingsPageBodies`); the indicators above it stay
/// the declarative live rows of `SettingsLive`.
public struct IslandLayoutSettings: View {
    @Bindable var home: HomeModel
    /// Opens the island so the change can be seen. Nil leaves the button out (tests, no island).
    var openIsland: (@MainActor () -> Void)?

    /// Extra sections hosted under the editors (the ported lock-screen, companion and combine settings). ShellKit
    /// does not see the ported code, so the app hands the view in.
    var extras: (@MainActor () -> AnyView)?

    /// Every command the extra dock can hold (`ShellContext.dockCatalog`). Nil leaves the editor without names.
    var dockCatalog: (@MainActor () -> [DockCommand])?

    /// Whether a command can run now (`ShellContext.dockAvailability`), for the reasons the picker shows.
    /// Nil lists every command as available.
    var dockAvailability: (@MainActor (DockCommand) -> DockAvailability)?

    public init(home: HomeModel, openIsland: (@MainActor () -> Void)? = nil,
                extras: (@MainActor () -> AnyView)? = nil,
                dockCatalog: (@MainActor () -> [DockCommand])? = nil,
                dockAvailability: (@MainActor (DockCommand) -> DockAvailability)? = nil) {
        self.home = home
        self.openIsland = openIsland
        self.extras = extras
        self.dockCatalog = dockCatalog
        self.dockAvailability = dockAvailability
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.l) {
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    Toggle("Activer Dynamic Island", isOn: $home.islandEnabled).toggleStyle(IslandToggleStyle())
                    caption("Facultatif. Désactivé, l’île disparaît de l’écran ; l’icône de la barre des menus et le panneau rapide restent.")
                }
            }
            if let openIsland {
                Button("Ouvrir Dynamic Island", systemImage: "rectangle.topthird.inset.filled", action: openIsland)
                    .buttonStyle(IslandButtonStyle())
                    .disabled(!home.islandEnabled)
            }
            sizeCard
            lookCard
            fitCard
            buttonsCard
            extraDockCard
            tilesCard
            if let extras { extras() }
        }
    }

    // MARK: - Size

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Taille", subtitle: "Compacte ou spacieuse, ou vos propres dimensions.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.m) {
                        ForEach(IslandSizeMode.allCases) { mode in sizeTile(mode) }
                    }
                    if home.sizeMode == .custom {
                        Divider()
                        labelledSlider("Largeur", value: $home.customWidth, range: HomeGeometry.customWidthRange, unit: " pt")
                        labelledSlider("Hauteur", value: $home.customHeight, range: HomeGeometry.customHeightRange, unit: " pt")
                    }
                }
            }
        }
    }

    private func sizeTile(_ mode: IslandSizeMode) -> some View {
        let selected = home.sizeMode == mode
        return Button {
            home.sizeMode = mode
        } label: {
            VStack(spacing: IslandSpacing.xs) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 20))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(IslandPalette.textPrimary.color.opacity(0.08), in: RoundedRectangle(cornerRadius: IslandRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: IslandRadius.small)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(mode.title).font(.islandCaptionEmphasis)
                    .foregroundStyle(selected ? Color.accentColor : IslandPalette.textPrimary.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Look

    private var lookCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Apparence de l’îlot")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Toggle("Fond translucide", isOn: $home.translucentBackground).toggleStyle(IslandToggleStyle())
                    caption("Ouverte, l’île floute ce qui se trouve derrière avec le matériau du système.")
                    Divider()
                    Toggle("Afficher le contour", isOn: $home.showsOutline).toggleStyle(IslandToggleStyle())
                }
            }
        }
    }

    // MARK: - Notch fit

    private var fitCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Ajustement à l’encoche")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Toggle("Masquer l’espace sous l’encoche", isOn: $home.hidesNotchGap).toggleStyle(IslandToggleStyle())
                    caption("Étend l’île jusqu’au bas de la barre des menus pour masquer la fine bande sous l’encoche.")
                    Divider()
                    labelledSlider("Largeur", value: $home.notchFitWidth, range: HomeModel.fitWidthRange, unit: "")
                    labelledSlider("Hauteur", value: $home.notchFitHeight, range: HomeModel.fitHeightRange, unit: "")
                    caption("Si un bord de l’encoche apparaît autour de l’île, modifiez ces valeurs jusqu’à ce qu’il disparaisse.")
                    Button("Remettre à zéro") {
                        home.notchFitWidth = 0
                        home.notchFitHeight = 0
                    }
                    .buttonStyle(IslandButtonStyle())
                    .disabled(home.notchFitWidth == 0 && home.notchFitHeight == 0)
                }
            }
        }
    }

    // MARK: - Round buttons

    /// The cap line under the card title, from the real caps.
    static var buttonsCaption: String {
        "Jusqu’à \(HomeButtonLayout.maxPerSide) boutons par côté, \(HomeButtonLayout.maxBottom) en bas, chaque action une seule fois."
    }

    private var buttonsCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Boutons autour de l’îlot",
                         subtitle: Self.buttonsCaption)
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.m) {
                    ForEach(HomeButtonSide.allCases, id: \.self) { side in
                        sideSection(side)
                        if side != HomeButtonSide.allCases.last { Divider() }
                    }
                    Divider()
                    Button("Rétablir les boutons d’origine") { home.buttons = .initial }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(home.buttons == .initial)
                }
            }
        }
    }

    private func sideSection(_ side: HomeButtonSide) -> some View {
        let row = home.buttons.buttons(on: side)
        let catalog = dockCatalog?() ?? []
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack {
                Text(side.title).font(.islandBodyEmphasis)
                Text("\(row.count) sur \(HomeButtonLayout.capacity(of: side))")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                Spacer()
                HomeButtonAddControl(side: side, layout: home.buttons, catalog: catalog,
                                     availability: { dockAvailability?($0) ?? .available },
                                     add: { home.buttons.add(actionID: $0, side: side) })
            }
            if row.isEmpty {
                caption("Aucun bouton de ce côté.")
            }
            ForEach(row) { button in buttonRow(button, in: row, catalog: catalog) }
        }
    }

    /// What a stored button stands for: its home action, else the dock-catalog command of the same identity.
    private func buttonFace(_ button: HomeButton, catalog: [DockCommand]) -> (title: String, symbol: String, known: Bool) {
        if let action = HomeActionCatalog.action(button.actionID) { return (action.title, action.systemImage, true) }
        if let identity = HomeActionCatalog.identity(of: button.actionID),
           let command = catalog.first(where: { $0.id == identity }) { return (command.title, command.systemImage, true) }
        return ("Commande introuvable", "questionmark.circle", false)
    }

    private func buttonRow(_ button: HomeButton, in row: [HomeButton], catalog: [DockCommand]) -> some View {
        let face = buttonFace(button, catalog: catalog)
        let index = row.firstIndex(where: { $0.id == button.id }) ?? 0
        return HStack(spacing: IslandSpacing.s) {
            Image(systemName: face.symbol).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(face.title).font(.islandBody)
                if !face.known {
                    Text(button.actionID).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            Spacer()
            Button("Monter", systemImage: "chevron.up") { home.buttons.reorder(id: button.id, by: -1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index == 0)
            Button("Descendre", systemImage: "chevron.down") { home.buttons.reorder(id: button.id, by: 1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index == row.count - 1)
            Menu("Déplacer") {
                ForEach(HomeButtonSide.allCases.filter { $0 != button.side }, id: \.self) { side in
                    Button(side.title) { home.buttons.move(id: button.id, to: side) }
                        .disabled(!home.buttons.hasRoom(on: side))
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button("Retirer", systemImage: "minus.circle") { home.buttons.remove(id: button.id) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
        }
    }

    // MARK: - Extra dock

    private var extraDockCard: some View {
        let catalog = dockCatalog?() ?? []
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = home.extraDock.ids
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Extra-dock",
                         subtitle: "Une rangée de raccourcis sur l’accueil : ajoute, retire et réordonne n’importe quelle commande de l’app.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Toggle("Afficher l’extra-dock sur l’accueil", isOn: $home.showsExtraDock).toggleStyle(IslandToggleStyle())
                    Divider()
                    HStack {
                        Text("\(ids.count) sur \(ExtraDockLayout.maxItems) commandes").font(.islandBodyEmphasis)
                        Spacer()
                        dockAddMenu(catalog)
                    }
                    if ids.isEmpty { caption("L’extra-dock est vide.") }
                    ForEach(ids, id: \.self) { id in dockRow(id, command: byID[id], count: ids.count) }
                    Divider()
                    Button("Rétablir l’extra-dock d’origine") { home.extraDock = .initial }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(home.extraDock == .initial)
                }
            }
        }
    }

    private func dockAddMenu(_ catalog: [DockCommand]) -> some View {
        let free = catalog.filter { !home.extraDock.contains($0.id) }
        return Menu("Ajouter une commande") {
            ForEach(ExtraDockCatalog.grouped(free), id: \.category) { group in
                Menu(group.category.title) {
                    ForEach(group.commands) { command in
                        Button(command.title, systemImage: command.systemImage) { home.extraDock.add(command.id) }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(free.isEmpty || home.extraDock.isFull)
    }

    private func dockRow(_ id: String, command: DockCommand?, count: Int) -> some View {
        let index = home.extraDock.ids.firstIndex(of: id) ?? 0
        return HStack(spacing: IslandSpacing.s) {
            Image(systemName: command?.systemImage ?? "questionmark.circle").frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(command?.title ?? "Commande introuvable").font(.islandBody)
                if command == nil {
                    Text(id).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            Spacer()
            Button("Monter", systemImage: "chevron.up") { home.extraDock.reorder(id, by: -1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index == 0)
            Button("Descendre", systemImage: "chevron.down") { home.extraDock.reorder(id, by: 1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index >= count - 1)
            Button("Retirer", systemImage: "minus.circle") { home.extraDock.remove(id) }
                .labelStyle(.iconOnly).buttonStyle(.plain)
        }
    }

    // MARK: - Hidden tiles

    private var tilesCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Raccourcis de l’accueil")
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                        Text(Self.hiddenSummary(count: home.hiddenTiles.count)).font(.islandBody)
                        caption("Clic droit sur un raccourci de l’accueil pour le masquer. L’Explorateur les liste tous.")
                    }
                    Spacer()
                    Button("Tout afficher") { home.showAllTiles() }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(home.hiddenTiles.isEmpty)
                }
            }
        }
    }

    /// "Aucun raccourci masqué" / "1 raccourci masqué" / "3 raccourcis masqués".
    static func hiddenSummary(count: Int) -> String {
        switch count {
        case ...0: "Aucun raccourci masqué"
        case 1: "1 raccourci masqué"
        default: "\(count) raccourcis masqués"
        }
    }

    // MARK: - Pieces

    private func labelledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: IslandSpacing.s) {
            Text(title).font(.islandBody).frame(width: 70, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue))\(unit)").font(.islandValue).frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
