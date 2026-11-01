# Parity sweep 1: Settings pages 01-34

Ground truth: `tasks/parity/pages/01..34-*.txt` (crawled from the real app). Method: every control label of the crawl
(1362 distinct labels over the 34 pages) was looked up in the sources the page renders from (French string tables of
the ported code and ShellKit), the page model was asked for greyed rows after every body is registered
(`SettingsSweepDumpTests.dumpPages`: `planned.txt`), and every page was rendered in an `NSHostingView` to a PNG
(`MIS_SWEEP_DIR`, `MIS_SWEEP_PAGES`) to look for clipping. Status: live = drawn and bound, greyed = "Bientôt" row,
unwired = drawn but nothing reads the key, missing = not on the page.

Result: 0 greyed rows and 0 "Bientôt" on pages 01-34. Gaps found and fixed: 3 (below). 1 deliberate difference.

| Page | Rows (distinct labels) | Status | Note |
|---|---|---|---|
| 01 Général | 19 | live | login item, language, appearance, global shortcut (`keepAwakeShortcutEnabled`, `keepAwakeShortcut`), feedback; the "Pas encore branché" badge only shows while the service is not armed (the app arms it at launch) |
| 02 Barre des menus | 75 | live | ported panel tab editor (`MenuBarPanelPage`) |
| 03 Fonctions | 63 | live, 2 fixed | FIXED: each row drew its name twice (`IslandToggleStyle` ignores `labelsHidden`); FIXED: missing "N fonctions sur M installées", "Tout installer", "Tout désinstaller" (confirmed). Presets, search, safe mode, kill switch, status and permission buttons were already there. Per-feature "Désinstaller X" = the row's own switch (a Mac Island feature is on or off, never removed from the app) |
| 04 Dynamic Island | 30 | live, 1 fixed | FIXED: no "Activer Dynamic Island" switch. Now `notchEnabled` (migrated key; first launch stores on before upstream's registered `false`), `IslandController.hide()` / `show()`; "Ouvrir Dynamic Island" disabled while off. "Disposition" = the round-button editor; size, look, notch fit sliders live |
| 05 Moniteur, 06 Ventilateurs | 60, 54 | live | ported pages; the "Mémoire: Plus d'options"-style labels are accessibility names built at runtime |
| 07 Barre de commande | 60 | live | two captions are variants shown by state |
| 08-13 Panneau rapide, Actions rapides, Caméra, Fond d'écran, Brouillon, Mode nettoyage | 41 each | live | ported pages; wallpaper and camera bound in `MediaToolsLane` / `CaptureToolsLane` |
| 14 Capture d'écran, 15 Enregistrement, 16 OCR, 17 Pipette | 73, 33, 16, 19 | live | |
| 18 Menu radial | 41 | live | |
| 19-23 Musique, Mélangeur, Sortie, Priorité, Micro | 4, 36, 4, 28, 41 | live | "EPSON PJ" in 22 is the crawl machine's own device |
| 24 Garder éveillé | 50 | live | |
| 25 Écrans, 26 Luminosité extra, 27 Bluetooth | 9, 4, 5 | live | "27%" is a live reading |
| 28 Sélecteur de fenêtres | 63 | live | usage hints are format strings (`switcherUsageHintFormat`) |
| 29-31 Dock Preview, Clics, Espaces | 37 each | live | |
| 32 Disposition, 33 Maximiser | 103 each | live | |
| 34 Quitter à la fermeture | 12 | live | |

Features with no registry binding after the sweep: `pastePlain` (clipboard lane, not this range), `notch` (its switch is
now the island page's `notchEnabled`), `notchAgents` (our `agents` feature).

Not verifiable here: the crawl was taken with the real app's permissions; a page that hides a row behind a missing
permission was rendered without any, so rows shown only after a grant were checked in source only.
