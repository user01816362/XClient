//
//  LiveSampleCardPreview.swift
//  XClient
//
//  Interactive Live Sample PostCard container demonstrating current theme tokens,
//  dynamic contrast, and Liquid Glass refraction in real time.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

/// Observable state managing interactive mutations in LiveSampleCardPreview.
@MainActor
public final class LiveSampleCardState: ObservableObject, Sendable {
    @Published public var isLiked: Bool = false
    @Published public var isReposted: Bool = false
    @Published public var isBookmarked: Bool = false
    @Published public var likeCount: Int = 42
    @Published public var repostCount: Int = 12

    public init(
        isLiked: Bool = false,
        isReposted: Bool = false,
        isBookmarked: Bool = false,
        likeCount: Int = 42,
        repostCount: Int = 12
    ) {
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.isBookmarked = isBookmarked
        self.likeCount = likeCount
        self.repostCount = repostCount
    }
}

/// Live interactive sample card rendered over a vibrant background to visually demonstrate
/// Liquid Glass material refraction and active theme color tokens.
public struct LiveSampleCardPreview: View {
    public let preference: AppThemePreference
    public let glassIntensity: Double
    public let samplePost: PostItem

    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var cardState: LiveSampleCardState

    public init(preference: AppThemePreference, glassIntensity: Double, cardState: LiveSampleCardState? = nil) {
        self.preference = preference
        self.glassIntensity = glassIntensity
        _cardState = StateObject(wrappedValue: cardState ?? LiveSampleCardState())

        let mockAuthor = XUser(
            id: "sample_usr",
            name: "Liquid Glass",
            username: "liquidglass",
            description: "Native Apple experiences preview.",
            verified: true,
            profileImageUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=256&h=256&q=80",
            verifiedType: "blue"
        )
        self.samplePost = PostItem(
            id: "sample_preview_post",
            text: "Experience real-time Liquid Glass materials, dynamic theme switching, and native SwiftUI responsiveness in XClient! 🍎✨ #Swift6 #LiquidGlass",
            author: mockAuthor,
            createdAt: Date(),
            replyCount: 7,
            repostCount: 12,
            likeCount: 42,
            bookmarkCount: 9,
            isLiked: false,
            isReposted: false,
            isBookmarked: false
        )
    }

    public var body: some View {
        let palette = ColorPalette.resolve(preference: preference, systemScheme: systemScheme)

        VStack(alignment: .leading, spacing: 8) {
            // Live Preview Canvas with Vibrant Gradient Background
            ZStack {
                // Background Gradient showcasing material refraction
                LinearGradient(
                    colors: [
                        Color(hex: 0x1D9BF0).opacity(0.85),
                        Color(hex: 0x7856FF).opacity(0.80),
                        Color(hex: 0xF91880).opacity(0.70)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Themed & Liquid Glass Post Card
                VStack(alignment: .leading, spacing: 10) {
                    // 1. Author Row
                    HStack(spacing: 10) {
                        Circle()
                            .fill(palette.accent.opacity(0.3))
                            .frame(width: 38, height: 38)
                            .overlay {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(palette.accent)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(samplePost.author.name)
                                    .font(.headline)
                                    .foregroundStyle(palette.textPrimary)

                                Image(systemName: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(palette.verifiedBlue)
                            }

                            Text("@\(samplePost.author.username)")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }

                        Spacer()

                        Text("Just now")
                            .font(.caption2)
                            .foregroundStyle(palette.textSecondary)
                    }

                    // 2. Post Body
                    Text(samplePost.text)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(3)

                    // 3. Interactive Action Row
                    HStack {
                        // Reply
                        Label("\(samplePost.replyCount)", systemImage: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)

                        Spacer()

                        // Repost
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                cardState.isReposted.toggle()
                                cardState.repostCount += cardState.isReposted ? 1 : -1
                            }
                        } label: {
                            Label("\(cardState.repostCount)", systemImage: "arrow.2.squarepath")
                                .font(.caption)
                                .foregroundStyle(cardState.isReposted ? palette.repostActive : palette.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Like
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                cardState.isLiked.toggle()
                                cardState.likeCount += cardState.isLiked ? 1 : -1
                            }
                        } label: {
                            Label("\(cardState.likeCount)", systemImage: cardState.isLiked ? "heart.fill" : "heart")
                                .font(.caption)
                                .foregroundStyle(cardState.isLiked ? palette.likeActive : palette.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Bookmark
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                cardState.isBookmarked.toggle()
                            }
                        } label: {
                            Image(systemName: cardState.isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.caption)
                                .foregroundStyle(cardState.isBookmarked ? palette.bookmarkActive : palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(
                    palette.background.opacity(0.40)
                )
                .liquidGlass(
                    style: .standard,
                    cornerRadius: 16,
                    intensity: glassIntensity
                )
                .padding(16)
            }

            // Status Caption
            HStack {
                Text("Theme: \(preference.displayName)")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("Glass: \(Int(round(glassIntensity * 100)))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
