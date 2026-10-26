import Foundation
import XKitModels
import XKitTransport

private final class MockStateBox: @unchecked Sendable {
    private let lock = NSLock()
    var recordedRequests: [HTTPRequest] = []
    var responseQueue: [Result<HTTPResponse, Error>] = []
    var customHandler: (@Sendable (HTTPRequest) async throws -> HTTPResponse)?

    func recordAndDequeue(request: HTTPRequest) -> (
        handler: (@Sendable (HTTPRequest) async throws -> HTTPResponse)?,
        nextResult: Result<HTTPResponse, Error>?
    ) {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.append(request)
        let handler = customHandler
        let next = responseQueue.isEmpty ? nil : responseQueue.removeFirst()
        return (handler, next)
    }

    func enqueue(response: Result<HTTPResponse, Error>) {
        lock.lock()
        defer { lock.unlock() }
        responseQueue.append(response)
    }

    func setHandler(_ handler: (@Sendable (HTTPRequest) async throws -> HTTPResponse)?) {
        lock.lock()
        defer { lock.unlock() }
        customHandler = handler
    }

    func getRecordedRequests() -> [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedRequests.removeAll()
        responseQueue.removeAll()
        customHandler = nil
    }
}

/// A mock HTTPTransport for deterministic offline testing conforming to Swift 6 strict concurrency.
public final class MockTransport: HTTPTransport, Sendable {
    private let state = MockStateBox()

    public init() {}

    public var recordedRequests: [HTTPRequest] {
        state.getRecordedRequests()
    }

    public func enqueue(statusCode: Int, headers: [String: String] = [:], data: Data) {
        state.enqueue(response: .success(HTTPResponse(statusCode: statusCode, headers: headers, data: data)))
    }

    public func enqueue(statusCode: Int, headers: [String: String] = [:], jsonString: String) {
        enqueue(statusCode: statusCode, headers: headers, data: Data(jsonString.utf8))
    }

    public func enqueue(error: Error) {
        state.enqueue(response: .failure(error))
    }

    public func setHandler(_ handler: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse) {
        state.setHandler(handler)
    }

    public func reset() {
        state.reset()
    }

    public func send(request: HTTPRequest) async throws -> HTTPResponse {
        let (handler, nextResult) = state.recordAndDequeue(request: request)

        if let handler = handler {
            return try await handler(request)
        }

        if let result = nextResult {
            switch result {
            case .success(let response):
                return response
            case .failure(let error):
                throw error
            }
        }

        return HTTPResponse(statusCode: 200, headers: [:], data: Data())
    }
}
