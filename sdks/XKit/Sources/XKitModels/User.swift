import Foundation

/// Represents an X API v2 user.
public struct XUser: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let username: String
    public let description: String?
    public let verified: Bool?
    public let profileImageUrl: String?

    public init(
        id: String,
        name: String,
        username: String,
        description: String? = nil,
        verified: Bool? = nil,
        profileImageUrl: String? = nil
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.description = description
        self.verified = verified
        self.profileImageUrl = profileImageUrl
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case username
        case description
        case verified
        case profileImageUrl = "profile_image_url"
    }
}