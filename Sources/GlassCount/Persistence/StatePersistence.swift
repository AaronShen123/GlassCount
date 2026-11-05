import Foundation

struct PersistedState: Codable, Equatable, Sendable {
    static let currentSchema = 1
    var schemaVersion = PersistedState.currentSchema
    var events: [CountdownEvent] = []
    var settings = AppSettings()

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        events = try c.decodeIfPresent([CountdownEvent].self, forKey: .events) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

protocol StatePersistence: Sendable {
    /// Returns nil when nothing has been saved yet. Throws when the data exists but is unreadable.
    func load() throws -> PersistedState?
    func save(_ state: PersistedState) throws
    /// Moves unreadable data aside (never deletes it).
    func quarantine() throws
}

struct JSONFilePersistence: StatePersistence {
    let fileURL: URL

    init(directory: URL) { fileURL = directory.appendingPathComponent("state.json") }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load() throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .glassCountStateDidSave, object: fileURL)
    }

    func quarantine() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = fileURL.deletingLastPathComponent().appendingPathComponent("state.corrupt-\(stamp).json")
        try FileManager.default.moveItem(at: fileURL, to: dest)
    }
}

/// Serialises writes so an older snapshot can never overwrite a newer one.
actor PersistenceWriter {
    private let persistence: StatePersistence
    private(set) var lastError: String?
    init(_ p: StatePersistence) { persistence = p }
    func write(_ state: PersistedState) {
        do { try persistence.save(state); lastError = nil } catch { lastError = error.localizedDescription }
    }
}

enum AppPaths {
    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GlassCount", isDirectory: true)
    }
    static func backgroundsDirectory(in root: URL) -> URL {
        root.appendingPathComponent("Backgrounds", isDirectory: true)
    }
}

extension Notification.Name {
    static let glassCountStateDidSave = Notification.Name("GlassCount.stateDidSave")
}
