import Foundation

/// OAuth 2.0 token issued by the X API v2 token endpoint.
///
/// `createdAt` records local acquisition time (the token endpoint does not
/// return it). It is persisted as `created_at` for symmetry, but decoding
/// tolerates payloads without it by defaulting to `Date()`.
public struct OAuthToken: Sendable, Codable, Equatable, Hashable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let scope: String?
    public let createdAt: Date

    /// Absolute expiry time derived from `createdAt + expiresIn`.
    public var expiresAt: Date {
        createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }

    /// True when the current date is at or past `expiresAt`.
    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public init(
        accessToken: String,
        tokenType: String,
        expiresIn: Int,
        refreshToken: String?,
        scope: String?,
        createdAt: Date
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        // Some OAuth servers encode expires_in as a JSON string; accept both.
        if let intValue = try? container.decode(Int.self, forKey: .expiresIn) {
            expiresIn = intValue
        } else {
            let stringValue = try container.decode(String.self, forKey: .expiresIn)
            guard let parsed = Int(stringValue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .expiresIn,
                    in: container,
                    debugDescription: "expires_in is neither Int nor numeric String"
                )
            }
            expiresIn = parsed
        }
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encode(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
