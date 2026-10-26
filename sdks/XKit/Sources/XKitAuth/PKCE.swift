import CryptoKit
import Foundation
import Security

/// PKCE artifacts for one authorization attempt (RFC 7636, S256).
public struct PKCEParameters: Sendable, Equatable, Hashable {
    /// 43–128 chars from the unreserved set, sent to the token endpoint.
    public let verifier: String
    /// `BASE64URL(SHA256(verifier))` without padding, sent to the authorize endpoint.
    public let challenge: String
    /// Opaque anti-CSRF value echoed back with the authorization code.
    public let state: String

    public init(verifier: String, challenge: String, state: String) {
        self.verifier = verifier
        self.challenge = challenge
        self.state = state
    }
}

/// Failures from secure random generation.
public enum PKCEError: Error, Sendable, Equatable {
    case randomGenerationFailed(status: OSStatus)
    case invalidByteCount(requested: Int, allowed: ClosedRange<Int>)
}

/// Cryptographically secure PKCE / state generation (RFC 7636, S256).
///
/// `code_verifier` uses base64url-encoded random bytes, which consist only of
/// `[A-Z a-z 0-9 - _]` — a subset of the RFC 7636 unreserved characters — so
/// no further alphabet mapping is required.
public enum PKCE: Sendable {
    /// Random bytes that yield a 43-char verifier (RFC minimum).
    public static let defaultVerifierByteCount = 32
    /// Random bytes for `state` (43 chars base64url, no padding).
    public static let defaultStateByteCount = 32
    /// Verifier byte counts mapping to 43...128 base64url chars.
    public static let allowedVerifierByteCount = 32 ... 96
    /// State byte counts mapping to roughly 22...128 base64url chars.
    public static let allowedStateByteCount = 16 ... 96

    /// Generates a fresh verifier/challenge/state triple.
    public static func generate(
        verifierByteCount: Int = defaultVerifierByteCount,
        stateByteCount: Int = defaultStateByteCount
    ) throws -> PKCEParameters {
        let verifier = try makeVerifier(byteCount: verifierByteCount)
        let state = try makeState(byteCount: stateByteCount)
        return PKCEParameters(
            verifier: verifier,
            challenge: makeChallenge(for: verifier),
            state: state
        )
    }

    /// Generates a `code_verifier` of `ceil(byteCount * 4 / 3)` chars.
    public static func makeVerifier(byteCount: Int = defaultVerifierByteCount) throws -> String {
        guard allowedVerifierByteCount.contains(byteCount) else {
            throw PKCEError.invalidByteCount(requested: byteCount, allowed: allowedVerifierByteCount)
        }
        return base64URLEncode(try randomBytes(count: byteCount))
    }

    /// Generates an opaque `state` value.
    public static func makeState(byteCount: Int = defaultStateByteCount) throws -> String {
        guard allowedStateByteCount.contains(byteCount) else {
            throw PKCEError.invalidByteCount(requested: byteCount, allowed: allowedStateByteCount)
        }
        return base64URLEncode(try randomBytes(count: byteCount))
    }

    /// Computes `BASE64URL-ENCODE(SHA256(verifier))` without padding.
    public static func makeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    // MARK: - Primitives

    /// Base64url encoding without padding, per RFC 7636 Appendix A.
    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Cryptographically secure random bytes via `SecRandomCopyBytes`.
    public static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PKCEError.randomGenerationFailed(status: status)
        }
        return Data(bytes)
    }
}
