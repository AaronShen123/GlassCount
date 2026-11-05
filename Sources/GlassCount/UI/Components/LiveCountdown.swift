import SwiftUI

/// Minute- or second-aligned schedule that stops after the target has passed.
struct CountdownSchedule: TimelineSchedule {
    let target: Date
    let showsSeconds: Bool

    func entries(from startDate: Date, mode: Mode) -> Entries {
        Entries(cursor: startDate, target: target, showsSeconds: showsSeconds && mode == .normal,
                lowFrequency: mode == .lowFrequency, emittedFirst: false, finished: startDate >= target)
    }

    struct Entries: Sequence, IteratorProtocol {
        var cursor: Date
        let target: Date
        let showsSeconds: Bool
        let lowFrequency: Bool
        var emittedFirst: Bool
        var finished: Bool

        mutating func next() -> Date? {
            if !emittedFirst { emittedFirst = true; return cursor }   // render immediately
            if finished { return nil }
            let remaining = target.timeIntervalSince(cursor)
            guard var period = CountdownEngine.tickInterval(remaining: remaining, showsSeconds: showsSeconds) else {
                finished = true; return nil
            }
            if lowFrequency && remaining > 120 { period = 60 }
            let t = cursor.timeIntervalSinceReferenceDate
            var next = Date(timeIntervalSinceReferenceDate: ((t + 0.001) / period).rounded(.up) * period)
            if next >= target { next = target; finished = true }
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
