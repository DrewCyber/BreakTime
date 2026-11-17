# BreakTime

A macOS menu bar app that reminds you to take regular breaks — an original,
from-scratch implementation inspired by the concept of break timers such as
Time Out. It is not affiliated with Dejal Systems, and contains none of their
code or assets.

The interface follows the classic layout: a sidebar over the toolbar
(+ / pause / gear / help), **Activity**, a **Breaks** section with live
countdown rows, and **Options** (General, Shortcuts, Rules, Advanced).

## Features

- **Menu bar status item**: without a Dock icon, clicking it opens a compact
  sidebar panel (Activity / Breaks / Options) — right-clicking shows the classic
  menu (Begin / Make Due / Postpone / Skip, Pause, Reset). The label offers
  ten modes (countdown, due/finish time, time since last break…) and the icon
  is pickable (timer, nature and activity symbols).
- **Two default breaks**: *Normal* (10 min every hour, 10-second Get Ready warning)
  and *Micro* (15 sec every 5 min). Add custom breaks with the + toolbar button.
- **Sidebar break rows** show the live countdown, "new break" / "had natural
  break" status and — on hover — **Start** and **Options ▾** buttons with the
  full options menu: Edit, Make Due In ▸, Postpone, Skip, Pause Break ▸,
  Reset, Disable, Duplicate, Delete. Drag rows to set break priority.
- **Per-break pages** with pill tabs — **Name | Schedule | Themes | Controls | Actions**:
  - *Name* — name, Label color, mini pie chart of today's counters, comments.
  - *Schedule* — Break for, Every (minutes / times per hour) with a
    "(work for …)" hint, editable Next due, Get-Ready mode, idle options.
  - *Themes* — live preview of the overlay, background color, opacity,
    countdown style, all screens.
  - *Controls* — fade in/out, postpone buttons (two configurable durations),
    skip and end-early buttons, mindfulness (buttons disabled for N seconds,
    today's counters), daily postpone/skip limits.
  - *Actions* — system sounds at break start/end with volume control.
- **Full-screen break overlay** on all screens: fade in/out, circular / bar /
  digits countdown, Postpone and Skip controls honoring limits.
- **Activity**: *Log* (every event, grouped under Today) and *Statistics*
  (breaks and minutes per day, streaks — Swift Charts, fully local).
- **Rules**: "If [app] is frontmost → automatically skip / pause breaks",
  picked from running apps.
- **Shortcuts**: real global hot keys (Carbon) for 9 actions with a
  Record Shortcut UI.
- **General**: launch at login, Dock icon, menu bar status modes.
- **Advanced**: natural break detection method and threshold,
  "Hide" checkboxes for tempting items (Pause, Make Due, Reset, Disable,
  Delete, Quit), reset timers / all settings.

## Build & run

Requires Xcode with Swift 5.9+ (built with Swift 6.4) and macOS 13+.

```bash
./make-app.sh            # debug build:  ./make-app.sh debug
open build/BreakTime.app
```

The script compiles the Swift Package, generates the app icon programmatically
(`Scripts/make_icon.swift`), assembles the `BreakTime.app` bundle and ad-hoc signs it.

Dev tip: `open build/BreakTime.app --args --settings --select controls`
opens Settings directly on a given page (`name|schedule|themes|controls|actions|
activity|statistics|general|shortcuts|rules|advanced`).

To build just the binary: `swift build`.

## Layout

```
Sources/BreakTime/
├── main.swift / AppDelegate.swift     app bootstrap (LSUIElement menu bar app)
├── Model/      BreakConfig (+Controls), AppSettings, Rules, Shortcuts, Store
├── Engine/     Scheduler, idle monitor, rules engine, hot keys, sounds, activity log
├── Overlay/    per-screen NSPanels + SwiftUI break overlay
├── StatusItem/ menu bar status item and menu
└── Settings/   sidebar settings window, per-break tabs, activity/statistics,
                general/shortcuts/rules/advanced pages, welcome window
App/Info.plist, Scripts/make_icon.swift, make-app.sh
```

Data lives in `~/Library/Application Support/BreakTime/` (config.json, activity.jsonl).

## Notes

- Timers pause while breaks are paused, when a pause rule matches, or (optionally)
  while you are idle; idle time can count as taking a break (a "natural break").
- No network access, no telemetry — everything is local.
