import AppKit
import Observation

/// Publishes "the clock changed" signals (sleep/wake, manual clock change, timezone, midnight)
/// plus a minute-aligned `now` used by the menu bar. No per-second work happens here.
@MainActor
@Observable
final class ClockObserver {
    /// Increments whenever an external time event occurs; views use it as an identity to force a recompute.
    private(set) var epoch = 0
    /// Minute-resolution "now" for low-frequency consumers (menu bar).
    private(set) var minuteNow = Date()

    @ObservationIgnored var onTimeEvent: (() -> Void)?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {}

    func start() {
        guard tasks.isEmpty, observers.isEmpty else { return }
        let names: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (.default, .NSSystemClockDidChange),
            (.default, .NSSystemTimeZoneDidChange),
            (.default, .NSCalendarDayChanged),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fire() }
            }
            observers.append((center, token))
        }
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let wait = 60 - now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) + 0.05
                try? await Task.sleep(for: .seconds(wait))
                guard let self else { return }
                self.minuteNow = Date()
            }
        })
    }

    func fire() {
        epoch += 1
        minuteNow = Date()
        onTimeEvent?()
    }

    deinit {
        tasks.forEach { $0.cancel() }
        observers.forEach { $0.0.removeObserver($0.1) }
    }
}
