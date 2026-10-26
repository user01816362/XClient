import Foundation
import XKitModels
import XKitTransport

public struct SingleResourceResponse<T: Codable & Sendable>: Codable, Sendable {
    public let data: T

    public init(data: T) {
        self.data = data
    }
}

public struct ActionSuccessResponse: Codable, Sendable {
    public struct DataPayload: Codable, Sendable {
        public let deleted: Bool?
        public let bookmarked: Bool?
    }
    public let data: DataPayload?
}

public struct APIRequestExecutor: Sendable {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func execute<T: Codable & Sendable>(
        url: URL,
        method: HTTPMethod = .get,
        token: String,
        body: Data? = nil
    ) async throws -> T {
        var headers: [String: String] = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        if body != nil {
            headers["Content-Type"] = "application/json"
        }

        let request = HTTPRequest(url: url, method: method, headers: headers, body: body)
        let response = try await transport.send(request: request)

        // Check for Rate Limit (HTTP 429)
        if response.statusCode == 429 {
            var resetDate: Date? = nil
            if let resetHeader = response.headers["x-rate-limit-reset"],
               let epoch = TimeInterval(resetHeader) {
                resetDate = Date(timeIntervalSince1970: epoch)
            }
            throw XKitError.rateLimitExceeded(resetDate: resetDate)
        }

        let responseData = response.data ?? Data()

        guard (200 ..< 300).contains(response.statusCode) else {
            // Attempt decoding RFC 7807 problem details
            if let problem = try? JSONDecoder().decode(APIProblemDetails.self, from: responseData) {
                throw XKitError.apiError(title: problem.title, detail: problem.detail, type: problem.type)
            }
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: responseData)
        } catch {
            throw XKitError.httpError(statusCode: response.statusCode, data: response.data)
        }
    }
}
