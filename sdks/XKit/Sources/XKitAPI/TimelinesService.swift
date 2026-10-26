import Foundation
import XKitModels
import XKitTransport

public struct TimelinesService: Sendable {
    private let executor: APIRequestExecutor

    public init(transport: HTTPTransport) {
        self.executor = APIRequestExecutor(transport: transport)
    }

    /// Fetches reverse-chronological home timeline for a user (`GET /2/users/{id}/timelines/reverse_chronological`).
    public func reverseChronologicalHome(
        userId: String,
        token: String,
        paginationToken: String? = nil,
        maxResults: Int = 20
    ) async throws -> PaginatedResponse<XPost> {
        var components = URLComponents(string: "https://api.x.com/2/users/\(userId)/timelines/reverse_chronological")
        var queryItems = [URLQueryItem(name: "max_results", value: "\(maxResults)")]
        if let token = paginationToken {
            queryItems.append(URLQueryItem(name: "pagination_token", value: token))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }
        return try await executor.execute(url: url, token: token)
    }

    /// Fetches user's posted tweets (`GET /2/users/{id}/tweets`).
    public func userTweets(
        userId: String,
        token: String,
        paginationToken: String? = nil,
        maxResults: Int = 20
    ) async throws -> PaginatedResponse<XPost> {
        var components = URLComponents(string: "https://api.x.com/2/users/\(userId)/tweets")
        var queryItems = [URLQueryItem(name: "max_results", value: "\(maxResults)")]
        if let token = paginationToken {
            queryItems.append(URLQueryItem(name: "pagination_token", value: token))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw XKitError.invalidURL
        }
        return try await executor.execute(url: url, token: token)
    }
}
