# Known issues & limitations
1. **Two ways to build:** `GlassCount.xcodeproj` (generated from `project.yml` with XcodeGen; app + WidgetKit extension + tests; builds with `xcodebuild`, ad-hoc signed) and the SwiftPM path (`Package.swift` + `Scripts/build_app.sh`). Regenerate the project with `xcodegen generate` after editing `project.yml`.
2. **Two “widgets”.** (a) A floating desktop window (resizable, works from the SwiftPM and Xcode builds). (b) A real WidgetKit widget in the Xcode build; it reads `state.json` via a sandbox *temporary read exception*, which works for local ad-hoc builds only and would be rejected by the App Store. The WidgetKit widget was **built but never added to the desktop or seen running**.
3. **XCUITests are written (5) but currently FAIL** (the runner cannot find the “Add Countdown” button — likely accessibility identifiers not exposed through the glass button style). Not investigated further. Unit tests (62) run and pass both with `swift test` and `xcodebuild test`. UI was otherwise never seen by the agent (no Screen Recording access); the main-window offscreen snapshot rendered blank, the Background sheet snapshot rendered correctly.
12. Not intended for the App Store: bundle ID is a placeholder, no team/signing, widget uses a sandbox exception, app is not sandboxed.
4. **Liquid Glass compiles and links** (Xcode 27.2 SDK) but its visual result has **not been inspected**. The Material fallback (macOS 15) has not been inspected either.
5. **Notifications:** scheduling logic is tested against a fake; real delivery and the system permission prompt were **not** exercised. Needs the packaged `.app`.
6. Menu bar label updates once per minute (never shows seconds) by design; on expiry it can lag up to ~60 s.
7. Target is an absolute instant: if you travel across timezones, the event stays at the same moment (its wall-clock time changes). Day counts are calendar-based (DST-correct).
8. With a photo background the content is forced to a dark colour scheme for legibility, so light mode only applies to the built-in backgrounds.
9. Deployment target is macOS 15 (needed for `.windowStyle(.plain)` / `defaultLaunchBehavior`).
10. App icon exists (`Tools/build_icon.sh` regenerates it). Ad-hoc signature only (Gatekeeper may need right-click › Open on other Macs). Bundle ID `com.glasscount.app` is a placeholder.
11. Not measured: CPU while minimized/occluded, Instruments leak/time profiles, external-display and scaling changes, sleep/wake behaviour in the live app (maths is unit-tested).

## Bugs found and fixed during development
- Launch crash / runaway: `MenuBarExtra(isInserted:)` setter wrote settings during scene evaluation → infinite App-body re-evaluation (stack overflow). Fixed: no-op writes are ignored (regression test).
- 50–78 % idle CPU: `.numericText` transitions, CPU-blurred shapes and per-tick shadows. Fixed → ~1 %.
- Notification sync actor re-entrancy caused redundant adds. Fixed with FIFO serialisation (test).
