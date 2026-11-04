# Performance results

One section per lane, appended.

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
