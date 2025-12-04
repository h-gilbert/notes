import SwiftUI

// MARK: - Soft Cloud Theme
// A dreamy, pastel aesthetic inspired by cotton candy skies and morning clouds

enum Theme {

    // MARK: - Color Palette

    enum Colors {
        // Base tones - warm cream background
        static let background = Color(hex: "FBF9F7")
        static let backgroundSecondary = Color(hex: "F5F2EE")
        static let surface = Color.white

        // Text hierarchy
        static let textPrimary = Color(hex: "2D2A26")
        static let textSecondary = Color(hex: "8A847B")
        static let textTertiary = Color(hex: "B8B2A8")

        // Accent - soft coral
        static let accent = Color(hex: "E8A598")
        static let accentLight = Color(hex: "F5D5CF")

        // Soft shadows
        static let shadowLight = Color(hex: "D4CEC4").opacity(0.4)
        static let shadowMedium = Color(hex: "B8B2A8").opacity(0.3)
    }

    // MARK: - Typography

    enum Typography {
        // Display - for titles and headers
        static func displayLarge() -> Font {
            .system(size: 28, weight: .bold, design: .rounded)
        }

        static func displayMedium() -> Font {
            .system(size: 22, weight: .semibold, design: .rounded)
        }

        // Headlines
        static func headline() -> Font {
            .system(size: 17, weight: .semibold, design: .rounded)
        }

        static func headlineSmall() -> Font {
            .system(size: 15, weight: .medium, design: .rounded)
        }

        // Body text
        static func body() -> Font {
            .system(size: 16, weight: .regular, design: .default)
        }

        static func bodySmall() -> Font {
            .system(size: 14, weight: .regular, design: .default)
        }

        // Labels and captions
        static func label() -> Font {
            .system(size: 12, weight: .medium, design: .rounded)
        }

        static func caption() -> Font {
            .system(size: 11, weight: .regular, design: .rounded)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Animations

    enum Animation {
        static let springy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeOut(duration: 0.2)
        // Smooth animation for list item removal/addition
        static let smooth = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct SoftCardStyle: ViewModifier {
    let backgroundColor: Color
    let cornerRadius: CGFloat

    init(backgroundColor: Color = Theme.Colors.surface, cornerRadius: CGFloat = Theme.Radius.medium) {
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.Colors.shadowLight, radius: 8, x: 0, y: 4)
            .shadow(color: Theme.Colors.shadowMedium, radius: 1, x: 0, y: 1)
    }
}

struct PillButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let foregroundColor: Color

    init(backgroundColor: Color = Theme.Colors.accent, foregroundColor: Color = .white) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headlineSmall())
            .foregroundColor(foregroundColor)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(backgroundColor)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
    }
}

extension View {
    func softCard(color: Color = Theme.Colors.surface, radius: CGFloat = Theme.Radius.medium) -> some View {
        modifier(SoftCardStyle(backgroundColor: color, cornerRadius: radius))
    }
}
