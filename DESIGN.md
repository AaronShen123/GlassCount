# GlassCount — Design

> Environment note (see `KNOWN_ISSUES.md`): this machine has only the Command Line Tools
> (Swift 6.1.2, macOS 15.5 SDK). No Xcode, so the project is a **Swift Package** that Xcode opens
> natively, plus a script that assembles the `.app`. Liquid Glass APIs (macOS 26 SDK) are
> compiled conditionally and could **not** be compiled or run here.

## 1. Product goals
- A lightweight, beautiful, fully offline countdown utility for macOS.
- Native look: Liquid Glass surfaces over a user photo, HIG-conformant, light/dark adaptive.
- Always-correct time (derived from wall clock, never a decrementing counter).
- Near-zero idle cost: no tick loop when nothing is visible.
- Private by construction: local files only, no network, no telemetry.

## 2. User stories
1. As a user I create a countdown with a title, date/time, icon and colour.
2. I see the most important event big, with live d/h/m/s, and the rest as cards.
3. I upload my own photo as the window background and tune blur / dimming / opacity.
4. I give individual events their own background.
5. I glance at the menu bar for the featured event and switch which one is featured.
6. I get reminders (7 d, 1 d, 1 h, at time) as native notifications.
7. I edit, duplicate, delete and reorder events; everything survives relaunch.

## 3. Feature requirements
Mapped 1:1 to the brief: multiple events; featured event; optional start date + progress;
event colour/icon; Fill/Fit; blur/dim/opacity; default background; per-event background;
menu bar item; local notifications with permission handling; JSON persistence; Settings
window; empty states; accessibility labels; resizable window.

## 4. UI layout
```
┌──────────────────────────────────────────────────────────┐
│ (traffic lights)                                         │
│ GlassCount                     [+ Add] [Background] [⚙]  │  header (glass buttons)
│ ┌──────────────────────────────────────────────────────┐ │
│ │ ★ Event title                      Sat, Dec 25, 9:00 │ │  featured glass card
│ │   128   :  04  :  17  :  09                          │ │
│ │  DAYS     HRS    MIN    SEC     ▓▓▓▓▓░░░░ 54 %       │ │
│ └──────────────────────────────────────────────────────┘ │
│ ┌────────┐ ┌────────┐ ┌────────┐                         │  adaptive LazyVGrid of cards
│ │ card   │ │ card   │ │ card   │                         │
│ └────────┘ └────────┘ └────────┘                         │
└──────────────────────────────────────────────────────────┘
```
Layers (back to front): default gradient or custom image → blur → dim → glass containers → type/controls.
Sheets: Event editor, Background customizer. Settings: native `Settings` scene (General, Notifications, Background, About).
Menu bar: `MenuBarExtra` (window style) with featured summary, event list (tap = make featured), Open, Settings, Quit.

## 5. Visual design system
- Corner radii: card 28, featured 36, controls capsule. Continuous corners.
- Type: SF Rounded; digits `.monospacedDigit()` + `numericText` transition; labels in `.caption` uppercase tracking.
- Colour: 7 muted event accents (blue, teal, green, orange, pink, purple, graphite) used only as small tints/icons.
- Glass: `glassEffect` + `GlassEffectContainer` on macOS 26+; `ultraThinMaterial` + hairline gradient stroke + soft shadow elsewhere. All glass access goes through `GlassSurface.swift`.
- Readability: with a custom image, content switches to a dark colour scheme and glass is dark-tinted; text carries a soft shadow.
- Motion: 0.25 s snappy spring; disabled when Reduce Motion is on.

## 6. Application architecture
```
GlassCountApp (scenes) ── AppModel (composition root, @MainActor @Observable)
   ├─ AppStore            events + settings, debounced JSON persistence
   ├─ ClockObserver       wake / clock / timezone / day-change signals
   ├─ NotificationScheduler (actor) ── NotificationClient (protocol; UNUserNotificationCenter impl)
   ├─ BackgroundImageStore  import/validate/downsample/delete files
   └─ BackgroundImageCache  NSCache of downsampled images
Pure logic (no UI/IO): CountdownEngine, CountdownFormatter, ReminderPlanner, EventDraft validation.
```
Single SwiftPM executable target `GlassCount`; tests use `@testable import`.

## 7. Data model
- `CountdownEvent { id, title, targetDate(Date, absolute instant), startDate?, iconName, colorToken, backgroundImageFileName?, remindersEnabled, createdAt }`
- `AppSettings { featuredEventID?, background: BackgroundSettings, notifications: NotificationSettings, appearance, showMenuBarItem, menuBarDisplay }`
- `BackgroundSettings { imageFileName?, fit, blur 0…40, dimming 0…0.8, opacity 0.1…1 }`
- `NotificationSettings { enabled, offsets: Set<ReminderOffset> }`
- On disk: `state.json` = `{ schemaVersion, events[] (array order = display order), settings }`, ISO-8601 dates, decoded with defaults for missing keys (forward-compatible).

## 8. Component responsibilities
| Component | Responsibility |
|---|---|
| `CountdownEngine` | `now,target → breakdown` using `Calendar`; expiry; progress; tick policy |
| `CountdownFormatter` | digits, menu-bar title, accessibility strings |
| `AppStore` | CRUD, reorder, featured fallback, debounced save, `onChange` hook |
| `JSONFilePersistence` | atomic write, corrupt-file quarantine (never deletes) |
| `BackgroundImageStore` | validate type by sniffing, downsample ≤3200 px, write JPEG/PNG copy |
| `ReminderPlanner` | pure: events × offsets × now → future `PlannedReminder`s (stable IDs) |
| `NotificationScheduler` | diff desired vs pending, add/remove only differences, permission state |
| `LiveCountdown` | `TimelineView` with a custom aligned schedule |
| `GlassSurface` | the only place that touches Liquid Glass / material APIs |

## 9. Background image workflow
`fileImporter(jpeg,png,heic)` → `BackgroundImageStore.importImage(url)` (detached task):
size cap → `CGImageSource` open → sniff real type (extension is not trusted) → pixel-count cap →
thumbnail ≤3200 px with orientation applied → write `<uuid>.jpg` (or `.png` if alpha) to
`Application Support/GlassCount/Backgrounds/` via temp file + move → return file name →
stored in settings/event. Original file is only ever read. Replace/remove deletes only our copy
and only when no longer referenced. Missing file → silently fall back to default background and warn in UI.

## 10. Notification lifecycle
Toggle on → request authorization (only then) → `sync`. `sync` runs (debounced) after any event/setting
change, wake, clock change, timezone change, day change. Desired set = `ReminderPlanner`; pending set read
from the centre; add/remove only differences, so no duplicates (identifier =
`glasscount.<eventID>.<offset>`). Denied → toggle shows guidance + link to System Settings. Max 60 pending.

## 11. Performance strategy
- Time is computed from `Date()` at each render; ticks are only a redraw trigger.
- `TimelineView` only runs for visible views. Featured card: 1 s. Cards: 60 s, minute-aligned, switching to 1 s in the last 2 minutes. Expired: no ticks.
- Menu bar label: one `Task.sleep` to the next minute boundary; popover content ticks only while open.
- Images downsampled at import and again at display size; `NSCache` with cost limit; cards load ≤640 px.
- Debounced, off-main file writes; no polling anywhere.

## 12. Key technical risks
1. No Xcode: cannot compile Liquid Glass path, run XCUITest, Instruments, or create a verified `.xcodeproj`.
2. `MenuBarExtra` label refresh and `TimelineView` behaviour when windows are occluded — measured, not assumed.
3. Notifications need a real app bundle (ad-hoc signed `.app`); unverifiable delivery headless.
4. DST/timezone semantics: target is an absolute instant; day counts are calendar-based.

## Project structure
```
GlassCount/
├─ Package.swift
├─ Resources/Info.plist
├─ Scripts/build_app.sh, measure_perf.sh
├─ Sources/GlassCount/
│  ├─ App/            GlassCountApp, AppModel, AppDelegate, LaunchOptions
│  ├─ Models/         CountdownEvent, AppSettings, EventStyle
│  ├─ Engine/         CountdownEngine, CountdownFormatter, ClockObserver
│  ├─ Persistence/    StatePersistence, AppStore
│  ├─ Notifications/  ReminderPlanner, NotificationScheduler
│  ├─ Background/     BackgroundImageStore, BackgroundImageCache
│  ├─ MenuBar/        MenuBarContent, MenuBarLabel
│  └─ UI/             Components/, Views/, Settings/
├─ Tests/GlassCountTests/
└─ DESIGN.md README.md TEST_PLAN.md RESULTS.md KNOWN_ISSUES.md
```
