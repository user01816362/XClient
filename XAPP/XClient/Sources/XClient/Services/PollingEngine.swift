//
//  PollingEngine.swift
//  XClient
//
//  Dedicated Swift actor managing background periodic timeline polling,
//  configurable intervals, pause/resume lifecycle, and exponential error backoff.
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import XKitModels

/// Strongly-typed polling interval presets matching application settings preferences.
public enum PollingInterval: TimeInterval, CaseIterable, Identifiable, Sendable, Codable {
    case fifteenSeconds = 15.0
    case thirtySeconds = 30.0
    case oneMinute = 60.0
    case twoMinutes = 120.0
    case manual = 0.0

    public var id: Double { rawValue }

    public var displayName: String {
        switch self {
        case .fifteenSeconds: return "15 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .manual: return "Manual (Off)"
        }
    }
}

/// Dedicated Swift actor managing background periodic polling for new timeline posts without blocking MainActor.
public actor TimelinePollingEngine: Sendable {
    // MARK: - State Typology
    public enum State: Sendable, Equatable {
        case idle
        case polling
        case paused
        case backingOff(failures: Int, delay: TimeInterval)
    }

    public struct BackoffPolicy: Sendable, Equatable {
        public var baseInterval: TimeInterval
        public var multiplier: Double
        public var maxInterval: TimeInterval

        public init(
            baseInterval: TimeInterval = 30.0,
            multiplier: Double = 1.5,
            maxInterval: TimeInterval = 300.0
        ) {
            self.baseInterval = baseInterval
            self.multiplier = multiplier
            self.maxInterval = maxInterval
        }

        public func calculateDelay(forFailures failures: Int) -> TimeInterval {
            guard failures > 0 else { return baseInterval }
            let calculated = baseInterval * pow(multiplier, Double(failures))
            return min(calculated, maxInterval)
        }
    }

    // MARK: - Isolated Properties
    public private(set) var state: State = .idle
    public private(set) var currentInterval: TimeInterval
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var knownPostIds: Set<String> = []

    private var backoffPolicy: BackoffPolicy
    private let defaultService: (any XClientServiceProtocol)?
    private var pollingTask: Task<Void, Never>?
    private var fetchHandler: (@Sendable () async throws -> [XPost])?
    private var onNewPostsCallback: (@Sendable ([XPost]) async -> Void)?
    private var onErrorCallback: (@Sendable (Error) async -> Void)?

    // MARK: - Initialization
    public init(
        interval: TimeInterval = 30.0,
        backoffPolicy: BackoffPolicy? = nil,
        service: (any XClientServiceProtocol)? = nil
    ) {
        self.currentInterval = interval
        self.backoffPolicy = backoffPolicy ?? BackoffPolicy(baseInterval: interval)
        self.defaultService = service
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Lifecycle Management

    /// Starts or restarts the polling engine with specified handlers.
    public func startPolling(
        interval: TimeInterval? = nil,
        initialKnownIds: [String] = [],
        fetchHandler: @Sendable @escaping () async throws -> [XPost],
        onNewPosts: @Sendable @escaping ([XPost]) async -> Void,
        onError: (@Sendable (Error) async -> Void)? = nil
    ) {
        stopPolling()

        if let interval = interval {
            self.currentInterval = interval
            self.backoffPolicy.baseInterval = interval
        }
        for id in initialKnownIds {
            self.knownPostIds.insert(id)
        }
        self.fetchHandler = fetchHandler
        self.onNewPostsCallback = onNewPosts
        self.onErrorCallback = onError
        self.state = .polling
        self.consecutiveFailures = 0

        guard currentInterval > 0 else {
            // Manual mode: do not schedule background timer loop
            return
        }

        schedulePollingLoop()
    }

    /// Convenience startPolling overload conforming directly to PROJECT.md interface contract.
    public func startPolling(
        interval: TimeInterval,
        onNewPosts: @Sendable @escaping ([XPost]) -> Void
    ) {
        let activeService = self.defaultService
        startPolling(
            interval: interval,
            initialKnownIds: [],
            fetchHandler: {
                if let activeService {
                    return try await activeService.fetchHomeTimeline()
                } else {
                    let service = await MainActor.run { XClientService() }
                    return try await service.fetchHomeTimeline()
                }
            },
            onNewPosts: { posts in onNewPosts(posts) },
            onError: nil
        )
    }

    /// Suspends background timer without clearing known posts or handlers.
    public func pause() {
        guard state == .polling || state != .idle else { return }
        pollingTask?.cancel()
        pollingTask = nil
        state = .paused
    }

    /// Resumes polling if previously paused.
    public func resume() {
        guard state == .paused else { return }
        state = .polling
        guard currentInterval > 0 else { return }
        schedulePollingLoop()
    }

    /// Stops polling completely and frees active background tasks.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        state = .idle
        consecutiveFailures = 0
    }

    /// Alias for stopPolling per interface requirements.
    public func stop() {
        stopPolling()
    }

    /// Dynamically updates polling interval (e.g. from Settings).
    public func updateInterval(_ newInterval: TimeInterval) {
        self.currentInterval = newInterval
        self.backoffPolicy.baseInterval = newInterval
        if state == .polling {
            pollingTask?.cancel()
            if newInterval > 0 {
                schedulePollingLoop()
            }
        }
    }

    /// Registers newly ingested post IDs to prevent duplicate notifications.
    public func recordKnownPostIds(_ ids: [String]) {
        for id in ids {
            knownPostIds.insert(id)
        }
    }

    // MARK: - Single Poll Execution (Interactive & Testing)

    /// Performs a single isolated poll iteration and returns any newly discovered posts.
    @discardableResult
    public func pollOnce() async -> [XPost] {
        guard let fetch = fetchHandler else { return [] }
        do {
            let fetchedPosts = try await fetch()
            guard state != .idle else { return [] }

            consecutiveFailures = 0
            if case .backingOff = state {
                state = .polling
            }

            // Identify posts not previously known
            let newPosts = fetchedPosts.filter { !knownPostIds.contains($0.id) }
            for post in fetchedPosts {
                knownPostIds.insert(post.id)
            }

            if !newPosts.isEmpty, let callback = onNewPostsCallback {
                await callback(newPosts)
            }
            return newPosts
        } catch {
            // Guard against state revival if stopped while fetch was in-flight or task was cancelled
            guard state != .idle, !(error is CancellationError) else { return [] }

            consecutiveFailures += 1
            let nextDelay = backoffPolicy.calculateDelay(forFailures: consecutiveFailures)
            state = .backingOff(failures: consecutiveFailures, delay: nextDelay)

            if let errorCallback = onErrorCallback {
                await errorCallback(error)
            }
            return []
        }
    }

    // MARK: - Internal Loop Scheduling
    private func schedulePollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                let delay: TimeInterval = await self.calculateCurrentSleepDelay()
                if delay <= 0 { break }

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Task cancelled during sleep
                    break
                }

                if Task.isCancelled { break }
                _ = await self.pollOnce()
            }
        }
    }

    private func calculateCurrentSleepDelay() -> TimeInterval {
        switch state {
        case .polling:
            return currentInterval
        case .backingOff(_, let delay):
            return delay
        case .idle, .paused:
            return 0
        }
    }
}
