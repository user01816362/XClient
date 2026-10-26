import Foundation
import XKitModels

/// Indirect container for nested quoted posts avoiding recursive value type layout errors.
public indirect enum QuotedPostReference: Sendable, Equatable, Hashable, Codable {
    case post(PostItem)

    public var postItem: PostItem {
        switch self {
        case .post(let item): return item
        }
    }
}

/// Rich UI domain representation of a post item in XClient.
public struct PostItem: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let text: String
    public let author: XUser
    public let createdAt: Date
    public let conversationId: String?
    public let inReplyToPostId: String?
    public let mediaAttachments: [MediaAttachment]
    public var replyCount: Int
    public var repostCount: Int
    public var likeCount: Int
    public var bookmarkCount: Int
    public var isLiked: Bool
    public var isReposted: Bool
    public var isBookmarked: Bool
    public var quotedPost: QuotedPostReference?

    public init(
        id: String,
        text: String,
        author: XUser,
        createdAt: Date = Date(),
        conversationId: String? = nil,
        inReplyToPostId: String? = nil,
        mediaAttachments: [MediaAttachment] = [],
        replyCount: Int = 0,
        repostCount: Int = 0,
        likeCount: Int = 0,
        bookmarkCount: Int = 0,
        isLiked: Bool = false,
        isReposted: Bool = false,
        isBookmarked: Bool = false,
        quotedPost: QuotedPostReference? = nil
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.createdAt = createdAt
        self.conversationId = conversationId
        self.inReplyToPostId = inReplyToPostId
        self.mediaAttachments = mediaAttachments
        self.replyCount = replyCount
        self.repostCount = repostCount
        self.likeCount = likeCount
        self.bookmarkCount = bookmarkCount
        self.isLiked = isLiked
        self.isReposted = isReposted
        self.isBookmarked = isBookmarked
        self.quotedPost = quotedPost
    }

    /// Converts this rich domain model to an XKit wire model.
    public var asXPost: XPost {
        XPost(
            id: id,
            text: text,
            authorId: author.id,
            createdAt: createdAt,
            conversationId: conversationId
        )
    }

    /// Initializes a PostItem from an XKit wire model and matching author.
    public init(post: XPost, author: XUser) {
        self.id = post.id
        self.text = post.text
        self.author = author
        self.createdAt = post.createdAt ?? Date()
        self.conversationId = post.conversationId
        self.inReplyToPostId = nil
        self.mediaAttachments = []
        self.replyCount = 0
        self.repostCount = 0
        self.likeCount = 0
        self.bookmarkCount = 0
        self.isLiked = false
        self.isReposted = false
        self.isBookmarked = false
        self.quotedPost = nil
    }

    /// Returns whether the text content exceeds standard 280-character limit and requires "Show more" expansion.
    public var isNoteTweet: Bool {
        text.count > 280
    }

    /// Formatted relative timestamp string (e.g., "now", "5m", "2h", "1d").
    public var relativeTimeString: String {
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

    // MARK: - Hashable Conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
        hasher.combine(author.id)
        hasher.combine(createdAt)
        hasher.combine(isLiked)
        hasher.combine(isReposted)
        hasher.combine(isBookmarked)
    }
}
