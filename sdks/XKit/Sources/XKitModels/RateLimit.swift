import Foundation

/// Encapsulates rate limit information returned in HTTP response headers.
public struct RateLimitInfo: Sendable, Codable, Equatable {
    public let limit: Int
    public let remaining: Int
    public let reset: Date

    /// Convenience alias used by earlier scaffolding.
    public var resetDate: Date { reset }

    public init(limit: Int, remaining: Int, reset: Date) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
    }

    public init(limit: Int, remaining: Int, resetDate: Date) {
        self.init(limit: limit, remaining: remaining, reset: resetDate)
    }

    public var isExhausted: Bool {
        remaining <= 0
    }

    public var secondsUntilReset: TimeInterval {
        max(0, reset.timeIntervalSinceNow)
    }

    enum CodingKeys: String, CodingKey {
        case limit
        case remaining
        case reset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try container.decode(Int.self, forKey: .limit)
        remaining = try container.decode(Int.self, forKey: .remaining)

        if container.contains(.reset) {
            if let timestamp = try? container.decode(Double.self, forKey: .reset) {
                reset = Date(timeIntervalSince1970: timestamp)
            } else if let string = try? container.decode(String.self, forKey: .reset) {
                reset = RateLimitInfo.parseDate(string) ?? Date(timeIntervalSince1970: 0)
            } else {
                throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected number or string for reset"))
            }
        } else {
            throw DecodingError.keyNotFound(CodingKeys.reset, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected reset date"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(limit, forKey: .limit)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(RateLimitInfo.iso8601String(reset), forKey: .reset)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}