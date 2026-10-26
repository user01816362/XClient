import Testing
import Foundation
import XKitModels
import XKitTransport
import XKitTesting

@Suite("Transport Tests")
struct TransportTests {
    @Test("MockTransport records requests and returns staged payloads")
    func testMockTransportEnqueuing() async throws {
        let mock = MockTransport()
        let payload = "{\"status\": \"ok\"}"
        mock.enqueue(statusCode: 200, headers: ["content-type": "application/json"], jsonString: payload)

        let request = HTTPRequest(url: URL(string: "https://api.x.com/2/test")!)
        let response = try await mock.send(request: request)

        #expect(response.statusCode == 200)
        #expect(mock.recordedRequests.count == 1)
        #expect(mock.recordedRequests.first?.url.absoluteString == "https://api.x.com/2/test")
    }

    @Test("RateLimitInfo parsing and active duration")
    func testRateLimitInfoParsing() {
        let now = Date()
        let resetDate = now.addingTimeInterval(300)
        let info = RateLimitInfo(limit: 900, remaining: 150, resetDate: resetDate)

        #expect(info.limit == 900)
        #expect(info.remaining == 150)
        #expect(!info.isExhausted)
        #expect(info.secondsUntilReset > 0)
    }

    @Test("RateLimitInfo exhaustion check")
    func testRateLimitExhausted() {
        let past = Date().addingTimeInterval(-10)
        let info = RateLimitInfo(limit: 100, remaining: 0, resetDate: past)

        #expect(info.isExhausted)
        #expect(info.secondsUntilReset == 0)
    }
}
