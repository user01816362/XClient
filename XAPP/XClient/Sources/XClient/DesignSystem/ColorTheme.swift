//
//  ColorTheme.swift
//  XClient
//
//  Semantic Color Themes, Palettes, and WCAG 2.1 Compliant Design Tokens.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI

// MARK: - AppThemePreference / ThemeMode

/// User preference for application color theme.
public enum AppThemePreference: String, Sendable, CaseIterable, Identifiable, Codable {
    case system = "system"
    case light = "light"
    case darkDim = "darkDim"
    case darkLightsOut = "darkLightsOut"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .darkDim: return "Dark Dim (Navy)"
        case .darkLightsOut: return "Dark Lights Out (OLED Black)"
        }
    }

    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .darkDim: return "moon.fill"
        case .darkLightsOut: return "moon.stars.fill"
        }
    }

    /// Resolves preferred color scheme for SwiftUI container.
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .darkDim, .darkLightsOut: return .dark
        }
    }
}

/// Headless theme mode enum corresponding to the four primary theme configurations.
public enum ThemeMode: String, Sendable, CaseIterable, Identifiable, Codable {
    case system = "system"
    case light = "light"
    case dim = "dim"
    case lightsOut = "lights_out"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light"
        case .dim: return "Dark Dim (Navy)"
        case .lightsOut: return "Dark Lights Out (OLED Black)"
        }
    }

    /// Converts ThemeMode to AppThemePreference
    public var preference: AppThemePreference {
        switch self {
        case .system: return .system
        case .light: return .light
        case .dim: return .darkDim
        case .lightsOut: return .darkLightsOut
        }
    }

    public init(preference: AppThemePreference) {
        switch preference {
        case .system: self = .system
        case .light: self = .light
        case .darkDim: self = .dim
        case .darkLightsOut: self = .lightsOut
        }
    }
}

// MARK: - ColorTheme (Hex Tokens Model)

/// Pure Swift semantic color theme structure exposing verbatim hex values for contrast validation.
public struct ColorTheme: Sendable, Equatable, Hashable {
    public let surfaceHex: String
    public let secondarySurfaceHex: String
    public let primaryTextHex: String
    public let secondaryTextHex: String
    public let borderHex: String
    public let accentHex: String

    public init(
        surfaceHex: String,
        secondarySurfaceHex: String,
        primaryTextHex: String,
        secondaryTextHex: String,
        borderHex: String,
        accentHex: String
    ) {
        self.surfaceHex = surfaceHex
        self.secondarySurfaceHex = secondarySurfaceHex
        self.primaryTextHex = primaryTextHex
        self.secondaryTextHex = secondaryTextHex
        self.borderHex = borderHex
        self.accentHex = accentHex
    }

    /// Pure Native Apple Light Theme Hex Tokens.
    public static let light = ColorTheme(
        surfaceHex: "#FFFFFF",
        secondarySurfaceHex: "#F7F9F9",
        primaryTextHex: "#0F1419",
        secondaryTextHex: "#536471",
        borderHex: "#EFF3F4",
        accentHex: "#1D9BF0"
    )

    /// Dark Dim Theme Hex Tokens (Slate Navy).
    public static let dim = ColorTheme(
        surfaceHex: "#15202B",
        secondarySurfaceHex: "#1E2732",
        primaryTextHex: "#F7F9F9",
        secondaryTextHex: "#8B98A5",
        borderHex: "#38444D",
        accentHex: "#1D9BF0"
    )

    /// Dark Lights Out Theme Hex Tokens (Pure OLED Black).
    /// secondaryTextHex is calibrated to #8B98A5 to guarantee WCAG 2.1 AA (>= 4.5:1)
    /// across both primary surface (#000000, 7.15:1) and secondary surface (#16181C, 6.04:1).
    public static let lightsOut = ColorTheme(
        surfaceHex: "#000000",
        secondarySurfaceHex: "#16181C",
        primaryTextHex: "#E7E9EA",
        secondaryTextHex: "#8B98A5",
        borderHex: "#2F3336",
        accentHex: "#1D9BF0"
    )

    /// Verification badge semantic hex colors.
    public struct VerificationBadge: Sendable, Equatable {
        public static let blueHex = "#1D9BF0"
        public static let goldHex = "#E7A43B"
        public static let grayHex = "#71767B"
    }
}

// MARK: - ColorPalette (SwiftUI Color Model)

/// Comprehensive semantic color palette for XClient view styling.
public struct ColorPalette: Sendable, Equatable, Hashable {
    // Surfaces & Backgrounds
    public let background: Color
    public let secondaryBackground: Color
    public let tertiaryBackground: Color
    public let groupedBackground: Color

    // Text & Labels
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color

    // Strokes & Dividers
    public let borderSubtle: Color
    public let borderDefault: Color
    public let borderStrong: Color

    // Accents & Actions
    public let accent: Color
    public let verifiedBlue: Color
    public let verifiedGold: Color
    public let likeActive: Color
    public let repostActive: Color
    public let bookmarkActive: Color
    public let warning: Color
    public let destructive: Color

    public init(
        background: Color,
        secondaryBackground: Color,
        tertiaryBackground: Color,
        groupedBackground: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        borderSubtle: Color,
        borderDefault: Color,
        borderStrong: Color,
        accent: Color = Color(hex: 0x1D9BF0),
        verifiedBlue: Color = Color(hex: 0x1D9BF0),
        verifiedGold: Color = Color(hex: 0xE7A43B),
        likeActive: Color = Color(hex: 0xF91880),
        repostActive: Color = Color(hex: 0x00BA7C),
        bookmarkActive: Color = Color(hex: 0x1D9BF0),
        warning: Color = Color(hex: 0xFF9500),
        destructive: Color = Color(hex: 0xF4212E)
    ) {
        self.background = background
        self.secondaryBackground = secondaryBackground
        self.tertiaryBackground = tertiaryBackground
        self.groupedBackground = groupedBackground
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.borderSubtle = borderSubtle
        self.borderDefault = borderDefault
        self.borderStrong = borderStrong
        self.accent = accent
        self.verifiedBlue = verifiedBlue
        self.verifiedGold = verifiedGold
        self.likeActive = likeActive
        self.repostActive = repostActive
        self.bookmarkActive = bookmarkActive
        self.warning = warning
        self.destructive = destructive
    }

    // MARK: - Static Theme Presets

    /// Light Theme Palette.
    public static let light = ColorPalette(
        background: Color(hex: 0xFFFFFF),
        secondaryBackground: Color(hex: 0xF7F9F9),
        tertiaryBackground: Color(hex: 0xEFF3F4),
        groupedBackground: Color(hex: 0xF7F9FA),
        textPrimary: Color(hex: 0x0F1419),
        textSecondary: Color(hex: 0x536471),
        textTertiary: Color(hex: 0x8F9CA7),
        borderSubtle: Color(hex: 0xEFF3F4),
        borderDefault: Color(hex: 0xCFD9DE),
        borderStrong: Color(hex: 0x8B98A5)
    )

    /// Dark Dim Theme Palette (Deep Navy Slate).
    public static let darkDim = ColorPalette(
        background: Color(hex: 0x15202B),
        secondaryBackground: Color(hex: 0x1E2732),
        tertiaryBackground: Color(hex: 0x22303C),
        groupedBackground: Color(hex: 0x10171E),
        textPrimary: Color(hex: 0xF7F9F9),
        textSecondary: Color(hex: 0x8B98A5),
        textTertiary: Color(hex: 0x5C6E7E),
        borderSubtle: Color(hex: 0x273340),
        borderDefault: Color(hex: 0x38444D),
        borderStrong: Color(hex: 0x5C6E7E)
    )

    /// Dark Lights Out Theme Palette (Pure OLED Black).
    /// textSecondary uses Color(hex: 0x8B98A5) guaranteeing >= 4.5:1 WCAG AA compliance on cards.
    public static let darkLightsOut = ColorPalette(
        background: Color(hex: 0x000000),
        secondaryBackground: Color(hex: 0x16181C),
        tertiaryBackground: Color(hex: 0x202327),
        groupedBackground: Color(hex: 0x000000),
        textPrimary: Color(hex: 0xE7E9EA),
        textSecondary: Color(hex: 0x8B98A5),
        textTertiary: Color(hex: 0x474B51),
        borderSubtle: Color(hex: 0x2F3336),
        borderDefault: Color(hex: 0x3A3E42),
        borderStrong: Color(hex: 0x536471)
    )

    /// Resolves the effective palette based on preference and active system color scheme.
    public static func resolve(preference: AppThemePreference, systemScheme: ColorScheme) -> ColorPalette {
        switch preference {
        case .system:
            return systemScheme == .dark ? .darkLightsOut : .light
        case .light:
            return .light
        case .darkDim:
            return .darkDim
        case .darkLightsOut:
            return .darkLightsOut
        }
    }
}

// MARK: - SwiftUI Environment Keys

private struct ColorPaletteKey: EnvironmentKey {
    static let defaultValue: ColorPalette = .light
}

private struct ThemePreferenceKey: EnvironmentKey {
    static let defaultValue: AppThemePreference = .system
}

public extension EnvironmentValues {
    /// The active semantic color palette.
    var colorPalette: ColorPalette {
        get { self[ColorPaletteKey.self] }
        set { self[ColorPaletteKey.self] = newValue }
    }

    /// The user's theme preference setting.
    var themePreference: AppThemePreference {
        get { self[ThemePreferenceKey.self] }
        set { self[ThemePreferenceKey.self] = newValue }
    }
}

// MARK: - Theme Container & Modifiers

public struct ThemeModifier: ViewModifier, Sendable {
    @Environment(\.colorScheme) private var systemScheme
    public let preference: AppThemePreference

    public init(preference: AppThemePreference) {
        self.preference = preference
    }

    public func body(content: Content) -> some View {
        let palette = ColorPalette.resolve(preference: preference, systemScheme: systemScheme)

        content
            .environment(\.themePreference, preference)
            .environment(\.colorPalette, palette)
            .preferredColorScheme(preference.preferredColorScheme)
            .background(palette.background)
    }
}

public extension View {
    /// Applies the specified theme preference across the view hierarchy.
    func applyTheme(_ preference: AppThemePreference) -> some View {
        modifier(ThemeModifier(preference: preference))
    }

    /// Convenience modifier filling view canvas with the theme background.
    func themedBackground() -> some View {
        modifier(ThemedBackgroundModifier())
    }

    /// Convenience modifier filling card view with secondary card background.
    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

private struct ThemedBackgroundModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content.background(palette.background)
    }
}

private struct CardBackgroundModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.secondaryBackground)
            )
    }
}

// MARK: - Cross-Platform Hex Color Helper

public extension Color {
    /// Creates a SwiftUI Color from an integer hex value (e.g. 0x1D9BF0).
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// Creates a SwiftUI Color from a hex string (e.g. "#1D9BF0", "1D9BF0", or "#1D9BF0FF").
    init(hexString: String, opacity: Double = 1.0) {
        var clean = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        if clean.count == 6, let hex = UInt32(clean, radix: 16) {
            self.init(hex: hex, opacity: opacity)
        } else if clean.count == 8, let hex = UInt64(clean, radix: 16) {
            let red = Double((hex >> 24) & 0xFF) / 255.0
            let green = Double((hex >> 16) & 0xFF) / 255.0
            let blue = Double((hex >> 8) & 0xFF) / 255.0
            let alpha = Double(hex & 0xFF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity * alpha)
        } else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: opacity)
        }
    }
}
