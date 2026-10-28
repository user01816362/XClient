//
//  AuthorView.swift
//  XClient
//
//  Author header subview of PostCard displaying avatar with initials fallback,
//  display name, verification badge (blue/gold/gray), @handle, relative timestamp,
//  and overflow action menu.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

private let verifiedTypeLock = NSLock()
nonisolated(unsafe) private var verifiedTypeStorage: [String: String] = [:]

extension XUser {
    public var verifiedType: String? {
        get {
            verifiedTypeLock.lock()
            defer { verifiedTypeLock.unlock() }
            return verifiedTypeStorage[id]
        }
        set {
            verifiedTypeLock.lock()
            defer { verifiedTypeLock.unlock() }
            verifiedTypeStorage[id] = newValue
        }
    }

    public init(
        id: String,
        name: String,
        username: String,
        description: String? = nil,
        verified: Bool? = nil,
        profileImageUrl: String? = nil,
        verifiedType: String?
    ) {
        self.init(
            id: id,
            name: name,
            username: username,
            description: description,
            verified: verified,
            profileImageUrl: profileImageUrl
        )
        self.verifiedType = verifiedType
    }
}

/// Verification badge categorization matching first-party conventions.
public enum VerificationBadgeType: Sendable, Equatable {
    case none
    case blue
    case gold
    case gray

    public static func resolve(from user: XUser) -> VerificationBadgeType {
        guard user.verified == true else { return .none }
        if let type = user.verifiedType?.lowercased() {
            switch type {
            case "business", "gold":
                return .gold
            case "government", "gray", "grey":
                return .gray
            case "blue":
                return .blue
            case "none":
                return .none
            default:
                return .blue
            }
        }
        return .blue
    }
}

/// Header row displaying author avatar, names, verification badge, timestamp, and actions menu.
public struct AuthorView: View {
    @Environment(\.colorPalette) private var palette

    public let author: XUser
    public let createdAt: Date
    public let isBookmarked: Bool
    public var onProfileTap: (() -> Void)?
    public var onBookmarkToggle: (() -> Void)?
    public var onShare: (() -> Void)?
    public var onCopyLink: (() -> Void)?

    public init(
        author: XUser,
        createdAt: Date,
        isBookmarked: Bool = false,
        onProfileTap: (() -> Void)? = nil,
        onBookmarkToggle: (() -> Void)? = nil,
        onShare: (() -> Void)? = nil,
        onCopyLink: (() -> Void)? = nil
    ) {
        self.author = author
        self.createdAt = createdAt
        self.isBookmarked = isBookmarked
        self.onProfileTap = onProfileTap
        self.onBookmarkToggle = onBookmarkToggle
        self.onShare = onShare
        self.onCopyLink = onCopyLink
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // 1. Avatar Button
            Button(action: { onProfileTap?() }) {
                AvatarImage(author: author, size: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile of \(author.name), @\(author.username)")

            // 2. Names & Timestamp
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 4) {
                    // Display Name
                    Text(author.name)
                        .postAuthorStyle()

                    // Verification Badge
                    let badgeType = VerificationBadgeType.resolve(from: author)
                    if badgeType != .none {
                        VerificationBadgeView(badgeType: badgeType)
                    }

                    // Middle Dot
                    Text("·")
                        .font(Typography.postTimestamp)
                        .foregroundStyle(palette.textTertiary)

                    // Relative Timestamp
                    Text(relativeTimeString)
                        .postTimestampStyle()
                }

                // Handle
                Text("@\(author.username)")
                    .postHandleStyle()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onProfileTap?()
            }

            Spacer(minLength: 8)

            // 3. Overflow Menu Button
            Menu {
                if let onShare {
                    Button(action: onShare) { Label("Share Post", systemImage: "square.and.arrow.up") }
                }
                if let onCopyLink {
                    Button(action: onCopyLink) { Label("Copy Link to Post", systemImage: "doc.on.doc") }
                }
                if let onBookmarkToggle {
                    Button(action: onBookmarkToggle) {
                        Label(isBookmarked ? "Remove Bookmark" : "Bookmark Post",
                              systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More options for post by \(author.name)")
        }
    }

    private var relativeTimeString: String {
        let seconds = max(1, Int(-createdAt.timeIntervalSinceNow))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        return "\(weeks)w"
    }
}

// MARK: - Avatar Image with Initials Fallback
public struct AvatarImage: View {
    @Environment(\.colorPalette) private var palette
    public let author: XUser
    public let size: CGFloat

    public init(author: XUser, size: CGFloat = 40) {
        self.author = author
        self.size = size
    }

    public var body: some View {
        Group {
            if let imageUrlString = author.profileImageUrl, let url = URL(string: imageUrlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        initialsFallbackView
                    @unknown default:
                        initialsFallbackView
                    }
                }
            } else {
                initialsFallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(palette.borderSubtle, lineWidth: 1))
    }

    private var initialsFallbackView: some View {
        ZStack {
            fallbackGradient
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let parts = author.name.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = author.name.first {
            return String(first).uppercased()
        } else if let first = author.username.first {
            return String(first).uppercased()
        }
        return "?"
    }

    private var fallbackGradient: LinearGradient {
        let hash = abs(author.id.hashValue)
        let palettes: [[Color]] = [
            [Color(hex: 0x1D9BF0), Color(hex: 0x00BA7C)],
            [Color(hex: 0x7856FF), Color(hex: 0x1D9BF0)],
            [Color(hex: 0xFF7A00), Color(hex: 0xF91880)],
            [Color(hex: 0x00BA7C), Color(hex: 0x008556)],
            [Color(hex: 0xF91880), Color(hex: 0x7856FF)]
        ]
        let selected = palettes[hash % palettes.count]
        return LinearGradient(colors: selected, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Verification Badge View
public struct VerificationBadgeView: View {
    @Environment(\.colorPalette) private var palette
    public let badgeType: VerificationBadgeType

    public init(badgeType: VerificationBadgeType) {
        self.badgeType = badgeType
    }

    public var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(badgeColor)
            .accessibilityLabel(accessibilityLabel)
    }

    private var badgeColor: Color {
        switch badgeType {
        case .none: return .clear
        case .blue: return palette.verifiedBlue
        case .gold: return palette.verifiedGold
        case .gray: return Color(hexString: ColorTheme.VerificationBadge.grayHex)
        }
    }

    private var accessibilityLabel: String {
        switch badgeType {
        case .none: return ""
        case .blue: return "Verified account"
        case .gold: return "Verified organization"
        case .gray: return "Government official"
        }
    }
}
