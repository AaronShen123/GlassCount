import SwiftUI

/// Minute- or second-aligned schedule for both remaining and elapsed time.
struct CountdownSchedule: TimelineSchedule {
    let target: Date
    let showsSeconds: Bool

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(cursor: startDate, target: target, showsSeconds: showsSeconds && mode == .normal,
                lowFrequency: mode == .lowFrequency, emittedFirst: false)
    }

    struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let target: Date
        let showsSeconds: Bool
        let lowFrequency: Bool
        var emittedFirst: Bool

        mutating func next() -> Date? {
            if !emittedFirst { emittedFirst = true; return cursor }   // render immediately
            let remaining = target.timeIntervalSince(cursor)
            // Expired cards still display elapsed time, so they need ongoing refreshes.
            var period = CountdownEngine.tickInterval(remaining: remaining, showsSeconds: showsSeconds)
                ?? (showsSeconds ? 1 : 60)
            if lowFrequency && remaining > 120 { period = 60 }
            let t = cursor.timeIntervalSinceReferenceDate
            var next = Date(timeIntervalSinceReferenceDate: ((t + 0.001) / period).rounded(.up) * period)
            if cursor < target && next >= target { next = target }
            cursor = next
            return next
        }
    }
}

/// Re-evaluates the countdown from the real clock on every tick. Ticks only drive redraws.
struct LiveCountdown<Content: View>: View {
    @Environment(AppModel.self) private var model
    let target: Date
    var showsSeconds = true
    @ViewBuilder var content: (CountdownBreakdown, Date) -> Content

    var body: some View {
        TimelineView(CountdownSchedule(target: target, showsSeconds: showsSeconds)) { ctx in
            content(CountdownEngine.breakdown(from: ctx.date, to: target), ctx.date)
        }
        .id(model.clock.epoch)   // forces a fresh schedule after wake / clock / timezone changes
    }
}

struct DigitBlock: View {
    let value: String
    let label: String
    var size: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.3)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.medium))
                .tracking(1.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
