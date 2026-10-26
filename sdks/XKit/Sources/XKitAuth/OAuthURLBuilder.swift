import Foundation

/// Input for one OAuth 2.0 authorization request.
public struct OAuthAuthorizationRequest: Sendable, Equatable, Hashable {
    public let clientID: String
    public let redirectURI: String
    public let scope: String
    public let state: String
    public let codeChallenge: String

    public init(
        clientID: String,
        redirectURI: String,
        scope: String,
        state: String,
        codeChallenge: String
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scope = scope
        self.state = state
        self.codeChallenge = codeChallenge
    }
}

public enum OAuthURLBuilderError: Error, Sendable, Equatable {
    case invalidComponents
}

/// Builds the `https://x.com/i/oauth2/authorize` URL for the
/// Authorization Code + PKCE flow (public client, S256).
public enum OAuthURLBuilder: Sendable {
    public static let authorizeURLString = "https://x.com/i/oauth2/authorize"

    /// Builds an authorize URL from discrete parameters.
    public static func build(
        clientID: String,
        redirectURI: String,
        scope: String,
        state: String,
        codeChallenge: String,
        responseType: String = "code",
        codeChallengeMethod: String = "S256"
    ) throws -> URL {
        try build(
            request: OAuthAuthorizationRequest(
                clientID: clientID,
                redirectURI: redirectURI,
                scope: scope,
                state: state,
                codeChallenge: codeChallenge
            ),
            responseType: responseType,
            codeChallengeMethod: codeChallengeMethod
        )
    }

    /// Builds an authorize URL from an `OAuthAuthorizationRequest`.
    public static func build(
        request: OAuthAuthorizationRequest,
        responseType: String = "code",
        codeChallengeMethod: String = "S256"
    ) throws -> URL {
        guard var components = URLComponents(string: authorizeURLString) else {
            throw OAuthURLBuilderError.invalidComponents
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: responseType),
            URLQueryItem(name: "client_id", value: request.clientID),
            URLQueryItem(name: "redirect_uri", value: request.redirectURI),
            URLQueryItem(name: "scope", value: request.scope),
            URLQueryItem(name: "state", value: request.state),
            URLQueryItem(name: "code_challenge", value: request.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod),
        ]
        guard let url = components.url else {
            throw OAuthURLBuilderError.invalidComponents
        }
        return url
    }
}
