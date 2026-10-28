//
//  DesignSystemTests.swift
//  XClientTests
//
//  Automated Unit Tests for Design System, ColorTheme, LiquidGlass, and Typography.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
@testable import XClient

// MARK: - WCAG Luminance & Contrast Math Helper (Headless CLI)

private struct WCAGColorEvaluator {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        var rgbValue: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&rgbValue)
        self.r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        self.g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        self.b = Double(rgbValue & 0x0000FF) / 255.0
    }

    /// Relative luminance calculation conforming to WCAG 2.1 specifications
    var relativeLuminance: Double {
        func sRGBtoLin(_ c: Double) -> Double {
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * sRGBtoLin(r) + 0.7152 * sRGBtoLin(g) + 0.0722 * sRGBtoLin(b)
    }

    /// Computes contrast ratio between two colors
    static func contrastRatio(_ c1: WCAGColorEvaluator, _ c2: WCAGColorEvaluator) -> Double {
        let l1 = c1.relativeLuminance
        let l2 = c2.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

// MARK: - Design System Test Suite

@Suite("Design System & Liquid Glass Test Suite", .serialized)
struct DesignSystemTests {

    // MARK: - Theme Tokens Validation

    @Test("Verify ThemeMode Enum Completeness and Conformance")
    func testThemeModeEnum() {
        let allCases = ThemeMode.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.system))
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.dim))
        #expect(allCases.contains(.lightsOut))

        for theme in allCases {
            #expect(!theme.id.isEmpty)
            #expect(!theme.displayName.isEmpty)
        }
    }

    @Test("Verify AppThemePreference Enum Completeness and Conformance")
    func testAppThemePreferenceCases() {
        let allCases = AppThemePreference.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.system))
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.darkDim))
        #expect(allCases.contains(.darkLightsOut))

        for pref in allCases {
            #expect(!pref.id.isEmpty)
            #expect(!pref.displayName.isEmpty)
            #expect(!pref.iconName.isEmpty)
        }
    }

    @Test("Verify Light Mode Color Tokens and Hex Fidelity")
    func testLightModeColorTokens() {
        let theme = ColorTheme.light
        #expect(theme.surfaceHex == "#FFFFFF")
        #expect(theme.secondarySurfaceHex == "#F7F9F9")
        #expect(theme.primaryTextHex == "#0F1419")
        #expect(theme.secondaryTextHex == "#536471")
        #expect(theme.borderHex == "#EFF3F4")
        #expect(theme.accentHex == "#1D9BF0")
    }

    @Test("Verify Dark Dim Mode Color Tokens and Slate Navy Palette")
    func testDarkDimColorTokens() {
        let theme = ColorTheme.dim
        #expect(theme.surfaceHex == "#15202B")
        #expect(theme.secondarySurfaceHex == "#1E2732")
        #expect(theme.primaryTextHex == "#F7F9F9")
        #expect(theme.secondaryTextHex == "#8B98A5")
        #expect(theme.borderHex == "#38444D")
        #expect(theme.accentHex == "#1D9BF0")
    }

    @Test("Verify Dark Lights Out Mode Color Tokens and OLED Black Palette")
    func testDarkLightsOutColorTokens() {
        let theme = ColorTheme.lightsOut
        #expect(theme.surfaceHex == "#000000")
        #expect(theme.secondarySurfaceHex == "#16181C")
        #expect(theme.primaryTextHex == "#E7E9EA")
        // Remediation: Secondary text updated to #8B98A5 to guarantee WCAG AA on #16181C
        #expect(theme.secondaryTextHex == "#8B98A5")
        #expect(theme.borderHex == "#2F3336")
        #expect(theme.accentHex == "#1D9BF0")
    }

    @Test("Verify WCAG 2.1 Text Contrast Ratio Across All Themes and Surfaces")
    func testWCAGContrastCompliance() {
        let themes: [(name: String, theme: ColorTheme)] = [
            ("Light", .light),
            ("Dim", .dim),
            ("Lights Out", .lightsOut)
        ]

        for (name, theme) in themes {
            let primaryText = WCAGColorEvaluator(hex: theme.primaryTextHex)
            let secondaryText = WCAGColorEvaluator(hex: theme.secondaryTextHex)

            let surfaces: [(kind: String, color: WCAGColorEvaluator)] = [
                ("Primary Surface", WCAGColorEvaluator(hex: theme.surfaceHex)),
                ("Secondary Surface", WCAGColorEvaluator(hex: theme.secondarySurfaceHex))
            ]

            for (surfaceKind, surfaceColor) in surfaces {
                let primaryRatio = WCAGColorEvaluator.contrastRatio(surfaceColor, primaryText)
                let secondaryRatio = WCAGColorEvaluator.contrastRatio(surfaceColor, secondaryText)

                // WCAG AA requires at least 4.5:1 for standard body and sub-headline text
                #expect(
                    primaryRatio >= 4.5,
                    "\(name) primary text on \(surfaceKind) contrast \(primaryRatio) must meet WCAG AA (>= 4.5:1)"
                )
                #expect(
                    secondaryRatio >= 4.5,
                    "\(name) secondary text on \(surfaceKind) contrast \(secondaryRatio) must meet WCAG AA (>= 4.5:1)"
                )

                // On Primary Surface, Light and Lights Out primary text must reach AAA (>= 7.0:1)
                if surfaceKind == "Primary Surface" && (theme == .light || theme == .lightsOut) {
                    #expect(
                        primaryRatio >= 7.0,
                        "\(name) primary text on \(surfaceKind) contrast \(primaryRatio) must reach WCAG AAA (>= 7.0:1)"
                    )
                }
            }
        }
    }

    @Test("Verify Verification Badge Semantic Colors")
    func testVerificationBadgeColors() {
        #expect(ColorTheme.VerificationBadge.blueHex == "#1D9BF0")
        #expect(ColorTheme.VerificationBadge.goldHex == "#E7A43B")
        #expect(ColorTheme.VerificationBadge.grayHex == "#71767B")
    }

    @Test("Verify ColorPalette Resolution Across Preferences")
    func testColorPaletteResolution() {
        let lightPalette = ColorPalette.resolve(preference: .light, systemScheme: .dark)
        #expect(lightPalette == ColorPalette.light)

        let darkDimPalette = ColorPalette.resolve(preference: .darkDim, systemScheme: .light)
        #expect(darkDimPalette == ColorPalette.darkDim)

        let lightsOutPalette = ColorPalette.resolve(preference: .darkLightsOut, systemScheme: .light)
        #expect(lightsOutPalette == ColorPalette.darkLightsOut)

        let systemLight = ColorPalette.resolve(preference: .system, systemScheme: .light)
        #expect(systemLight == ColorPalette.light)

        let systemDark = ColorPalette.resolve(preference: .system, systemScheme: .dark)
        #expect(systemDark == ColorPalette.darkLightsOut)
    }

    // MARK: - Liquid Glass Style Attributes

    @Test("Verify LiquidGlassStyle Enum Completeness and Conformance")
    func testLiquidGlassStyleCases() {
        let styles = LiquidGlassStyle.allCases
        #expect(styles.count == 3)
        #expect(styles.contains(.standard))
        #expect(styles.contains(.elevated))
        #expect(styles.contains(.prominent))
    }

    @Test("Verify Standard Elevation Style Attributes")
    func testStandardLiquidGlassAttributes() {
        let attrs = LiquidGlassAttributes.resolve(
            style: .standard,
            intensity: 1.0,
            reduceTransparency: false
        )
        #expect(attrs.style == .standard)
        #expect(attrs.isOpaqueFallback == false)
        #expect(attrs.strokeBorderWidth == 1.0)
        #expect(attrs.shadowRadius == 4.0)
        #expect(attrs.shadowYOffset == 2.0)
        #expect(attrs.shadowOpacity > 0.05 && attrs.shadowOpacity <= 0.15)
        #expect(attrs.cornerRadius == 16.0)
    }

    @Test("Verify Elevated and Prominent Style Attributes Scaling")
    func testElevatedAndProminentAttributes() {
        let standard = LiquidGlassAttributes.resolve(style: .standard, intensity: 1.0, reduceTransparency: false)
        let elevated = LiquidGlassAttributes.resolve(style: .elevated, intensity: 1.0, reduceTransparency: false)
        let prominent = LiquidGlassAttributes.resolve(style: .prominent, intensity: 1.0, reduceTransparency: false)

        // Elevation progression checks
        #expect(elevated.shadowRadius > standard.shadowRadius)
        #expect(prominent.shadowRadius > elevated.shadowRadius)

        #expect(elevated.shadowYOffset > standard.shadowYOffset)
        #expect(prominent.shadowYOffset > elevated.shadowYOffset)

        #expect(prominent.strokeBorderWidth >= elevated.strokeBorderWidth)
        #expect(elevated.strokeBorderWidth >= standard.strokeBorderWidth)
    }

    @Test("Verify Liquid Glass Intensity Clamping and Edge Values")
    func testIntensityClamping() {
        let negative = LiquidGlassAttributes.resolve(style: .standard, intensity: -0.5, reduceTransparency: false)
        #expect(negative.intensity == 0.0)
        #expect(negative.isOpaqueFallback == true)

        let excessive = LiquidGlassAttributes.resolve(style: .standard, intensity: 2.5, reduceTransparency: false)
        #expect(excessive.intensity == 1.0)

        let lowThreshold = LiquidGlassAttributes.resolve(style: .standard, intensity: 0.04, reduceTransparency: false)
        #expect(lowThreshold.isOpaqueFallback == true)

        let aboveThreshold = LiquidGlassAttributes.resolve(style: .standard, intensity: 0.10, reduceTransparency: false)
        #expect(aboveThreshold.isOpaqueFallback == false)
    }

    @Test("Verify NaN and Non-Finite Intensity Safely Triggers Opaque Fallback")
    func testNaNAndNonFiniteIntensityHandling() {
        for style in LiquidGlassStyle.allCases {
            // IEEE 754 NaN must trigger defensive fallback rather than glass
            let nanAttrs = LiquidGlassAttributes.resolve(
                style: style,
                intensity: Double.nan,
                reduceTransparency: false
            )
            #expect(nanAttrs.isOpaqueFallback == true, "NaN intensity on \(style) must trigger safe opaque fallback")
            #expect(nanAttrs.shadowOpacity == 0.0, "NaN fallback must suppress shadows")
            #expect(nanAttrs.strokeOpacity >= 0.8, "NaN fallback must provide high-contrast border")
            #expect(nanAttrs.intensity == 0.0, "NaN intensity must normalize to 0.0")

            // Negative infinity must clamp to 0.0 fallback
            let negInfAttrs = LiquidGlassAttributes.resolve(
                style: style,
                intensity: -Double.infinity,
                reduceTransparency: false
            )
            #expect(negInfAttrs.isOpaqueFallback == true)
            #expect(negInfAttrs.intensity == 0.0)

            // Positive infinity must clamp to safe fallback or bound
            let posInfAttrs = LiquidGlassAttributes.resolve(
                style: style,
                intensity: Double.infinity,
                reduceTransparency: false
            )
            #expect(posInfAttrs.isOpaqueFallback == true)
            #expect(posInfAttrs.intensity == 0.0)
        }
    }

    // MARK: - Accessibility Fallback Behavior

    @Test("Verify Accessibility Reduce Transparency Trigger Forces Opaque Fallback")
    func testReduceTransparencyFallback() {
        let reduced = LiquidGlassAttributes.resolve(
            style: .prominent,
            intensity: 1.0,
            reduceTransparency: true
        )
        #expect(reduced.isOpaqueFallback == true)
        #expect(reduced.shadowOpacity == 0.0) // Shadows suppressed in high accessibility mode
        #expect(reduced.strokeOpacity >= 0.8) // High contrast solid border fallback
    }

    // MARK: - Typography Scale, Weights & Dynamic Type

    @Test("Verify Apple HIG Typography Default Point Sizes")
    func testTypographyDefaultPointSizes() {
        #expect(AppTypography.pointSize(for: .largeTitle) == 34.0)
        #expect(AppTypography.pointSize(for: .title) == 28.0)
        #expect(AppTypography.pointSize(for: .title2) == 22.0)
        #expect(AppTypography.pointSize(for: .title3) == 20.0)
        #expect(AppTypography.pointSize(for: .headline) == 17.0)
        #expect(AppTypography.pointSize(for: .body) == 17.0)
        #expect(AppTypography.pointSize(for: .callout) == 16.0)
        #expect(AppTypography.pointSize(for: .subheadline) == 15.0)
        #expect(AppTypography.pointSize(for: .footnote) == 13.0)
        #expect(AppTypography.pointSize(for: .caption) == 12.0)
        #expect(AppTypography.pointSize(for: .caption2) == 11.0)
    }

    @Test("Verify Typography Font Weight Mappings")
    func testTypographyFontWeights() {
        #expect(AppTypography.weight(for: .largeTitle) == .bold)
        #expect(AppTypography.weight(for: .title) == .bold)
        #expect(AppTypography.weight(for: .title2) == .bold)
        #expect(AppTypography.weight(for: .title3) == .semibold)
        #expect(AppTypography.weight(for: .headline) == .semibold)
        #expect(AppTypography.weight(for: .body) == .regular)
        #expect(AppTypography.weight(for: .subheadline) == .regular)
        #expect(AppTypography.weight(for: .footnote) == .regular)
        #expect(AppTypography.weight(for: .caption) == .regular)
        #expect(AppTypography.weight(for: .caption2) == .regular)
    }

    @Test("Verify Dynamic Scaling Monotonicity Across Size Categories")
    func testDynamicScalingMonotonicity() {
        let categories: [AppDynamicTypeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge,
            .extraExtraLarge, .extraExtraExtraLarge, .accessibility1,
            .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]

        for style in AppTextStyle.allCases {
            var previousSize: CGFloat = 0.0
            for category in categories {
                let scaled = AppTypography.scaledPointSize(for: style, category: category)
                #expect(scaled >= previousSize, "Style \(style) point size must monotonically increase from \(previousSize) to \(scaled)")
                previousSize = scaled
            }
        }
    }

    @Test("Verify Dynamic Scaling Lower and Upper Bounds")
    func testDynamicScalingBounds() {
        for style in AppTextStyle.allCases {
            let smallest = AppTypography.scaledPointSize(for: style, category: .extraSmall)
            let largest = AppTypography.scaledPointSize(for: style, category: .accessibility5)

            #expect(smallest >= 8.0, "Smallest scaled point size must never drop below 8pt")
            #expect(largest <= 120.0, "Largest scaled point size must remain within sane bounds")
        }
    }

    @Test("Verify Typography Tokens and Semantic View Modifiers Dynamic Type Conformance")
    @MainActor
    func testTypographyTokensAndModifiers() {
        // 1. Verify all 17 public semantic font tokens instantiate without crash
        let tokens: [Font] = [
            Typography.largeTitle,
            Typography.screenTitle,
            Typography.sectionHeader,
            Typography.sidebarItem,
            Typography.tabItem,
            Typography.postAuthor,
            Typography.postHandle,
            Typography.postTimestamp,
            Typography.postBody,
            Typography.postTag,
            Typography.postMetrics,
            Typography.composerEditor,
            Typography.characterCount,
            Typography.statCount,
            Typography.statLabel,
            Typography.badge,
            Typography.actionButton
        ]
        #expect(tokens.count == 17)

        // 2. Verify view modifiers apply cleanly to SwiftUI View content
        let renderedView = Text("Sample Post Content")
            .postBodyStyle()
            .postAuthorStyle()
            .postHandleStyle()
            .postTimestampStyle()
            .monospacedMetricsStyle()
            .environment(\.dynamicTypeSize, .accessibility5)
        #expect(renderedView != nil)

        // 3. Verify monotonic expansion for all token text style curves
        let primaryStyles: [AppTextStyle] = [
            .largeTitle, .title2, .headline, .subheadline, .body, .footnote, .caption, .caption2
        ]
        for style in primaryStyles {
            let baseSize = AppTypography.pointSize(for: style)
            let a5Size = AppTypography.scaledPointSize(for: style, category: .accessibility5)
            #expect(a5Size >= baseSize * 1.5, "Style \(style) in .accessibility5 must scale by at least 1.5x")
        }
    }
}
