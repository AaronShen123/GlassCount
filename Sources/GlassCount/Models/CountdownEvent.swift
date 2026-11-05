import Foundation

/// Colour accents available for events. UI mapping lives in `EventStyle.swift`.
enum EventColor: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, orange, pink, purple, graphite
}

struct CountdownEvent: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    /// Absolute instant. Stored as a timestamp, never as a remaining-time counter.
    var targetDate: Date
    var startDate: Date?
    var iconName: String
    var colorToken: EventColor
    var backgroundImageFileName: String?
    var remindersEnabled: Bool
    var createdAt: Date
    /// User-chosen card size in points (nil = default). Clamped to `CardSize` limits.
    var cardWidth: Double?
    var cardHeight: Double?

    init(id: UUID = UUID(),
         title: String,
         targetDate: Date,
         startDate: Date? = nil,
         iconName: String = "calendar",
         colorToken: EventColor = .blue,
         backgroundImageFileName: String? = nil,
         remindersEnabled: Bool = true,
         createdAt: Date = Date(),
         cardWidth: Double? = nil,
         cardHeight: Double? = nil) {
        self.id = id
        self.title = title
        self.targetDate = targetDate
        self.startDate = startDate
        self.iconName = iconName
        self.colorToken = colorToken
        self.backgroundImageFileName = backgroundImageFileName
        self.remindersEnabled = remindersEnabled
        self.createdAt = createdAt
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
    }

    // Tolerant decoding: newer/older files with missing optional keys still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        targetDate = try c.decode(Date.self, forKey: .targetDate)
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        iconName = try c.decodeIfPresent(String.self, forKey: .iconName) ?? "calendar"
        colorToken = (try? c.decodeIfPresent(EventColor.self, forKey: .colorToken)) ?? .blue
        backgroundImageFileName = try c.decodeIfPresent(String.self, forKey: .backgroundImageFileName)
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        cardWidth = try c.decodeIfPresent(Double.self, forKey: .cardWidth).map(CardSize.clampWidth)
        cardHeight = try c.decodeIfPresent(Double.self, forKey: .cardHeight).map(CardSize.clampHeight)
    }

    func isExpired(at now: Date) -> Bool { targetDate <= now }
}

enum CardSize {
    static let defaultWidth = 280.0, defaultHeight = 150.0
    static let widthRange = 200.0...560.0, heightRange = 120.0...320.0
    static let step = 10.0
    static func clampWidth(_ v: Double) -> Double { snap(v).clamped(to: widthRange) }
    static func clampHeight(_ v: Double) -> Double { snap(v).clamped(to: heightRange) }
    private static func snap(_ v: Double) -> Double { (v / step).rounded() * step }
}

// MARK: - Draft + validation (pure, testable)

enum EventValidationIssue: Equatable, Sendable, Hashable {
    case emptyTitle
    case titleTooLong
    case startNotBeforeTarget
    case targetOutOfRange

    var message: String {
        switch self {
        case .emptyTitle: return "Please enter a name."
        case .titleTooLong: return "The name is too long (max \(EventDraft.maxTitleLength) characters)."
        case .startNotBeforeTarget: return "The start date must be before the target date."
        case .targetOutOfRange: return "The target date is out of the supported range (years 1970–9999)."
        }
    }
}

struct EventDraft: Equatable, Sendable {
    static let maxTitleLength = 80
    static let minDate = Date(timeIntervalSince1970: 0)
    static let maxDate = Date(timeIntervalSince1970: 253_370_764_800) // 9999-12-31

    var title = ""
    var targetDate: Date
    var hasStartDate = false
    var startDate: Date
    var iconName = "calendar"
    var colorToken: EventColor = .blue
    var backgroundImageFileName: String?
    var remindersEnabled = true
    var makeFeatured = false

    init(now: Date = Date()) {
        // Default: tomorrow at 9:00 in the current calendar.
        let cal = Calendar.autoupdatingCurrent
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        targetDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        startDate = now
    }

    init(event: CountdownEvent, isFeatured: Bool = false) {
        title = event.title
        targetDate = event.targetDate
        hasStartDate = event.startDate != nil
        startDate = event.startDate ?? Date()
        iconName = event.iconName
        colorToken = event.colorToken
        backgroundImageFileName = event.backgroundImageFileName
        remindersEnabled = event.remindersEnabled
        makeFeatured = isFeatured
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    func validate() -> [EventValidationIssue] {
        var issues: [EventValidationIssue] = []
        if trimmedTitle.isEmpty { issues.append(.emptyTitle) }
        if trimmedTitle.count > Self.maxTitleLength { issues.append(.titleTooLong) }
        if !(targetDate >= Self.minDate && targetDate <= Self.maxDate) { issues.append(.targetOutOfRange) }
        // Compare the date-only values that makeEvent() will persist. DatePicker can
        // retain hidden time components even though the editor displays only dates.
        if hasStartDate && Self.startOfDay(startDate) >= Self.startOfDay(targetDate) {
            issues.append(.startNotBeforeTarget)
        }
        return issues
    }

    /// Builds an event, or nil when the draft is invalid. Dates are normalised to local midnight.
    func makeEvent(id: UUID = UUID(), createdAt: Date = Date()) -> CountdownEvent? {
        guard validate().isEmpty else { return nil }
        return CountdownEvent(
            id: id, title: trimmedTitle,
            targetDate: Self.startOfDay(targetDate),
            startDate: hasStartDate ? Self.startOfDay(startDate) : nil,
            iconName: iconName, colorToken: colorToken,
            backgroundImageFileName: backgroundImageFileName,
            remindersEnabled: remindersEnabled, createdAt: createdAt)
    }

    /// The editor picks a date only; the event happens at 00:00 on that day (local calendar).
    static func startOfDay(_ d: Date, calendar: Calendar = .autoupdatingCurrent) -> Date { calendar.startOfDay(for: d) }

    static func floorToMinute(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}
