import IslandKit
import IslandUI
import SwiftUI

/// Everything the Settings window needs, built once by the window controller.
@MainActor
struct SettingsEnvironment {
    let registry: FeatureRegistry
    let defaults: UserDefaults
    let sheetTabs: [String: IslandTab]
    let openPermission: @MainActor (FeaturePermission) -> Void
    let relaunch: (@MainActor () -> Void)?
    let login: LoginItemModel
    let backup: SettingsBackup
    /// Opens another page of this window (About's "Revoir les nouveautés").
    var navigate: @MainActor (String) -> Void = { _ in }
}

/// Sidebar with search, nine sections, and the page that is open.
struct SettingsRootView: View {
    let env: SettingsEnvironment
    @Bindable var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(router: router)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.5))
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Précédent", systemImage: "chevron.left") { router.goBack() }
                    .disabled(!router.canGoBack)
                Button("Suivant", systemImage: "chevron.right") { router.goForward() }
                    .disabled(!router.canGoForward)
            }
        }
        .frame(minWidth: 772, minHeight: 528)
    }

    @ViewBuilder private var detail: some View {
        // A new id replaces the page outright; no layout animation (it made the old and new page
        // lay out together). Not animating also honours Reduce Motion.
        SettingsPageView(pageID: router.selection, env: env)
            .id(router.selection)
            .transaction { $0.animation = nil }
    }
}

/// Picks the view for one page.
struct SettingsPageView: View {
    let pageID: String
    let env: SettingsEnvironment

    var body: some View {
        if let page = SettingsPageCatalog.page(pageID) {
            switch page.kind {
            case .general: GeneralPage(page: page, defaults: env.defaults, login: env.login)
            case .features:
                FeaturesHubPage(registry: env.registry, sheetTabs: env.sheetTabs,
                                openPermission: env.openPermission, relaunch: env.relaunch)
            case .advanced: AdvancedPage(page: page, backup: env.backup, openPermission: env.openPermission, login: env.login)
            case .about: AboutPage(page: page, defaults: env.defaults, navigate: env.navigate)
            case .whatsNew: WhatsNewPage(page: page)
            case .support: SupportPage(page: page)
            case .declarative:
                DeclarativePage(page: page, registry: env.registry, store: LiveStore(defaults: env.defaults),
                                openPermission: env.openPermission)
            }
        }
    }
}
