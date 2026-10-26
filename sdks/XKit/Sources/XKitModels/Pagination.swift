import Foundation

/// Envelope for paginated X API v2 responses.
public struct PaginatedResponse<T: Sendable & Codable>: Sendable, Codable {
    public let data: [T]
    public let resultCount: Int?
    public let nextToken: String?
    public let previousToken: String?

    public init(
        data: [T],
        resultCount: Int? = nil,
        nextToken: String? = nil,
        previousToken: String? = nil
    ) {
        self.data = data
        self.resultCount = resultCount
        self.nextToken = nextToken
        self.previousToken = previousToken
    }

    enum CodingKeys: String, CodingKey {
        case data
        case resultCount = "result_count"
        case nextToken = "next_token"
        case previousToken = "previous_token"
    }
}