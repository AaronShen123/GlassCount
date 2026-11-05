import SwiftUI

extension EventColor {
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.30, green: 0.53, blue: 0.96)
        case .teal: return Color(red: 0.20, green: 0.70, blue: 0.72)
        case .green: return Color(red: 0.32, green: 0.72, blue: 0.45)
        case .orange: return Color(red: 0.96, green: 0.60, blue: 0.25)
        case .pink: return Color(red: 0.93, green: 0.40, blue: 0.60)
        case .purple: return Color(red: 0.62, green: 0.45, blue: 0.92)
        case .graphite: return Color(red: 0.55, green: 0.58, blue: 0.64)
        }
    }
    var title: String { rawValue.capitalized }
}

enum EventIcons {
    static let all = ["calendar", "gift", "airplane", "heart", "graduationcap", "party.popper", "birthday.cake",
                      "star", "briefcase", "house", "figure.run", "camera", "sparkles", "flag.checkered",
                      "moon.stars", "sun.max"]
}

extension AppearancePreference {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
