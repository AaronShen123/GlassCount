import Foundation

enum CountdownFormatter {
    static func twoDigits(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }

    /// Big "days" digit with grouping for very long countdowns (e.g. 12,345).
    static func days(_ b: CountdownBreakdown) -> String {
        b.totalDays.formatted(.number.grouping(.automatic))
    }

    /// Short form for cards: "12d 4h 5m", "4h 05m 09s", "Ended 3d ago". Honors the minutes/seconds preference.
    static func compact(_ b: CountdownBreakdown, detail: CountdownDetail = CountdownDetail()) -> String {
        let body: String
        if b.years > 0 { body = "\(b.years)y \(b.months)mo \(b.daysRemainder)d" }
        else if b.totalDays > 0 { body = "\(b.totalDays)d \(b.hours)h" + (detail.showMinutes ? " \(b.minutes)m" : "") }
        else if b.hours > 0 {
            body = "\(b.hours)h" + (detail.showMinutes ? " \(twoDigits(b.minutes))m" : "")
                + (detail.effectiveSeconds ? " \(twoDigits(b.seconds))s" : "")
        }
        else if !detail.showMinutes { body = "<1h" }
        else if b.minutes > 0 { body = "\(b.minutes)m" + (detail.effectiveSeconds ? " \(twoDigits(b.seconds))s" : "") }
        else { body = detail.effectiveSeconds ? "\(b.seconds)s" : "<1m" }
        return b.isExpired ? "\(body) ago" : body
    }

    /// Minute-resolution text for the menu bar (never shows seconds, so one tick per minute suffices).
    static func menuBar(_ b: CountdownBreakdown, daysOnly: Bool = false) -> String {
        if b.isExpired { return "Now" }
        if daysOnly { return b.totalDays > 0 ? "\(b.totalDays)d" : (b.hours > 0 ? "\(b.hours)h" : "<1h") }
        if b.years > 0 { return "\(b.years)y \(b.months)mo" }
        if b.totalDays > 0 { return "\(b.totalDays)d \(b.hours)h" }
        if b.hours > 0 { return "\(b.hours)h \(twoDigits(b.minutes))m" }
        if b.minutes > 0 { return "\(b.minutes)m" }
        return "<1m"
    }

    /// Secondary caption for multi-year spans: "2 years, 3 months, 12 days".
    static func yearsSummary(_ b: CountdownBreakdown) -> String? {
        guard b.years > 0 else { return nil }
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = [.year, .month, .day]
        f.maximumUnitCount = 3
        return f.string(from: DateComponents(year: b.years, month: b.months, day: b.daysRemainder))
    }

    /// Full sentence for VoiceOver.
    static func spoken(_ b: CountdownBreakdown) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = [.day, .hour, .minute, .second]
        f.maximumUnitCount = 4
        f.zeroFormattingBehavior = .dropLeading
        let s = f.string(from: DateComponents(day: b.totalDays, hour: b.hours, minute: b.minutes, second: b.seconds)) ?? ""
        return b.isExpired ? "\(s) ago" : s
    }
}
