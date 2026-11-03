# Edit keys (Cmd+C / X / V / A / Z) in every text input

Harold, 2026-11-03: in the Brouillon the standard editing shortcuts did nothing.

## Cause

Mac Island is an accessory app with no main menu, and its panels are non-activating. AppKit turns Cmd+letter into
`copy:` / `paste:` / ... only through the main menu (or a view's `performKeyEquivalent`). Neither existed, so the key
never reached the focused `NSTextView` / field editor. The terminal had its own `performKeyEquivalent`, which is why only
it worked.

## Mechanism (one, reusable)

- `Sources/IslandKit/EditKeyRouting.swift`: pure `action(modifiers:key:)` (Command alone, Shift+Command+Z for redo; nothing
  with Option or Control, so Option+Cmd+V stays the plain-paste global hotkey) and `handle(_:in:)`, which sends the action to
  the window's first responder only when it is an `NSText` (text view or field editor) and not composing (IME marked text).
  The terminal (not an `NSText`) is never touched; it keeps its own handling.
- `IslandKit.NotchPanel.performKeyEquivalent`: views answer first (`super`), the rest goes to `EditKeyRouting`.
- Patch `scripts/port/patches/2150-island-edit-key-equivalents.patch`: same two lines in the upstream panels
  (`OverlayPanel`, the ported `NotchPanel`, the Shelf panel), plus Shelf: Cmd+A selects tiles only when no text input holds
  the keyboard.
- `Sources/IslandKit/EditMenu.swift`, called first in `AppDelegate.applicationDidFinishLaunching`: a main menu with the
  standard Edit items for normal windows (Settings). Accessory policy unchanged, no menu bar shown; no-op when the app
  already has a Paste item.
- Cmd+arrows, Option+arrows, Cmd+Backspace are key bindings resolved in `keyDown` (not key equivalents): they already worked,
  pinned by `EditKeysTests.commandArrowsAndOptionArrowsMoveTheCaret`.
- Cmd+B / Cmd+I: not added (the editors are plain text).

Tests: `Tests/IslandKitTests/EditKeysTests.swift`.

## Text input surfaces

| Surface | Where | Host window | Status |
|---|---|---|---|
| Clipboard tab, Brouillon (`TextEditor`) | `Features/Clipboard/ScratchpadPane.swift` | island `NotchPanel` | fixed (panel) |
| Clipboard tab search (`TextField`) | `Features/Clipboard/HistoryPane.swift` | island `NotchPanel` | fixed (panel) |
| IP scanner range + search | `Features/IPScanner/IPScanner{Scan,Results}Card.swift` | island `NotchPanel` | fixed (panel) |
| Terminal profile rename (`TextField`) | `Features/Terminal/TerminalSettingsBody.swift` | Settings window | fixed (Edit menu) |
| Terminal view | `Features/Terminal/ActivityTerminalView.swift` | island `NotchPanel` | untouched: own `performKeyEquivalent`, not an `NSText` |
| Terminal toast `NSTextField` | same | none (label) | n/a, not editable |
| Settings search, features search, dock picker search | `ShellKit/Settings/SettingsSidebar.swift`, `FeaturesHubPage.swift`, `ShellKit/Home/ExtraDockPicker.swift` | Settings window / island | fixed (Edit menu / panel) |
| Ported Brouillon (`PlainTextEditor`, `NSTextView`) | `PortKit/UI/Scratchpad/ScratchpadView.swift`, `UI/Notch/NotchScratchpadView.swift` | island `NotchPanel`, ported panels, Settings | fixed (panel, patch 2150, Edit menu) |
| Ported Notch clipboard / watch / sections | `PortKit/UI/Notch/Notch{Clipboard,Watch,Sections}View.swift` | ported `NotchPanel` | fixed (patch 2150) |
| Ported Shelf notes and tile fields | `PortKit/UI/Shelf/ShelfTilesView.swift` | Shelf panel | fixed (patch 2150; Cmd+A no longer steals the field) |
| Ported Command bar (`CommandBarView`, `CommandBarDroplet`) | `PortKit/UI/CommandBar/` | `OverlayPanel` | fixed (patch 2150) |
| Ported panels: clipboard quick panel, menu panel views, snippets | `PortKit/UI/MenuPanel/*`, `SnippetLibraryView.swift` | `OverlayPanel` / menu panel | fixed where hosted in `OverlayPanel` |
| Ported Settings pages (about 20 files of `TextField`) | `PortKit/UI/Settings/*` | Settings window | fixed (Edit menu) |
| Screenshot editor, recorder inspector, media workspace | `PortKit/UI/Screenshot`, `Recorder`, `Media` | own windows (`NSWindow`) | fixed (Edit menu) when app is active; panels with their own `NSPanel` subclass (`QuickLauncherService`, `ScreenshotQuickPreviewController`, `ScreenshotPinController`, `RecentCaptureService`) have no text inputs: not routed |
| Shortcut recorder | `PortKit/UI/ShortcutRecorderButton.swift` | any | untouched on purpose: it captures raw keys |

Not verified here: a real keyboard in the running app (the sandbox cannot launch it). The tests drive the real
`NSPanel.performKeyEquivalent` with synthetic events.
