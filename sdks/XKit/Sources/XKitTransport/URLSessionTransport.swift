import Foundation
import XKitModels

/// `HTTPTransport` implementation backed by `URLSession.shared`.
public struct URLSessionTransport: HTTPTransport, Sendable {
    public init() {}

    public func send(request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
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