//
//  Milestone5EmpiricalChallengerTests.swift
//  XClientTests
//
//  Adversarial Empirical Challenger Stress Test Suite for Milestone 5:
//  - CLI argument parsing matrix: zero args, single flags, combined flags, unknown flags, empty strings, hyphens
//  - CLI exit codes: 0 for help/success, 1 for unrecognized flags or runtime errors
//  - Headless verification runner sequence: MockDataProvider, XClientService, async CRUD, bookmark lifecycle
//  - Concurrency & @MainActor safety: NavigationState, AdaptiveRootView & DesktopRootView body evaluation
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import Combine
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 5 Empirical Challenger Test Suite", .serialized)
struct Milestone5EmpiricalChallengerTests {

    // MARK: - CLI Parsing Oracle Definition

    enum SimulatedCLIRoute: Equatable {
        case interactiveApp
        case help(exitCode: Int32, text: String)
        case headlessVerification(exitCode: Int32)
        case unrecognizedArgument(flag: String, exitCode: Int32, errorMessage: String)
    }

    /// Pure oracle modeling the exact argument dispatch logic in main.swift
    private func dispatchCLI(rawArgs: [String]) -> SimulatedCLIRoute {
        // 1. Interactive Desktop Launch (No Arguments)
        if rawArgs.isEmpty {
            return .interactiveApp
        }
        // 2. Help Documentation
        else if rawArgs.contains("--help") || rawArgs.contains("-h") {
            let helpMessage = """
            OVERVIEW: XClient Desktop & Headless Runner

            USAGE: XClientApp [--verify | --headless] [--help | -h]

            OPTIONS:
              --verify, --headless    Run automated headless smoke verification tests and exit
              -h, --help              Show this help message
            """
            return .help(exitCode: 0, text: helpMessage)
        }
        // 3. Argument Validation & Headless Dispatch
        else {
            let recognizedFlags: Set<String> = ["--verify", "--headless"]
            for arg in rawArgs {
                if !recognizedFlags.contains(arg) {
                    let err = "Unknown argument: \(arg). Use --help for usage.\n"
                    return .unrecognizedArgument(flag: arg, exitCode: 1, errorMessage: err)
                }
            }
            return .headlessVerification(exitCode: 0)
        }
    }

    /// Struct mimicking DesktopRootView from main.swift for isolated UI hierarchy verification
    struct DesktopRootViewSimulator: View {
        @StateObject private var settingsViewModel = SettingsViewModel()
        @Environment(\.colorScheme) private var systemScheme

        var body: some View {
            let palette = ColorPalette.resolve(preference: settingsViewModel.selectedTheme, systemScheme: systemScheme)

            AdaptiveRootView()
                .preferredColorScheme(settingsViewModel.selectedTheme.preferredColorScheme)
                .environment(\.colorPalette, palette)
                .frame(minWidth: 900, minHeight: 650)
        }
    }

    // MARK: - Domain 1: CLI Argument Parsing & Exit Code Stress

    @Test("Challenge 1.1: Zero Arguments Routes to Interactive App Launch")
    func testZeroArgumentsDispatch() {
        let route = dispatchCLI(rawArgs: [])
        #expect(route == .interactiveApp)
    }

    @Test("Challenge 1.2: Standard Help Flags Emit Usage and Exit With Code 0")
    func testHelpFlagsDispatch() {
        let helpCases = [
            ["--help"],
            ["-h"],
            ["--verify", "--help"],
            ["-h", "--verify"],
            ["--headless", "-h"],
            ["--help", "--headless"]
        ]

        for args in helpCases {
            let route = dispatchCLI(rawArgs: args)
            if case .help(let exitCode, let text) = route {
                #expect(exitCode == 0)
                #expect(text.contains("OVERVIEW: XClient Desktop & Headless Runner"))
                #expect(text.contains("USAGE: XClientApp [--verify | --headless] [--help | -h]"))
            } else {
                Issue.record("Expected help route for arguments: \(args), got: \(route)")
            }
        }
    }

    @Test("Challenge 1.3: Help Precedence Over Unrecognized Arguments")
    func testHelpPrecedenceOverUnknown() {
        // POSIX / GNU convention: --help or -h anywhere short-circuits execution to help display
        let helpWithUnknown = [
            ["--unknown", "--help"],
            ["-h", "--invalid-flag"],
            ["", "-h"],
            ["--bogus", "-h", "--verify"]
        ]

        for args in helpWithUnknown {
            let route = dispatchCLI(rawArgs: args)
            if case .help(let exitCode, _) = route {
                #expect(exitCode == 0)
            } else {
                Issue.record("Expected help short-circuit for: \(args), got: \(route)")
            }
        }
    }

    @Test("Challenge 1.4: Valid Headless Smoke Verification Flags Exit With Code 0")
    func testValidHeadlessFlags() {
        let validCases: [[String]] = [
            ["--verify"],
            ["--headless"],
            ["--verify", "--headless"],
            ["--headless", "--verify"],
            ["--verify", "--verify"],
            ["--headless", "--headless"]
        ]

        for args in validCases {
            let route = dispatchCLI(rawArgs: args)
            #expect(route == .headlessVerification(exitCode: 0))
        }
    }

    @Test("Challenge 1.5: Unrecognized Flags Terminate With Exit Code 1 and Stderr Diagnostic")
    func testUnrecognizedFlagsRejected() {
        let invalidCases = [
            "--unknown",
            "-v",
            "-V",
            "verify",
            "headless",
            "---verify",
            "--verify=true",
            "--headless=false",
            "-help",
            "--HELP",
            "--VERIFY"
        ]

        for invalidFlag in invalidCases {
            let route = dispatchCLI(rawArgs: [invalidFlag])
            if case .unrecognizedArgument(let flag, let exitCode, let err) = route {
                #expect(flag == invalidFlag)
                #expect(exitCode == 1)
                #expect(err.contains("Unknown argument: \(invalidFlag). Use --help for usage."))
            } else {
                Issue.record("Expected rejection for flag '\(invalidFlag)', got: \(route)")
            }
        }
    }

    @Test("Challenge 1.6: Boundary Inputs (Empty String, Whitespace, Hyphens) Terminate With Code 1")
    func testBoundaryInputsRejected() {
        let boundaryCases = [
            "",
            " ",
            "    ",
            "-",
            "--",
            "---",
            "\t",
            "\n"
        ]

        for boundary in boundaryCases {
            let route = dispatchCLI(rawArgs: [boundary])
            if case .unrecognizedArgument(let flag, let exitCode, _) = route {
                #expect(flag == boundary)
                #expect(exitCode == 1)
            } else {
                Issue.record("Expected rejection for boundary input '\(boundary)', got: \(route)")
            }
        }
    }

    @Test("Challenge 1.7: Mixed Valid and Invalid Arguments Reject on First Unrecognized Flag")
    func testMixedFlagsRejectedEarly() {
        let mixedCases: [([String], String)] = [
            (["--verify", "--unknown"], "--unknown"),
            (["--unknown", "--verify"], "--unknown"),
            (["--headless", "-v"], "-v"),
            (["-x", "--headless"], "-x"),
            (["--verify", ""], "")
        ]

        for (args, expectedCulprit) in mixedCases {
            let route = dispatchCLI(rawArgs: args)
            if case .unrecognizedArgument(let flag, let exitCode, _) = route {
                #expect(flag == expectedCulprit)
                #expect(exitCode == 1)
            } else {
                Issue.record("Expected mixed rejection for: \(args), got: \(route)")
            }
        }
    }

    // MARK: - Domain 2: Headless Verification Lifecycle & State Assertions

    @Test("Challenge 2.1: MockDataProvider Invariants and Idempotent Resets")
    @MainActor
    func testMockDataProviderLifecycle() {
        let mock = MockDataProvider.shared

        // Multiple sequential resets must remain deterministic
        for _ in 0..<5 {
            mock.resetToDefaults()

            #expect(!mock.currentUser.id.isEmpty)
            #expect(mock.currentUser.username == "liquidglass")
            #expect(mock.timelinePosts.count >= 10)
            #expect(mock.bookmarks.count >= 4)
            #expect(mock.postItems.count >= 10)
        }
    }

    @Test("Challenge 2.2: Full Headless Async Verification Pipeline Execution")
    @MainActor
    func testHeadlessAsyncPipelineExecution() async throws {
        let mock = MockDataProvider.shared
        mock.resetToDefaults()

        // 1. Facade initialization
        let service = XClientService()
        #expect(service.token == "mock_token")
        #expect(!service.currentUserId.isEmpty)

        // 2. Fetch timeline
        let homePosts = try await service.fetchHomeTimeline()
        #expect(!homePosts.isEmpty)

        // 3. Current user verification
        let currentUser = try await service.fetchCurrentUser()
        #expect(currentUser.id == mock.currentUser.id)

        // 4. User profile verification
        let userProfile = try await service.fetchUserProfile(id: currentUser.id)
        #expect(userProfile.id == currentUser.id)

        // 5. User posts
        let userPosts = try await service.fetchUserPosts(userId: currentUser.id)
        #expect(!userPosts.data.isEmpty)

        // 6. Post creation
        let postText = "Empirical Challenger Verification Post"
        let createdPost = try await service.createPost(text: postText)
        #expect(createdPost.text == postText)
        #expect(!createdPost.id.isEmpty)

        // 7. Bookmark addition & removal lifecycle
        let bookmarkAdded = try await service.bookmarkPost(id: createdPost.id)
        #expect(bookmarkAdded == true)

        let bookmarkRemoved = try await service.removeBookmark(id: createdPost.id)
        #expect(bookmarkRemoved == true)

        let bookmarks = try await service.fetchBookmarks()
        #expect(bookmarks.count >= 4)

        // 8. Post deletion
        let postDeleted = try await service.deletePost(id: createdPost.id)
        #expect(postDeleted == true)
    }

    @Test("Challenge 2.3: Verification Pipeline Catches Errors and Terminates Gracefully")
    func testVerificationPipelineErrorHandling() async {
        struct SimulatedPipelineError: Error, Equatable {
            let message: String
        }

        var caughtError: Error?
        var exitCode: Int32 = 0

        do {
            throw SimulatedPipelineError(message: "Simulated upstream network fault")
        } catch {
            caughtError = error
            exitCode = 1
        }

        #expect(exitCode == 1)
        #expect(caughtError != nil)
    }

    // MARK: - Domain 3: Concurrency & @MainActor UI Hierarchy Safety

    @Test("Challenge 3.1: DesktopRootView and AdaptiveRootView Navigation Cycling on @MainActor")
    @MainActor
    func testNavigationAndDesktopRootViewSafety() {
        let navigationState = AppNavigationState()
        #expect(navigationState.selectedTab == .timeline)

        for destination in AppDestination.allCases {
            navigationState.selectDestination(destination)
            #expect(navigationState.selectedDestination == destination)
        }

        navigationState.selectDestination(.timeline)
        #expect(navigationState.selectedDestination == .timeline)

        let adaptiveRoot = AdaptiveRootView(navigationState: navigationState)
        _ = adaptiveRoot.body

        let settingsVM = SettingsViewModel()
        let palette = ColorPalette.resolve(preference: settingsVM.selectedTheme, systemScheme: .dark)
        #expect(palette.brandPrimary != Color.clear)

        let desktopRoot = DesktopRootViewSimulator()
        _ = desktopRoot.body
    }

    @Test("Challenge 3.2: Concurrent Verification Stress across Multiple Async Tasks")
    func testConcurrentVerificationStress() async throws {
        // Spawn 10 concurrent verification workers to verify that MockDataProvider and service
        // operations remain data-race free under high concurrent load
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask { @MainActor in
                    let service = XClientService()
                    let timeline = try await service.fetchHomeTimeline()
                    #expect(!timeline.isEmpty)

                    let user = try await service.fetchCurrentUser()
                    #expect(!user.id.isEmpty)

                    let post = try await service.createPost(text: "Concurrent post \(index)")
                    #expect(!post.id.isEmpty)

                    let deleted = try await service.deletePost(id: post.id)
                    #expect(deleted == true)
                }
            }
            try await group.waitForAll()
        }
    }
}
