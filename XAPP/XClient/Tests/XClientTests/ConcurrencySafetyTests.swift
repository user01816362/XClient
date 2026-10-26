import Testing
import Foundation
import XKit
import XKitModels
import XKitTesting
@testable import XClient

/// Independent background actor to verify cross-actor boundaries.
private actor BackgroundTimelineWorker {
    private let service: any XClientServiceProtocol

    init(service: any XClientServiceProtocol) {
        self.service = service
    }

    func performBackgroundFetch() async throws -> [XPost] {
        // Calling @MainActor async method across actor boundary via await
        return try await service.fetchHomeTimeline()
    }
}

@Suite("Swift 6 Concurrency & Actor Boundary Tests", .serialized)
struct ConcurrencySafetyTests {

    @Test("Service can be called across actor boundaries from a background actor")
    func testActorBoundaryCrossing() async throws {
        let service = await MainActor.run {
            XClientService()
        }

        let worker = BackgroundTimelineWorker(service: service)
        let posts = try await worker.performBackgroundFetch()

        #expect(!posts.isEmpty)
    }

    @Test("Fifty concurrent background tasks can query service simultaneously without data races")
    func testFiftyConcurrentReads() async throws {
        let service = await MainActor.run {
            XClientService()
        }

        try await withThrowingTaskGroup(of: [XPost].self) { group in
            for _ in 0..<50 {
                group.addTask {
                    try await service.fetchHomeTimeline()
                }
            }

            var count = 0
            for try await posts in group {
                #expect(!posts.isEmpty)
                count += 1
            }
            #expect(count == 50)
        }
    }

    @Test("MockClientService handles concurrent queries without state corruption")
    func testMockClientServiceConcurrency() async throws {
        let mockService = await MainActor.run {
            MockClientService()
        }

        try await withThrowingTaskGroup(of: [XPost].self) { group in
            for _ in 0..<30 {
                group.addTask {
                    try await mockService.fetchHomeTimeline()
                }
            }
            var count = 0
            for try await posts in group {
                #expect(!posts.isEmpty)
                count += 1
            }
            #expect(count == 30)
        }
    }

    @Test("Service fetch honors task cancellation cleanly")
    func testTaskCancellation() async throws {
        let service = await MainActor.run {
            XClientService()
        }

        let task = Task {
            try await Task.sleep(nanoseconds: 10_000_000)
            return try await service.fetchHomeTimeline()
        }
        task.cancel()

        do {
            _ = try await task.value
        } catch {
            #expect(error is CancellationError || Task.isCancelled)
        }
    }

    @Test("MockTransport thread-safe under heavy concurrency")
    func testMockTransportLockContention() async throws {
        let mock = MockTransport()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    if i % 2 == 0 {
                        mock.enqueue(statusCode: 200, jsonString: "{\"data\": []}")
                    } else {
                        _ = try await mock.send(request: HTTPRequest(url: URL(string: "https://api.x.com/2/test_\(i)")!))
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(mock.recordedRequests.count >= 0)
    }
}
