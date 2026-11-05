import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var events: [CountdownEvent]
    private(set) var settings: AppSettings
    private(set) var statusMessage: String?
    private(set) var saveErrorMessage: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let persistence: StatePersistence
    @ObservationIgnored private let writer: PersistenceWriter
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var saveRevision = 0

    init(persistence: StatePersistence, saveDelay: Duration = .milliseconds(300)) {
        self.persistence = persistence
        self.writer = PersistenceWriter(persistence)
        self.saveDelay = saveDelay
        var loaded = PersistedState()
        var message: String?
        do {
            if let s = try persistence.load() { loaded = s }
        } catch {
            try? persistence.quarantine()
            message = "Your saved data could not be read and was moved aside (state.corrupt-*.json). Starting fresh."
        }
        events = loaded.events
        settings = loaded.settings
        statusMessage = message
        normalizeFeatured()
    }

    // MARK: Queries

    /// Explicit selection, else the soonest upcoming event, else the first event.
    var featuredEvent: CountdownEvent? {
        if let id = settings.featuredEventID, let e = events.first(where: { $0.id == id }) { return e }
        let now = Date()
        return events.filter { $0.targetDate > now }.min { $0.targetDate < $1.targetDate } ?? events.first
    }

    func event(id: UUID) -> CountdownEvent? { events.first { $0.id == id } }

    var referencedImageFileNames: Set<String> {
        var set = Set(events.compactMap(\.backgroundImageFileName))
        if let n = settings.background.imageFileName { set.insert(n) }
        return set
    }

    // MARK: Event mutations

    func add(_ event: CountdownEvent, featured: Bool = false) {
        events.append(event)
        if featured || settings.featuredEventID == nil && events.count == 1 { settings.featuredEventID = event.id }
        commit()
    }

    func update(_ event: CountdownEvent, featured: Bool? = nil) {
        guard let i = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[i] = event
        if featured == true { settings.featuredEventID = event.id }
        else if featured == false, settings.featuredEventID == event.id { settings.featuredEventID = nil }
        commit()
    }

    func delete(id: UUID) {
        events.removeAll { $0.id == id }
        normalizeFeatured()
        commit()
    }

    @discardableResult
    func duplicate(id: UUID) -> CountdownEvent? {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = events[i]
        copy.id = UUID()
        copy.title += " Copy"
        copy.createdAt = Date()
        events.insert(copy, at: i + 1)
        commit()
        return copy
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        events.move(fromOffsets: fromOffsets, toOffset: toOffset)
        commit()
    }

    /// Moves `id` by `delta` positions (clamped). Used by context menus.
    func moveEvent(id: UUID, by delta: Int) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        let j = (i + delta).clamped(to: 0...(events.count - 1))
        guard i != j else { return }
        let e = events.remove(at: i)
        events.insert(e, at: j)
        commit()
    }

    /// Drag & drop: place `id` at the position currently held by `target`.
    func moveEvent(id: UUID, onto target: UUID) {
        guard id != target,
              let from = events.firstIndex(where: { $0.id == id }),
              let to = events.firstIndex(where: { $0.id == target }) else { return }
        let e = events.remove(at: from)
        events.insert(e, at: to)
        commit()
    }

    /// Sets (or with nil, resets) a card's size. Values are snapped and clamped.
    func setCardSize(id: UUID, width: Double?, height: Double?) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        let w = width.map(CardSize.clampWidth), h = height.map(CardSize.clampHeight)
        guard events[i].cardWidth != w || events[i].cardHeight != h else { return }
        events[i].cardWidth = w
        events[i].cardHeight = h
        commit()
    }

    func setFeatured(id: UUID?) {
        settings.featuredEventID = id
        normalizeFeatured()
        commit()
    }

    // MARK: Settings

    /// No-op (no observation notification, no save) when the mutation changes nothing. This matters:
    /// SwiftUI calls some binding setters during scene evaluation, and an unconditional write there
    /// re-invalidates the App body in a feedback loop.
    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        commit()
    }

    func clearStatusMessage() { statusMessage = nil }

    // MARK: Persistence

    private func normalizeFeatured() {
        if let id = settings.featuredEventID, !events.contains(where: { $0.id == id }) {
            settings.featuredEventID = nil
        }
    }

    private func commit() {
        scheduleSave()
        onChange?()
    }

    func retrySave() { scheduleSave() }

    private func scheduleSave() {
        saveRevision &+= 1
        let revision = saveRevision
        saveTask?.cancel()
        let snapshot = snapshotState()
        let delay = saveDelay
        let writer = writer
        saveTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let error = await writer.write(snapshot)
            guard !Task.isCancelled, revision == saveRevision else { return }
            saveErrorMessage = error.map { "Could not save: \($0)" }
        }
    }

    func snapshotState() -> PersistedState {
        var s = PersistedState()
        s.events = events
        s.settings = settings
        return s
    }

    /// Synchronous save, used on app termination and by tests.
    func flushNow() {
        saveRevision &+= 1
        saveTask?.cancel()
        do { try persistence.save(snapshotState()); saveErrorMessage = nil }
        catch { saveErrorMessage = "Could not save: \(error.localizedDescription)" }
    }
}
