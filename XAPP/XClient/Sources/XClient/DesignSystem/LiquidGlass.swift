//
//  LiquidGlass.swift
//  XClient
//
//  Liquid Glass Appearance Styling, Material Layers, and High-Contrast Fallbacks.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI

// MARK: - LiquidGlassStyle

/// Defines the elevation and visual prominence hierarchy for Liquid Glass surfaces.
public enum LiquidGlassStyle: String, Sendable, CaseIterable, Identifiable, Hashable {
    case standard
    case elevated
    case prominent

    public var id: String { rawValue }

    public var defaultCornerRadius: CGFloat {
        switch self {
        case .standard: return 16
        case .elevated: return 20
        case .prominent: return 24
        }
    }

    public var shadowRadius: CGFloat {
        switch self {
        case .standard: return 4
        case .elevated: return 10
        case .prominent: return 16
        }
    }

    public var shadowY: CGFloat {
        switch self {
        case .standard: return 2
        case .elevated: return 5
        case .prominent: return 8
        }
    }

    public var shadowOpacity: Double {
        switch self {
        case .standard: return 0.06
        case .elevated: return 0.12
        case .prominent: return 0.18
        }
    }

    public var strokeWidth: CGFloat {
        switch self {
        case .standard: return 1.0
        case .elevated: return 1.0
        case .prominent: return 1.5
        }
    }
}

// MARK: - LiquidGlassAttributes (Decoupled Pure-Swift Model)

/// Pure-Swift value model decoupling Liquid Glass attributes for deterministic headless verification.
public struct LiquidGlassAttributes: Sendable, Equatable {
    public let style: LiquidGlassStyle
    public let intensity: Double
    public let isReduceTransparencyActive: Bool
    public let isOpaqueFallback: Bool
    public let strokeBorderWidth: CGFloat
    public let strokeOpacity: Double
    public let shadowRadius: CGFloat
    public let shadowYOffset: CGFloat
    public let shadowOpacity: Double
    public let cornerRadius: CGFloat

    public init(
        style: LiquidGlassStyle,
        intensity: Double,
        isReduceTransparencyActive: Bool,
        isOpaqueFallback: Bool,
        strokeBorderWidth: CGFloat,
        strokeOpacity: Double,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat,
        shadowOpacity: Double,
        cornerRadius: CGFloat
    ) {
        self.style = style
        self.intensity = intensity
        self.isReduceTransparencyActive = isReduceTransparencyActive
        self.isOpaqueFallback = isOpaqueFallback
        self.strokeBorderWidth = strokeBorderWidth
        self.strokeOpacity = strokeOpacity
        self.shadowRadius = shadowRadius
        self.shadowYOffset = shadowYOffset
        self.shadowOpacity = shadowOpacity
        self.cornerRadius = cornerRadius
    }

    /// Resolves visual parameters based on style, intensity, and accessibility settings.
    /// Defensively guards against Double.nan and non-finite values by immediately triggering safe opaque fallback.
    public static func resolve(
        style: LiquidGlassStyle,
        intensity: Double,
        reduceTransparency: Bool
    ) -> LiquidGlassAttributes {
        // Defensive sanitization: Double.nan, +infinity, -infinity, or non-finite numbers
        // must trigger safe high-contrast opaque fallback with zero shadow opacity and solid border.
        guard intensity.isFinite && !intensity.isNaN else {
            return LiquidGlassAttributes(
                style: style,
                intensity: 0.0,
                isReduceTransparencyActive: reduceTransparency,
                isOpaqueFallback: true,
                strokeBorderWidth: style.strokeWidth,
                strokeOpacity: 1.0,
                shadowRadius: style.shadowRadius,
                shadowYOffset: style.shadowY,
                shadowOpacity: 0.0,
                cornerRadius: style.defaultCornerRadius
            )
        }

        let clampedIntensity = max(0.0, min(1.0, intensity))
        let isFallback = reduceTransparency || clampedIntensity <= 0.05

        let strokeWidth = style.strokeWidth
        let strokeOpacity: Double = isFallback ? 1.0 : (0.6 * clampedIntensity)
        let shadowRad = style.shadowRadius
        let shadowY = style.shadowY
        let shadowOp: Double = isFallback ? 0.0 : (style.shadowOpacity * clampedIntensity)
        let cornerRad = style.defaultCornerRadius

        return LiquidGlassAttributes(
            style: style,
            intensity: clampedIntensity,
            isReduceTransparencyActive: reduceTransparency,
            isOpaqueFallback: isFallback,
            strokeBorderWidth: strokeWidth,
            strokeOpacity: strokeOpacity,
            shadowRadius: shadowRad,
            shadowYOffset: shadowY,
            shadowOpacity: shadowOp,
            cornerRadius: cornerRad
        )
    }
}

// MARK: - LiquidGlassModifier (RoundedRectangle)

/// View modifier applying the native Liquid Glass appearance to rounded rectangle shapes.
public struct LiquidGlassModifier: ViewModifier, Sendable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorPalette) private var palette

    public let style: LiquidGlassStyle
    public let cornerRadius: CGFloat
    public let intensity: Double

    public init(
        style: LiquidGlassStyle = .standard,
        cornerRadius: CGFloat? = nil,
        intensity: Double = 1.0
    ) {
        self.style = style
        self.cornerRadius = cornerRadius ?? style.defaultCornerRadius
        if intensity.isNaN || !intensity.isFinite {
            self.intensity = 0.0
        } else {
            self.intensity = max(0.0, min(1.0, intensity))
        }
    }

    public func body(content: Content) -> some View {
        let attrs = LiquidGlassAttributes.resolve(
            style: style,
            intensity: intensity,
            reduceTransparency: reduceTransparency
        )

        content
            .background {
                let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

                if attrs.isOpaqueFallback {
                    // Opaque High-Contrast Accessibility Fallback
                    shape
                        .fill(fallbackBackgroundColor)
                        .overlay {
                            shape.strokeBorder(palette.borderDefault, lineWidth: attrs.strokeBorderWidth)
                        }
                } else {
                    // Liquid Glass Translucent Material Layer
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.strokeBorder(rimGradient(intensity: attrs.intensity), lineWidth: attrs.strokeBorderWidth)
                        }
                        .shadow(
                            color: Color.black.opacity(attrs.shadowOpacity),
                            radius: attrs.shadowRadius,
                            x: 0,
                            y: attrs.shadowYOffset
                        )
                }
            }
    }

    private var fallbackBackgroundColor: Color {
        switch style {
        case .standard:
            return palette.secondaryBackground
        case .elevated:
            return palette.tertiaryBackground
        case .prominent:
            return palette.secondaryBackground
        }
    }

    private func rimGradient(intensity: Double) -> LinearGradient {
        let isDark = (colorScheme == .dark)

        let colors: [Color]
        switch (style, isDark) {
        case (.prominent, true):
            colors = [
                Color.white.opacity(0.55 * intensity),
                Color.white.opacity(0.15 * intensity),
                Color.clear
            ]
        case (.prominent, false):
            colors = [
                Color.white.opacity(0.90 * intensity),
                Color.black.opacity(0.12 * intensity)
            ]
        case (.elevated, true):
            colors = [
                Color.white.opacity(0.38 * intensity),
                Color.white.opacity(0.08 * intensity),
                Color.clear
            ]
        case (.elevated, false):
            colors = [
                Color.white.opacity(0.80 * intensity),
                Color.black.opacity(0.08 * intensity)
            ]
        case (.standard, true):
            colors = [
                Color.white.opacity(0.25 * intensity),
                Color.white.opacity(0.05 * intensity),
                Color.clear
            ]
        case (.standard, false):
            colors = [
                Color.white.opacity(0.60 * intensity),
                Color.black.opacity(0.04 * intensity)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - LiquidGlassCapsuleModifier (Capsule)

/// View modifier applying Liquid Glass styling specifically to pill/capsule shapes.
public struct LiquidGlassCapsuleModifier: ViewModifier, Sendable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorPalette) private var palette

    public let style: LiquidGlassStyle
    public let intensity: Double

    public init(style: LiquidGlassStyle = .standard, intensity: Double = 1.0) {
        self.style = style
        if intensity.isNaN || !intensity.isFinite {
            self.intensity = 0.0
        } else {
            self.intensity = max(0.0, min(1.0, intensity))
        }
    }

    public func body(content: Content) -> some View {
        let attrs = LiquidGlassAttributes.resolve(
            style: style,
            intensity: intensity,
            reduceTransparency: reduceTransparency
        )

        content
            .background {
                let shape = Capsule()

                if attrs.isOpaqueFallback {
                    shape
                        .fill(style == .prominent ? palette.secondaryBackground : palette.tertiaryBackground)
                        .overlay {
                            shape.strokeBorder(palette.borderDefault, lineWidth: attrs.strokeBorderWidth)
                        }
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            shape.strokeBorder(capsuleGradient(intensity: attrs.intensity), lineWidth: attrs.strokeBorderWidth)
                        }
                        .shadow(
                            color: Color.black.opacity(attrs.shadowOpacity),
                            radius: attrs.shadowRadius,
                            x: 0,
                            y: attrs.shadowYOffset
                        )
                }
            }
    }

    private func capsuleGradient(intensity: Double) -> LinearGradient {
        let isDark = (colorScheme == .dark)
        let colors: [Color]
        if style == .prominent {
            colors = isDark
                ? [Color.white.opacity(0.55 * intensity), Color.white.opacity(0.15 * intensity), Color.clear]
                : [Color.white.opacity(0.90 * intensity), Color.black.opacity(0.12 * intensity)]
        } else {
            colors = isDark
                ? [Color.white.opacity(0.35 * intensity), Color.white.opacity(0.08 * intensity), Color.clear]
                : [Color.white.opacity(0.75 * intensity), Color.black.opacity(0.06 * intensity)]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - View Extension Ergonomics

public extension View {
    /// Applies Liquid Glass styling with customizable elevation style, corner radius, and intensity.
    func liquidGlass(
        style: LiquidGlassStyle = .standard,
        cornerRadius: CGFloat? = nil,
        intensity: Double = 1.0
    ) -> some View {
        modifier(LiquidGlassModifier(style: style, cornerRadius: cornerRadius, intensity: intensity))
    }

    /// Standard Liquid Glass card styling.
    func liquidGlassStandard(cornerRadius: CGFloat = 16, intensity: Double = 1.0) -> some View {
        liquidGlass(style: .standard, cornerRadius: cornerRadius, intensity: intensity)
    }

    /// Elevated Liquid Glass floating panel styling.
    func liquidGlassElevated(cornerRadius: CGFloat = 20, intensity: Double = 1.0) -> some View {
        liquidGlass(style: .elevated, cornerRadius: cornerRadius, intensity: intensity)
    }

    /// Prominent Liquid Glass primary control styling.
    func liquidGlassProminent(cornerRadius: CGFloat = 24, intensity: Double = 1.0) -> some View {
        liquidGlass(style: .prominent, cornerRadius: cornerRadius, intensity: intensity)
    }

    /// Liquid Glass capsule styling for pills, badges, and floating action buttons.
    func liquidGlassCapsule(style: LiquidGlassStyle = .standard, intensity: Double = 1.0) -> some View {
        modifier(LiquidGlassCapsuleModifier(style: style, intensity: intensity))
    }
}
