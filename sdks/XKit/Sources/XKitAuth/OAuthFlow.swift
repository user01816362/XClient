import Foundation

/// Public-client OAuth configuration for an installed XClient application.
/// Native apps use PKCE and must not embed a client secret.
public struct OAuthFlowConfiguration: Sendable, Equatable, Hashable {
    public let clientID: String
    public let redirectURI: String
    public let scopes: [String]

    public init(clientID: String, redirectURI: String, scopes: [String]) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scopes = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public var scopeParameter: String {
        scopes.joined(separator: " ")
    }

    fileprivate var isUsable: Bool {
        guard !clientID.isEmpty,
              !scopes.isEmpty,
              scopes.allSatisfy({ !$0.contains(where: { $0.isWhitespace }) }),
              let redirect = URLComponents(string: redirectURI),
              let scheme = redirect.scheme,
              !scheme.isEmpty,
              redirect.user == nil,
              redirect.password == nil,
              redirect.query == nil,
              redirect.fragment == nil,
              redirect.host != nil || !redirect.path.isEmpty else {
            return false
        }
        return true
    }
}

/// Opaque, one-time state retained by the caller for a single authorization.
/// The verifier must not be persisted or logged.
public struct PendingOAuthAuthorization: Sendable, Equatable, Hashable {
    public let state: String
    public let codeVerifier: String
    public let redirectURI: String

    fileprivate init(state: String, codeVerifier: String, redirectURI: String) {
        self.state = state
        self.codeVerifier = codeVerifier
        self.redirectURI = redirectURI
    }
}

public enum OAuthFlowError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidCallback
    case missingState
    case stateMismatch
    case providerRejected(String)
    case missingAuthorizationCode
}

/// Coordinates the installed-app Authorization Code + PKCE flow.
///
/// The caller presents `authorizationURL` with the platform's system
/// authentication session, retains `pendingAuthorization` in memory, and
/// passes the resulting callback to `exchangeCallback`. Callback origin and
/// state are checked before the authorization code is sent to the token API.
public struct OAuthFlow: Sendable {
    public let configuration: OAuthFlowConfiguration
    private let tokenClient: TokenClient

    public init(
        configuration: OAuthFlowConfiguration,
        tokenClient: TokenClient = TokenClient()
    ) {
        self.configuration = configuration
        self.tokenClient = tokenClient
    }

    public func makeAuthorizationRequest() throws -> (
        authorizationURL: URL,
        pendingAuthorization: PendingOAuthAuthorization
    ) {
        guard configuration.isUsable else {
            throw OAuthFlowError.invalidConfiguration
        }

        let pkce = try PKCE.generate()
        let url = try OAuthURLBuilder.build(
            clientID: configuration.clientID,
            redirectURI: configuration.redirectURI,
            scope: configuration.scopeParameter,
            state: pkce.state,
            codeChallenge: pkce.challenge
        )

        return (
            url,
            PendingOAuthAuthorization(
                state: pkce.state,
                codeVerifier: pkce.verifier,
                redirectURI: configuration.redirectURI
            )
        )
    }

    public func exchangeCallback(
        _ callbackURL: URL,
        pendingAuthorization: PendingOAuthAuthorization
    ) async throws -> OAuthToken {
        guard Self.matchesRedirect(callbackURL, expected: pendingAuthorization.redirectURI),
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthFlowError.invalidCallback
        }

        let queryItems = components.queryItems ?? []
        let returnedStates = queryItems.filter { $0.name == "state" }
        guard returnedStates.count == 1, let returnedState = returnedStates[0].value else {
            throw OAuthFlowError.missingState
        }
        guard Self.constantTimeEqual(returnedState, pendingAuthorization.state) else {
            throw OAuthFlowError.stateMismatch
        }

        if let providerError = queryItems.first(where: { $0.name == "error" })?.value {
            throw OAuthFlowError.providerRejected(providerError)
        }

        let codes = queryItems.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty else {
            throw OAuthFlowError.missingAuthorizationCode
        }

        return try await tokenClient.exchange(
            code: code,
            verifier: pendingAuthorization.codeVerifier,
            redirectURI: pendingAuthorization.redirectURI,
            clientID: configuration.clientID
        )
    }

    private static func matchesRedirect(_ callback: URL, expected: String) -> Bool {
        guard let expectedComponents = URLComponents(string: expected),
              let callbackComponents = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expectedScheme = expectedComponents.scheme,
              let callbackScheme = callbackComponents.scheme,
              expectedComponents.user == nil,
              expectedComponents.password == nil,
              callbackComponents.user == nil,
              callbackComponents.password == nil,
              callbackComponents.fragment == nil else {
            return false
        }

        return expectedScheme.caseInsensitiveCompare(callbackScheme) == .orderedSame &&
            normalizedHost(expectedComponents.host) == normalizedHost(callbackComponents.host) &&
            expectedComponents.port == callbackComponents.port &&
            expectedComponents.path == callbackComponents.path
    }

    private static func normalizedHost(_ host: String?) -> String? {
        host?.lowercased()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
