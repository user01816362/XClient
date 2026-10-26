import Foundation
import XKitModels

/// Rich UI domain representation of a user profile surface in XClient.
public struct UserProfile: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let user: XUser
    public let headerImageUrl: URL?
    public let bio: String?
    public let location: String?
    public let websiteUrl: URL?
    public let joinedDate: Date
    public var followersCount: Int
    public var followingCount: Int
    public var postsCount: Int
    public var isFollowing: Bool

    public var id: String { user.id }
    public var name: String { user.name }
    public var username: String { user.username }
    public var isVerified: Bool { user.verified ?? false }
    public var profileImageUrl: String? { user.profileImageUrl }

    public init(
        user: XUser,
        headerImageUrl: URL? = nil,
        bio: String? = nil,
        location: String? = nil,
        websiteUrl: URL? = nil,
        joinedDate: Date = Date(),
        followersCount: Int = 0,
        followingCount: Int = 0,
        postsCount: Int = 0,
        isFollowing: Bool = false
    ) {
        self.user = user
        self.headerImageUrl = headerImageUrl
        self.bio = bio ?? user.description
        self.location = location
        self.websiteUrl = websiteUrl
        self.joinedDate = joinedDate
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.postsCount = postsCount
        self.isFollowing = isFollowing
    }

    /// Formatted joined date string (e.g. "Joined October 2023").
    public var joinedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return "Joined \(formatter.string(from: joinedDate))"
    }

    /// Formatted metric strings for UI display (e.g., "18.4K", "1.2M").
    public static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 10_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        } else {
            return "\(count)"
        }
    }

    // MARK: - Hashable Conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(user.id)
        hasher.combine(user.name)
        hasher.combine(user.username)
        hasher.combine(followersCount)
        hasher.combine(followingCount)
        hasher.combine(isFollowing)
    }
}
