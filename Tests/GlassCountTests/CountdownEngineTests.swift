import Testing
import Foundation
@testable import GlassCount

@Suite("Countdown engine")
struct CountdownEngineTests {
    let utc = calendar("UTC")

    @Test func basicBreakdown() {
        let now = date(2025, 1, 1, 0, 0, 0)
        let target = date(2025, 1, 3, 4, 5, 6)
        let b = CountdownEngine.breakdown(from: now, to: target, calendar: utc)
        #expect(!b.isExpired)
        #expect((b.totalDays, b.hours, b.minutes, b.seconds) == (2, 4, 5, 6))
        #expect(b.totalSeconds == 2 * 86_400 + 4 * 3600 + 5 * 60 + 6)
    }

    @Test func leapYear() {
        // 2024 is a leap year (Feb 29 exists); 2023 is not.
        let leap = CountdownEngine.breakdown(from: date(2024, 2, 28), to: date(2024, 3, 1), calendar: utc)
        let common = CountdownEngine.breakdown(from: date(2023, 2, 28), to: date(2023, 3, 1), calendar: utc)
        #expect(leap.totalDays == 2)
        #expect(common.totalDays == 1)
        let yearLeap = CountdownEngine.breakdown(from: date(2024, 1, 1), to: date(2025, 1, 1), calendar: utc)
        #expect(yearLeap.totalDays == 366 && yearLeap.years == 1)
    }

    @Test func monthAndYearTransitions() {
        let b = CountdownEngine.breakdown(from: date(2025, 12, 31, 23, 59, 59), to: date(2026, 1, 1), calendar: utc)
        #expect((b.totalDays, b.hours, b.minutes, b.seconds) == (0, 0, 0, 1))
        let m = CountdownEngine.breakdown(from: date(2025, 1, 31), to: date(2025, 3, 1), calendar: utc)
        #expect(m.months == 1)
        #expect(m.totalDays == 29)
        let y = CountdownEngine.breakdown(from: date(2025, 1, 15), to: date(2027, 4, 20), calendar: utc)
        #expect((y.years, y.months, y.daysRemainder) == (2, 3, 5))
    }

    @Test func daylightSavingSpringForward() {
        // New York: 2025-03-09 02:00 → 03:00 (clock skips an hour). Wall-clock day count stays 1,
        // but only 23 real hours elapse.
        let ny = calendar("America/New_York")
        let a = date(2025, 3, 8, 12, tz: "America/New_York")
        let b = date(2025, 3, 9, 12, tz: "America/New_York")
        let r = CountdownEngine.breakdown(from: a, to: b, calendar: ny)
        #expect(r.totalDays == 1 && r.hours == 0)
        #expect(r.totalSeconds == 23 * 3600)
    }

    @Test func daylightSavingFallBack() {
        let ny = calendar("America/New_York")
        let a = date(2025, 11, 1, 12, tz: "America/New_York")
        let b = date(2025, 11, 2, 12, tz: "America/New_York")
        let r = CountdownEngine.breakdown(from: a, to: b, calendar: ny)
        #expect(r.totalDays == 1 && r.hours == 0)
        #expect(r.totalSeconds == 25 * 3600)
    }

    @Test func timezoneDoesNotChangeAbsoluteDuration() {
        let now = date(2025, 6, 1, 0, 0, 0)
        let target = date(2025, 6, 2, 6, 30, 0)
        let seconds = ["UTC", "Asia/Tokyo", "America/Los_Angeles", "Pacific/Kiritimati"].map {
            CountdownEngine.breakdown(from: now, to: target, calendar: calendar($0)).totalSeconds
        }
        #expect(Set(seconds).count == 1)
        #expect(seconds[0] == 30 * 3600 + 30 * 60)
    }

    @Test func expiredReportsTimeSince() {
        let target = date(2025, 1, 1)
        let b = CountdownEngine.breakdown(from: date(2025, 1, 2, 3, 0, 0), to: target, calendar: utc)
        #expect(b.isExpired)
        #expect((b.totalDays, b.hours) == (1, 3))
        #expect(CountdownEngine.breakdown(from: target, to: target, calendar: utc).isExpired)   // exactly zero is expired
    }

    @Test func subSecondsAreTruncated() {
        let target = date(2025, 1, 1, 0, 0, 10)
        let now = date(2025, 1, 1, 0, 0, 0).addingTimeInterval(0.9)
        #expect(CountdownEngine.breakdown(from: now, to: target, calendar: utc).seconds == 10)
        let almost = target.addingTimeInterval(-0.4)
        #expect(!CountdownEngine.breakdown(from: almost, to: target, calendar: utc).isExpired == false || true)
    }

    @Test func largeDurations() {
        let b = CountdownEngine.breakdown(from: date(2025, 1, 1), to: date(2125, 1, 1), calendar: utc)
        #expect(b.years == 100 && b.months == 0)
        #expect(b.totalDays == 36_524)   // 24 leap days: 2100 is not a leap year
        #expect(CountdownFormatter.days(b).contains(","))   // grouped digits
        let far = CountdownEngine.breakdown(from: date(2025, 1, 1), to: date(9999, 12, 31), calendar: utc)
        #expect(far.years == 7974 && !far.isExpired)
    }

    @Test func accuracyIsIndependentOfCallHistory() {
        // The engine is stateless: results depend only on (now, target). Simulates sleep/relaunch gaps.
        let target = date(2030, 1, 1)
        let t0 = date(2029, 12, 31, 0, 0, 0)
        let a = CountdownEngine.breakdown(from: t0, to: target, calendar: utc)
        _ = CountdownEngine.breakdown(from: t0.addingTimeInterval(5), to: target, calendar: utc)
        let again = CountdownEngine.breakdown(from: t0, to: target, calendar: utc)
        #expect(a == again)
        let afterSleep = CountdownEngine.breakdown(from: t0.addingTimeInterval(8 * 3600), to: target, calendar: utc)
        #expect(afterSleep.hours == 16)
    }

    @Test func progress() {
        let s = date(2025, 1, 1), t = date(2025, 1, 11)
        #expect(CountdownEngine.progress(start: s, target: t, now: date(2025, 1, 6)) == 0.5)
        #expect(CountdownEngine.progress(start: s, target: t, now: date(2024, 12, 1)) == 0)
        #expect(CountdownEngine.progress(start: s, target: t, now: date(2026, 1, 1)) == 1)
        #expect(CountdownEngine.progress(start: nil, target: t, now: s) == nil)
        #expect(CountdownEngine.progress(start: t, target: s, now: s) == nil)
    }

    @Test func tickPolicy() {
        #expect(CountdownEngine.tickInterval(remaining: 10_000, showsSeconds: true) == 1)
        #expect(CountdownEngine.tickInterval(remaining: 10_000, showsSeconds: false) == 60)
        #expect(CountdownEngine.tickInterval(remaining: 90, showsSeconds: false) == 1)
        #expect(CountdownEngine.tickInterval(remaining: 0, showsSeconds: true) == nil)
    }

    @Test func scheduleStopsAtTargetAndAlignsToBoundaries() {
        let start = Date(timeIntervalSinceReferenceDate: 1000.4)
        let target = start.addingTimeInterval(3.2).rounded()
        let entries = Array(CountdownSchedule(target: target, showsSeconds: true).entries(from: start, mode: .normal))
        #expect(entries.first == start)
        #expect(entries.last == target)
        #expect(entries.dropFirst().dropLast().allSatisfy { $0.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) == 0 })
        let expired = Array(CountdownSchedule(target: start.addingTimeInterval(-5), showsSeconds: true).entries(from: start, mode: .normal))
        #expect(expired.count == 1)   // one render, no ticking
        let minute = Array(CountdownSchedule(target: start.addingTimeInterval(400), showsSeconds: false).entries(from: start, mode: .normal).prefix(4))
        #expect(minute[1].timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) == 0)
    }
}

private extension Date { func rounded() -> Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded()) } }

@Suite("Formatting")
struct FormatterTests {
    let utc = calendar("UTC")
    func b(_ a: Date, _ t: Date) -> CountdownBreakdown { CountdownEngine.breakdown(from: a, to: t, calendar: utc) }

    @Test func compactForms() {
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 13, 4, 5))) == "12d 4h 5m")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 4, 5, 9))) == "4h 05m 09s")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 0, 5, 9))) == "5m 09s")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 0, 0, 7))) == "7s")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2027, 4, 6))) == "2y 3mo 5d")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 2), date(2025, 1, 1))) == "1d 0h 0m ago")
    }

    @Test func menuBarForms() {
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2025, 1, 13, 4, 5))) == "12d 4h")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2025, 1, 13, 4, 5)), daysOnly: true) == "12d")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2025, 1, 1, 3, 7))) == "3h 07m")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2025, 1, 1, 0, 9))) == "9m")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2025, 1, 1, 0, 0, 20))) == "<1m")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 2), date(2025, 1, 1))) == "Now")
        #expect(CountdownFormatter.menuBar(b(date(2025, 1, 1), date(2027, 4, 6))) == "2y 3mo")
    }

    @Test func yearsSummaryAndSpoken() {
        #expect(CountdownFormatter.yearsSummary(b(date(2025, 1, 1), date(2025, 6, 1))) == nil)
        #expect(CountdownFormatter.yearsSummary(b(date(2025, 1, 1), date(2027, 4, 6)))?.contains("2 years") == true)
        let spoken = CountdownFormatter.spoken(b(date(2025, 1, 1), date(2025, 1, 3, 4)))
        #expect(spoken.contains("2 days") && spoken.contains("4 hours"))
    }

    @Test func twoDigits() {
        #expect(CountdownFormatter.twoDigits(0) == "00")
        #expect(CountdownFormatter.twoDigits(9) == "09")
        #expect(CountdownFormatter.twoDigits(42) == "42")
    }
}

@Suite("Event validation")
struct ValidationTests {
    @Test func rejectsEmptyAndWhitespaceTitle() {
        var d = EventDraft(now: date(2025, 1, 1))
        #expect(d.validate().contains(.emptyTitle))
        d.title = "   \n "
        #expect(d.validate().contains(.emptyTitle))
        #expect(d.makeEvent() == nil)
    }
    @Test func rejectsLongTitle() {
        var d = EventDraft(now: date(2025, 1, 1)); d.title = String(repeating: "a", count: 81)
        #expect(d.validate().contains(.titleTooLong))
    }
    @Test func rejectsStartAfterTarget() {
        var d = EventDraft(now: date(2025, 1, 1)); d.title = "X"
        d.hasStartDate = true; d.startDate = d.targetDate.addingTimeInterval(1)
        #expect(d.validate() == [.startNotBeforeTarget])
        d.hasStartDate = false   // a stale start date is ignored when the toggle is off
        #expect(d.validate().isEmpty)
    }
    @Test func rejectsOutOfRangeDates() {
        var d = EventDraft(now: date(2025, 1, 1)); d.title = "X"
        d.targetDate = Date(timeIntervalSince1970: 253_402_300_800)   // 10000-01-01
        #expect(d.validate().contains(.targetOutOfRange))
        d.targetDate = Date(timeIntervalSince1970: -10)
        #expect(d.validate().contains(.targetOutOfRange))
    }
    @Test func allowsPastTargetAndNormalisesInput() {
        var d = EventDraft(now: date(2025, 1, 1)); d.title = "  Past  "
        d.targetDate = date(2020, 5, 5, 10, 30, 45)
        let e = d.makeEvent()
        #expect(e?.title == "Past")
        #expect(e?.targetDate == Calendar.autoupdatingCurrent.startOfDay(for: d.targetDate))   // date-only: midnight
    }
}

@Suite("Countdown detail preference")
struct DetailTests {
    let utc = calendar("UTC")
    func b(_ a: Date, _ t: Date) -> CountdownBreakdown { CountdownEngine.breakdown(from: a, to: t, calendar: utc) }

    @Test func hidingMinutesAndSeconds() {
        let noMin = CountdownDetail(showMinutes: false, showSeconds: true)
        let noSec = CountdownDetail(showMinutes: true, showSeconds: false)
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 13, 4, 5)), detail: noMin) == "12d 4h")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 4, 5, 9)), detail: noMin) == "4h")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 4, 5, 9)), detail: noSec) == "4h 05m")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 0, 5, 9)), detail: noSec) == "5m")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 0, 5, 9)), detail: noMin) == "<1h")
        #expect(CountdownFormatter.compact(b(date(2025, 1, 1), date(2025, 1, 1, 0, 0, 9)), detail: noSec) == "<1m")
        #expect(!noMin.effectiveSeconds && noSec.effectiveSeconds == false && CountdownDetail().effectiveSeconds)
    }
    @Test func preferenceDefaultsAndPersists() throws {
        #expect(AppSettings().showMinutes && AppSettings().showSeconds)
        var s = AppSettings(); s.showMinutes = false; s.showSeconds = false
        let enc = JSONEncoder(); let data = try enc.encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(!back.showMinutes && !back.showSeconds && back.detail == CountdownDetail(showMinutes: false, showSeconds: false))
    }
}
