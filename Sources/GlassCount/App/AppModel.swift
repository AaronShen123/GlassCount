import AppKit
import Observation
import UserNotifications

enum EditorTarget: Identifiable, Equatable {
    case new
    case edit(UUID)
    var id: String { switch self { case .new: return "new"; case .edit(let id): return id.uuidString } }
}

/// Composition root: owns the services and the transient UI state shared across scenes.
@MainActor
@Observable
final class AppModel {
    let store: AppStore
    let clock: ClockObserver
    let backgrounds: BackgroundImageStore
    let imageCache: BackgroundImageCache
    let notifications: NotificationScheduler
    let dataDirectory: URL

    var editor: EditorTarget?
    var showBackgroundSheet = false
    private(set) var notificationAuth: NotificationAuthorization = .notDetermined
    private(set) var lastSync: SyncReport?
    var message: String?
    /// Set by the App scene: opens/closes the desktop widget window to match the setting.
    @ObservationIgnored var widgetWindowControl: ((Bool) -> Void)?

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var imageImports = ImageImportSessions()
    @ObservationIgnored private let options: LaunchOptions

    init(options: LaunchOptions = LaunchOptions(),
         persistence: StatePersistence? = nil,
         notificationClient: NotificationClient? = nil) {
        self.options = options
        dataDirectory = options.dataDirectory
        store = AppStore(persistence: persistence ?? JSONFilePersistence(directory: options.dataDirectory))
        clock = ClockObserver()
        backgrounds = BackgroundImageStore(directory: AppPaths.backgroundsDirectory(in: options.dataDirectory))
        imageCache = BackgroundImageCache(store: backgrounds)
        let client: NotificationClient = notificationClient
            ?? (options.systemNotifications ? SystemNotificationClient() : UnavailableNotificationClient())
        notifications = NotificationScheduler(client: client)
        message = store.statusMessage

        if options.seedDemo && store.events.isEmpty { Self.seedDemo(into: store) }
        store.onChange = { [weak self] in self?.requestSync() }
        clock.onTimeEvent = { [weak self] in self?.requestSync() }
    }

    /// Idempotent; called from the app delegate once launched.
    func start() {
        guard !started else { return }
        started = true
        clock.start()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.flushNow() }
        }
        if let seed = options.seedBackground, store.settings.background.imageFileName == nil {
            Task { _ = await importAsGlobalBackground(seed) }
        }
        requestSync()
    }

    func syncDesktopWidget() { widgetWindowControl?(store.settings.showDesktopWidget) }

    // MARK: Notifications

    /// Debounced reconcile of system notifications with the current events/settings.
    func requestSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            let report = await self.notifications.sync(events: self.store.events, settings: self.store.settings.notifications)
            self.lastSync = report
            self.notificationAuth = report.authorization
        }
    }

    func refreshAuthorization() async { notificationAuth = await notifications.authorization() }

    /// Turning reminders on is the only place that triggers the system permission prompt.
    func setRemindersEnabled(_ on: Bool) async {
        if on {
            let auth = await notifications.requestPermission()
            notificationAuth = auth
            switch auth {
            case .authorized: store.updateSettings { $0.notifications.enabled = true }
            case .denied: message = "Notifications are turned off for GlassCount. Enable them in System Settings › Notifications."
                store.updateSettings { $0.notifications.enabled = false }
            case .unavailable: message = "Notifications need the packaged GlassCount.app (not available when running the bare binary)."
                store.updateSettings { $0.notifications.enabled = false }
            case .notDetermined: store.updateSettings { $0.notifications.enabled = false }
            }
        } else {
            store.updateSettings { $0.notifications.enabled = false }
        }
    }

    // MARK: Backgrounds

    /// Imports a photo and returns its stored name; reports failures through `message`.
    func importImage(_ url: URL) async -> String? {
        do { return try await backgrounds.importImage(from: url) }
        catch { message = error.localizedDescription; return nil }
    }

    func beginImageSession(_ id: UUID) { imageImports.begin(id) }

    func endImageSession(_ id: UUID) {
        imageImports.end(id)
        cleanupImages()
    }

    func importImage(_ url: URL, for session: UUID) async -> String? {
        guard imageImports.contains(session) else { return nil }
        imageImports.beginImport()
        defer { imageImports.endImport(); cleanupImages() }
        guard let name = await importImage(url) else { return nil }
        guard imageImports.retain(name, for: session) else {
            // The editor was dismissed while decoding. Do not attach a late result.
            backgrounds.remove(fileName: name)
            return nil
        }
        return name
    }

    @discardableResult
    func importAsGlobalBackground(_ url: URL) async -> Bool {
        imageImports.beginImport()
        defer { imageImports.endImport(); cleanupImages() }
        guard let name = await importImage(url) else { return false }
        let old = store.settings.background.imageFileName
        store.updateSettings { $0.background.imageFileName = name }
        if let old, old != name { imageCache.evict(fileName: old) }
        cleanupImages()
        return true
    }

    func removeGlobalBackground() {
        store.updateSettings { $0.background.imageFileName = nil }
        cleanupImages()
    }

    func restoreDefaultBackground() {
        store.updateSettings { $0.background = BackgroundSettings() }
        cleanupImages()
    }

    /// Deletes app-owned image copies nothing references any more.
    func cleanupImages(protecting extra: Set<String> = []) {
        // A decoder may have written its output before its MainActor continuation records ownership.
        guard imageImports.inFlight == 0 else { return }
        backgrounds.removeUnreferenced(keeping: store.referencedImageFileNames
            .union(imageImports.protectedFileNames).union(extra))
    }

    // MARK: Demo data

    static func seedDemo(into store: AppStore) {
        let cal = Calendar.current
        let now = Date()
        func at(_ comps: DateComponents) -> Date { cal.date(byAdding: comps, to: now) ?? now }
        store.add(CountdownEvent(title: "Summer Trip", targetDate: at(.init(day: 47, hour: 3)), startDate: at(.init(day: -30)),
                                 iconName: "airplane", colorToken: .teal), featured: true)
        store.add(CountdownEvent(title: "Product Launch", targetDate: at(.init(day: 9, hour: 5, minute: 12)), iconName: "sparkles", colorToken: .purple))
        store.add(CountdownEvent(title: "Birthday Party", targetDate: at(.init(hour: 20, minute: 30)), iconName: "birthday.cake", colorToken: .pink))
        store.add(CountdownEvent(title: "Graduation", targetDate: at(.init(year: 2, month: 3, day: 12)), iconName: "graduationcap", colorToken: .orange))
        store.add(CountdownEvent(title: "Team Offsite", targetDate: at(.init(day: -3)), iconName: "flag.checkered", colorToken: .green))
    }
}

/// Used when the system notification centre must not be touched (tests, bare binary).
struct UnavailableNotificationClient: NotificationClient {
    func authorizationStatus() async -> NotificationAuthorization { .unavailable }
    func requestAuthorization() async -> NotificationAuthorization { .unavailable }
    func pending() async -> [PlannedReminder] { [] }
    func add(_ reminder: PlannedReminder) async throws {}
    func remove(ids: [String]) async {}
}
