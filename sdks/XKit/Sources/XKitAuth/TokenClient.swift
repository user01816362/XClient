import Foundation

/// Transport-level failures for the public-client token endpoint.
public enum TokenClientError: Error, Sendable, Equatable {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingError(String)
}

/// Public-client (no secret) token exchange + refresh against
/// `https://api.x.com/2/oauth2/token`.
///
/// Bodies are `application/x-www-form-urlencoded` per the OAuth 2.0 token
/// endpoint. `client_id` is sent in the body because native apps cannot hold
/// a confidential secret.
public struct TokenClient: Sendable {
    public let tokenURL: URL
    private let session: URLSession
    private let dateProvider: @Sendable () -> Date

    public init(
        tokenURL: URL = URL(string: "https://api.x.com/2/oauth2/token")!,
        session: URLSession = .shared,
        dateProvider: @Sendable @escaping () -> Date = Date.init
    ) {
        self.tokenURL = tokenURL
        self.session = session
        self.dateProvider = dateProvider
    }

    /// Exchanges an authorization `code` for tokens.
    public func exchange(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String
    ) async throws -> OAuthToken {
        try await perform(formFields: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
        ])
    }

    /// Refreshes tokens with a `refresh_token`.
    public func refresh(
        refreshToken: String,
        clientID: String
    ) async throws -> OAuthToken {
        try await perform(formFields: [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
        ])
    }

    // MARK: - Private

    private func perform(formFields: [(String, String)]) async throws -> OAuthToken {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(from: formFields)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokenClientError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw TokenClientError.httpError(statusCode: http.statusCode, body: body)
        }
        let decoded: OAuthToken
        do {
            decoded = try JSONDecoder().decode(OAuthToken.self, from: data)
        } catch {
            throw TokenClientError.decodingError(String(describing: error))
        }
        // Stamp acquisition time with the injected clock; the endpoint does
        // not return `created_at`, and decoding defaults it to `Date()`.
        return OAuthToken(
            accessToken: decoded.accessToken,
            tokenType: decoded.tokenType,
            expiresIn: decoded.expiresIn,
            refreshToken: decoded.refreshToken,
            scope: decoded.scope,
            createdAt: dateProvider()
        )
    }

    /// Percent-encodes `application/x-www-form-urlencoded` bodies.
    static func formBody(from fields: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        // `percentEncodedQuery` applies the correct form encoding.
        let query = components.percentEncodedQuery ?? ""
        return Data(query.utf8)
    }
}
