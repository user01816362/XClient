//
//  ProfileGeometry.swift
//  XClient
//
//  Pure layout geometry engine for ProfileView parallax scrolling,
//  dynamic avatar scaling, and navigation bar opacity morphing.
//  100% Swift 6 strict concurrency compliant.
//

import Foundation
import CoreGraphics

public enum ProfileGeometry: Sendable {
    public static let defaultBannerBaseHeight: CGFloat = 150.0
    public static let defaultLargeAvatarSize: CGFloat = 76.0

    /// Calculates effective banner height during scroll.
    /// Pull-down (scrollOffsetY < 0) stretches linearly; scroll-up stays at baseHeight.
    public static func effectiveBannerHeight(baseHeight: CGFloat = defaultBannerBaseHeight, scrollOffsetY: CGFloat) -> CGFloat {
        scrollOffsetY < 0 ? (baseHeight - scrollOffsetY) : baseHeight
    }

    /// Calculates banner parallax translation offset.
    /// Pull-down stretches at 1.0x velocity; scroll-up translates at 0.4x parallax velocity.
    public static func effectiveBannerOffset(scrollOffsetY: CGFloat) -> CGFloat {
        scrollOffsetY < 0 ? scrollOffsetY : (scrollOffsetY * 0.4)
    }

    /// Dynamic avatar scale factor clamped to [0.0, 1.0].
    /// Pins to 1.0 during overscroll; collapses linearly to 0.0 at 90pt scroll up.
    public static func avatarScale(for scrollOffsetY: CGFloat) -> CGFloat {
        max(0.0, 1.0 - (max(0.0, scrollOffsetY) / 90.0))
    }

    /// Dynamic avatar opacity clamped to [0.0, 1.0].
    /// Pins to 1.0 during overscroll; fades to 0.0 at 70pt scroll up.
    public static func avatarOpacity(for scrollOffsetY: CGFloat) -> CGFloat {
        max(0.0, 1.0 - (max(0.0, scrollOffsetY) / 70.0))
    }

    /// Morphing navigation bar opacity clamped to [0.0, 1.0].
    /// Becomes visible between 80pt and 120pt scroll offset.
    public static func navigationBarOpacity(for scrollOffsetY: CGFloat) -> Double {
        min(1.0, max(0.0, Double((scrollOffsetY - 80.0) / 40.0)))
    }
}
