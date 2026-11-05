import SwiftUI

/// Status-item label. Updates once a minute (via `ClockObserver.minuteNow`), never per second.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.store.settings
        HStack(spacing: 4) {
            Image(systemName: model.store.featuredEvent?.iconName ?? "hourglass")
            if settings.menuBarDisplay != .iconOnly, let e = model.store.featuredEvent {
                let b = CountdownEngine.breakdown(from: model.clock.minuteNow, to: e.targetDate)
                Text(CountdownFormatter.menuBar(b, daysOnly: settings.menuBarDisplay == .daysOnly)).monospacedDigit()
            }
        }
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let e = model.store.featuredEvent else { return "GlassCount" }
        let b = CountdownEngine.breakdown(from: model.clock.minuteNow, to: e.targetDate)
        return "\(e.title), \(CountdownFormatter.spoken(b))"
    }
}
