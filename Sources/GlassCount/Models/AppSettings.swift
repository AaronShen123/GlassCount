import Foundation

enum BackgroundFit: String, Codable, CaseIterable, Sendable { case fill, fit
    var title: String { self == .fill ? "Fill" : "Fit" }
}

enum ReminderOffset: String, Codable, CaseIterable, Sendable, Hashable {
    case sevenDays, oneDay, oneHour, atEvent

    /// Seconds before the target at which the reminder fires.
    var interval: TimeInterval {
        switch self {
        case .sevenDays: return 7 * 86_400
        case .oneDay: return 86_400
        case .oneHour: return 3_600
        case .atEvent: return 0
        }
    }
    var title: String {
        switch self {
        case .sevenDays: return "7 days before"
        case .oneDay: return "1 day before"
        case .oneHour: return "1 hour before"
        case .atEvent: return "At the event time"
        }
    }
    var sortKey: Int { Int(-interval) }
}

enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
    var title: String { rawValue.capitalized }
}

enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case compact, daysOnly, iconOnly
    var title: String {
        switch self {
        case .compact: return "Compact (12d 4h)"
        case .daysOnly: return "Days only"
        case .iconOnly: return "Icon only"
        }
    }
}

/// Built-in procedural backgrounds (no image assets needed).
enum DefaultBackgroundStyle: String, Codable, CaseIterable, Sendable {
    case aurora, sunset, ocean, forest, lavender, midnight, rose, desert, mint, graphite

    var title: String { rawValue.capitalized }

    /// (base gradient start, end, glow 1, glow 2) for light and dark appearances, as RGB triples.
    var palette: (light: [[Double]], dark: [[Double]]) {
        switch self {
        case .aurora:   return ([[0.80,0.87,0.98],[0.94,0.86,0.96],[0.30,0.80,0.90],[0.90,0.50,0.80]], [[0.05,0.07,0.16],[0.14,0.08,0.22],[0.10,0.45,0.80],[0.50,0.20,0.70]])
        case .sunset:   return ([[1.00,0.88,0.78],[0.98,0.78,0.85],[1.00,0.60,0.35],[0.90,0.40,0.60]], [[0.18,0.07,0.12],[0.10,0.05,0.20],[0.85,0.35,0.20],[0.60,0.20,0.50]])
        case .ocean:    return ([[0.80,0.93,0.98],[0.78,0.88,0.98],[0.20,0.60,0.90],[0.20,0.80,0.80]], [[0.02,0.10,0.18],[0.03,0.14,0.26],[0.05,0.45,0.75],[0.05,0.55,0.60]])
        case .forest:   return ([[0.85,0.94,0.85],[0.80,0.92,0.88],[0.30,0.70,0.40],[0.60,0.80,0.30]], [[0.04,0.12,0.08],[0.06,0.15,0.14],[0.15,0.55,0.30],[0.35,0.55,0.15]])
        case .lavender: return ([[0.90,0.86,0.98],[0.96,0.88,0.96],[0.60,0.45,0.90],[0.85,0.60,0.90]], [[0.10,0.07,0.20],[0.16,0.09,0.24],[0.45,0.30,0.80],[0.65,0.35,0.75]])
        case .midnight: return ([[0.82,0.85,0.93],[0.76,0.80,0.92],[0.25,0.30,0.70],[0.30,0.45,0.85]], [[0.02,0.03,0.08],[0.05,0.06,0.16],[0.15,0.20,0.55],[0.20,0.30,0.65]])
        case .rose:     return ([[0.99,0.88,0.90],[0.98,0.84,0.92],[0.95,0.45,0.60],[1.00,0.65,0.55]], [[0.20,0.06,0.10],[0.16,0.06,0.16],[0.75,0.25,0.40],[0.85,0.40,0.35]])
        case .desert:   return ([[0.98,0.92,0.80],[0.96,0.86,0.76],[0.90,0.65,0.30],[0.85,0.50,0.35]], [[0.17,0.11,0.06],[0.20,0.10,0.08],[0.70,0.45,0.15],[0.65,0.30,0.20]])
        case .mint:     return ([[0.86,0.97,0.93],[0.84,0.94,0.98],[0.30,0.85,0.70],[0.35,0.70,0.90]], [[0.03,0.14,0.13],[0.04,0.12,0.18],[0.10,0.60,0.50],[0.15,0.45,0.65]])
        case .graphite: return ([[0.92,0.92,0.94],[0.84,0.85,0.88],[0.70,0.72,0.78],[0.60,0.62,0.70]], [[0.08,0.08,0.10],[0.14,0.14,0.17],[0.30,0.32,0.40],[0.22,0.24,0.32]])
        }
    }
}

struct BackgroundSettings: Codable, Equatable, Sendable {
    static let blurRange: ClosedRange<Double> = 0...40
    static let dimRange: ClosedRange<Double> = 0...0.8
    static let opacityRange: ClosedRange<Double> = 0.1...1

    var imageFileName: String?
    var defaultStyle: DefaultBackgroundStyle = .aurora
    var fit: BackgroundFit = .fill
    var blur: Double = 0
    var dimming: Double = 0.15
    var opacity: Double = 1

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        defaultStyle = (try? c.decodeIfPresent(DefaultBackgroundStyle.self, forKey: .defaultStyle)) ?? .aurora
        fit = (try? c.decodeIfPresent(BackgroundFit.self, forKey: .fit)) ?? .fill
        blur = (try c.decodeIfPresent(Double.self, forKey: .blur) ?? 0).clamped(to: Self.blurRange)
        dimming = (try c.decodeIfPresent(Double.self, forKey: .dimming) ?? 0.15).clamped(to: Self.dimRange)
        opacity = (try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1).clamped(to: Self.opacityRange)
    }
}

struct NotificationSettings: Codable, Equatable, Sendable {
    var enabled = false
    var offsets: Set<ReminderOffset> = [.oneDay, .atEvent]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        offsets = try c.decodeIfPresent(Set<ReminderOffset>.self, forKey: .offsets) ?? [.oneDay, .atEvent]
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var featuredEventID: UUID?
    var background = BackgroundSettings()
    var notifications = NotificationSettings()
    var appearance: AppearancePreference = .system
    var showMenuBarItem = true
    var menuBarDisplay: MenuBarDisplay = .compact
    var showDesktopWidget = false
    /// Which fine-grained units the countdown shows (days and hours are always shown).
    var showMinutes = true
    var showSeconds = true
    /// Desktop widget: one of the fixed sizes, and where it was last placed (window origin, screen coords).
    var widgetPreset: WidgetPreset = .small
    var widgetOrigin: [Double]?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        featuredEventID = try c.decodeIfPresent(UUID.self, forKey: .featuredEventID)
        background = try c.decodeIfPresent(BackgroundSettings.self, forKey: .background) ?? BackgroundSettings()
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? NotificationSettings()
        appearance = (try? c.decodeIfPresent(AppearancePreference.self, forKey: .appearance)) ?? .system
        showMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        menuBarDisplay = (try? c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay)) ?? .compact
        showDesktopWidget = try c.decodeIfPresent(Bool.self, forKey: .showDesktopWidget) ?? false
        showMinutes = try c.decodeIfPresent(Bool.self, forKey: .showMinutes) ?? true
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? true
        widgetPreset = (try? c.decodeIfPresent(WidgetPreset.self, forKey: .widgetPreset)) ?? .small
        widgetOrigin = try c.decodeIfPresent([Double].self, forKey: .widgetOrigin).flatMap { $0.count == 2 ? $0 : nil }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// Seconds only make sense next to minutes, so `showSeconds` is ignored when minutes are hidden.
struct CountdownDetail: Equatable, Sendable {
    var showMinutes = true
    var showSeconds = true
    var effectiveSeconds: Bool { showMinutes && showSeconds }
}

extension AppSettings {
    var detail: CountdownDetail { CountdownDetail(showMinutes: showMinutes, showSeconds: showSeconds) }
}

/// Fixed desktop-widget sizes (card size in points), like system widgets.
enum WidgetPreset: String, Codable, CaseIterable, Sendable {
    case small, medium, large
    var title: String { rawValue.capitalized }
    var size: CGSize {
        switch self {
        case .small: return CGSize(width: 160, height: 160)
        case .medium: return CGSize(width: 340, height: 160)
        case .large: return CGSize(width: 340, height: 340)
        }
    }
    /// The preset whose size is closest to a freely dragged size (used to snap while resizing).
    static func nearest(to size: CGSize) -> WidgetPreset {
        allCases.min { dist($0.size, size) < dist($1.size, size) } ?? .small
    }
    private static func dist(_ a: CGSize, _ b: CGSize) -> CGFloat { hypot(a.width - b.width, a.height - b.height) }
}

/// Where a widget may sit: inside the screen's visible area (not under the menu bar or Dock), on a 20 pt grid.
enum WidgetPlacement {
    static let grid: CGFloat = 20
    static let margin: CGFloat = 12

    /// `card` is the card rect (screen coords, y up); returns the snapped, clamped card rect.
    static func snap(card: CGRect, in visible: CGRect) -> CGRect {
        let area = visible.insetBy(dx: margin, dy: margin)
        var r = card
        r.size.width = min(r.width, area.width); r.size.height = min(r.height, area.height)
        // Snap left edge and top edge to the grid measured from the top-left of the area.
        let gx = ((r.minX - area.minX) / grid).rounded() * grid
        let gy = ((area.maxY - r.maxY) / grid).rounded() * grid
        r.origin.x = area.minX + gx
        r.origin.y = area.maxY - gy - r.height
        r.origin.x = min(max(r.origin.x, area.minX), area.maxX - r.width)
        r.origin.y = min(max(r.origin.y, area.minY), area.maxY - r.height)
        return r
    }

    /// Like `snap`, but also avoids `obstacles` (rects of other desktop widgets): if the snapped spot
    /// overlaps one, the nearest free grid position is used. If none is free, the snapped spot is kept.
    static func resolve(card: CGRect, in visible: CGRect, avoiding obstacles: [CGRect]) -> CGRect {
        let snapped = snap(card: card, in: visible)
        let gap: CGFloat = 8
        func free(_ r: CGRect) -> Bool { !obstacles.contains { $0.insetBy(dx: -gap, dy: -gap).intersects(r) } }
        if free(snapped) { return snapped }
        let area = visible.insetBy(dx: margin, dy: margin)
        guard area.width >= snapped.width, area.height >= snapped.height else { return snapped }
        var best: CGRect?
        var bestDist = CGFloat.infinity
        var x = area.minX
        while x + snapped.width <= area.maxX + 0.5 {
            var top = area.maxY
            while top - snapped.height >= area.minY - 0.5 {
                let r = CGRect(x: x, y: top - snapped.height, width: snapped.width, height: snapped.height)
                if free(r) {
                    let d = hypot(r.minX - snapped.minX, r.minY - snapped.minY)
                    if d < bestDist { best = r; bestDist = d }
                }
                top -= grid
            }
            x += grid
        }
        return best ?? snapped
    }
}
