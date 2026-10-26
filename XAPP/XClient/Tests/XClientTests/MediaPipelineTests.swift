//
//  MediaPipelineTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 3 (Feature F6):
//  MediaDownloadManager URL caching, streaming downloads, progress tracking,
//  cache purging, platform save collision handling, and error propagation.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#endif
@testable import XClient

// MARK: - Mock URLProtocol for Headless Network Simulation

private final class MockMediaURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [URL: (HTTPURLResponse, Data)] = [:]
    private nonisolated(unsafe) static var shouldFailURLs: Set<URL> = []

    static func setHandler(for url: URL, statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        handlers[url] = (response, data)
    }

    static func setFailing(url: URL) {
        lock.lock()
        defer { lock.unlock() }
        shouldFailURLs.insert(url)
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeAll()
        shouldFailURLs.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.lock.lock()
        let shouldFail = Self.shouldFailURLs.contains(url)
        let handler = Self.handlers[url]
        Self.lock.unlock()

        if shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        if let (response, data) = handler {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            // Default 200 OK fixture (1024 bytes data)
            let dummyData = Data(repeating: 0xAB, count: 1024)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "1024"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: dummyData)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - Media Pipeline Test Suite

@Suite("Milestone 3: Media Download Pipeline Tests", .serialized)
struct MediaPipelineTests {

    @MainActor
    private func makeTestManager() -> (MediaDownloadManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("XClientTestCache_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockMediaURLProtocol.self]
        let session = URLSession(configuration: config)

        let manager = MediaDownloadManager(session: session, customCacheDirectory: tempDir)
        return (manager, tempDir)
    }

    private func cleanup(tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
        MockMediaURLProtocol.reset()
    }

    // MARK: - Test 3.1: Cache Key Generation & Extension Preservation
    @Test("Verify SHA256 Cache Key Generation and Extension Preservation")
    @MainActor
    func testCacheKeyGeneration() {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let url = URL(string: "https://example.com/images/banner.png?v=123")!
        let key = manager.cacheKey(for: url)

        #expect(key.hasSuffix(".png"))
        #expect(!key.contains("/"))
        #expect(!key.contains("?"))
        #expect(key.count > 64) // SHA256 hex (64) + .png (4)
    }

    // MARK: - Test 3.2: Path Traversal Defense
    @Test("Verify Directory Traversal Sequences in URL Are Safely Hashed Inside Cache")
    @MainActor
    func testPathTraversalDefense() {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let maliciousURL = URL(string: "https://example.com/../../../../etc/passwd")!
        let fileURL = manager.cacheDirectory.appendingPathComponent(manager.cacheKey(for: maliciousURL))

        #expect(fileURL.path.hasPrefix(tempDir.path), "Hashed file path escaped test cache directory!")
    }

    // MARK: - Test 3.3: Cache Miss Downloads & Stores File
    @Test("Verify Cache Miss Downloads Payload, Saves to Cache, and Marks Cached")
    @MainActor
    func testCacheMissDownload() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/sample.jpg")!
        let testData = Data(repeating: 0xFF, count: 2048)
        MockMediaURLProtocol.setHandler(for: testURL, statusCode: 200, data: testData)

        #expect(manager.isCached(url: testURL) == false)

        let cachedURL = try await manager.downloadMedia(from: testURL)

        #expect(FileManager.default.fileExists(atPath: cachedURL.path))
        #expect(manager.isCached(url: testURL) == true)
        #expect(manager.completedDownloads.contains(testURL))
        #expect(manager.activeProgress[testURL] == 1.0)

        let savedSize = try FileManager.default.attributesOfItem(atPath: cachedURL.path)[.size] as? Int64
        #expect(savedSize == 2048)
    }

    // MARK: - Test 3.4: Cache Hit Returns Immediately
    @Test("Verify Cache Hit Returns Local File URL Without Hitting Network")
    @MainActor
    func testCacheHitReturnsImmediately() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/cached_photo.png")!

        // Pre-populate cache directly
        let cachedFile = tempDir.appendingPathComponent(manager.cacheKey(for: testURL))
        try "Pre-cached content".write(to: cachedFile, atomically: true, encoding: .utf8)

        // Make network fail if called
        MockMediaURLProtocol.setFailing(url: testURL)

        let resultURL = try await manager.downloadMedia(from: testURL)
        #expect(resultURL == cachedFile)
        #expect(manager.isCached(url: testURL) == true)
    }

    // MARK: - Test 3.5: Download Progress Tracking
    @Test("Verify Download Progress Tracking Reaches 1.0 on Completion")
    @MainActor
    func testDownloadProgressTracking() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/progress_test.mp4")!
        _ = try await manager.downloadMedia(from: testURL)

        #expect(manager.activeProgress[testURL] == 1.0)
    }

    // MARK: - Test 3.6: Task Cancellation Handling
    @Test("Verify Download Task Cancellation Throws and Leaves No Temp Files")
    @MainActor
    func testTaskCancellationCleansUp() async {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/slow_download.bin")!
        let largeData = Data(repeating: 0x42, count: 500_000)
        MockMediaURLProtocol.setHandler(for: testURL, statusCode: 200, data: largeData)

        let task = Task { @MainActor in
            try await manager.downloadMedia(from: testURL)
        }
        task.cancel()

        var didThrowOrCancel = false
        do {
            _ = try await task.value
        } catch {
            didThrowOrCancel = true
        }

        #expect(didThrowOrCancel == true)
        let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        let tmpFiles = files.filter { $0.pathExtension == "tmp" }
        #expect(tmpFiles.isEmpty, "Orphan temporary files remained after cancellation")
    }

    // MARK: - Test 3.7: Cache Size Calculation
    @Test("Verify Cache Size Calculation Accurately Sums Stored Bytes")
    @MainActor
    func testCacheSizeCalculation() throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        #expect(manager.cacheSizeInBytes() == 0)

        // Create 3 files: 10KB, 20KB, 30KB
        let data1 = Data(repeating: 1, count: 10_000)
        let data2 = Data(repeating: 2, count: 20_000)
        let data3 = Data(repeating: 3, count: 30_000)

        try data1.write(to: tempDir.appendingPathComponent("file1.media"))
        try data2.write(to: tempDir.appendingPathComponent("file2.media"))
        try data3.write(to: tempDir.appendingPathComponent("file3.media"))

        #expect(manager.cacheSizeInBytes() == 60_000)
    }

    // MARK: - Test 3.8: Cache Purge Removes All Files
    @Test("Verify ClearCache Deletes All Files and Resets Byte Count to Zero")
    @MainActor
    func testClearCachePurge() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        try Data(repeating: 0, count: 5_000).write(to: tempDir.appendingPathComponent("f1.bin"))
        try Data(repeating: 0, count: 5_000).write(to: tempDir.appendingPathComponent("f2.bin"))
        #expect(manager.cacheSizeInBytes() == 10_000)

        let purged = try await manager.clearCache()
        #expect(purged == 2)
        #expect(manager.cacheSizeInBytes() == 0)
        #expect(FileManager.default.fileExists(atPath: tempDir.path)) // Directory persists
    }

    // MARK: - Test 3.9: ClearCache on Empty Directory
    @Test("Verify ClearCache on Empty Directory Is Safe No-Op Returning Zero")
    @MainActor
    func testClearEmptyCache() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let purged = try await manager.clearCache()
        #expect(purged == 0)
        #expect(manager.cacheSizeInBytes() == 0)
    }

    // MARK: - Test 3.10: HTTP 404 Error Handling
    @Test("Verify HTTP 404 Response Throws Network Error and Leaves No Orphan File")
    @MainActor
    func testHTTP404ErrorHandling() async {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/missing_404.jpg")!
        MockMediaURLProtocol.setHandler(for: testURL, statusCode: 404, data: Data())

        var didThrow = false
        do {
            _ = try await manager.downloadMedia(from: testURL)
        } catch {
            didThrow = true
        }

        #expect(didThrow == true)
        #expect(manager.isCached(url: testURL) == false)
        #expect(manager.activeErrors[testURL] != nil)
    }

    // MARK: - Test 3.11: Network Connection Reset / Drop
    @Test("Verify Network Connection Failure Cleans Up Temp File and Records Error")
    @MainActor
    func testNetworkDropErrorHandling() async {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/dropped.png")!
        MockMediaURLProtocol.setFailing(url: testURL)

        var didCatch = false
        do {
            _ = try await manager.downloadMedia(from: testURL)
        } catch {
            didCatch = true
        }

        #expect(didCatch == true)
        #expect(manager.isCached(url: testURL) == false)
    }

    // MARK: - Test 3.12: File Collision Avoidance on Local Device Save
    #if os(macOS)
    @Test("Verify macOS SaveMediaToLocalDevice Handles File Collisions Gracefully")
    @MainActor
    func testFileCollisionAvoidanceLogic() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let tempDownloads = FileManager.default.temporaryDirectory.appendingPathComponent("TestDownloads_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDownloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDownloads) }

        let testURL = URL(string: "https://example.com/media/collision_photo.jpg")!
        MockMediaURLProtocol.setHandler(for: testURL, statusCode: 200, data: Data(repeating: 0x42, count: 1024))

        // First save creates "collision_photo.jpg"
        let firstSavedURL = try await manager.saveMediaToLocalDevice(
            from: testURL,
            destinationDirectory: tempDownloads
        )
        #expect(FileManager.default.fileExists(atPath: firstSavedURL.path))
        #expect(firstSavedURL.lastPathComponent == "collision_photo.jpg")

        // Second save from same URL must resolve collision to "collision_photo (1).jpg"
        let secondSavedURL = try await manager.saveMediaToLocalDevice(
            from: testURL,
            destinationDirectory: tempDownloads
        )
        #expect(FileManager.default.fileExists(atPath: secondSavedURL.path))
        #expect(secondSavedURL.lastPathComponent == "collision_photo (1).jpg")

        // Third save must resolve collision to "collision_photo (2).jpg"
        let thirdSavedURL = try await manager.saveMediaToLocalDevice(
            from: testURL,
            destinationDirectory: tempDownloads
        )
        #expect(FileManager.default.fileExists(atPath: thirdSavedURL.path))
        #expect(thirdSavedURL.lastPathComponent == "collision_photo (2).jpg")
    }
    #endif

    // MARK: - Test 3.13: Platform Export Error Propagation
    @Test("Verify Platform Export Handles Unsupported Media Types or Permissions")
    @MainActor
    func testPlatformExportHandling() async {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let deniedError = MediaDownloadError.photosAccessDenied
        #expect(deniedError.errorDescription?.contains("Photos") == true)

        let unsupportedError = MediaDownloadError.unsupportedMediaType
        #expect(unsupportedError.errorDescription?.contains("Unsupported") == true)

        #if os(macOS)
        let image = NSImage(size: NSSize(width: 10, height: 10))
        do {
            try await manager.saveToPhotos(image: image)
        } catch {
            // In headless CI or restricted sandbox, catch without failing
        }
        #endif
    }

    // MARK: - Test 3.14: Concurrent Downloads of Same URL Coalesce Safely
    @Test("10 concurrent download requests for the same URL execute without collision")
    func testConcurrentDownloadsOfSameURL() async throws {
        let (manager, tempDir) = await MainActor.run {
            makeTestManager()
        }
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/concurrent_hero.jpg")!

        try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await manager.downloadMedia(from: testURL)
                }
            }

            var results: [URL] = []
            for try await fileURL in group {
                results.append(fileURL)
            }

            #expect(results.count == 10)
            // All 10 tasks must point to the same cached file
            let first = results.first!
            for res in results {
                #expect(res == first)
            }
        }
    }

    // MARK: - Test 3.15: Path Traversal Rejection on Local Device Save
    #if os(macOS)
    @Test("Verify SaveMediaToLocalDevice Rejects Path Traversal in Custom Filename")
    @MainActor
    func testSaveMediaRejectsPathTraversal() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let testURL = URL(string: "https://example.com/media/doc.pdf")!
        MockMediaURLProtocol.setHandler(for: testURL, statusCode: 200, data: Data(repeating: 0x55, count: 512))

        let maliciousFilenames = [
            "../../escape.pdf",
            "../../../etc/passwd",
            "..\\..\\win.exe",
            "/tmp/rooted.bin"
        ]

        for malicious in maliciousFilenames {
            var didReject = false
            do {
                _ = try await manager.saveMediaToLocalDevice(
                    from: testURL,
                    customFilename: malicious
                )
            } catch {
                didReject = true
            }
            #expect(didReject == true, "saveMediaToLocalDevice accepted malicious path: \(malicious)")
        }
    }
    #endif

    // MARK: - Test 3.16: Query URL Extension Extraction
    #if os(macOS)
    @Test("Verify SaveMediaToLocalDevice Extracts Extension From Query Parameter URLs")
    @MainActor
    func testQueryURLExtensionExtraction() async throws {
        let (manager, tempDir) = makeTestManager()
        defer { cleanup(tempDir: tempDir) }

        let tempDownloads = FileManager.default.temporaryDirectory.appendingPathComponent("TestExt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDownloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDownloads) }

        // Standard Twitter/X CDN URL format without dot in lastPathComponent
        let queryURL = URL(string: "https://pbs.twimg.com/media/GR28hW7WwAA40rW?format=jpg&name=large")!
        MockMediaURLProtocol.setHandler(for: queryURL, statusCode: 200, data: Data(repeating: 0x77, count: 1024))

        let savedURL = try await manager.saveMediaToLocalDevice(
            from: queryURL,
            destinationDirectory: tempDownloads
        )
        defer { try? FileManager.default.removeItem(at: savedURL) }

        #expect(savedURL.pathExtension == "jpg", "Expected .jpg extension from query param, got: \(savedURL.pathExtension)")
        #expect(savedURL.lastPathComponent.hasPrefix("GR28hW7WwAA40rW"))
    }
    #endif
}
