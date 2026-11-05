# Results
Environment: macOS 27.2, Xcode 27.2 (Swift 6.4.2, macOS 27.2 SDK), Apple Silicon. “Observed” = measured/run here. Numbers are single machine, small samples.

| Test | Expected | Actual | Status |
|---|---|---|---|
| Application build | Compiles | `swift build` and `Scripts/build_app.sh` succeed, no errors (Liquid Glass branches compiled) | **Pass** |
| Automated tests | All pass | 62 tests passed via `swift test` and via `xcodebuild test` | **Pass** |
| Xcode project build (app + widget) | Succeeds | `xcodebuild build` succeeded; widget embedded | **Pass** (not run on desktop) |
| XCUITests | Pass | 5 written; failed in the runner (button not found) — not fixed | **Fail** |
| Create event | Event appears | Store creation tested automatically; **not clicked through in the live UI** | Partial (unit only) |
| Countdown accuracy | Correct remaining time | Engine unit tests incl. leap/DST/TZ/expired/large pass; live on-screen display not visually checked | **Pass (logic)** / UI not verified |
| Image import | Background updates | Import pipeline tested (JPEG/PNG/HEIC, rejection cases, 48 MP → 3200×2400 in ~0.085 s). App launched with `--seed-background` and wrote the resized copy; on-screen result not seen | Partial |
| Persistence | Events survive relaunch | Relaunch round-trip test passes; app wrote `state.json` + `Backgrounds/` when launched | **Pass** |
| Menu bar | Countdown displayed | Launches without crash; item **not visually inspected** | Not verified |
| Notifications | Correctly scheduled | Planner/dedupe/permission logic passes with a fake client; real delivery **not tested** | Pass (logic) / delivery not tested |
| Desktop widget (window) | Shows on desktop | Compiles; behaviour **not observed** | Not verified |
| Card resize | Sizes persist | Clamp/snap/persist/reset tested; drag gesture **not exercised live** | Partial |
| Memory | < 150 MB | RSS 121–126 MB (5 events), 179 MB with a 4000×2600 photo; phys. footprint 49–52 MB / 89 MB | RSS: **Pass** for no-photo; **Fail** vs 150 MB RSS with photo (footprint 89 MB) |
| CPU (idle, window visible, 30 s avg) | < 1 % | 0.90 %, 1.17 % (5 events); 1.10 % (with photo); 0.17 % (empty). Borderline on target | **Borderline** |
| Timer overhead / menu-bar refresh | Low | Menu bar refresh is one wake per minute by design; not separately profiled | Not measured |
| Minimized/occluded CPU, Instruments, display changes | — | — | Not measured |

CPU history (same demo data): 78 % before fixes → 0.8–1.2 % after removing `numericText`, CPU blur and per-tick shadows.
