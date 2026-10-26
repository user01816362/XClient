//
//  ClientTransactionSigner.swift
//  XKit
//
//  Extracts and signs requests for internal Twitter/X endpoints with dynamic
//  transaction IDs, public Web bearer token, and guest tokens.
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import CryptoKit
import XKitModels

public struct ClientTransactionSigner: Sendable {
    /// Canonical public Twitter/X Web client bearer token observed across official web and mobile clients.
    public static let publicWebBearerToken = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

    /// Default animation keyword and constant seeds extracted from the client transaction generator algorithm.
    public static let defaultKeyword = "ondemand.s"
    public static let baseEpochSeconds: Int64 = 1682924400

    public init() {}

    /// Generates standard client headers required to query internal endpoints and GraphQL queries.
    public static func defaultHeaders(
        path: String = "",
        method: String = "GET",
        guestToken: String? = nil,
        authToken: String? = nil
    ) -> [String: String] {
        var headers: [String: String] = [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "authorization": publicWebBearerToken,
            "cache-control": "no-cache",
            "content-type": "application/json",
            "pragma": "no-cache",
            "origin": "https://x.com",
            "referer": "https://x.com",
            "user-agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "x-twitter-active-user": "yes",
            "x-twitter-client-language": "en",
            "x-twitter-auth-type": "OAuth2Session"
        ]

        if let guest = guestToken, !guest.isEmpty {
            headers["x-guest-token"] = guest
        }

        if let token = authToken, !token.isEmpty {
            headers["x-twitter-auth-type"] = "OAuth2Session"
            if !token.starts(with: "Bearer ") {
                headers["authorization"] = "Bearer \(token)"
            } else {
                headers["authorization"] = token
            }
        }

        if !path.isEmpty {
            headers["x-client-transaction-id"] = generateTransactionId(method: method, path: path)
        }

        return headers
    }

    /// Generates the `x-client-transaction-id` header using timestamp offset, method, path, and SHA-256 digest.
    public static func generateTransactionId(method: String, path: String, date: Date = Date()) -> String {
        let nowSeconds = Int64(date.timeIntervalSince1970)
        let timeOffset = max(0, nowSeconds - baseEpochSeconds)

        var timeBytes = [UInt8]()
        for i in 0..<4 {
            let byte = UInt8((timeOffset >> (i * 8)) & 0xFF)
            timeBytes.append(byte)
        }

        let input = "\(method)!\(path)!\(timeOffset)\(defaultKeyword)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let digestBytes = Array(digest.prefix(16))

        let randomPrefix: [UInt8] = [
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255),
            UInt8.random(in: 0...255)
        ]

        var payload = [UInt8]()
        payload.append(contentsOf: randomPrefix)
        payload.append(contentsOf: timeBytes)
        payload.append(contentsOf: digestBytes)
        payload.append(UInt8.random(in: 0...255))

        return Data(payload).base64EncodedString()
    }
}
