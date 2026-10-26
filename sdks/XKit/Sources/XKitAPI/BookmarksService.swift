import Foundation
import XKitModels
import XKitTransport

public struct BookmarksService: Sendable {
    private let executor: APIRequestExecutor

    public init(transport: HTTPTransport) {
        self.executor = APIRequestExecutor(transport: transport)
    }

    /// Fetches bookmarked posts for user (`GET /2/users/{id}/bookmarks`).
    public func list(
        userId: String,
        token: String,
        paginationToken: String? = nil,
        maxResults: Int = 20
    ) async throws -> PaginatedResponse<XPost> {
        var components = URLComponents(string: "https://api.x.com/2/users/\(userId)/bookmarks")
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

    /// Bookmarks a post (`POST /2/users/{id}/bookmarks`).
    public func add(userId: String, postId: String, token: String) async throws -> Bool {
        guard let url = URL(string: "https://api.x.com/2/users/\(userId)/bookmarks") else {
            throw XKitError.invalidURL
        }
        let payload = ["tweet_id": postId]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let response: ActionSuccessResponse = try await executor.execute(
            url: url,
            method: .post,
            token: token,
            body: bodyData
        )
        return response.data?.bookmarked ?? true
    }

    /// Removes a bookmark (`DELETE /2/users/{id}/bookmarks/{tweet_id}`).
    public func remove(userId: String, postId: String, token: String) async throws -> Bool {
        guard let url = URL(string: "https://api.x.com/2/users/\(userId)/bookmarks/\(postId)") else {
            throw XKitError.invalidURL
        }
        let response: ActionSuccessResponse = try await executor.execute(
            url: url,
            method: .delete,
            token: token
        )
        return response.data?.bookmarked != true
    }
}
