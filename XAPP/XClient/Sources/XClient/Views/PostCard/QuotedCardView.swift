//
//  QuotedCardView.swift
//  XClient
//
//  Embedded quoted mini-post card with single-level recursion limit,
//  compact author header, body text preview, and media thumbnail.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

/// Inset mini-card rendering an embedded quoted post citation.
public struct QuotedCardView: View {
    @Environment(\.colorPalette) private var palette

    public let post: PostItem
    public var onSelect: ((String) -> Void)?

    public init(post: PostItem, onSelect: ((String) -> Void)? = nil) {
        self.post = post
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Compact Author Header
            HStack(spacing: 6) {
                AvatarImage(author: post.author, size: 24)

                Text(post.author.name)
                    .font(Typography.postAuthor)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundStyle(palette.textPrimary)

                if post.author.verified == true {
                    VerificationBadgeView(badgeType: .resolve(from: post.author))
                }

                Text("@\(post.author.username)")
                    .font(Typography.postHandle)
                    .lineLimit(1)
                    .foregroundStyle(palette.textSecondary)

                Text("·")
                    .font(Typography.postTimestamp)
                    .foregroundStyle(palette.textTertiary)

                Text(post.relativeTimeString)
                    .font(Typography.postTimestamp)
                    .foregroundStyle(palette.textSecondary)

                Spacer(minLength: 0)
            }

            // 2. Body Text (Limited to 4 lines)
            Text(post.text)
                .font(Typography.postBody)
                .lineLimit(4)
                .foregroundStyle(palette.textPrimary)

            // 3. Compact Media Thumbnail (if present)
            if let firstMedia = post.mediaAttachments.first {
                AsyncImage(url: firstMedia.previewUrl ?? firstMedia.url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: 150)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.secondaryBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onSelect?(post.id)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quoted post by \(post.author.name): \(post.text)")
    }
}
