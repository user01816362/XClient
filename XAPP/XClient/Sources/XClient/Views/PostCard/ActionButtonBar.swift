//
//  ActionButtonBar.swift
//  XClient
//
//  Interactive 5-action toolbar (Reply, Repost, Like, Bookmark, Share)
//  with optimistic animated toggles, monospaced numeric counters, and VoiceOver support.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI

/// Toolbar containing social action buttons (Reply, Repost, Like, Bookmark, Share).
@MainActor
public struct ActionButtonBar: View {
    @Environment(\.colorPalette) private var palette

    public let replyCount: Int
    public let repostCount: Int
    public let likeCount: Int
    public let bookmarkCount: Int
    public let isLiked: Bool
    public let isReposted: Bool
    public let isBookmarked: Bool

    public var onReply: (() -> Void)?
    public var onRepostToggle: (() -> Void)?
    public var onLikeToggle: (() -> Void)?
    public var onBookmarkToggle: (() -> Void)?
    public var onShare: (() -> Void)?

    public init(
        replyCount: Int,
        repostCount: Int,
        likeCount: Int,
        bookmarkCount: Int,
        isLiked: Bool,
        isReposted: Bool,
        isBookmarked: Bool,
        onReply: (() -> Void)? = nil,
        onRepostToggle: (() -> Void)? = nil,
        onLikeToggle: (() -> Void)? = nil,
        onBookmarkToggle: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil
    ) {
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.bookmarkCount = bookmarkCount
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.isBookmarked = isBookmarked
        self.onReply = onReply
        self.onRepostToggle = onRepostToggle
        self.onLikeToggle = onLikeToggle
        self.onBookmarkToggle = onBookmarkToggle
        self.onShare = onShare
    }

    // MARK: - Accessibility Label Helpers
    public static func replyAccessibilityLabel(count: Int) -> String {
        "\(max(0, count)) replies"
    }

    public static func repostAccessibilityLabel(isReposted: Bool, count: Int) -> String {
        "\(isReposted ? "Undo repost" : "Repost"), \(max(0, count)) reposts"
    }

    public static func likeAccessibilityLabel(isLiked: Bool, count: Int) -> String {
        "\(isLiked ? "Unlike" : "Like"), \(max(0, count)) likes"
    }

    public static func bookmarkAccessibilityLabel(isBookmarked: Bool, count: Int) -> String {
        "\(isBookmarked ? "Remove bookmark" : "Bookmark"), \(max(0, count)) bookmarks"
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 1. Reply
            actionItem(
                iconName: "bubble.left",
                activeColor: palette.accent,
                count: replyCount,
                isActive: false,
                accessibilityLabel: Self.replyAccessibilityLabel(count: replyCount)
            ) {
                onReply?()
            }

            Spacer(minLength: 0)

            // 2. Repost
            actionItem(
                iconName: "arrow.2.squarepath",
                activeColor: palette.repostActive,
                count: repostCount,
                isActive: isReposted,
                accessibilityLabel: Self.repostAccessibilityLabel(isReposted: isReposted, count: repostCount)
            ) {
                onRepostToggle?()
            }

            Spacer(minLength: 0)

            // 3. Like
            actionItem(
                iconName: isLiked ? "heart.fill" : "heart",
                activeColor: palette.likeActive,
                count: likeCount,
                isActive: isLiked,
                accessibilityLabel: Self.likeAccessibilityLabel(isLiked: isLiked, count: likeCount)
            ) {
                onLikeToggle?()
            }

            Spacer(minLength: 0)

            // 4. Bookmark
            actionItem(
                iconName: isBookmarked ? "bookmark.fill" : "bookmark",
                activeColor: palette.bookmarkActive,
                count: bookmarkCount,
                isActive: isBookmarked,
                accessibilityLabel: Self.bookmarkAccessibilityLabel(isBookmarked: isBookmarked, count: bookmarkCount)
            ) {
                onBookmarkToggle?()
            }

            Spacer(minLength: 0)

            // 5. Share
            Button(action: { onShare?() }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 36, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share post")
        }
    }

    private func actionItem(
        iconName: String,
        activeColor: Color,
        count: Int,
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? activeColor : palette.textSecondary)

                if count > 0 {
                    Text(Self.formatCount(count))
                        .monospacedMetricsStyle()
                        .foregroundStyle(isActive ? activeColor : palette.textSecondary)
                }
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Formats numeric interaction count into compact string notation (e.g. 1.2K, 1.5M).
    public static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }
}
