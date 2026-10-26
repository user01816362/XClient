import Foundation
import XKitModels
import XKitTransport

public struct PostsService: Sendable {
    private let executor: APIRequestExecutor

    public init(transport: HTTPTransport) {
        self.executor = APIRequestExecutor(transport: transport)
    }

    /// Fetches a single Post by ID (`GET /2/tweets/{id}`).
    public func lookup(id: String, token: String) async throws -> XPost {
        guard let url = URL(string: "https://api.x.com/2/tweets/\(id)") else {
            throw XKitError.invalidURL
        }
        let response: SingleResourceResponse<XPost> = try await executor.execute(url: url, token: token)
        return response.data
    }

    /// Creates a new Post (`POST /2/tweets`).
    public func create(text: String, token: String) async throws -> XPost {
        guard let url = URL(string: "https://api.x.com/2/tweets") else {
            throw XKitError.invalidURL
        }
        let payload = ["text": text]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let response: SingleResourceResponse<XPost> = try await executor.execute(
            url: url,
            method: .post,
            token: token,
            body: bodyData
        )
        return response.data
    }

    /// Deletes a Post by ID (`DELETE /2/tweets/{id}`).
    public func delete(id: String, token: String) async throws -> Bool {
        guard let url = URL(string: "https://api.x.com/2/tweets/\(id)") else {
            throw XKitError.invalidURL
        }
        let response: ActionSuccessResponse = try await executor.execute(
            url: url,
            method: .delete,
            token: token
        )
        return response.data?.deleted ?? true
    }
}
