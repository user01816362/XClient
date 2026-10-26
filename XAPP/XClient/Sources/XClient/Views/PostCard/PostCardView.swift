//
//  PostCardView.swift
//  XClient
//
//  Unified 5-part PostCard container assembling AuthorView, PostBodyView,
//  AttachmentView, QuotedCardView, and ActionButtonBar with Liquid Glass styling.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Unified post card presenting author info, formatted body text, media attachments,
/// quoted references, and social action buttons wrapped in standard Liquid Glass.
public struct PostCardView: View {
    @Environment(\.colorPalette) private var palette

    public let post: PostItem
    public var onSelectPost: ((String) -> Void)?
    public var onSelectProfile: ((String) -> Void)?
    public var onReply: ((PostItem) -> Void)?
    public var onRepostToggle: ((String) -> Void)?
    public var onLikeToggle: ((String) -> Void)?
    public var onBookmarkToggle: ((String) -> Void)?
    public var onMediaTap: ((MediaAttachment) -> Void)?
    public var onSaveMedia: ((MediaAttachment) -> Void)?
    public var onCopyMediaLink: ((MediaAttachment) -> Void)?
    public var onShareMedia: ((MediaAttachment) -> Void)?
    public var onHashtagTap: ((String) -> Void)?
    public var onMentionTap: ((String) -> Void)?
    public var onURLTap: ((URL) -> Void)?

    public init(
        post: PostItem,
        onSelectPost: ((String) -> Void)? = nil,
        onSelectProfile: ((String) -> Void)? = nil,
        onReply: ((PostItem) -> Void)? = nil,
        onRepostToggle: ((String) -> Void)? = nil,
        onLikeToggle: ((String) -> Void)? = nil,
        onBookmarkToggle: ((String) -> Void)? = nil,
        onMediaTap: ((MediaAttachment) -> Void)? = nil,
        onSaveMedia: ((MediaAttachment) -> Void)? = nil,
        onCopyMediaLink: ((MediaAttachment) -> Void)? = nil,
        onShareMedia: ((MediaAttachment) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        onMentionTap: ((String) -> Void)? = nil,
        onURLTap: ((URL) -> Void)? = nil
    ) {
        self.post = post
        self.onSelectPost = onSelectPost
        self.onSelectProfile = onSelectProfile
        self.onReply = onReply
        self.onRepostToggle = onRepostToggle
        self.onLikeToggle = onLikeToggle
        self.onBookmarkToggle = onBookmarkToggle
        self.onMediaTap = onMediaTap
        self.onSaveMedia = onSaveMedia
        self.onCopyMediaLink = onCopyMediaLink
        self.onShareMedia = onShareMedia
        self.onHashtagTap = onHashtagTap
        self.onMentionTap = onMentionTap
        self.onURLTap = onURLTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Author Header Row
            AuthorView(
                author: post.author,
                createdAt: post.createdAt,
                isBookmarked: post.isBookmarked,
                onProfileTap: { onSelectProfile?(post.author.id) },
                onBookmarkToggle: { onBookmarkToggle?(post.id) },
                onShare: { sharePost() },
                onCopyLink: { copyPostLink() }
            )

            // 2. Post Body
            PostBodyView(
                text: post.text,
                isNoteTweet: post.isNoteTweet,
                onMentionTap: onMentionTap,
                onHashtagTap: onHashtagTap,
                onURLTap: onURLTap
            )

            // 3. Media Attachments (if any)
            if !post.mediaAttachments.isEmpty {
                AttachmentView(
                    attachments: post.mediaAttachments,
                    onMediaTap: onMediaTap,
                    onSaveMedia: onSaveMedia,
                    onCopyMediaLink: onCopyMediaLink,
                    onShareMedia: onShareMedia
                )
            }

            // 4. Quoted Card (if any)
            if let quotedItem = post.quotedPost?.postItem {
                QuotedCardView(post: quotedItem) { quotedId in
                    onSelectPost?(quotedId)
                }
            }

            // 5. Action Button Bar
            ActionButtonBar(
                replyCount: post.replyCount,
                repostCount: post.repostCount,
                likeCount: post.likeCount,
                bookmarkCount: post.bookmarkCount,
                isLiked: post.isLiked,
                isReposted: post.isReposted,
                isBookmarked: post.isBookmarked,
                onReply: { onReply?(post) },
                onRepostToggle: { onRepostToggle?(post.id) },
                onLikeToggle: { onLikeToggle?(post.id) },
                onBookmarkToggle: { onBookmarkToggle?(post.id) },
                onShare: { sharePost() }
            )
        }
        .padding(14)
        .liquidGlassStandard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            onSelectPost?(post.id)
        }
    }

    private func sharePost() {
        copyPostLink()
    }

    private func copyPostLink() {
        let urlString = "https://x.com/\(post.author.username)/status/\(post.id)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #else
        UIPasteboard.general.string = urlString
        #endif
    }
}
