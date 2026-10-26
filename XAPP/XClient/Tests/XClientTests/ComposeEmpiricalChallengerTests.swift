//
//  ComposeEmpiricalChallengerTests.swift
//  XClientTests
//
//  Empirical Challenger Stress Test Suite for Milestone 4 (Post Composer):
//  - 280-character boundary math progression (0, 1, 259, 260, 279, 280, 281, 10,000+ chars)
//  - Gauge status enum evaluation, progress float clamping [0.0, 1.0], negative remaining text
//  - Whitespace-only rejection (spaces, newlines, tabs, zero-width chars)
//  - Media attachment limits (max 4 photos, video replacement, duplicate URL/ID handling, removal)
//  - Draft persistence across view model lifecycle (UserDefaults and in-memory roundtrips)
//  - Discard confirmation triggers and reset logic
//  - Swift 6 strict concurrency and double-publish race defenses
//

import Testing
import Foundation
import SwiftUI
@testable import XClient
import XKitModels
import XKitAPI

@Suite("Milestone 4: Post Composer Empirical Challenger Stress Tests", .serialized)
struct ComposeEmpiricalChallengerTests {

    // MARK: - Test Storage Double
    private final class MockChallengerDraftStorage: DraftStorageProtocol, @unchecked Sendable {
        private let lock = NSLock()
        var activeDraft: ComposeDraft?
        var drafts: [ComposeDraft] = []

        func saveActiveDraft(_ draft: ComposeDraft) {
            lock.lock()
            defer { lock.unlock() }
            activeDraft = draft
        }

        func loadActiveDraft() -> ComposeDraft? {
            lock.lock()
            defer { lock.unlock() }
            return activeDraft
        }

        func clearActiveDraft() {
            lock.lock()
            defer { lock.unlock() }
            activeDraft = nil
        }

        func listDrafts() -> [ComposeDraft] {
            lock.lock()
            defer { lock.unlock() }
            return drafts
        }

        func saveDraftToList(_ draft: ComposeDraft) {
            lock.lock()
            defer { lock.unlock() }
            drafts.removeAll { $0.id == draft.id }
            drafts.insert(draft, at: 0)
        }

        func deleteDraft(id: UUID) {
            lock.lock()
            defer { lock.unlock() }
            drafts.removeAll { $0.id == id }
        }
    }

    // MARK: - 1. 280-Character Boundary Mathematics Progression

    @Test("EC-1.1: Boundary Progression at Exactly 0 Characters")
    @MainActor
    func testBoundaryZeroCharacters() {
        let node = ComposeNode(text: "")
        #expect(node.characterCount == 0)
        #expect(node.remainingCharacters == 280)
        #expect(node.progressRatio == 0.0)
        #expect(node.clampedProgress == 0.0)
        #expect(node.gaugeStatus == .normal)
        #expect(node.gaugeStatus.showsRemainingCount == false)
        #expect(node.isWarning == false)
        #expect(node.isOverLimit == false)
        #expect(node.isEmpty == true)
        #expect(node.isValid == false)
    }

    @Test("EC-1.2: Boundary Progression at Exactly 1 Character")
    @MainActor
    func testBoundaryOneCharacter() {
        let node = ComposeNode(text: "A")
        #expect(node.characterCount == 1)
        #expect(node.remainingCharacters == 279)
        #expect(abs(node.progressRatio - (1.0 / 280.0)) < 1e-6)
        #expect(abs(node.clampedProgress - (1.0 / 280.0)) < 1e-6)
        #expect(node.gaugeStatus == .normal)
        #expect(node.gaugeStatus.showsRemainingCount == false)
        #expect(node.isWarning == false)
        #expect(node.isOverLimit == false)
        #expect(node.isEmpty == false)
        #expect(node.isValid == true)
    }

    @Test("EC-1.3: Boundary Progression at 259 Characters (Sub-Warning Upper Boundary)")
    @MainActor
    func testBoundary259Characters() {
        let node = ComposeNode(text: String(repeating: "x", count: 259))
        #expect(node.characterCount == 259)
        #expect(node.remainingCharacters == 21)
        #expect(abs(node.progressRatio - (259.0 / 280.0)) < 1e-6)
        #expect(abs(node.clampedProgress - (259.0 / 280.0)) < 1e-6)
        #expect(node.gaugeStatus == .normal)
        #expect(node.gaugeStatus.showsRemainingCount == false)
        #expect(node.isWarning == false)
        #expect(node.isOverLimit == false)
        #expect(node.isValid == true)
    }

    @Test("EC-1.4: Boundary Progression at 260 Characters (Warning Threshold Entry)")
    @MainActor
    func testBoundary260Characters() {
        let node = ComposeNode(text: String(repeating: "w", count: 260))
        #expect(node.characterCount == 260)
        #expect(node.remainingCharacters == 20)
        #expect(abs(node.progressRatio - (260.0 / 280.0)) < 1e-6)
        #expect(abs(node.clampedProgress - (260.0 / 280.0)) < 1e-6)
        #expect(node.gaugeStatus == .warning)
        #expect(node.gaugeStatus.showsRemainingCount == true)
        #expect(node.isWarning == true)
        #expect(node.isOverLimit == false)
        #expect(node.isValid == true)
    }

    @Test("EC-1.5: Boundary Progression at 279 Characters (Warning Maximum)")
    @MainActor
    func testBoundary279Characters() {
        let node = ComposeNode(text: String(repeating: "w", count: 279))
        #expect(node.characterCount == 279)
        #expect(node.remainingCharacters == 1)
        #expect(abs(node.progressRatio - (279.0 / 280.0)) < 1e-6)
        #expect(abs(node.clampedProgress - (279.0 / 280.0)) < 1e-6)
        #expect(node.gaugeStatus == .warning)
        #expect(node.gaugeStatus.showsRemainingCount == true)
        #expect(node.isWarning == true)
        #expect(node.isOverLimit == false)
        #expect(node.isValid == true)
    }

    @Test("EC-1.6: Boundary Progression at Exactly 280 Characters (Full Limit)")
    @MainActor
    func testBoundary280Characters() {
        let node = ComposeNode(text: String(repeating: "L", count: 280))
        #expect(node.characterCount == 280)
        #expect(node.remainingCharacters == 0)
        #expect(node.progressRatio == 1.0)
        #expect(node.clampedProgress == 1.0)
        #expect(node.gaugeStatus == .atLimit)
        #expect(node.gaugeStatus.showsRemainingCount == true)
        #expect(node.isOverLimit == false)
        #expect(node.isValid == true)
    }

    @Test("EC-1.7: Boundary Progression at 281 Characters (Single Char Overage)")
    @MainActor
    func testBoundary281Characters() {
        let node = ComposeNode(text: String(repeating: "O", count: 281))
        #expect(node.characterCount == 281)
        #expect(node.remainingCharacters == -1)
        #expect(node.progressRatio > 1.0)
        #expect(node.clampedProgress == 1.0) // Must remain clamped at 1.0
        #expect(node.gaugeStatus == .overage)
        #expect(node.gaugeStatus.showsRemainingCount == true)
        #expect(node.isOverLimit == true)
        #expect(node.isValid == false)
    }

    @Test("EC-1.8: Boundary Progression at 10,000+ Characters (Massive Overage)")
    @MainActor
    func testBoundary10000Characters() {
        let node10k = ComposeNode(text: String(repeating: "Z", count: 10_000))
        #expect(node10k.characterCount == 10_000)
        #expect(node10k.remainingCharacters == -9720)
        #expect(abs(node10k.progressRatio - (10_000.0 / 280.0)) < 1e-6)
        #expect(node10k.clampedProgress == 1.0)
        #expect(node10k.gaugeStatus == .overage)
        #expect(node10k.gaugeStatus.showsRemainingCount == true)
        #expect(node10k.isOverLimit == true)
        #expect(node10k.isValid == false)

        // 50,000 character extreme stress
        let node50k = ComposeNode(text: String(repeating: "M", count: 50_000))
        #expect(node50k.characterCount == 50_000)
        #expect(node50k.remainingCharacters == -49_720)
        #expect(node50k.clampedProgress == 1.0)
        #expect(node50k.gaugeStatus == .overage)
        #expect(node50k.isValid == false)
    }

    @Test("EC-1.9: Warning Threshold Exact Invariant at 280 Characters")
    @MainActor
    func testWarningThresholdExactInvariantAt280() {
        let node279 = ComposeNode(text: String(repeating: "w", count: 279))
        #expect(node279.isWarning == true)
        #expect(node279.gaugeStatus == .warning)

        let node280 = ComposeNode(text: String(repeating: "L", count: 280))
        #expect(node280.gaugeStatus == .atLimit)
        #expect(node280.isWarning == false, "DEFECT: node.isWarning evaluates to true at 280 characters, contradicting gaugeStatus == .atLimit!")
    }

    // MARK: - 2. Negative Remaining Counts & Formatted Strings

    @Test("EC-2.1: Negative Counts String Formatting and Countdown Text")
    @MainActor
    func testNegativeCountsStringFormatting() {
        let node281 = ComposeNode(text: String(repeating: "A", count: 281))
        #expect("\(node281.remainingCharacters)" == "-1")

        let node300 = ComposeNode(text: String(repeating: "A", count: 300))
        #expect("\(node300.remainingCharacters)" == "-20")

        let node10k = ComposeNode(text: String(repeating: "A", count: 10_000))
        #expect("\(node10k.remainingCharacters)" == "-9720")

        let node50k = ComposeNode(text: String(repeating: "A", count: 50_000))
        #expect("\(node50k.remainingCharacters)" == "-49720")
    }

    // MARK: - 3. Whitespace-Only Submission Rejections

    @Test("EC-3.1: Whitespace-Only Text Rejections (Spaces, Newlines, Tabs)")
    @MainActor
    func testWhitespaceOnlyTextRejections() async {
        let whitespaces: [String] = [
            " ",
            "      ",
            "\t",
            "\t\t\t",
            "\n",
            "\n\n\n",
            "\r\n\r\n",
            "   \t   \n   \r   \n   ",
            "\u{00A0} \u{00A0}", // Non-breaking spaces
            "\u{2003}\u{2009}"    // Unicode spaces
        ]

        let service = MockClientService()
        let storage = MockChallengerDraftStorage()

        for (index, ws) in whitespaces.enumerated() {
            let node = ComposeNode(text: ws)
            #expect(node.isEmpty == true, "Whitespace case \(index) failed: '\(ws)' not empty")
            #expect(node.isValid == false, "Whitespace case \(index) failed: '\(ws)' was valid")

            let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)
            vm.updateNodeText(id: vm.nodes[0].id, text: ws)
            #expect(vm.isThreadValid == false)

            let success = await vm.publishThread()
            #expect(success == false, "Whitespace case \(index) succeeded publishing")
        }
    }

    @Test("EC-3.2: Multi-Node Thread With Empty or Whitespace Node Rejects Publish")
    @MainActor
    func testThreadWithWhitespaceNodeRejectsPublish() async {
        let service = MockClientService()
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Valid tweet text")
        vm.addNode()
        vm.updateNodeText(id: vm.nodes[1].id, text: "   \t\n   ")

        #expect(vm.isThreadValid == false)
        let success = await vm.publishThread()
        #expect(success == false)
        #expect(service.createdPosts.isEmpty)
    }

    @Test("EC-3.3: Empty Text Node with Attached Media IS Valid")
    @MainActor
    func testEmptyTextWithMediaIsValid() async {
        let service = MockClientService()
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.addAttachment(to: vm.nodes[0].id, attachment: .samplePhoto)
        #expect(vm.nodes[0].isEmpty == false)
        #expect(vm.nodes[0].isValid == true)
        #expect(vm.isThreadValid == true)

        let success = await vm.publishThread()
        #expect(success == true)
        #expect(service.createdPosts.count == 1)
    }

    // MARK: - 4. Media Attachment Constraints, Duplicates, and Removal

    @Test("EC-4.1: Media Attachment Cap (0, 1, 4 items and 5th Rejection)")
    @MainActor
    func testMediaAttachmentCap() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        #expect(vm.nodes[0].mediaAttachments.count == 0)

        let p1 = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)
        let p2 = MediaAttachment(id: "p2", url: URL(string: "https://example.com/p2.jpg")!, type: .photo)
        let p3 = MediaAttachment(id: "p3", url: URL(string: "https://example.com/p3.jpg")!, type: .photo)
        let p4 = MediaAttachment(id: "p4", url: URL(string: "https://example.com/p4.jpg")!, type: .photo)
        let p5 = MediaAttachment(id: "p5", url: URL(string: "https://example.com/p5.jpg")!, type: .photo)

        vm.addAttachment(to: nodeId, attachment: p1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        vm.addAttachment(to: nodeId, attachment: p2)
        vm.addAttachment(to: nodeId, attachment: p3)
        vm.addAttachment(to: nodeId, attachment: p4)
        #expect(vm.nodes[0].mediaAttachments.count == 4)

        // Attempt 5th item
        vm.addAttachment(to: nodeId, attachment: p5)
        #expect(vm.nodes[0].mediaAttachments.count == 4)
        #expect(vm.nodes[0].mediaAttachments.contains(where: { $0.id == "p5" }) == false)
    }

    @Test("EC-4.2: Media Attachment Video Mutual Exclusivity")
    @MainActor
    func testMediaVideoMutualExclusivity() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let p1 = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)
        let p2 = MediaAttachment(id: "p2", url: URL(string: "https://example.com/p2.jpg")!, type: .photo)
        let v1 = MediaAttachment(id: "v1", url: URL(string: "https://example.com/v1.mp4")!, type: .video)

        vm.addAttachment(to: nodeId, attachment: p1)
        vm.addAttachment(to: nodeId, attachment: p2)
        #expect(vm.nodes[0].mediaAttachments.count == 2)

        // Adding video replaces photos
        vm.addAttachment(to: nodeId, attachment: v1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].type == .video)

        // Adding photo replaces video
        vm.addAttachment(to: nodeId, attachment: p1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].type == .photo)
    }

    @Test("EC-4.3: Media Attachment Removal by Attachment ID")
    @MainActor
    func testMediaAttachmentRemoval() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let p1 = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)
        let p2 = MediaAttachment(id: "p2", url: URL(string: "https://example.com/p2.jpg")!, type: .photo)

        vm.addAttachment(to: nodeId, attachment: p1)
        vm.addAttachment(to: nodeId, attachment: p2)
        #expect(vm.nodes[0].mediaAttachments.count == 2)

        vm.removeAttachment(from: nodeId, attachmentId: "p1")
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].id == "p2")

        // Removing non-existent ID is safe no-op
        vm.removeAttachment(from: nodeId, attachmentId: "ghost_id")
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        vm.removeAttachment(from: nodeId, attachmentId: "p2")
        #expect(vm.nodes[0].mediaAttachments.isEmpty)
    }

    @Test("EC-4.4: Duplicate Media Attachment URL and ID Rejection")
    @MainActor
    func testDuplicateMediaAttachmentHandling() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let photo1 = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)
        let photo1DuplicateId = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1_diff.jpg")!, type: .photo)
        let photo1DuplicateUrl = MediaAttachment(id: "p2", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)

        vm.addAttachment(to: nodeId, attachment: photo1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // Attempt duplicate ID
        vm.addAttachment(to: nodeId, attachment: photo1DuplicateId)
        #expect(vm.nodes[0].mediaAttachments.count == 1, "DEFECT: addAttachment allowed duplicate attachment ID into mediaAttachments!")

        // Attempt duplicate URL
        vm.addAttachment(to: nodeId, attachment: photo1DuplicateUrl)
        #expect(vm.nodes[0].mediaAttachments.count == 1, "DEFECT: addAttachment allowed duplicate attachment URL into mediaAttachments!")
    }

    // MARK: - 5. Draft Persistence Across ViewModel Lifecycle

    @Test("EC-5.1: Draft Persistence Across ViewModel Lifecycle with Mock Storage")
    @MainActor
    func testDraftPersistenceAcrossLifecycle() {
        let storage = MockChallengerDraftStorage()

        // Phase 1: Draft initial thread
        do {
            let vm1 = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
            vm1.updateNodeText(id: vm1.nodes[0].id, text: "Initial thread post")
            vm1.addAttachment(to: vm1.nodes[0].id, attachment: .samplePhoto)
            vm1.addNode()
            vm1.updateNodeText(id: vm1.nodes[1].id, text: "Second thread post")
            vm1.persistActiveDraft()

            #expect(storage.activeDraft != nil)
            #expect(storage.activeDraft?.nodes.count == 2)
        }

        // Phase 2: Restore in new ViewModel instance
        do {
            let vm2 = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: true)
            #expect(vm2.nodes.count == 2)
            #expect(vm2.nodes[0].text == "Initial thread post")
            #expect(vm2.nodes[0].mediaAttachments.count == 1)
            #expect(vm2.nodes[1].text == "Second thread post")
            #expect(vm2.isDirty == true)

            // Save to drafts list
            vm2.saveCurrentAsDraft()
            #expect(storage.activeDraft == nil)
            #expect(storage.drafts.count == 1)
            #expect(storage.drafts[0].previewText.contains("Initial thread post"))
            #expect(vm2.isDirty == false)
            #expect(vm2.nodes.count == 1)
        }

        // Phase 3: Restore saved draft from list
        do {
            let vm3 = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
            let saved = storage.drafts[0]
            vm3.restoreDraft(saved)
            #expect(vm3.nodes.count == 2)
            #expect(vm3.nodes[0].text == "Initial thread post")

            // Discard draft
            vm3.discardDraft()
            #expect(storage.activeDraft == nil)
            #expect(vm3.isDirty == false)
            #expect(vm3.nodes.count == 1)
            #expect(vm3.nodes[0].text.isEmpty)
        }
    }

    @Test("EC-5.2: UserDefaults-Backed Draft Storage Round-Trip and Deletion")
    @MainActor
    func testUserDefaultsDraftStorageRoundTrip() {
        let suiteName = "xclient.challenger.drafts.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated UserDefaults")
            return
        }
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let storage = UserDefaultsDraftStorage(userDefaults: userDefaults)
        #expect(storage.loadActiveDraft() == nil)
        #expect(storage.listDrafts().isEmpty)

        let node = ComposeNode(text: "Persisted draft text", mediaAttachments: [.samplePhoto])
        let draft = ComposeDraft(nodes: [node])

        // Save active
        storage.saveActiveDraft(draft)
        let loaded = storage.loadActiveDraft()
        #expect(loaded != nil)
        #expect(loaded?.nodes.count == 1)
        #expect(loaded?.nodes[0].text == "Persisted draft text")

        // Save to list
        storage.saveDraftToList(draft)
        let list = storage.listDrafts()
        #expect(list.count == 1)
        #expect(list[0].id == draft.id)

        // Delete from list
        storage.deleteDraft(id: draft.id)
        #expect(storage.listDrafts().isEmpty)

        // Clear active
        storage.clearActiveDraft()
        #expect(storage.loadActiveDraft() == nil)
    }

    // MARK: - 6. Discard Confirmation Logic & isDirty State

    @Test("EC-6.1: Discard Confirmation isDirty Transitions")
    @MainActor
    func testDiscardConfirmationIsDirtyTransitions() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        // Initial blank state: not dirty
        #expect(vm.isDirty == false)

        // Whitespace only: not dirty (no confirmation needed)
        vm.updateNodeText(id: vm.nodes[0].id, text: "   \t\n  ")
        #expect(vm.isDirty == false)

        // Meaningful text: dirty (confirmation needed)
        vm.updateNodeText(id: vm.nodes[0].id, text: "Important post")
        #expect(vm.isDirty == true)

        // Clear text: not dirty
        vm.updateNodeText(id: vm.nodes[0].id, text: "")
        #expect(vm.isDirty == false)

        // Media only: dirty even without text
        vm.addAttachment(to: vm.nodes[0].id, attachment: .samplePhoto)
        #expect(vm.isDirty == true)

        // Remove media: not dirty
        vm.removeAttachment(from: vm.nodes[0].id, attachmentId: MediaAttachment.samplePhoto.id)
        #expect(vm.isDirty == false)
    }

    // MARK: - 7. Concurrency & Swift 6 Race Protection

    @Test("EC-7.1: Double-Publish Concurrency Race Protection")
    @MainActor
    func testDoublePublishConcurrencyRaceProtection() async {
        final class LatencyMockService: XClientServiceProtocol, @unchecked Sendable {
            var calls = 0
            func fetchHomeTimeline() async throws -> [XPost] { [] }
            func fetchUserProfile(id: String) async throws -> XUser { throw XKitError.networkError }
            func bookmarkPost(id: String) async throws -> Bool { true }
            func removeBookmark(id: String) async throws -> Bool { true }
            func fetchHomeTimeline(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> { PaginatedResponse(data: []) }
            func fetchUserPosts(userId: String, paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> { PaginatedResponse(data: []) }
            func fetchBookmarks(paginationToken: String?, maxResults: Int) async throws -> PaginatedResponse<XPost> { PaginatedResponse(data: []) }
            func deletePost(id: String) async throws -> Bool { true }
            func fetchCurrentUser() async throws -> XUser { throw XKitError.networkError }

            func createPost(text: String) async throws -> XPost {
                try await Task.sleep(nanoseconds: 30_000_000) // 30ms latency
                calls += 1
                return XPost(id: "created_\(calls)", text: text, authorId: "me", createdAt: Date(), conversationId: nil)
            }
        }

        let service = LatencyMockService()
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Simultaneous double-click post")

        async let call1 = vm.publishThread()
        async let call2 = vm.publishThread()

        let (r1, r2) = await (call1, call2)
        let successCount = [r1, r2].filter { $0 }.count

        #expect(successCount == 1, "Expected exactly 1 publish call to succeed, but got \(successCount)")
        #expect(service.calls == 1, "Service called \(service.calls) times instead of 1")
    }

    @Test("EC-7.2: Rapid High-Frequency Text and Node Mutations")
    @MainActor
    func testRapidMutationsUnderConcurrency() {
        let storage = MockChallengerDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        for i in 0..<50 {
            vm.updateNodeText(id: vm.activeNodeId, text: "Text iteration \(i)")
            if i % 10 == 0 {
                vm.addNode()
            }
        }

        #expect(vm.nodes.count == 6)
        #expect(vm.isDirty == true)
        #expect(storage.activeDraft?.nodes.count == 6)

        vm.resetComposer()
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text.isEmpty)
    }
}
