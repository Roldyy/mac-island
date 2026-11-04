# Performance results

One section per lane, appended.

## Lane 1: Now Playing poll, Claude status timer, clipboard pollers, hover log (branch worktree-perf1)

BEFORE (read-only, installed 1.0.0 build 113, pid 5298, island closed, 2026-11-04): Spotify open but not playing, `ps` 5 samples 1.2 / 1.4 / 0.6 / 0.0 / 0.0 % (mean 0.6); the evening Spotify-playing baseline in BASELINE.md is 3.7 % mean. `perl now-playing.pl ... watch_all` alive (the adapter is available on this Mac).
AFTER: not measurable here (no install, no run of the app). Compared by test: timers and reads are counted with fake clocks/schedulers, see "Tests".

### What changed

1. Now Playing (offender 1), `Sources/Features/NowPlaying/`:
   - The adapter is the single source of truth while it delivers. New `NowPlayingAdapterReading` (public), `NowPlayingModel.adapterDelivered/adapterUnavailable`, `NowPlayingFeature.adapterDelivered/adapterUnavailable`. While it delivers, `poll()` returns at once and no AppleScript runs (also not for `refreshNow`, the Home or the Lecture tab, and not after a transport command). The model takes the cover from the adapter. Unavailable (adapter restarting, crashed, never started): AppleScript polling resumes as before.
   - Bridge: `Sources/PortKit/Bridge/IslandMusicFeed.swift` (`PortMusicFeed.observe`, event driven off `NotchMusicService.objectWillChange`), wired once in `AppDelegate`. Live means: music session running, adapter child alive and answered once (`adapterIsLive`, patch 2253).
   - No player open: no timer. `WorkspaceAppEvents` listens to NSWorkspace launch/terminate (Spotify and Music only); the model does one read and arms nothing, a launch re-arms, a quit ends the loop.
   - Closed island: the background poll runs only if the closed-island music indicator is switched on (Settings, `notchIdleShowMusic`, off by default); `NowPlayingFeature` follows that switch through the defaults notification. With the adapter delivering, a 1 s progress tick runs only while the Lecture page or Home card is visible and a track plays (3 s when only the closed ring needs it, none when paused).
   - `AppleScriptRunner` caches the compiled `NSAppleScript` per source (`CompiledScriptCache`).
2. Claude status (offender 6), `ClaudeStatusModel`: no more static timer for the life of the app. A timer exists only while a terminal shell exists or a "Termine" badge is settling; `TerminalSession` posts `sessionChanged` on shell start and exit. Timer tolerance 0.3 s. The process tree is scanned only when a shell exists (already true, kept).
3. Clipboard (offender 7): ONE `PasteboardChangeHub` (new, `Sources/IslandKit/PasteboardChangeHub.swift`; it sits in IslandKit because `ClipboardFeature` and `PortKit` share no other module). One timer at the fastest subscriber interval with tolerance, one `changeCount` read per tick on a private queue (off the main thread, as upstream insists since #189), delivered to every subscriber; it stops with the last subscriber. Subscribers: `PasteboardWatcher` (ours), `URLCleanerService` (patch 2250, its lane pass now only runs when the count moved), `ClipboardAutoClearService` (2251, decides from the hub count), `ClipboardHistoryService` (2252, idle: `portedStoreOwnsHistory` is false in the shipped app).
4. `IslandKit/NotchPanel.swift`: the `NSLog` on every hover enter/exit is gone.

### Deliberate deviations

- Closed island with the music indicator off: the last-track memory no longer updates from a background poll while the adapter is not delivering; it updates when the Home opens (poll on open) and continuously while the adapter delivers.
- A Now Playing reading through the adapter also shows players other than Spotify and Music (whatever the system session is) and needs no Automation permission; the card then reads `ready`.
- The hub lives in IslandKit (a new file there), not in Features/Clipboard or PortKit Compat (neither module can see the other).
- Handlers of the hub may be called more often than their requested interval (every tick of the fastest subscriber), the URL cleaner and auto clear compare counts so this costs nothing.
- Not done: the adapter is not started on behalf of Now Playing. It runs only when a music feature (lyrics, queue, live equalizer) or the music tab holds `MusicSession`; otherwise AppleScript stays the reader (now with the economies above).

### Tests (written first; RED = build failure on the missing API, then green)

- `Tests/NowPlayingTests/PollingEconomyTests.swift`: no timer without a player; launch notification arms, quit ends; closed without indicator: no poll; adapter delivering: provider not polled (Home open too); adapter lost: fallback resumes; paused: no tick; script cache.
- `Tests/TerminalTests/ClaudeStatusModelTests.swift`: no shell no timer; one timer; scan only with a shell; timer ends after the badge settles.
- `Tests/IslandKitTests/PasteboardChangeHubTests.swift`: no subscriber no timer; stops with the last subscriber; ONE read per tick for N subscribers; follows the fastest interval; in-flight read skips the tick.
- `Tests/ClipboardTests/PasteboardWatcherHubTests.swift`: subscribe/unsubscribe, one report per change, stale count ignored.
- Runs: NowPlayingFeatureTests 121 pass, TerminalFeatureTests 115 pass, ClipboardFeatureTests 129 pass, PortKitTests 1305 pass, ShellKitTests 398 pass, PasteboardChangeHubTests 6 pass; `swift build` green.
- Patches 2250-2253 verified with a full `scripts/port/import.sh` from `tasks/parity/vorssaint-3.4.2-src.tgz` in a temp worktree: `diff -r` against `Sources/PortKit` shows only `Core/AlertSoundStrings.swift` and the new `Bridge/IslandMusicFeed.swift` (hand-written, never touched by the import).

### How to verify on the Mac (installed build, island closed, 10 min, nothing typed)

1. Nothing playing, Spotify and Music quit: `ps -o %cpu= -p $(pgrep -x MacIsland)` 5 times 2 s apart, expect mean < 0.3 %; `sample $(pgrep -x MacIsland) 10` shows no `AppleScriptRunner` or `ClaudeStatusModel` frames.
2. Spotify playing, island closed, closed music indicator off: mean < 1.5 % target, no `AppleScriptRunner` frames in `sample`, `log stream --predicate 'process == "MacIsland"'` shows no "hover" lines.
3. Open the Home with Spotify playing: progress bar still moves, play/pause works, track change shows at once.
4. Quit the perl adapter (`pkill -f now-playing.pl`): within seconds the card falls back to AppleScript; the adapter restarts by itself and takes over again.
5. Copy a URL with tracking parameters and a password-manager entry with auto clear on: the URL is cleaned, the clear still fires after the delay; history still records.
6. `sudo powermetrics --samplers tasks --show-process-energy -i 5000 -n 12` for wakeups (typed by Harold).

## Lane 2: Claude session reader and usage parsing (worktree-perf2)

Offenders 2 and 8 of BASELINE.md. No live measurement yet: CPU and footprint numbers need the rebuilt app (UNKNOWN until then).

Changes
- One reader: `ClaudeLiveMonitor.shared` (ClaudeLiveKit). The shell ("agents" switch, consumer `shell`), the Agents tab (`agents-tab`, via `AgentsLiveModel`) and the usage warm-up (`AgentsUsageModel.liveSessions`, no file read, `claudeIsActive()` removed) all use it. Named consumers: the last `release` cancels the watchers and the poll and withdraws the activities.
- Event driven: `DispatchFileWatcher` (O_EVTONLY, write/extend/delete/rename) on the sessions folder, each pid-named session file (rewritten in place, a folder source does not see that) and the hook folder; first event opens a 250 ms window, one read per burst; re-armed after delete/rename and at every slow tick. Slow poll 30 s with a session, 120 s without; with no pid-named file nothing is read. The 2 s loop is gone.
- Security rules untouched (SafeFileRead, name regex, 16 KB cap, allow-listed fields, procStart +-2 s, unknown never idle); the watcher only gets names that pass `pid(fromFileName:)`.
- `AgentUsageService`: the repeating 30 s Timer became a one-shot re-armed per sweep: 30 s while the AI page is open or `snapshot.live` is non-empty (closed-island rest indicator), 180 s otherwise; `pageDidAppear` leaves the slow cadence at once. File events and the 2 s poller (already off with no recent log) are unchanged.
- Usage parsing (Features/Agents): repeated message ids folded while streaming (one record per id), 250 000 records per file cap (extra counted in malformedLines), model/project strings interned (bounded 512), `UsageFileCache.merged()` one pass and one array instead of two, progress reports every 1 s instead of 0.3 s, no `settled + x` copy when `settled` is empty. Suspected spike source: each 0.3 s cold-read report built 2-3 full `[UsageRecord]` arrays on top of un-folded repeats. Not measured with `heap`/`footprint`: confirm after rebuild.

Tests (RED seen as compile failures first, then green)
- ClaudeLiveKitTests 69 passed (new: single shared instance, one refresh after debounce, no read with an empty folder, slow poll only, stops with last consumer, hostile names never watched or read).
- AgentsFeatureTests 133 passed (new: BoundedParsingTests, SharedMonitorTests). ActivityTests 231 passed. ShellKitTests: 1 timing test (SettingsPerformanceTests) failed under parallel load, passes alone.
- Allocation peak test is opt-in (process-wide counters): `MIS_ALLOC_TEST=1 swift test --filter BoundedParsingTests` (peak growth < 25 MB on a 45 MB log, passes).

## Lane 3: closed strip animations, island hover, focus follows mouse (offenders 3, 4, 5)

Not measured on a running app yet (needs the installed build and the BASELINE measurements); the changes below are
verified by build and tests only.

- Offender 3: one `AmbientClock` (IslandKit) gates the four animations. It pauses when the island is open, the panel
  is occluded (`NSWindow.occlusionState`), the screens sleep (`screensDidSleep` / `willSleep`) or the session is
  locked (`sessionDidResignActive`), and resumes on the matching notification. Rates: equalizer 20 -> 12 fps, busy
  ring 30 -> 15 fps, marquee 30 -> 20 fps and only when the text overflows. Paused means a paused `TimelineView`
  (no display link), or a static text for the elapsed time. Elapsed time shows seconds, so it stays at 1 s while
  visible. The wall clock indicator was already one sleep aligned to the minute (`ShellKit/Ambient/ClockSampler.swift`).
  Policy is pure: `AmbientClockPolicy`, tests `AmbientClockPolicyTests`.
- Offender 5: the always-on global and local `mouseMoved` monitors are gone. `HoverTrackingView` (an
  `NSTrackingArea`, `.activeAlways`, refreshed on every frame or open-state change) reports enter and exit of
  `IslandHoverRegion.zone` (closed frame while closed, panel while open, +2 pt at the top edge). No event reaches
  the app while the pointer is elsewhere. Tests `IslandHoverRegionTests`. NOT verified live: hover opening on a
  second display, in a full-screen Space, and under another screen-saver-level overlay.
- Offender 4: patch `2300-focus-follows-mouse-one-shot-settle.patch`. Nothing is read or installed while the feature
  is off (already true, preferences are now nil until start). While on: raise / wait-for-stop / delay are read once
  at start and on `UserDefaults.didChangeNotification`, not per move; moves are processed at most 20 per second
  (the newest point is kept and picked up when the timer fires); the 20 Hz repeating timer is a one-shot for the
  delay, re-armed for the remainder if the pointer moved (2 timers for a settle in the burst test); the window list
  is fetched once per settle, as before. Tests `FocusFollowsMouseSettleTests`.
  `scripts/port/import.sh` in a temp worktree: `diff -r` equals `Sources/PortKit` except `Core/AlertSoundStrings.swift`.
- Tests green (one filter group at a time): IslandKitTests 129, PortKitTests 1311, ShellKitTests 398 (includes
  IslandFluidityTests, HomeClosedPillTests), ActivityTests 231.
