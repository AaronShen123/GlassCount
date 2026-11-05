# Test plan
| Area | Method | Where |
|---|---|---|
| Countdown maths (leap year, month/year, DST both ways, timezones, expired, 100-year/year-9999 spans, sub-second, schedule/tick policy) | Swift Testing, automated | `CountdownEngineTests.swift` |
| Formatting (compact, menu bar, years summary, VoiceOver text) | automated | same |
| Input validation | automated | `ValidationTests` |
| Persistence (CRUD, relaunch round-trip, corrupt file, tolerant decoding, reorder, featured fallback, card sizes, settings no-op regression) | automated, temp dirs | `PersistenceTests.swift` |
| Background import (JPEG/PNG/HEIC, fake/unsupported/corrupt/missing files, 48 MP downsample, alpha, originals untouched via SHA-256, replace/remove, path traversal) | automated | `BackgroundImageTests.swift` |
| Notifications (offsets, past skipped, stable IDs, 60-limit, dedupe, concurrent syncs, edit/delete reconcile, denial, no prompt during sync) | automated with a fake client | `NotificationTests.swift` |
| Offscreen view rendering | opt-in PNG snapshots (manual review) | `SnapshotTests.swift` |
| Launch stability / CPU / memory | manual script runs | `Scripts/measure_perf.sh` |
| **UI flows (create/edit/delete via clicks, file picker, Settings window)** | **XCUITest — not written** | see KNOWN_ISSUES |
| Real notification delivery, menu bar rendering, desktop widget behaviour, Liquid Glass look | manual — **not performed** (no GUI/screen access from the agent) | — |
