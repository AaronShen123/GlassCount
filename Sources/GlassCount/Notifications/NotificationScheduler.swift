import Foundation
import UserNotifications

enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
    /// No app bundle / system service available (e.g. running a bare binary or tests).
    case unavailable
}

protocol NotificationClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    /// Pending reminders created by GlassCount only.
    func pending() async -> [PlannedReminder]
    func add(_ reminder: PlannedReminder) async throws
    func remove(ids: [String]) async
}

struct SyncReport: Equatable, Sendable {
    var added = 0
    var removed = 0
    var unchanged = 0
    var authorization: NotificationAuthorization = .notDetermined
}

/// Actor so overlapping syncs are serialised and cannot create duplicates.
actor NotificationScheduler {
    private let client: NotificationClient
    init(client: NotificationClient) { self.client = client }

    func authorization() async -> NotificationAuthorization { await client.authorizationStatus() }

    /// Asks the system for permission (shows the system prompt only when undetermined).
    func requestPermission() async -> NotificationAuthorization {
        let current = await client.authorizationStatus()
        if current == .notDetermined { return await client.requestAuthorization() }
        return current
    }

    /// Actors are re-entrant at every `await`, so overlapping syncs would interleave and redundantly re-add
    /// reminders. Each sync therefore waits for the previous one to finish (strict FIFO).
    private var lastSync: Task<Void, Never>?

    @discardableResult
    func sync(events: [CountdownEvent], settings: NotificationSettings, now: Date = Date()) async -> SyncReport {
        let previous = lastSync
        let task = Task { () -> SyncReport in
            await previous?.value
            return await self.performSync(events: events, settings: settings, now: now)
        }
        lastSync = Task { _ = await task.value }
        return await task.value
    }

    private func performSync(events: [CountdownEvent], settings: NotificationSettings, now: Date) async -> SyncReport {
        var report = SyncReport()
        report.authorization = await client.authorizationStatus()
        let pending = await client.pending()

        // Disabled, or not allowed to deliver: make sure nothing of ours lingers.
        guard settings.enabled, report.authorization == .authorized else {
            if !pending.isEmpty { await client.remove(ids: pending.map(\.id)); report.removed = pending.count }
            return report
        }

        let desired = ReminderPlanner.plan(events: events, settings: settings, now: now)
        let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
        let pendingByID = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let stale = pending.map(\.id).filter { desiredByID[$0] == nil }
        if !stale.isEmpty { await client.remove(ids: stale); report.removed = stale.count }

        for reminder in desired {
            if let existing = pendingByID[reminder.id], Self.same(existing, reminder) {
                report.unchanged += 1
                continue
            }
            do { try await client.add(reminder); report.added += 1 } catch { /* keep going; next sync retries */ }
        }
        return report
    }

    private static func same(_ a: PlannedReminder, _ b: PlannedReminder) -> Bool {
        a.title == b.title && a.body == b.body && abs(a.fireDate.timeIntervalSince(b.fireDate)) < 1
    }
}

/// Real implementation backed by UserNotifications.
struct SystemNotificationClient: NotificationClient {
    private var center: UNUserNotificationCenter { .current() }

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func authorizationStatus() async -> NotificationAuthorization {
        guard Self.isAvailable else { return .unavailable }
        let s = await center.notificationSettings().authorizationStatus
        switch s {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        guard Self.isAvailable else { return .unavailable }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func pending() async -> [PlannedReminder] {
        guard Self.isAvailable else { return [] }
        let requests = await center.pendingNotificationRequests()
        return requests.compactMap { r in
            guard r.identifier.hasPrefix(ReminderPlanner.identifierPrefix),
                  let trigger = r.trigger as? UNCalendarNotificationTrigger,
                  let fire = trigger.nextTriggerDate(),
                  let idString = r.content.userInfo["eventID"] as? String, let eid = UUID(uuidString: idString),
                  let raw = r.content.userInfo["offset"] as? String, let off = ReminderOffset(rawValue: raw)
            else { return nil }
            return PlannedReminder(id: r.identifier, eventID: eid, offset: off, fireDate: fire,
                                   title: r.content.title, body: r.content.body)
        }
    }

    func add(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["eventID": reminder.eventID.uuidString, "offset": reminder.offset.rawValue]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        // Same identifier replaces any existing request, so this can never duplicate.
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    func remove(ids: [String]) async {
        guard Self.isAvailable, !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
