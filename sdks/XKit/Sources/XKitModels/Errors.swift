import Foundation

/// Structured errors emitted by XKit operations.
public enum XKitError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    case invalidURL
    case networkError
    case httpError(statusCode: Int, data: Data?)
    case apiError(title: String, detail: String, type: String?)
    case rateLimitExceeded(resetDate: Date?)

    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError:
            return "Network connection error"
        case .httpError(let statusCode, _):
            return "HTTP error with status code \(statusCode)"
        case .apiError(let title, let detail, _):
            return "API Error: \(title) - \(detail)"
        case .rateLimitExceeded(let resetDate):
            if let date = resetDate {
                return "Rate limit exceeded. Resets at \(date)"
            }
            return "Rate limit exceeded"
        }
    }

    public var errorDescription: String? {
        return self.description
    }
}

/// RFC 7807 Problem Details representation used by X API v2.
public struct APIProblemDetails: Codable, Sendable, Equatable {
    public let title: String
    public let detail: String
    public let type: String?
    public let status: Int?

    public init(title: String, detail: String, type: String? = nil, status: Int? = nil) {
        self.title = title
        self.detail = detail
        self.type = type
        self.status = status
    }
}