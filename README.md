# Mac Island

A notch app for macOS. Move the pointer over the notch and an island opens with a terminal, Claude Code sessions, your clipboard history, a file shelf, a mixer, a system monitor, fan control, window and Finder tools, a network scanner and many more, each one switched on from the Functions page of the settings. On a Mac without a notch it sits at the top center as a black pill.

It runs on macOS 14 or later, on Apple silicon. The interface is in French for now.

## Install

Build it from source. You need the Command Line Tools and nothing else:

```sh
git clone https://github.com/Roldyy/mac-island
cd mac-island
make install
```

`make install` builds the app, signs it and copies it to `/Applications`. By default the signature is ad hoc, and macOS ties each privacy permission to the app's signature, so after a rebuild you may have to grant a permission again. With a Developer ID certificate the signature stays the same and permissions persist:

```sh
make install SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

The helper for fan control only accepts an app signed with a Developer ID, so it needs this variant.

A one-command installer for a notarized release exists in the repository (`install.sh`), but no release is published yet. It will be announced here when it is.

## Using it

Hover over the notch to open the island. Hovering never takes the keyboard from the app you are in. Click inside the terminal, a search field or a note to type there.

| Tab | What it does |
|---|---|
| Terminal | A login shell that keeps running when the island closes. A pill shows what Claude Code is doing (working, waiting, done). A button clears the screen and the scrollback. |
| Agents | Tokens and estimated cost for the month, read from the Claude Code logs on your Mac. Prices are estimates. |
| Presse-papiers | Clipboard history (50 entries, images included), a scratchpad, and `⌥⌘V` to paste as plain text. Items marked as concealed by password managers are never recorded. |
| Étagère | A shelf for files you drop on the island, and your latest finished downloads. Drag items out to any app. |
| Éveil | Keeps the Mac awake for a chosen time, with an optional mouse nudge. |
| Lecture | What Spotify and Music are playing, with play, pause, next and previous. |
| Finder | `⌘X` then `⌘V` moves files in Finder. `⌘V` with an image on the clipboard saves it as a PNG. |
| Dock | Clicking a Dock icon minimizes or cycles the app's windows. Hovering shows window previews. |
| Écran | Built-in display brightness, and quitting apps that have had no window for a while. Auto-quit starts in simulation mode. |
| Mixer | Volume per app, and a priority list for audio devices. |
| Ventilos | Fan speeds. Manual control needs the helper described below. |
| Moniteur | CPU and memory gauges with threshold alerts. Alerts are off until you turn them on. |
| Commandes | A launcher on `⌥Space` for apps, files, a calculator and web search. |

## Permissions

Mac Island asks for nothing at launch. Each permission is requested from a button in the tab that needs it.

| Permission | Used for |
|---|---|
| Accessibility | Plain paste, Finder cut and paste, Dock clicks, the mouse nudge |
| Input Monitoring | Seeing `⌘X` and `⌘V` in Finder |
| Screen Recording | Window thumbnails in Dock previews |
| Automation | Finder, Spotify and Music |
| Audio capture | Per-app volume. It lowers or raises the sound and never records it. |
| Downloads folder | The list of recent downloads |
| Login Items | Approving the fan helper |

The terminal runs inside Mac Island, so a command you run there inherits the permissions you gave the app, as in Terminal.app. Grant Accessibility only if you accept that.

## Fan control

Reading fan speeds works without any extra setup. Changing them needs a small helper that runs as root. You install it yourself from the Ventilos tab and approve it in System Settings, under Login Items. The helper only accepts commands from the signed Mac Island app, and the app only talks to the signed helper. The helper never goes below the manufacturer minimum speed, returns to automatic mode when the app stops responding for a few seconds, and forces automatic mode when the Mac gets hot.

Manual mode stays on until you press "Retour automatique", quit the app, or the Mac gets hot, even when the island is closed. An indicator in the island tells you when it is on. Once approved, the helper keeps running idle, and launchd restarts it after a crash so it can put the fans back to automatic. Only builds signed with a Developer ID can drive the helper, so a local `make install` build can read fan speeds but not change them.

Writing fan speeds has not been confirmed on the M4 family. It may not work on your Mac. Use the self-test first: `/Applications/Mac\ Island.app/Contents/MacOS/FanHelper --self-test-read-only`.

## Coming from Vorssaint

On first launch Mac Island looks for a Vorssaint install and copies the settings it understands. It first writes a full backup to `~/Library/Application Support/be.roldy.macisland/Backups/`. Vorssaint itself is never modified. Keys it does not recognize are logged by name and left alone. Mac Island is derived from Vorssaint 3.4.2 and is released under the same GPL-3.0-or-later licence: much of its code comes from that project, with the credit kept in `NOTICE`. It is not affiliated with Vorssaint or Glasswave.

## Your data

Everything stays on your Mac. Mac Island has no network code except the web-search shortcut, which opens your browser, and the cover art for Spotify tracks. Settings live in `~/Library/Preferences/be.roldy.macisland.plist` and data in `~/Library/Application Support/be.roldy.macisland/`. The clipboard history is stored there in plain JSON with permissions `0600`. Turn the history off in the Presse-papiers tab if that is not acceptable to you.

## Uninstall

```sh
make uninstall            # or delete /Applications/Mac Island.app
rm -r ~/Library/Application\ Support/be.roldy.macisland     # optional: your data and backups
```

If you installed the fan helper, remove it first under System Settings, Login Items.

## Development

```sh
make test      # swift test
make run       # run from source, without a bundle (some permissions cannot be requested this way)
make check     # personal-data guard and tests
```

The code is a SwiftPM package with one module per feature under `Sources/Features/`. Each feature exposes a tab and is tested on its own. A pre-commit hook (`.githooks/pre-commit`, enabled with `git config core.hooksPath .githooks`) refuses commits that contain exported preferences, backups, clipboard data or secrets.

Releases are built with `scripts/notarize.sh`, which signs with a Developer ID, notarizes and staples the app and the disk image.

## License

GPL-3.0-or-later, see `LICENSE`. Part of the code is derived from Vorssaint (GPL-3.0-or-later). Third-party notices are in `NOTICE`.
