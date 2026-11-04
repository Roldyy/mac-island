# Performance results

One section per lane, appended.

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
