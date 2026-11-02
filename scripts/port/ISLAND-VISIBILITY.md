# Island visibility sweep (2026-11-02)

Question per feature: switched on in Fonctions, does something reach the closed strip, or does its page render? Tests:
`Tests/PortKitTests/IslandVisibilityTests.swift`, `IslandMascotVisibilityTests.swift`, `IslandGateRepairTests.swift`,
`Tests/ActivityTests/AmbientMascotTests.swift`, `Tests/IslandKitTests/AmbientMascotRenderTests.swift`,
`Tests/NowPlayingTests/StopTests.swift`.

## Root causes found

1. **Second switch.** Several ported features check an upstream key on top of the registry switch (`shell.enabled.<id>`).
   Upstream registers it off (`notchMascotEnabled`, `notchLiveEqualizer`, `notchLockScreen`) or forces it off at first launch.
   Fix: `IslandFeatureSeed.seed` runs in `PortFeatureBinding.runStart` for every bound feature: a gate key ABSENT from the
   person's own domain is written ON; a stored value (true or false) is never touched. Idempotent.
2. **Fresh-install ordering.** `AppDelegate` stored `notchEnabled` before upstream's registration; `migrateExistingNotchDefaults`
   then read it as "island configured before" and forced notifications, camera, accessories, lyrics, equalizer, queue and
   downloads OFF. Fix: `IslandFirstLaunch.storeIslandOn` writes it after registration (read before, as the key is absent only then).
3. **One-shot repair** (`IslandFeatureSeed.repairForcedOffGates`, marker `macIslandGateRepair.v1`): a profile with ALL SEVEN keys
   stored off together (nobody does that by hand) is restored to upstream's default profile; any key stored on, or absent, means a
   choice: untouched. Marker written either way. Harold's profile (downloads on, six keys absent) is not touched; the seed rule covers him.
4. **Mascot had no closed-strip slot** (his actual bug: switch on, key on, nothing drawn). Fix below.

## Table

| Feature | Path | Shown? | Fix / note |
|---|---|---|---|
| Compagnon (notchMascot) | switch -> `mascotStart` (host flag, seed, `AmbientMascotSlot.make`) -> `IslandMascotPresence` -> `AmbientIndicator(glyph .mascot)` -> `AmbientCenter` -> `ClosedStrip` | NO before | New opt-in indicator in the wing of its side setting (`NotchMascotSide`), pinned (never rotated away), counted in the wing width, dropped first by `AmbientMetrics.fitted`, no text, VoiceOver "Compagnon", Reduce Motion honoured by the mascot view. Absent when the feature is off: the strip keeps Claude, clock, battery, cup. Page: `CompanionTabContent` |
| Musique, bandeau (music wing) | `MusicSession` -> `MusicActivity` -> `ActivityCenter` -> `AmbientBridge` -> `music` channel | Yes, only with "Lecture en cours" on | By design (closed island rule, off by default) |
| Paroles / File d'attente | registry -> `NotchLyricsSupport` / `NotchQueueSupport` gates | Page yes | Seed covers a forced-off key |
| Égaliseur en direct | `NotchAudioLevelSupport.isEnabled` reads ONLY `notchLiveEqualizer` (off) | NO before | Seed. Still needs the "Autoriser" click for audio capture |
| Minuteur / Pomodoro / chrono | `TimerLane` -> `ClosedIslandTicker` -> `timer` indicator | NO before (`notchIdleShowTimer` off, buried in the tab) | Now ON unless the person turned it off; a running timer is user-started |
| Alarme (fin du minuteur) | `PortIslandOutput` alert | Yes | Test: notice reaches a wing only while the switch is on |
| Calendrier | `CalendarIndicator` | Only with its tab switch (off) | Kept opt-in: an appointment appears with nobody having started anything |
| Téléchargements | `IslandDownloadsFeed` -> board -> `ActivityCenter` -> alert wing | Yes once a folder is chosen | Seed for `notchDownloadsEnabled`. The service arms only a folder picked in the system panel (by design) |
| Surveillance (watch) | `IslandWatchFeed` | Yes | Needs Screen Recording (never prompts) |
| Notifications miroir | `PortIslandOutput` | Yes | Seed for the key; needs Accessibility |
| Accessoires | `PortIslandOutput` | Yes | Seed for the key |
| Écran verrouillé | `IslandLockScreenController` -> `NotchLockScreenService` | NO before (`notchLockScreen` off) | Seed. Still needs the private Space capability; sounds stay the person's tick |
| Miroir | `cameraPreview` + page acquires host `mirror` | Page yes | Seed for `notchCameraEnabled`; gate reads the registry verdict |
| Fichiers (tab) | needs the shelf | Page empty before | French state "a besoin de l'Étagère" when the shelf is off |

## Other gaps closed

- **Live pages.** `IslandActivityHost` was a lock-protected flag SwiftUI cannot watch. `IslandHostTicker` ticks on every change;
  the port gate, the mascot view, the Compagnon page and the Fichiers gate observe it.
- **Dock "Vider le presse-papiers"** was gated on `AppFeature.clipboardHistory` (always off: the app delegate replaces the bound
  starter) and would clear the ported store. Now gated on OUR clipboard feature state and calls `ClipboardFeature.clearUnpinned()`.
- **Dock "Coller sans mise en forme"** was gated on `shell.enabled.pastePlain`, owned by no descriptor. Now our clipboard state +
  `ClipboardFeature.pastePlain()`. The ported `PastePlainService` hotkey never starts (`pastePlain` is not bound; `ClipboardLane`).
- **Now Playing** had no stopper: now `NowPlayingFeature.stop()`, wired in `AppDelegate`.

## Not done

- A reachable per-feature toggle on each page for notifications, accessories, lyrics, queue, camera: the Fonctions switch now
  drives the key (seed), the page toggles of upstream live in `NotchSettings.swift`, which nothing creates.
- Upstream PortKit files are untouched: no patch 2000-2049 was needed.
