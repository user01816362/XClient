import Testing
import Foundation
@testable import XKitAuth

@Suite("PKCE Tests")
struct PKCETests {
    @Test("PKCE generation produces valid length verifier and non-empty challenge and state")
    func testPKCEGeneration() throws {
        let params = try PKCE.generate()
        #expect(params.verifier.count >= 43)
        #expect(params.verifier.count <= 128)
        #expect(!params.challenge.isEmpty)
        #expect(!params.state.isEmpty)
    }

    @Test("RFC 7636 Appendix B test vector verification")
    func testRFC7636Vector() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let challenge = PKCE.makeChallenge(for: verifier)
        #expect(challenge == expectedChallenge)
    }

    @Test("OAuthURLBuilder parameter inclusion")
    func testOAuthURLBuilder() throws {
        let url = try OAuthURLBuilder.build(
            clientID: "test_client_123",
            redirectURI: "https://example.com/callback",
            scope: "tweet.read tweet.write",
            state: "state123",
            codeChallenge: "challenge123"
        )

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.scheme == "https")
        #expect(components?.host == "x.com")
        #expect(components?.path == "/i/oauth2/authorize")

        let items = components?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "client_id", value: "test_client_123")))
        #expect(items.contains(URLQueryItem(name: "code_challenge_method", value: "S256")))
        #expect(items.contains(URLQueryItem(name: "response_type", value: "code")))
    }
}
