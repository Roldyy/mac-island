# Performance baseline, Mac Island 1.0.0 (build 113), 2026-11-04

Measured read-only on the installed app (pid 5298), macOS 15.7.9, island closed.

## Numbers

| | Evening (4h45 up, Spotify playing) | Morning (17h40 up, nothing playing) |
|---|---|---|
| CPU % (ps, 5 samples) | 3.9 / 6.0 / 2.1 / 3.4 / 3.2 (mean 3.7) | 0.2 / 0.1 / 0.0 / 0.3 / 1.0 |
| top CPU / POWER | 2.8 - 3.1 | n/a |
| RSS / footprint | 267 MB / 405 MB | 120 MB / 167 MB (peak footprint 541 MB) |
| Threads / open files | 15-18 / 100 | 14 / 99 |

Lifetime CPU time 50:16 over 17h40 wall clock (about 4.7 % of one core, sleep included).
Wakeups per second: UNKNOWN (needs `sudo powermetrics`). Child processes alive: `perl now-playing.pl ... watch_all`, a terminal `/bin/bash -l`.

## Targets (island closed, 10 min)

- Nothing playing: mean CPU < 0.5 %.
- Spotify playing: mean CPU < 1.5 %.
- Peak footprint after 8 h: < 250 MB, no monotonic growth.
- Wakeups per second: divided by at least 3 against the powermetrics baseline.

## Offenders, ranked (sample counts per 10 s unless noted)

1. Now Playing AppleScript poll: `Sources/Features/NowPlaying/NowPlayingModel.swift:326-330`, every 3 s closed (1 s open), a fresh `NSAppleScript` compile and run each round (`AppleScriptRunner.swift:28-40`, `ScriptedProviders.swift:16,35`), duplicates the event driven perl adapter (`NotchMusicService.swift:127`).
2. Claude session reader, up to three times: `ClaudeLiveMonitor.swift:39-44` (2 s, open or closed, started at `AppDelegate.swift:98`), a second monitor in `AgentsLiveModel.swift:15`, a third read by `AgentsUsageModel.startWarmup` every 60 s.
3. Closed strip animations never paused when hidden or when the screen sleeps: `IslandKit/AmbientEqualizer.swift:12` (20 fps), `AmbientGlyphView.swift:43` (30 fps), `AmbientValueText.swift:47` (30 fps marquee), `AmbientElementView.swift:39` (1 s clock).
4. Focus follows mouse: global monitor on every mouse move (`FocusFollowsMouseService.swift:59-61`), 20 Hz timer while settling (`:103`) fetching the full window list.
5. Global mouse monitors and 33 event tap sites; island hover uses an always-on global mouse move monitor (`IslandKit/NotchPanel.swift:266-272`) plus an `NSLog` on every hover enter/exit.
6. `Features/Terminal/ClaudeStatusModel.swift:13`: a 1 s timer held by a static, never stopped, scans the process tree.
7. Three or four clipboard pollers: `PasteboardWatcher.swift:16,38` (0.5 s), `URLCleanerService.swift:90` (0.8 s), `ClipboardAutoClearService.swift:95` (1 s), `ClipboardHistoryService.swift:658` (0.8 s, only when the ported store owns history).
8. Memory high water: live heap 71 MB against a 541 MB peak; candidates: agent usage parsing (`[UsageRecord]` arrays), artwork thumbnails, clipboard images. Cause UNKNOWN.
9. Two system metric samplers: `MonitorModel.swift:148-151` (5 s) and `PortKit/Services/SystemMonitor/SystemMonitor.swift:686` (own timer, can spawn nettop, system_profiler, diskutil).
10. Steady timers: `DockPreviewService.swift:1313` copies the whole `com.apple.dock` domain every 10 s; `KeyEventTap.swift:70` 5 s watchdog; `AgentUsageService` 30 s tick (2 s poll while logs changed in the last 30 min).

Already well gated: closed island samplers (`ShellKit/Ambient/*`), Home sliders loop, `MonitorModel` cadence, fans loops.

## How to measure (before and after)

Island closed, 10 minutes, once with Spotify playing and once without:
- `ps -o time=` delta and %CPU sampled 5 times 2 s apart;
- `sample <pid> 10`: total the `AppleScriptRunner`, Claude reader and SwiftUI rendering stacks;
- `sudo powermetrics --samplers tasks --show-process-energy -i 5000 -n 12` for wakeups and energy (typed by Harold in a terminal);
- `footprint <pid>` and `heap -s` after 1 h of use;
- `MIS_HITCH_LOG=1` for open/close regressions.
