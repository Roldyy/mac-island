import IslandUI
import SwiftUI

/// The open island: a black body (home, Explorer or a feature page) with round buttons around it.
/// Takes the notch size as plain values so it renders in tests without an `IslandState`.
struct HomeIslandContent: View {
    let context: ShellContext
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// False while the island is closed: the home stays built but stops polling the system levels.
    var isOpen = true
    /// False while no page or Explorer should be mounted (closed): they own tasks, timers and focus.
    var isLive = true

    private var home: HomeModel { context.home }

    var body: some View {
        let body = context.bodySize
        let left = home.buttons.buttons(on: .left), right = home.buttons.buttons(on: .right)
        let bottom = home.buttons.buttons(on: .bottom)
        let sides = !left.isEmpty || !right.isEmpty
        let dock = dockCommands()
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                if sides { column(left, body: body, dock: dock) }
                bodyView
                    .frame(width: body.width, height: body.height)
                if sides { column(right, body: body, dock: dock) }
            }
            if !bottom.isEmpty {
                HomeButtonStackView(axis: .horizontal, count: bottom.count,
                                    available: HomeButtonStack.bottomAvailable(panelWidth: home.panelSize(body: body).width)) {
                    HStack(spacing: HomeButtonStack.spacing) {
                        ForEach(bottom) { HomeCircleButton(button: $0, context: context, dock: dock) }
                    }
                }
                // The row is exactly `bottomRow` tall and is the last thing in the panel: an extra bottom padding made
                // the content 4 pt taller than the panel, so the foot of the round buttons was cut off.
                .frame(height: HomeGeometry.bottomRow, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Roldy Management mark, bottom left, in the free corner of the round-button row.
        .overlay(alignment: .bottomLeading) {
            RoldyMark().padding(.leading, 26).padding(.bottom, 24)
        }
        .islandAnimation(.easeOut(duration: 0.16), value: context.navigation.route)
        .contextMenu { islandMenu }
        .onExitCommand { _ = context.navigation.back() }
    }

    // MARK: - Body

    private var bodyView: some View {
        ZStack(alignment: .top) {
            bodyBackground
            VStack(spacing: 0) {
                band
                switch context.navigation.route {
                case .home: HomeView(context: context, isActive: isOpen).padding(.top, HomeGeometry.bandGap).transition(.identity)
                case .explore: if isLive { ExploreView(context: context).transition(.identity) } else { Color.clear }
                case .page(let id): if isLive { HomePageView(tabID: id, context: context).transition(.identity) } else { Color.clear }
                }
            }
        }
        .clipShape(shape)
        .overlay { outline }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 26, bottomTrailingRadius: 26,
                               topTrailingRadius: 12, style: .continuous)
    }

    /// Solid black like the notch; translucent only when the user asked for it, with the notch itself kept black.
    @ViewBuilder private var bodyBackground: some View {
        ZStack(alignment: .top) {
            if home.translucentBackground {
                Color.clear.islandGlass(cornerRadius: 26)
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                       topTrailingRadius: 12, style: .continuous)
                    .fill(IslandSurface.notchBlack)
                    .frame(width: max(notchWidth + CGFloat(home.notchFitWidth), 0), height: home.bandHeight)
            } else {
                shape.fill(IslandSurface.notchBlack)
            }
        }
    }

    /// Drawn ABOVE the page, not in the background: the fade at the foot of the scrolling tile grid is opaque black
    /// and, painted over a background stroke, hid the bottom edge of the outline.
    @ViewBuilder private var outline: some View {
        if home.showsOutline {
            shape.strokeBorder(IslandPalette.textPrimary.color.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// The strip behind the hardware notch. Alerts and the Claude pill sit to its right.
    private var band: some View {
        HStack(spacing: 0) {
            Color.clear.frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: IslandSpacing.s) {
                if let alert = context.alert() {
                    Label(alert.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: IslandType.minimumSize, weight: .medium))
                        .foregroundStyle(IslandStatus.warning.color)
                        .lineLimit(1)
                        .accessibilityLabel("\(alert.title). \(alert.message)")
                }
                if context.manualFansActive() {
                    // Manual fan mode outlives the island: always say so while it is on.
                    Label("Ventilos manuels", systemImage: "fan.fill")
                        .font(.system(size: IslandType.minimumSize, weight: .medium))
                        .foregroundStyle(IslandStatus.info.color)
                        .lineLimit(1)
                }
                context.claudePill()  // hidden while idle
            }
            .padding(.leading, IslandSpacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: home.bandHeight)
    }

    // MARK: - Round buttons

    /// The dock-catalog commands the round buttons that are not home actions point at, by id. Built once per pass and
    /// only when such a button exists, so the usual three-button layout pays nothing.
    private func dockCommands() -> [String: DockCommand] {
        let needed = home.buttons.buttons.contains { HomeActionCatalog.action($0.actionID) == nil }
        guard needed else { return [:] }
        return Dictionary(context.dockCatalog().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func column(_ buttons: [HomeButton], body: CGSize, dock: [String: DockCommand]) -> some View {
        HomeButtonStackView(axis: .vertical, count: buttons.count,
                            available: HomeButtonStack.sideAvailable(bodyHeight: body.height, band: home.bandHeight),
                            inset: home.bandHeight + HomeGeometry.bandGap) {
            VStack(spacing: HomeButtonStack.spacing) {
                ForEach(buttons) { HomeCircleButton(button: $0, context: context, dock: dock) }
            }
        }
        .frame(width: HomeGeometry.sideColumn, alignment: .top)
    }

    // MARK: - Right-click menu

    @ViewBuilder private var islandMenu: some View {
        let route = context.navigation.route
        Button(route == .explore ? "Retour" : "Explorer", systemImage: "square.grid.2x2") {
            context.navigation.toggleExplore()
        }
        Button("Réglages…", systemImage: "gearshape") { context.openSettings() }
        Divider()
        Menu("Taille") {
            Picker("Taille", selection: Binding(get: { home.sizeMode }, set: { home.sizeMode = $0 })) {
                ForEach(IslandSizeMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .pickerStyle(.inline)
        }
        Toggle("Fond translucide", isOn: Binding(get: { home.translucentBackground }, set: { home.translucentBackground = $0 }))
        Toggle("Afficher le contour", isOn: Binding(get: { home.showsOutline }, set: { home.showsOutline = $0 }))
        // Every command of the app, by category (the settings page offers the same list with a search field).
        Menu("Ajouter un bouton") {
            let free = context.dockCatalog().filter { !home.buttons.contains(actionID: $0.id) }
            ForEach(ExtraDockCatalog.grouped(free), id: \.category) { group in
                Menu(group.category.title) {
                    ForEach(group.commands) { command in
                        Button(command.title, systemImage: command.systemImage) { home.buttons.add(actionID: command.id) }
                    }
                }
            }
        }
        .disabled(home.buttons.firstFreeSide == nil)
        Button(HomeTileMenu.showAllTitle, systemImage: "eye") { home.showAllTiles() }
            .disabled(!HomeTileMenu.showAllEnabled(hidden: home.hiddenTiles))
        Divider()
        if let relaunch = context.relaunch {
            Button("Relancer Mac Island", systemImage: "arrow.clockwise") { relaunch() }
        }
        Button("Quitter Mac Island", systemImage: "power") { context.quit() }
    }
}
