import Testing
import Foundation
import XKitModels
import XKitTransport
import XKitTesting
import XKitAPI

@Suite("API Endpoint Tests")
struct APITests {
    @Test("UsersService.me parses profile accurately from JSON fixture")
    func testUsersMeSuccess() async throws {
        let mock = MockTransport()
        let json = """
        {
            "data": {
                "id": "2244994945",
                "name": "Twitter Dev",
                "username": "TwitterDev",
                "description": "Official Twitter Developer account",
                "verified": true
            }
        }
        """
        mock.enqueue(statusCode: 200, jsonString: json)

        let service = UsersService(transport: mock)
        let user = try await service.me(token: "test_bearer_token")

        #expect(user.id == "2244994945")
        #expect(user.name == "Twitter Dev")
        #expect(user.username == "TwitterDev")
        #expect(user.verified == true)
    }

    @Test("PostsService.lookup parses tweet details from fixture")
    func testPostsLookupSuccess() async throws {
        let mock = MockTransport()
        let json = """
        {
            "data": {
                "id": "1460323737035677698",
                "text": "Introducing a new era of developer tools on X."
            }
        }
        """
        mock.enqueue(statusCode: 200, jsonString: json)

        let service = PostsService(transport: mock)
        let post = try await service.lookup(id: "1460323737035677698", token: "test_token")

        #expect(post.id == "1460323737035677698")
        #expect(post.text == "Introducing a new era of developer tools on X.")
    }

    @Test("HTTP 429 raises XKitError.rateLimitExceeded with reset timestamp")
    func testRateLimitHandling() async throws {
        let mock = MockTransport()
        let resetEpoch = "\(Int(Date().timeIntervalSince1970 + 60))"
        mock.enqueue(statusCode: 429, headers: ["x-rate-limit-reset": resetEpoch], data: Data())

        let service = UsersService(transport: mock)
        await #expect(throws: XKitError.self) {
            _ = try await service.me(token: "test_token")
        }
    }

    @Test("RFC 7807 problem details are parsed into XKitError.apiError")
    func testRFC7807APIErrorParsing() async throws {
        let mock = MockTransport()
        let json = """
        {
            "title": "Unauthorized",
            "type": "about:blank",
            "status": 401,
            "detail": "Unauthorized"
        }
        """
        mock.enqueue(statusCode: 401, jsonString: json)

        let service = UsersService(transport: mock)
        await #expect(throws: XKitError.self) {
            _ = try await service.me(token: "invalid_token")
        }
    }
}
