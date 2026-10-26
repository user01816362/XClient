import Foundation
import XKitModels
import XKitTransport

public struct UsersService: Sendable {
    private let executor: APIRequestExecutor

    public init(transport: HTTPTransport) {
        self.executor = APIRequestExecutor(transport: transport)
    }

    /// Fetches the authenticated user profile (`GET /2/users/me`).
    public func me(token: String) async throws -> XUser {
        guard let url = URL(string: "https://api.x.com/2/users/me") else {
            throw XKitError.invalidURL
        }
        let response: SingleResourceResponse<XUser> = try await executor.execute(url: url, token: token)
        return response.data
    }

    /// Fetches a user by ID (`GET /2/users/{id}`).
    public func lookup(id: String, token: String) async throws -> XUser {
        guard let url = URL(string: "https://api.x.com/2/users/\(id)") else {
            throw XKitError.invalidURL
        }
        let response: SingleResourceResponse<XUser> = try await executor.execute(url: url, token: token)
        return response.data
    }

    /// Fetches a user by username (`GET /2/users/by/username/{username}`).
    public func lookup(username: String, token: String) async throws -> XUser {
        guard let url = URL(string: "https://api.x.com/2/users/by/username/\(username)") else {
            throw XKitError.invalidURL
        }
        let response: SingleResourceResponse<XUser> = try await executor.execute(url: url, token: token)
        return response.data
    }
}
