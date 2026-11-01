# Sweep 2: Settings pages 35-67 (lane Q2)

Ground truth: `tasks/parity/pages/35..67-*.txt` (crawled from the real app). Pages 49 (clipboard) and 50 (pasteplain)
belong to another lane. Method: `Tests/PortKitTests/SettingsSweep2Tests.swift` binds every lane the way the app does,
draws each page in the Settings window (defaults registered, features installed, in-page switches on), writes one PNG per
page, and a Vision OCR of those PNGs is compared to the crawled controls. The test also asserts that no page reads
"Bientôt", that no greyed row remains, and that nothing runs off a 7000 pt frame.

Result: 194 control rows live, 0 greyed, 0 "Bientôt", 25 not rendered (all explained below). Unwired rows were
looked for by reading each page's bound keys against its lane (every upstream page is bound through `PortFeatureBinding`
or `PortBridge`, with the lane tests); no unwired control was found. Pages 35-44 share one reference page ("Souris et
trackpad"): the app splits it into one page per feature, so each row is checked against the union of our pages.

## Gaps found and fixed in this sweep

| page | gap | fix |
|---|---|---|
| 64 advanced | no "Effacer toutes les autorisations", no "Désinstaller complètement", buttons named differently | `AppReset` (tccutil reset All on our own bundle id, login item off; uninstall = clear, support folders and preferences removed, app to the Trash, quit), each behind a confirmation; buttons and texts renamed to the reference |
| 65 about | no update block, no "Revoir l'introduction" / "Revoir les nouveautés" | `UpdateChecker` (GitHub releases, one GET, `autoCheckUpdates` honoured once a day at Settings open, `includeBetaUpdates` filters prereleases, `showReleaseNotesBeforeUpdate` shows the notes, `releaseNotesOnUpdate` opens Nouveautés once after an update); the two buttons navigate (introduction = the Fonctions page: Mac Island has no onboarding) |
| 66 whatsnew | no "Nouveautés de cette version", Résumé, Contributeurs | added (summary on `ChangelogEntry`, contributors card linking Vorssaint's GitHub) |
| 67 support | one star button only | the two cards of the reference (Buy Me a Coffee of the original author, star on GitHub) and the closing line |
| 62, 63, 51-53, 47 | rows hidden in a default render (features not installed, in-page switches off) | sweep fixture changed, not the app: every row is present once the feature is on |

## Not possible or not applicable (stated on the page where it matters)

- 65: no self-replacing update: the release page opens, the page says an app cannot replace itself while it runs.
- 66: the reference lists Vorssaint 3.4.2's release notes (English); Mac Island shows its own release notes.
- 67: Mac Island has no donation page of its own; the Coffee button points to Vorssaint's, and says so.
- 53: the "Dynamic Island" position of the shelf is Vorssaint's own island, which is off by design (one island).
- 58 / 55: the installed packages and learned sites are the reference Mac's data.
- 58: "Configurer Terminal" is "Copier la commande" (patch 1552: commands are copied, never run).
- 64: the fan helper and the closed-lid sudoers rule need an administrator password; the page says they stay to remove by hand.

## Rows

### 35 scrollreverse
Wiring: InputScroll lane, MouseSettings(.scrollDirection), wheel tap via ScrollInverter

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 36 hscroll
Wiring: InputScroll lane, .horizontalScroll, shares the wheel tap

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 37 middleclick
Wiring: InputMouse lane, MiddleClickPage; start gated by the MultitouchSupport probe, the page says why when absent

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 38 focusfollows
Wiring: InputMouse lane, FocusFollowsMousePage

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 39 smoothscroll
Wiring: InputScroll lane, .smoothScroll (SmoothScrollService)

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 40 linearscroll
Wiring: InputScroll lane, .linearScroll

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 41 noaccel
Wiring: InputMouse lane, MouseAccelerationPage (journal + relaunch cleanup flag)

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 42 sidebuttons
Wiring: InputMouse lane, MouseNavigationPage

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 43 mouseshortcuts
Wiring: InputMouse lane, MouseButtonShortcutsSection

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 44 clickfilter
Wiring: InputMouse lane, MouseClickDebouncePage

| row | status | note |
|---|---|---|
| CheckBox: Inverser le défilement vertical | live | rendered live, bound to its key |
| CheckBox: Inverser le défilement horizontal | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons latéraux pour Précédent et Suivant | live | rendered live, bound to its key |
| CheckBox: Utiliser les boutons supplémentaires comme raccourcis | live | rendered live, bound to its key |
| CheckBox: Changer d’espace en faisant glisser un bouton | live | rendered live, bound to its key |
| CheckBox: Le clic à trois doigts devient un clic du milieu | live | rendered live, bound to its key |

### 45 quitprotect
Wiring: InputKeyboard lane, QuitProtectionSettings

| row | status | note |
|---|---|---|
| PopUpButton: Maintenir pour confirmer | live | rendered live, bound to its key |
| Button: 250 ms | live | rendered live, bound to its key |
| Slider: 800 | live | rendered live, bound to its key |
| PopUpButton: Toutes les applications | live | rendered live, bound to its key |

### 46 debounce
Wiring: InputKeyboard lane, KeyboardDebounceSettings

| row | status | note |
|---|---|---|
| Heading: Touches spécifiques | live | rendered live, bound to its key |
| PopUpButton: Touche | live | rendered live, bound to its key |
| Button: Ajouter une touche | live | rendered live, bound to its key |

### 47 superkey
Wiring: InputKeyboard lane, SuperKeySettings (hidutil mapping, recovered at launch)

| row | status | note |
|---|---|---|
| PopUpButton: Verr. Maj | live | rendered live, bound to its key |
| Button: Shift | live | the key chooser of the super key, rendered |
| Button: Control | live | rendered live, bound to its key |
| Button: Option | live | rendered live, bound to its key |
| Button: Command | live | rendered live, bound to its key |
| Heading: Un appui seul | live | rendered live, bound to its key |
| RadioButton: Un appui seul, Rien | live | rendered live, bound to its key |
| RadioButton: Un appui seul, Active et désactive les majuscules | live | rendered live, bound to its key |
| RadioButton: Un appui seul, Changer de source d’entrée ; maintenir pour Verr. Maj | live | rendered live, bound to its key |
| RadioButton: Un appui seul, Appuie sur Échap | live | rendered with the super key on ("Un appui seul" + "Appuie sur Échap") |

### 48 snippets
Wiring: InputKeyboard lane, TextSnippetsSettings

| row | status | note |
|---|---|---|
| Heading: Menu rapide des extraits | live | rendered live, bound to its key |
| Button: Ajouter un extrait | live | rendered live, bound to its key |

### 51 cutpaste
Wiring: Finder lane (PortBridge page), CutPasteSettings(parts: cutPaste)

| row | status | note |
|---|---|---|
| Heading: Comment l’utiliser | live | rendered live, bound to its key |
| Button: Réinitialiser | live | rendered live, bound to its key |

### 52 renameshortcut
Wiring: Finder lane (PortBridge page), CutPasteSettings(parts: rename)

| row | status | note |
|---|---|---|
| Heading: Comment l’utiliser | live | rendered live, bound to its key |
| Button: Réinitialiser | live | rendered live, bound to its key |

### 53 shelf
Wiring: Shelf lane (replaces our store), ShelfSettings + IslandShelfDownloadsSettings

| row | status | note |
|---|---|---|
| Heading: Comment l’utiliser | live | rendered live, bound to its key |
| RadioButton: Fenêtre séparée | live | rendered live, bound to its key |
| Button: Réinitialiser | live | rendered live, bound to its key |
| PopUpButton: Sous l’icône de la barre des menus | live | rendered live, bound to its key |
| Button: Ouvrir maintenant | live | rendered live, bound to its key |
| Heading: Après utilisation | live | rendered live, bound to its key |
| Heading: Exceptions automatiques | live | rendered live, bound to its key |
| Button: Ajouter une app… | live | rendered live, bound to its key |

### 54 media
Wiring: MediaTools lane, MediaToolsPage

| row | status | note |
|---|---|---|
| RadioButton: Vidéo | live | rendered live, bound to its key |
| RadioButton: GIF | live | rendered live, bound to its key |
| RadioButton: Image | live | rendered live, bound to its key |
| RadioButton: Texte | live | rendered live, bound to its key |
| Button: Choisir un fichier, Déposez un fichier ici ou cliquez pour choisir. | live | rendered live, bound to its key |
| Button: Destination | live | rendered live, bound to its key |
| RadioButton: Résolution | live | rendered live, bound to its key |
| RadioButton: Poids | live | rendered live, bound to its key |
| Button: Faible | live | rendered live, bound to its key |
| Button: Moyenne | live | rendered live, bound to its key |
| Button: Forte | live | rendered live, bound to its key |
| Button: Compresser la vidéo | live | rendered live, bound to its key |
| Button: Modifier | live | rendered live, bound to its key |

### 55 urlcleaner
Wiring: FoundationExample lane, URLCleanerSettings

| row | status | note |
|---|---|---|
| Heading: Règles de nettoyage | live | rendered live, bound to its key |
| DisclosureTriangle: Tous les sites, 22 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: bilibili.com, 25 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: instagram.com, 1 paramètre | live | rendered live, bound to its key |
| DisclosureTriangle: reddit.com, 9 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: spotify.com, 1 paramètre | live | rendered live, bound to its key |
| DisclosureTriangle: tiktok.com, 9 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: twitter.com, 7 paramètres | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| DisclosureTriangle: x.com, 7 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: xiaohongshu.com, 11 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: youtu.be, 4 paramètres | live | rendered live, bound to its key |
| DisclosureTriangle: youtube.com, 4 paramètres | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Ajouter un site | live | rendered live, bound to its key |
| Heading: Nettoyer maintenant | live | rendered live, bound to its key |
| TextField: Collez une URL | live | rendered live, bound to its key |
| Button: Fermer | live | rendered live, bound to its key |
| Button: Coller | live | rendered live, bound to its key |
| Button: Copier | live | rendered live, bound to its key |

### 56 appupdates
Wiring: AppUpdates lane, AppUpdatesSettings (patch 1553: no notification prompt)

| row | status | note |
|---|---|---|
| DisclosureTriangle: Exceptions de mise à jour | live | rendered live, bound to its key |
| Heading: Vérifier en arrière-plan | live | rendered live, bound to its key |
| RadioButton: Désactivé | live | rendered live, bound to its key |
| RadioButton: Chaque jour | live | rendered live, bound to its key |
| RadioButton: Chaque semaine | live | rendered live, bound to its key |
| Heading: Sources | live | rendered live, bound to its key |

### 57 cleaner
Wiring: Cleaner lane, CleanerPageBody (trash only, patch 1502)

| row | status | note |
|---|---|---|
| Button: Analyser | live | rendered live, bound to its key |
| PopUpButton: Désactivé | live | rendered live, bound to its key |
| PopUpButton: Après 30 jours | live | rendered live, bound to its key |
| CheckBox: Téléchargements WhatsApp | live | rendered live, bound to its key |

### 58 homebrew
Wiring: AppUpdates lane, HomebrewPage (patches 1550-1557: commands copied, never run)

| row | status | note |
|---|---|---|
| PopUpButton: Casks | live | rendered live, bound to its key |
| Button: Rechercher | live | rendered live, bound to its key |
| Button: Actualiser | live | rendered live, bound to its key |
| Button: Mettre à jour Homebrew | live | rendered live, bound to its key |
| RadioButton: Tous 56 | live | rendered live, bound to its key |
| RadioButton: Casks 9 | live | rendered live, bound to its key |
| RadioButton: Formules 47 | live | rendered live, bound to its key |
| CheckBox: Regrouper les dépendances | live | rendered live, bound to its key |
| Button: Configurer Terminal | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: ExtraDock, 4.2.7 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: GitHub Desktop, 3.6.8-c5923f66 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Highball, 0.10.22 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Microsoft Excel, 16.114.26102031 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Microsoft OneNote, 16.114.26102031 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Microsoft Outlook, 16.114.26101123 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Microsoft PowerPoint, 16.114.26102031 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Microsoft Word, 16.114.26102031 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Vorssaint, 3.4.1 | live | rendered live, bound to its key |
| Button: bash-completion, 1.3_3 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: cmake, 4.4.0 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: ffmpeg | live | rendered live, bound to its key |
| Button: ffmpeg, 8.1.2_1 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: gh, 2.96.0 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: git-lfs, 3.8.1 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: node | live | rendered live, bound to its key |
| Button: node, 25.9.0_2 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: pipx | live | rendered live, bound to its key |
| Button: pipx, 1.13.0 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: powershell | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: powershell, 7.6.4 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: python@3.12 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: python@3.12, 3.12.14 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: Dépendances: python@3.14 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: python@3.14, 3.14.5 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |
| Button: uv, 0.13.1 | missing | listing of the reference Mac (installed packages, learned sites): the page fills it from this Mac's own data |

### 59 uninstaller
Wiring: Uninstaller lane, UninstallerView (patches 1554-1556)

| row | status | note |
|---|---|---|
| Button: Choisir une app… | live | rendered live, bound to its key |

### 60 forcequit
Wiring: KillPorts lane, KillProcessPage (patches 1401, 1752)

| row | status | note |
|---|---|---|
| Button: Actualiser | live | rendered live, bound to its key |
| Button: Processus | live | rendered live, bound to its key |
| Button: CPU | live | rendered live, bound to its key |
| Button: Mémoire | live | rendered live, bound to its key |
| Button: PID | live | rendered live, bound to its key |

### 61 ports
Wiring: KillPorts lane, PortManagerPage

| row | status | note |
|---|---|---|
| Button: Actualiser | live | rendered live, bound to its key |

### 62 shortcuts
Wiring: InputShortcuts lane (PortBridge page), ShortcutsPage: Mac Island card + ShortcutsSettings

| row | status | note |
|---|---|---|
| Heading: Fenêtres et Dock | live | rendered live, bound to its key |
| Button: Sélecteur de fenêtres, Actif, 2 | live | rendered live, bound to its key |
| Button: Disposition des fenêtres, Inactif, 42 | live | rendered live, bound to its key |
| Heading: Souris et clavier | live | section heading, OCR miss; its rows are present |
| Button: Réinitialiser | live | rendered live, bound to its key |
| Button: Éclairage du clavier, Inactif, 2 | live | rendered live, bound to its key |
| Heading: Presse-papiers et fichiers | live | rendered live, bound to its key |
| Heading: Son | live | rendered live, bound to its key |
| Heading: Énergie et écran | live | rendered live, bound to its key |
| Button: Écrans, Inactif, 2 | live | rendered live, bound to its key |
| Heading: Outils | live | rendered live, bound to its key |
| Button: Outils de capture, Inactif, 9 | live | rendered live, bound to its key |
| Button: Gérer le menu | live | rendered live, bound to its key |
| Button: ⌥Space | live | rendered live, bound to its key |
| Button: Raccourcis des apps | live | rendered live, bound to its key |

### 63 kbdlight
Wiring: DisplayBrightness lane (PortBridge page), KeyboardLightPage

| row | status | note |
|---|---|---|
| Heading: Fenêtres et Dock | live | rendered live, bound to its key |
| Button: Sélecteur de fenêtres, Actif, 2 | live | rendered live, bound to its key |
| Button: Disposition des fenêtres, Inactif, 42 | live | rendered live, bound to its key |
| Heading: Souris et clavier | live | section heading, OCR miss; its rows are present |
| Button: Réinitialiser | live | rendered live, bound to its key |
| Button: Éclairage du clavier, Inactif, 2 | live | rendered live, bound to its key |
| Heading: Presse-papiers et fichiers | live | rendered live, bound to its key |
| Heading: Son | live | rendered live, bound to its key |
| Heading: Énergie et écran | live | rendered live, bound to its key |
| Button: Écrans, Inactif, 2 | live | rendered live, bound to its key |
| Heading: Outils | live | rendered live, bound to its key |
| Button: Outils de capture, Inactif, 9 | live | rendered live, bound to its key |
| Button: Gérer le menu | live | rendered live, bound to its key |
| Button: ⌥Space | live | rendered live, bound to its key |
| Button: Raccourcis des apps | live | rendered live, bound to its key |

### 64 advanced
Wiring: ShellKit AdvancedPage: SettingsBackup + AppReset (this sweep)

| row | status | note |
|---|---|---|
| Heading: Sauvegarde | live | rendered live, bound to its key |
| Button: Exporter les réglages… | live | rendered live, bound to its key |
| Button: Importer les réglages… | live | rendered live, bound to its key |
| Heading: Autorisations | live | rendered live, bound to its key |
| Button: Effacer toutes les autorisations | live | rendered live, bound to its key |
| Heading: Désinstaller | live | rendered live, bound to its key |
| Button: Désinstaller complètement Vorssaint | live | rendered live, bound to its key |

### 65 about
Wiring: ShellKit AboutPage + UpdateChecker (this sweep)

| row | status | note |
|---|---|---|
| Button: Revoir l’introduction | live | rendered live, bound to its key |
| Button: Revoir les nouveautés | live | rendered live, bound to its key |
| Link: Voir sur GitHub | live | rendered live, bound to its key |
| Heading: Mises à jour | live | rendered live, bound to its key |
| Button: Rechercher maintenant | live | rendered live, bound to its key |
| Button: Télécharger et installer | live | "Télécharger la mise à jour": opens the release page, an app cannot replace itself while it runs (said on the page) |

### 66 whatsnew
Wiring: ShellKit WhatsNewPage + ChangelogEntry (this sweep)

| row | status | note |
|---|---|---|

### 67 support
Wiring: ShellKit SupportPage (this sweep)

| row | status | note |
|---|---|---|
| Button: Soutenir sur Buy Me a Coffee | live | rendered live, bound to its key |
| Button: Ajouter une étoile à Vorssaint sur GitHub | live | rendered live, bound to its key |
