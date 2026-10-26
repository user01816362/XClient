import Foundation
import XKitModels

/// HTTP methods supported by the transport.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"
}

/// A sendable request description.
public struct HTTPRequest: Sendable {
    public let url: URL
    public let method: HTTPMethod
    public let headers: [String: String]
    public let body: Data?

    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// A sendable response description.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data?

    public init(statusCode: Int, headers: [String: String] = [:], data: Data? = nil) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }
}

/// Abstraction over an underlying HTTP client.
public protocol HTTPTransport: Sendable {
    func send(request: HTTPRequest) async throws -> HTTPResponse
}