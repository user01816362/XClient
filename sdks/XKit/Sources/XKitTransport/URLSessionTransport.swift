import Foundation
import XKitModels

/// `HTTPTransport` implementation backed by `URLSession` with configurable timeouts and cookie jar support.
public struct URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        self.session = URLSession(configuration: configuration)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func send(request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw XKitError.networkError
            }

            var headers: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                guard let keyString = key as? String else { continue }
                if let valueString = value as? String {
                    headers[keyString] = valueString
                } else {
                    headers[keyString] = String(describing: value)
                }
            }

            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                data: data
            )
        } catch let error as XKitError {
            throw error
        } catch {
            throw XKitError.networkError
        }
    }
}