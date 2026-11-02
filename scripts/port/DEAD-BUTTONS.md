# Dead buttons of the ported views (Harold, 2026-11-02: "certains boutons ne marchent pas")

Cause, one mechanism: upstream's views reach their host through four doors that Mac Island never bound.
`SettingsRouter.shared` (upstream's own router: nothing in our Settings window observed it), `appDelegate()` stubs
(`openFeedbackWindow`, `reshowStatusItem`, ...), `NotchService.shared.perform` (collapses Vorssaint's island, which is
asleep, so ours stayed on screen) and a Companion page that read two switches and a "Dynamic Island installed" check.
Found by grepping `PortKit/UI`, `Services` and `Bridge` for every caller of those doors, then following each to its
implementation. A caller is listed once per surface; "all" means every caller of the same door.

Status: FIXED (bound, test), OK (reaches real code, nothing to do), UNREACHABLE (no hosted view can call it; listed in
`PortHookCatalog.allowlist` with the reason, a test fails when a new one appears).

## Navigation (door 1: `SettingsRouter.shared`, now forwarded by `PortSettingsBridge` to `SettingsWindowController.show(page:)`)

| View | Button | Action | Before | Status / fix |
|---|---|---|---|---|
| Compagnon page (`NotchMascotSettings`, island tab and island settings) | Ouvrir Fonctionnalites | `AppFeature.notch.showInFeatures()` | router set, nobody listened: nothing | FIXED, opens page `features`; the card no longer shows (see Companion) |
| `SettingsCard` (every page that gates an option on a feature) | Ouvrir Fonctionnalites | `feature.showInFeatures()` | nothing | FIXED, opens `features` |
| Notch settings rows (`unavailableAction`, brightness, mixer, mic mute, power) | "Activer ..." | `AppFeature.X.showInFeatures()` | nothing | FIXED (same door) |
| Quick panel, Mises a jour des apps | gear icon | `router.page = .appUpdates` + `openSettingsWindow()` | window opened on the page already showing | FIXED, `appupdates` |
| Quick panel, Gestionnaire de ports | gear icon | `router.page = .portManager` | same | FIXED, `ports` |
| Quick panel, Cleaner (WhatsApp) | Gerer | `cleanerTool` + `request(.cleaner)` | same | FIXED, `cleaner` |
| Snippet library | settings button | `router.page = .textSnippets` | same | FIXED, `snippets` |
| Command Bar entries (settings, uninstaller, "needs setup" rows, 4 callers) | row click | `router.request / page =` | same | FIXED (anchor wins: `dockclicks`, `displays`, ...) |
| Radial menu | App updates slice | `router.page = .appUpdates` | same | FIXED |
| Quick panel footer, menu bar popover, Command Bar "Reglages" | Reglages | `appDelegate()?.openSettingsWindow()` | opened (host `openSettings`) | OK |
| Island brightness row (`NotchControlsView`) | Reglages | `router.request(.brightness)` | not hosted (ours is `home`) | OK, FIXED anyway (`displays`) |
| Any second tap on the same page | same buttons | `router.page = X` when already X | router saw no change | FIXED: the bridge listens to every assignment, not to changes |

The mapping is `PortSettingsNavigation.pageID(for:)` (35 upstream pages, 41 section anchors, to our catalog ids). A test
checks every page, anchor and `AppFeature.settingsDestination` lands on a page of `SettingsPageCatalog`.

## Host stubs (door 2: `AppDelegate` facade)

| View | Button | Action | Before | Status / fix |
|---|---|---|---|---|
| Quick panel header | feedback bubble | `openFeedbackWindow()` | empty stub | FIXED, opens the GitHub issue form (`PortFeedbackURL`) |
| Command Bar | "Signaler un bug", "Proposer une idee" | `openFeedbackWindow(kind:)` | empty stub | FIXED, form with label `bug` / `enhancement` |
| General page card (upstream `GeneralSettings`) | Ouvrir | `openFeedbackWindow()` | not hosted (our General is ShellKit's, it opens the same form) | OK |
| Settings, "Barre des menus" (`GeneralAdvanced`, panel configuration) | Afficher l'icone dans la barre des menus | `reshowStatusItem()` | empty stub | FIXED: switches "hide the icon with metrics" off, shows our item |
| Quick panel update banner, island update chip | update available | `showUpdatePreview()` | empty stub | UNREACHABLE: `UpdateService.state` never leaves `.idle` (updates are ShellKit's `UpdateChecker`) |
| Upstream `SettingsView` (not hosted) | tour, onboarding, highlights | `showOnboarding`, `showUpdateHighlights` | empty stub | UNREACHABLE |
| Screenshot / recording editors | share link, delete link | `ScreenshotShareService`, `RecordingShareService` | throw `.unavailable` | UNREACHABLE: `isAvailable == false` hides every control (`ScreenshotSharingSupport`) |
| `AgentUsageService` | price refresh | `AgentPriceSource.download` | `completion(nil)` | UNREACHABLE: bundled list only, no network |
| `AdvancedSettings` | clear permissions / uninstall | `SelfUninstall` | stub | UNREACHABLE: not hosted (our Avance page is ShellKit's) |
| Notch (asleep) | hover over the menu bar item | `isOverMenuBarItem` | unbound | UNREACHABLE: read by Vorssaint's island only |

## Island (door 3: `NotchService.shared.perform`)

| View | Button | Action | Before | Status / fix |
|---|---|---|---|---|
| Surveillance tab | Choisir une zone (3 places) | `NotchService.shared.perform { chooseArea() }` | collapsed the asleep island; ours stayed open over the selection | FIXED: our island closes first (`closeIsland` door, patch 2051), the action runs 0.4 s later |
| Screenshot, clipboard history (asleep services) | paste / capture after "collapse" | `perform` | same | FIXED (same door) |
| Ported code asking "open the island on tab X" | none today | `appDelegate()?.openIslandTab(id:)` | no door | FIXED: bound to `ShellNavigation.open(tabID:)` + `island.open()`; no upstream caller needs it yet |

## Companion page (door 4)

| Surface | Problem | Status / fix |
|---|---|---|
| "Le compagnon vit dans le Dynamic Island. Activez << Dynamic Island >> dans Fonctionnalites." + button | the page asked whether Vorssaint's island was installed; our island is the app | FIXED (patch 2050): `PortHost.hostsOwnIsland`, the card never shows |
| Page toggle | read `notchMascotEnabled` only, while the feature runs on the registry's switch: off/grey with the feature on | FIXED: one source (`CompanionSwitch`): ON = registry switch AND key; the toggle writes both; starting the feature writes the key ON |
| Fonctionnalites row + page toggle | two switches for one thing | FIXED: same source, the page toggle drives the registry switch |

## Hooks that can stay unbound

`PortHookCatalog.bound` (bound by `AppDelegate`, checked by `PortHookTests` against the source) and
`PortHookCatalog.allowlist` (reasons above). `PortBridge.unboundHooks` lists any facade hook the app forgot; the app
delegate logs it at launch.
