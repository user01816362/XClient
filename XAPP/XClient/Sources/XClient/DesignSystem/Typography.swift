//
//  Typography.swift
//  XClient
//
//  Semantic Typography Tokens, Apple HIG Dynamic Type Foundation, and Metrics Styling.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI

// MARK: - AppTextStyle & AppDynamicTypeCategory (Testing & Pure-Swift Calculation)

/// Apple HIG Standard text styles for headless calculation and point size verification.
public enum AppTextStyle: String, CaseIterable, Identifiable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    public var id: String { rawValue }

    /// Corresponding native SwiftUI Font.TextStyle.
    public var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }
}

/// Dynamic Type content size categories for headless monotonicity tests.
public enum AppDynamicTypeCategory: String, CaseIterable, Identifiable, Sendable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
    case extraExtraLarge
    case extraExtraExtraLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    public var id: String { rawValue }

    public var scaleFactor: CGFloat {
        switch self {
        case .extraSmall: return 0.80
        case .small: return 0.86
        case .medium: return 0.93
        case .large: return 1.00 // Default reference size
        case .extraLarge: return 1.12
        case .extraExtraLarge: return 1.25
        case .extraExtraExtraLarge: return 1.38
        case .accessibility1: return 1.58
        case .accessibility2: return 1.80
        case .accessibility3: return 2.05
        case .accessibility4: return 2.30
        case .accessibility5: return 2.55
        }
    }
}

/// Dynamic Type scale calculations conforming to Apple Human Interface Guidelines.
public struct AppTypography: Sendable {
    /// Default reference point size for each style at category .large
    public static func pointSize(for style: AppTextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34.0
        case .title: return 28.0
        case .title2: return 22.0
        case .title3: return 20.0
        case .headline: return 17.0
        case .body: return 17.0
        case .callout: return 16.0
        case .subheadline: return 15.0
        case .footnote: return 13.0
        case .caption: return 12.0
        case .caption2: return 11.0
        }
    }

    /// Font weight mappings for each style
    public static func weight(for style: AppTextStyle) -> Font.Weight {
        switch style {
        case .largeTitle: return .bold
        case .title: return .bold
        case .title2: return .bold
        case .title3: return .semibold
        case .headline: return .semibold
        case .body: return .regular
        case .callout: return .regular
        case .subheadline: return .regular
        case .footnote: return .regular
        case .caption: return .regular
        case .caption2: return .regular
        }
    }

    /// Computes scaled point size for a given style and category.
    public static func scaledPointSize(for style: AppTextStyle, category: AppDynamicTypeCategory) -> CGFloat {
        let base = pointSize(for: style)
        let scaled = base * category.scaleFactor
        return max(8.0, min(120.0, (scaled * 2.0).rounded() / 2.0))
    }

    /// Creates a Dynamic Type scaling SwiftUI Font for a given AppTextStyle.
    public static func dynamicFont(
        for style: AppTextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> Font {
        let resolvedWeight = weight ?? self.weight(for: style)
        return Font.system(style.textStyle, design: design).weight(resolvedWeight)
    }
}

// MARK: - Typography (Semantic SwiftUI Tokens)

/// Semantic typography tokens and HIG Dynamic Type styling for XClient.
public enum Typography: Sendable {
    // MARK: - Navigation & Surface Titles

    /// Primary large window/screen title (34pt reference, bold, dynamic scaling with .largeTitle).
    public static var largeTitle: Font {
        Font.system(.largeTitle, design: .default).weight(.bold)
    }

    /// Modal header and screen view titles (22pt reference, bold, dynamic scaling with .title2).
    public static var screenTitle: Font {
        Font.system(.title2, design: .default).weight(.bold)
    }

    /// Uppercase section header label (13pt reference, semibold, dynamic scaling with .footnote).
    public static var sectionHeader: Font {
        Font.system(.footnote, design: .default).weight(.semibold)
    }

    /// Sidebar navigation destination item (15pt reference, medium, dynamic scaling with .subheadline).
    public static var sidebarItem: Font {
        Font.system(.subheadline, design: .default).weight(.medium)
    }

    /// TabBar compact destination label (11pt reference, medium, dynamic scaling with .caption2).
    public static var tabItem: Font {
        Font.system(.caption2, design: .default).weight(.medium)
    }

    // MARK: - Post Card & Timeline Tokens

    /// Post card author display name (17pt reference, semibold, dynamic scaling with .headline).
    public static var postAuthor: Font {
        Font.system(.headline, design: .default).weight(.semibold)
    }

    /// Post card author @username handle (15pt reference, regular, dynamic scaling with .subheadline).
    public static var postHandle: Font {
        Font.system(.subheadline, design: .default).weight(.regular)
    }

    /// Post card relative timestamp (12pt reference, regular, dynamic scaling with .caption).
    public static var postTimestamp: Font {
        Font.system(.caption, design: .default).weight(.regular)
    }

    /// Post card main body text (17pt reference, regular, dynamic scaling with .body).
    public static var postBody: Font {
        Font.system(.body, design: .default).weight(.regular)
    }

    /// Post card hashtags and @mentions (15pt reference, medium, dynamic scaling with .subheadline).
    public static var postTag: Font {
        Font.system(.subheadline, design: .default).weight(.medium)
    }

    /// Action bar metric counters (12pt reference, medium, dynamic scaling with .caption, monospaced digits).
    public static var postMetrics: Font {
        Font.system(.caption, design: .default).weight(.medium).monospacedDigit()
    }

    // MARK: - Composer & Inputs

    /// Composer text editor body font (17pt reference, regular, dynamic scaling with .body).
    public static var composerEditor: Font {
        Font.system(.body, design: .default).weight(.regular)
    }

    /// Composer character countdown badge (11pt reference, bold, dynamic scaling with .caption2, monospaced digits).
    public static var characterCount: Font {
        Font.system(.caption2, design: .default).weight(.bold).monospacedDigit()
    }

    // MARK: - Profile Stats & Badges

    /// Profile follower/following numeric count (17pt reference, bold, dynamic scaling with .headline, monospaced digits).
    public static var statCount: Font {
        Font.system(.headline, design: .default).weight(.bold).monospacedDigit()
    }

    /// Profile follower/following label (15pt reference, regular, dynamic scaling with .subheadline).
    public static var statLabel: Font {
        Font.system(.subheadline, design: .default).weight(.regular)
    }

    /// Notification badge and pill counter (11pt reference, bold, dynamic scaling with .caption2).
    public static var badge: Font {
        Font.system(.caption2, design: .default).weight(.bold)
    }

    /// Standard interactive action button (15pt reference, semibold, dynamic scaling with .subheadline).
    public static var actionButton: Font {
        Font.system(.subheadline, design: .default).weight(.semibold)
    }
}

// MARK: - Semantic View Modifiers

public extension View {
    /// Formats post body text with calibrated line spacing and dynamic type scaling.
    func postBodyStyle() -> some View {
        modifier(PostBodyTextModifier())
    }

    /// Formats post author display name with semibold weight and primary text color.
    func postAuthorStyle() -> some View {
        modifier(PostAuthorTextModifier())
    }

    /// Formats post handle text with subheadline font and secondary text color.
    func postHandleStyle() -> some View {
        modifier(PostHandleTextModifier())
    }

    /// Formats relative timestamp text with caption font and secondary text color.
    func postTimestampStyle() -> some View {
        modifier(PostTimestampTextModifier())
    }

    /// Formats interaction counters with monospaced digits to prevent jittering.
    func monospacedMetricsStyle() -> some View {
        modifier(PostMetricsTextModifier())
    }
}

private struct PostBodyTextModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.postBody)
            .lineSpacing(3.5)
            .foregroundStyle(palette.textPrimary)
    }
}

private struct PostAuthorTextModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.postAuthor)
            .lineLimit(1)
            .foregroundStyle(palette.textPrimary)
    }
}

private struct PostHandleTextModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.postHandle)
            .lineLimit(1)
            .foregroundStyle(palette.textSecondary)
    }
}

private struct PostTimestampTextModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.postTimestamp)
            .lineLimit(1)
            .foregroundStyle(palette.textSecondary)
    }
}

private struct PostMetricsTextModifier: ViewModifier, Sendable {
    @Environment(\.colorPalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(Typography.postMetrics)
            .foregroundStyle(palette.textSecondary)
    }
}
