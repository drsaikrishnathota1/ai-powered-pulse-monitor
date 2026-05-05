import SwiftUI

enum PulseTheme {
    static let bgTop = Color(hex: 0x0B1020)
    static let bgBottom = Color(hex: 0x141834)
    static let card = Color.white.opacity(0.07)
    static let cardStrong = Color(hex: 0x18243A).opacity(0.78)
    static let stroke = Color.white.opacity(0.13)
    static let accent = Color(hex: 0x5CE1E6)
    static let accent2 = Color(hex: 0xA78BFA)
    static let success = Color(hex: 0x69DB7C)
    static let caution = Color(hex: 0xFFD166)
    static let coral = Color(hex: 0xFF7A7A)

    static var screenBackground: LinearGradient {
        LinearGradient(
            colors: [bgTop, Color(hex: 0x10223A), bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var waveGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.95), accent2.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var actionGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color(hex: 0x7EF2B7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var dangerGradient: LinearGradient {
        LinearGradient(
            colors: [coral, Color(hex: 0xFFB86C)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
