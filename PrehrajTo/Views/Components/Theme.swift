import SwiftUI

enum AppTheme {
    // Primary Brand Colors (Modern Dark Cinema Aesthetic inspired by Prehraj.to Crimson/Coral + Apple TV+ Glass)
    static let brandPrimary = Color(red: 0.95, green: 0.22, blue: 0.32)      // #F23852
    static let brandSecondary = Color(red: 1.00, green: 0.45, blue: 0.26)    // #FF7342
    static let premiumGold = Color(red: 0.98, green: 0.78, blue: 0.25)       // #FAC740
    static let premiumGoldDark = Color(red: 0.85, green: 0.55, blue: 0.10)

    static let backgroundPrimary = Color(red: 0.05, green: 0.05, blue: 0.08) // #0D0D14
    static let backgroundSecondary = Color(red: 0.10, green: 0.11, blue: 0.16)
    static let cardBackground = Color(red: 0.13, green: 0.14, blue: 0.20)
    static let cardBorder = Color.white.opacity(0.08)

    static let brandGradient = LinearGradient(
        colors: [brandPrimary, brandSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let premiumGradient = LinearGradient(
        colors: [premiumGold, premiumGoldDark],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroOverlayGradient = LinearGradient(
        colors: [
            Color.clear,
            backgroundPrimary.opacity(0.55),
            backgroundPrimary
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
