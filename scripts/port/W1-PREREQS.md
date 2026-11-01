## Status after lane W1-0 (the binding foundation)

Done, with tests: items 1, 2, 4 and 5 below, plus the generic binding. Patches 0012 (register split), 0013
(Permissions from the host), 0014 (availability key and `isAvailable` through the registry), 0015 (every
`UserDefaults.standard` use -> `PortHost.defaults`), 0016 (Permissions injectable for tests). Hand-written:
`Bridge/PortHostState.swift`, `PortFeatureIDs.swift` (the one upstream-id -> registry-id table),
`PortFeatureBinding.swift`, `PortLanes.swift`, `FoundationExample.swift` (the URL cleaner). Item 3 (fans) is
untouched. A lane binds with `PortFeatureBinding.shared.bind(...)` from its `Bridge/<Lane>.swift` `bind(into:)`.
Three prompt families outside the three monitored permissions are still reachable from unbound features
(calendar, camera and microphone requests, notifications, Apple Events consent): the list is pinned by
`PortPromptScrubTests`, each later lane removes its own entry.

# W1 prerequisites (written down in P0-E, not implemented)

What the first input-wave lanes must do before they bind a ported feature. Each item comes from the two Opus
reviews of commit 9b64c96 (code-reviewer, security-auditor). Source changes to `Sources/PortKit` go through a
numbered patch in `scripts/port/patches` (see `import.sh`); hand-written code goes in `Sources/PortKit/Bridge`.

## 1. Split `Defaults.register()`

`Core/Defaults.swift` `register()` (about line 1970) registers every default and runs the upstream first-launch
seeds in one go. Today nothing calls it. Before a lane does:

- Register defaults only AFTER the Vorssaint migration (v1, v2 and the runtime-key purge) and after our own
  `FeatureRegistry` seed, so a registered default is never read as a migrated or user-chosen value.
- The seeds write the availability key directly with `defaults.set(..., forKey: AppFeature.<x>.availabilityKey)`:
  `notchMascot` (~2203), `notchWatch` (~2240), `linearScroll` (~2249), `fanControl` (~2259). Route all four
  through `PortHost.setEnabled` (our `FeatureRegistry` is the only writer of `shell.enabled.*`). The seeds that
  only read (`~2237`, `~2246`, `~2258`) must read through the registry too.
- `register()` must stay out of `main.swift`: upstream called it before the cleanup flags, we run
  `PortBridge.runCleanupFlagsIfRequested()` first and nothing else.

## 2. `Permissions.shared` reads our `PermissionMonitor`

- Patch `Core/Permissions.swift` so its published state comes from the `PermissionMonitor` snapshot (ShellKit), not
  from its own `AXIsProcessTrusted()` / CG probes and timer.
- Its `request*` calls (`requestAccessibility` ~255 uses `kAXTrustedCheckOptionPrompt`, `requestScreenRecording`
  ~267 uses `CGRequestScreenCaptureAccess`, the Input Monitoring and Full Disk Access variants, and the retry at
  ~294) must open the matching System Settings pane instead of prompting. Mac Island never triggers a TCC prompt
  from ported code.
- `MonitoredPermission` (ShellKit) lists, per permission, the feature ids that need it. Extend that list in the
  same change as each feature lane binds a feature, never ahead of it.

## 3. `FanControlService` becomes a shim over `FansFeature`

Before ANY fan lane: `Services/FanControl/FanControlService.swift` keeps its public surface but forwards to
`FansFeature` and `FanHelperContract` (`be.roldy.macisland.fanhelper`, team U3TUL63HHK). No `SMAppService`
registration, no second XPC protocol, no `restoreThenUnregister`. Until then it must not be bound:
`PortBridge.recoverAtLaunch` calls `FanControlService.recoverIfNeeded()` only when `fanControlRecoveryNeeded` is
set, and nothing in this app writes that key now (the migrator skips it and purges it).

Done by lane W6C (patch 1450, `Bridge/Fans.swift`, `FanControlBackend.swift`, `FanControlEngine.swift`): the service
is a ~110-line shim over `FanControlBackend`, which drives our helper through `FansFeature.driver` (`FanDriving`, no
change to `FanHelperContract` or the XPC protocol). `fanControlRecoveryNeeded` is the journal: set before the first
speed, cleared only on a confirmed automatic. The upstream fan tests are not enabled (they exercise the replaced
service); the lane's own tests are `FanControlEngineTests`, `FanControlBackendTests`, `FansLaneTests`, `FanDriverTests`.

## 4. `PermissionMonitor` poll cost

`PermissionMonitor.pollInterval` is 1 s and the poll runs for as long as any on-by-default feature lacks its
permission, which can be forever. Use 2.5 s with a timer tolerance (about 1 s), and back off (for example 5 s
after a minute without a change); keep the immediate re-read on app activation and on the Accessibility
notification, which is what makes a grant feel instant. Update the monitor tests that pin the 1 s value.

## 5. `UserDefaults` suite mismatch under `swift run`

PortKit reads and writes `UserDefaults.standard`, the registry and migrator use the `be.roldy.macisland` suite.
In the app bundle both are the same domain. Under `swift run` (no bundle id) `.standard` is the executable's own
domain, so ported code and registry disagree. Make `PortHost` carry the defaults object (set once from
`AppDefaults.make()`) and patch the ported `UserDefaults.standard` call sites to use it, or document `swift run`
as unsupported for ported features. Decide before the first lane that reads a ported key. `PortBridge.recoverAtLaunch`
takes a `defaults:` parameter for this reason.

## Also open from P0-E

- `KeepAwakeManager` has no re-exec flag (only `recoverIfNeeded`). `recoverIfNeeded` ends in `syncWithPreferences()`
  and may ask for an administrator password when `vorssDisabledSleep` is still set: the launch step only enters it
  when that marker (or the dimmed-display marker) exists. The KeepAwake lane must re-check this path.
- `FanControlService.recoverIfNeeded` may prefer a stored resume configuration over the hand-back; the launch step
  only enters it on `fanControlRecoveryNeeded`.
