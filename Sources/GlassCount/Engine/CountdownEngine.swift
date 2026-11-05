import Foundation

struct CountdownBreakdown: Equatable, Sendable {
    /// True when `now >= target`. Components then describe the time *since* the target.
    var isExpired: Bool
    var years = 0
    var months = 0
    /// Days left after removing whole years and months.
    var daysRemainder = 0
    /// Total calendar days (what the big "DAYS" digit shows).
    var totalDays = 0
    var hours = 0
    var minutes = 0
    var seconds = 0
    var totalSeconds = 0
}

/// Pure countdown maths. Everything is derived from two absolute instants plus a calendar,
/// so sleep, relaunch, clock and timezone changes cannot cause drift.
enum CountdownEngine {
    /// Calendar-aware breakdown. Both instants are truncated to whole seconds so that a tick landing
    /// on the target's second reads exactly zero / expired.
    static func breakdown(from now: Date, to target: Date,
                          calendar: Calendar = .autoupdatingCurrent) -> CountdownBreakdown {
        let n = whole(now), t = whole(target)
        let expired = t <= n
        let (a, b) = expired ? (t, n) : (n, t)
        let ymd = calendar.dateComponents([.year, .month, .day], from: a, to: b)
        let dhms = calendar.dateComponents([.day, .hour, .minute, .second], from: a, to: b)
        return CountdownBreakdown(
            isExpired: expired,
            years: ymd.year ?? 0, months: ymd.month ?? 0, daysRemainder: ymd.day ?? 0,
            totalDays: dhms.day ?? 0, hours: dhms.hour ?? 0, minutes: dhms.minute ?? 0, seconds: dhms.second ?? 0,
            totalSeconds: Int(b.timeIntervalSince(a)))
    }

    /// 0…1 progress between `start` and `target`; nil when not computable.
    static func progress(start: Date?, target: Date, now: Date) -> Double? {
        guard let start, target > start else { return nil }
        let p = now.timeIntervalSince(start) / target.timeIntervalSince(start)
        return p.clamped(to: 0...1)
    }

    /// How often a view needs to redraw. `nil` = never (expired).
    static func tickInterval(remaining: TimeInterval, showsSeconds: Bool) -> TimeInterval? {
        if remaining <= 0 { return nil }
        if showsSeconds || remaining <= 120 { return 1 }
        return 60
    }

    private static func whole(_ d: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: d.timeIntervalSinceReferenceDate.rounded(.down))
    }
}
