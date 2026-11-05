# GlassCount

A native, offline macOS countdown app (SwiftUI + AppKit, Liquid Glass on macOS 26+, Material fallback before).

## Download & install (for friends)
1. Download **GlassCount.zip** from the [Releases](../../releases) page and unzip it.
2. Drag **GlassCount.app** into your **Applications** folder.
3. The app is not notarized by Apple, so macOS blocks the first launch. Do **one** of these:
   - Right-click GlassCount.app › **Open** › **Open**; or
   - Run in Terminal: `xattr -dr com.apple.quarantine /Applications/GlassCount.app`
4. Requires macOS 15 or later (Apple silicon and Intel).

## Requirements
macOS 15+ to run. Xcode 26+ (built and tested here with Xcode 27.2 / Swift 6.4.2) to build.

## Open / build / run
```
open GlassCount.xcodeproj          # app + WidgetKit widget + tests (⌘R runs it); or: open Package.swift
xcodegen generate                  # regenerate the project after editing project.yml (brew install xcodegen)
./Scripts/build_app.sh             # release build → build/GlassCount.app (ad-hoc signed)
open build/GlassCount.app
```
Running the bare binary from Xcode/`swift run` works, but **notifications need the packaged `.app`**.
Developer switches: `--data-dir <path>` (isolated data), `--seed-demo`, `--seed-background <image>`, `--no-system-notifications`.

## Tests
```
swift test                         # 62 Swift Testing tests (also: xcodebuild -scheme GlassCount test -only-testing:GlassCountTests)
GC_SNAPSHOT_DIR=/tmp/snaps swift test --filter SnapshotTests   # optional offscreen PNGs
./Scripts/measure_perf.sh "label" --seed-demo                  # CPU/memory (needs the built .app)
```

## Using it
- **Add Countdown** (⌘N): name, date/time, optional start date (progress bar), icon, colour, optional card photo, reminders.
- **Resize cards:** drag the corner handle of any card (or right-click › Card Size). Sizes are saved per card.
- **Reorder:** drag a card onto another, or right-click › Move Up/Down. **Feature:** right-click › Make Featured, or from the menu bar.
- **Background:** header “Background” button or Settings › Background: pick one of 10 built-in backgrounds, or *Choose Image…* (JPEG/PNG/HEIC). Fill/Fit, blur, dimming, opacity, Remove, Restore Default.
- **Notifications:** Settings › Notifications › Enable reminders (macOS asks once). If blocked, use the button to open System Settings.
- **Menu bar:** the hourglass/icon + compact countdown at the top right; click for the popover (switch featured, open app, settings, desktop widget, quit). Toggle in Settings › General.
- **Settings › General › Countdown:** choose whether minutes and seconds are shown.
- **Desktop widget:** resizable (drag the corner handle; right-click › Reset Size). Settings › General › Show desktop widget (or the menu-bar popover button). A small glass card that stays on the desktop on all Spaces; drag it anywhere; hover for ✕.

## Where data lives
`~/Library/Application Support/GlassCount/state.json` (events + settings) and `Backgrounds/` (resized copies of imported photos). Originals are never modified. Unreadable `state.json` is moved to `state.corrupt-<time>.json`, never deleted. No network access, no telemetry.
