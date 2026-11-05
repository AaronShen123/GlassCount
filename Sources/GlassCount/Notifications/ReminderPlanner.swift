import Foundation

struct PlannedReminder: Equatable, Hashable, Sendable {
    var id: String
    var eventID: UUID
    var offset: ReminderOffset
    var fireDate: Date
    var title: String
    var body: String
}

enum ReminderPlanner {
    static let identifierPrefix = "glasscount."
    /// macOS keeps at most 64 pending local notifications per app.
    static let maxPending = 60

    static func identifier(eventID: UUID, offset: ReminderOffset) -> String {
        "\(identifierPrefix)\(eventID.uuidString).\(offset.rawValue)"
    }

    /// Pure function: which reminders should exist right now. Past reminders are dropped.
    static func plan(events: [CountdownEvent], settings: NotificationSettings, now: Date) -> [PlannedReminder] {
        guard settings.enabled else { return [] }
        var out: [PlannedReminder] = []
        for event in events where event.remindersEnabled {
            for offset in settings.offsets {
                let fire = Date(timeIntervalSince1970: (event.targetDate.timeIntervalSince1970 - offset.interval).rounded(.down))
                guard fire > now else { continue }
                out.append(PlannedReminder(
                    id: identifier(eventID: event.id, offset: offset), eventID: event.id, offset: offset,
                    fireDate: fire, title: event.title, body: body(for: offset, target: event.targetDate)))
            }
        }
        out.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(out.prefix(maxPending))
    }

    static func body(for offset: ReminderOffset, target: Date) -> String {
        let when = target.formatted(date: .abbreviated, time: .omitted)
        switch offset {
        case .sevenDays: return "7 days to go · \(when)"
        case .oneDay: return "Tomorrow · \(when)"
        case .oneHour: return "In 1 hour · \(when)"
        case .atEvent: return "It's time! · \(when)"
        }
    }
}
