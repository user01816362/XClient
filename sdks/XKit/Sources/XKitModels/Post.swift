import Foundation

/// Represents an X API v2 post (tweet).
public struct XPost: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let text: String
    public let authorId: String?
    public let createdAt: Date?
    public let conversationId: String?

    public init(
        id: String,
        text: String,
        authorId: String? = nil,
        createdAt: Date? = nil,
        conversationId: String? = nil
    ) {
        self.id = id
        self.text = text
        self.authorId = authorId
        self.createdAt = createdAt
        self.conversationId = conversationId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case authorId = "author_id"
        case createdAt = "created_at"
        case conversationId = "conversation_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        authorId = try container.decodeIfPresent(String.self, forKey: .authorId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)

        if container.contains(.createdAt) {
            if let timestamp = try? container.decode(Double.self, forKey: .createdAt) {
                createdAt = Date(timeIntervalSince1970: timestamp)
            } else if let string = try? container.decode(String.self, forKey: .createdAt) {
                createdAt = XPost.parseDate(string)
            } else {
                createdAt = nil
            }
        } else {
            createdAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(authorId, forKey: .authorId)
        if let createdAt {
            try container.encode(XPost.iso8601String(createdAt), forKey: .createdAt)
        }
        try container.encodeIfPresent(conversationId, forKey: .conversationId)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}