import Testing
import Foundation
import UserNotifications
@testable import GlassCount

/// In-memory stand-in for UNUserNotificationCenter.
final class FakeNotificationClient: NotificationClient, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: PlannedReminder] = [:]
    private var status: NotificationAuthorization
    private(set) var addCalls = 0
    private(set) var requestCalls = 0
    let grantOnRequest: Bool

    init(status: NotificationAuthorization, grantOnRequest: Bool = true) { self.status = status; self.grantOnRequest = grantOnRequest }

    var pendingIDs: Set<String> { lock.withLock { Set(store.keys) } }
    func authorizationStatus() async -> NotificationAuthorization { lock.withLock { status } }
    func requestAuthorization() async -> NotificationAuthorization {
        lock.withLock { requestCalls += 1; status = grantOnRequest ? .authorized : .denied; return status }
    }
    func pending() async -> [PlannedReminder] { lock.withLock { Array(store.values) } }
    func add(_ r: PlannedReminder) async throws { lock.withLock { addCalls += 1; store[r.id] = r } }   // same id replaces
    func remove(ids: [String]) async { lock.withLock { ids.forEach { store[$0] = nil } } }
}

@Suite("Notifications")
struct NotificationTests {
    let now = date(2025, 1, 1)
    func event(_ title: String = "E", in seconds: TimeInterval, reminders: Bool = true) -> CountdownEvent {
        CountdownEvent(title: title, targetDate: now.addingTimeInterval(seconds), remindersEnabled: reminders)
    }
    func settings(_ offsets: Set<ReminderOffset>, enabled: Bool = true) -> NotificationSettings {
        var s = NotificationSettings(); s.enabled = enabled; s.offsets = offsets; return s
    }

    // MARK: Planner

    @Test func offsetsAreCorrect() {
        let e = event(in: 10 * 86_400)
        let plan = ReminderPlanner.plan(events: [e], settings: settings(Set(ReminderOffset.allCases)), now: now)
        let byOffset = Dictionary(uniqueKeysWithValues: plan.map { ($0.offset, $0.fireDate) })
        #expect(byOffset[.sevenDays] == e.targetDate.addingTimeInterval(-7 * 86_400))
        #expect(byOffset[.oneDay] == e.targetDate.addingTimeInterval(-86_400))
        #expect(byOffset[.oneHour] == e.targetDate.addingTimeInterval(-3600))
        #expect(byOffset[.atEvent] == e.targetDate)
        #expect(plan.count == 4)
        #expect(plan == plan.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func pastRemindersAreSkipped() {
        let e = event(in: 2 * 3600)            // 2 h away: 7d and 1d are in the past
        let plan = ReminderPlanner.plan(events: [e], settings: settings(Set(ReminderOffset.allCases)), now: now)
        #expect(Set(plan.map(\.offset)) == [.oneHour, .atEvent])
        #expect(ReminderPlanner.plan(events: [event(in: -100)], settings: settings([.atEvent]), now: now).isEmpty)
    }

    @Test func disabledGlobalOrPerEvent() {
        let e = event(in: 86_400 * 3)
        #expect(ReminderPlanner.plan(events: [e], settings: settings([.atEvent], enabled: false), now: now).isEmpty)
        #expect(ReminderPlanner.plan(events: [event(in: 86_400 * 3, reminders: false)], settings: settings([.atEvent]), now: now).isEmpty)
    }

    @Test func identifiersAreStableAndUnique() {
        let e = event(in: 86_400 * 30)
        let a = ReminderPlanner.plan(events: [e], settings: settings(Set(ReminderOffset.allCases)), now: now)
        let b = ReminderPlanner.plan(events: [e], settings: settings(Set(ReminderOffset.allCases)), now: now.addingTimeInterval(60))
        #expect(a.map(\.id) == b.map(\.id))
        #expect(Set(a.map(\.id)).count == a.count)
        #expect(a.allSatisfy { $0.id.hasPrefix(ReminderPlanner.identifierPrefix) })
    }

    @Test func respectsSystemLimit() {
        let events = (0..<40).map { event("E\($0)", in: Double(86_400 * (10 + $0))) }
        let plan = ReminderPlanner.plan(events: events, settings: settings(Set(ReminderOffset.allCases)), now: now)
        #expect(plan.count == ReminderPlanner.maxPending)
        #expect(plan.first!.fireDate <= plan.last!.fireDate)   // soonest are kept
    }

    // MARK: Scheduler

    @Test func scheduleThenResyncDoesNotDuplicate() async {
        let client = FakeNotificationClient(status: .authorized)
        let sched = NotificationScheduler(client: client)
        let events = [event(in: 3 * 86_400)]
        let s = settings([.oneDay, .atEvent])
        let r1 = await sched.sync(events: events, settings: s, now: now)
        #expect(r1.added == 2 && r1.unchanged == 0)
        let r2 = await sched.sync(events: events, settings: s, now: now)
        #expect(r2.added == 0 && r2.unchanged == 2)
        #expect(client.addCalls == 2 && client.pendingIDs.count == 2)
    }

    @Test func concurrentSyncsStayDeduplicated() async {
        let client = FakeNotificationClient(status: .authorized)
        let sched = NotificationScheduler(client: client)
        let events = [event(in: 3 * 86_400), event("B", in: 5 * 86_400)]
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { _ = await sched.sync(events: events, settings: self.settings([.oneDay, .atEvent]), now: self.now) } }
        }
        #expect(client.pendingIDs.count == 4)
        #expect(client.addCalls == 4)
    }

    @Test func editedAndDeletedEventsAreReconciled() async {
        let client = FakeNotificationClient(status: .authorized)
        let sched = NotificationScheduler(client: client)
        var e = event(in: 3 * 86_400)
        let other = event("O", in: 4 * 86_400)
        _ = await sched.sync(events: [e, other], settings: settings([.atEvent]), now: now)
        e.targetDate = e.targetDate.addingTimeInterval(3600); e.title = "Renamed"
        let r = await sched.sync(events: [e], settings: settings([.atEvent]), now: now)
        #expect(r.added == 1 && r.removed == 1)
        let pending = await client.pending()
        #expect(pending.count == 1 && pending[0].title == "Renamed" && pending[0].fireDate == e.targetDate)
    }

    @Test func disablingRemovesEverything() async {
        let client = FakeNotificationClient(status: .authorized)
        let sched = NotificationScheduler(client: client)
        _ = await sched.sync(events: [event(in: 86_400 * 3)], settings: settings([.atEvent, .oneHour]), now: now)
        let r = await sched.sync(events: [event(in: 86_400 * 3)], settings: settings([.atEvent], enabled: false), now: now)
        #expect(r.removed == 2 && client.pendingIDs.isEmpty)
    }

    @Test func deniedPermissionSchedulesNothing() async {
        let client = FakeNotificationClient(status: .denied)
        let sched = NotificationScheduler(client: client)
        let r = await sched.sync(events: [event(in: 86_400 * 3)], settings: settings([.atEvent]), now: now)
        #expect(r.authorization == .denied && r.added == 0 && client.addCalls == 0)
    }

    @Test func notDeterminedDoesNotPromptDuringSync() async {
        let client = FakeNotificationClient(status: .notDetermined)
        let sched = NotificationScheduler(client: client)
        _ = await sched.sync(events: [event(in: 86_400 * 3)], settings: settings([.atEvent]), now: now)
        #expect(client.requestCalls == 0 && client.addCalls == 0)
    }

    @Test func permissionRequestedOnlyWhenUndetermined() async {
        let granting = FakeNotificationClient(status: .notDetermined, grantOnRequest: true)
        #expect(await NotificationScheduler(client: granting).requestPermission() == .authorized)
        #expect(granting.requestCalls == 1)
        let denying = FakeNotificationClient(status: .notDetermined, grantOnRequest: false)
        #expect(await NotificationScheduler(client: denying).requestPermission() == .denied)
        let already = FakeNotificationClient(status: .denied)
        _ = await NotificationScheduler(client: already).requestPermission()
        #expect(already.requestCalls == 0)       // never re-prompts once decided
    }

    @MainActor @Test func modelHandlesDenialGracefully() async {
        var opts = LaunchOptions(); opts.dataDirectory = makeTempDir()
        let client = FakeNotificationClient(status: .notDetermined, grantOnRequest: false)
        let model = AppModel(options: opts, notificationClient: client)
        await model.setRemindersEnabled(true)
        #expect(model.store.settings.notifications.enabled == false)
        #expect(model.notificationAuth == .denied && model.message != nil)
        let ok = AppModel(options: opts, notificationClient: FakeNotificationClient(status: .notDetermined, grantOnRequest: true))
        await ok.setRemindersEnabled(true)
        #expect(ok.store.settings.notifications.enabled)
    }
}

@Suite("Absolute notification triggers")
struct AbsoluteTriggerTests {
    @Test func componentsPreserveInstantAcrossCalendarTimezones() {
        let fire = date(2027, 6, 15, 9, tz: "America/New_York")
        let trigger = SystemNotificationClient.trigger(for: fire)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone?.secondsFromGMT(for: fire) == 0)
        #expect(trigger.dateComponents.calendar?.identifier == .gregorian)
        for zone in ["America/Los_Angeles", "Asia/Tokyo", "Europe/London"] {
            #expect(calendar(zone).date(from: trigger.dateComponents) == fire)
        }
    }

    @Test func nativeNextTriggerDateMatchesAbsoluteFutureInstant() {
        let fire = Date(timeIntervalSince1970: Date().addingTimeInterval(7200).timeIntervalSince1970.rounded(.down))
        #expect(SystemNotificationClient.trigger(for: fire).nextTriggerDate() == fire)
    }
}
