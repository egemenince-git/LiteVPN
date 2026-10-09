import SwiftUI

/// Dark glass-inspired tokens for the menu bar dashboard.
enum Theme {
    /// LiteVPN connection accent.
    static let green = Color(hex: 0x3ECF8E)
    static let blue = Color(hex: 0x69B8FF)
    static let purple = Color(hex: 0xB89AFF)
    static let red = Color(hex: 0xE5484D)
    static let amber = Color(hex: 0xF5A623)

    static let cardTop = Color.primary.opacity(0.075)
    static let cardBottom = Color.primary.opacity(0.025)
    static let card = Color.primary.opacity(0.045)
    static let metricBackground = Color.primary.opacity(0.035)
    static let cardStroke = Color.primary.opacity(0.12)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let buttonOnGreen = Color(hex: 0x08120F)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
