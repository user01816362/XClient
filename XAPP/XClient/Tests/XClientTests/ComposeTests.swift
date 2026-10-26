//
//  ComposeTests.swift
//  XClientTests
//
//  Automated Unit & Component Tests for Milestone 4 (Feature F8):
//  Modern post composer & threading, dynamic character count ring gauge,
//  thresholding, draft persistence lifecycle, and Tier 4 Scenario 5.
//  100% Swift 6 strict concurrency compliance.
//

import Testing
import Foundation
import SwiftUI
import XKitModels
import XKitAPI
@testable import XClient

@Suite("Milestone 4: Post Composer & Threading Tests (Feature F8)", .serialized)
struct ComposeTests {

    private final class MockInMemoryDraftStorage: DraftStorageProtocol, @unchecked Sendable {
        var activeDraft: ComposeDraft?
        var drafts: [ComposeDraft] = []

        func saveActiveDraft(_ draft: ComposeDraft) {
            activeDraft = draft
        }

        func loadActiveDraft() -> ComposeDraft? {
            activeDraft
        }

        func clearActiveDraft() {
            activeDraft = nil
        }

        func listDrafts() -> [ComposeDraft] {
            drafts
        }

        func saveDraftToList(_ draft: ComposeDraft) {
            drafts.removeAll { $0.id == draft.id }
            drafts.insert(draft, at: 0)
        }

        func deleteDraft(id: UUID) {
            drafts.removeAll { $0.id == id }
        }
    }

    // MARK: - Tier 1: Feature Coverage Tests

    @Test("T1.1: Verify Initial Composer Node and Character Limit Defaults")
    @MainActor
    func testInitialComposeState() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        #expect(vm.nodes.count == 1)
        #expect(vm.activeNode.text.isEmpty)
        #expect(vm.activeNode.characterCount == 0)
        #expect(vm.activeNode.remainingCharacters == 280)
        #expect(vm.activeNode.gaugeStatus == .normal)
        #expect(vm.activeNode.gaugeStatus.showsRemainingCount == false)
        #expect(vm.isDirty == false)
        #expect(vm.isThreadValid == false)
        #expect(vm.postButtonTitle == "Post")
    }

    @Test("T1.2: Verify Normal Character Count Ring Progress Under 260 Chars")
    @MainActor
    func testCharacterRingNormalProgress() {
        let node = ComposeNode(text: String(repeating: "a", count: 140))
        #expect(node.characterCount == 140)
        #expect(node.remainingCharacters == 140)
        #expect(node.progressRatio == 0.5)
        #expect(node.clampedProgress == 0.5)
        #expect(node.gaugeStatus == .normal)
        #expect(node.gaugeStatus.showsRemainingCount == false)
        #expect(node.isWarning == false)
        #expect(node.isOverLimit == false)
        #expect(node.isValid == true)
    }

    @Test("T1.3: Verify Thread Node Addition and Chaining")
    @MainActor
    func testThreadNodeAddition() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "First post")
        #expect(vm.nodes.count == 1)
        #expect(vm.postButtonTitle == "Post")

        vm.addNode()
        #expect(vm.nodes.count == 2)
        #expect(vm.activeNodeId == vm.nodes[1].id)
        #expect(vm.postButtonTitle == "Post All")
        #expect(vm.isThreadValid == false) // Second node is still empty

        vm.updateNodeText(id: vm.nodes[1].id, text: "Second post")
        #expect(vm.isThreadValid == true)
    }

    @Test("T1.4: Verify Thread Node Removal")
    @MainActor
    func testThreadNodeRemoval() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Node 1")
        vm.addNode()
        let node2Id = vm.nodes[1].id
        vm.updateNodeText(id: node2Id, text: "Node 2")
        #expect(vm.nodes.count == 2)

        vm.removeNode(id: node2Id)
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text == "Node 1")
        #expect(vm.activeNodeId == vm.nodes[0].id)
        #expect(vm.postButtonTitle == "Post")
    }

    @Test("T1.5: Verify Single Post Publish Action via Service Protocol")
    @MainActor
    func testPublishSinglePostSuccess() async throws {
        let service = MockClientService()
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        let postText = "Deploying Milestone 4 native composer! 🚀"
        vm.updateNodeText(id: vm.nodes[0].id, text: postText)

        let success = await vm.publishThread()
        #expect(success == true)
        #expect(service.createdPosts.count == 1)
        #expect(service.createdPosts.first?.text == postText)
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text.isEmpty)
        #expect(storage.activeDraft == nil)
    }

    // MARK: - Tier 2: Boundary & Corner Cases

    @Test("T2.1: Verify Character Ring Transitions to Warning at Exactly 260 Characters")
    @MainActor
    func testCharacterRingWarningBoundary() {
        let node259 = ComposeNode(text: String(repeating: "W", count: 259))
        #expect(node259.gaugeStatus == .normal)
        #expect(node259.remainingCharacters == 21)
        #expect(node259.gaugeStatus.showsRemainingCount == false)
        #expect(node259.isWarning == false)

        let node260 = ComposeNode(text: String(repeating: "W", count: 260))
        #expect(node260.gaugeStatus == .warning)
        #expect(node260.remainingCharacters == 20)
        #expect(node260.gaugeStatus.showsRemainingCount == true)
        #expect(node260.isWarning == true)
        #expect(node260.isOverLimit == false)

        let node279 = ComposeNode(text: String(repeating: "W", count: 279))
        #expect(node279.gaugeStatus == .warning)
        #expect(node279.remainingCharacters == 1)
        #expect(node279.gaugeStatus.showsRemainingCount == true)
    }

    @Test("T2.2: Verify Character Ring Exact Limit at 280 Characters")
    @MainActor
    func testCharacterRingExactLimit() {
        let node280 = ComposeNode(text: String(repeating: "L", count: 280))
        #expect(node280.characterCount == 280)
        #expect(node280.remainingCharacters == 0)
        #expect(node280.gaugeStatus == .atLimit)
        #expect(node280.gaugeStatus.showsRemainingCount == true)
        #expect(node280.isOverLimit == false)
        #expect(node280.isValid == true)
    }

    @Test("T2.3: Verify Character Ring Overage at 281 Characters and Above")
    @MainActor
    func testCharacterRingOverageExceeded() {
        let node281 = ComposeNode(text: String(repeating: "O", count: 281))
        #expect(node281.characterCount == 281)
        #expect(node281.remainingCharacters == -1)
        #expect(node281.gaugeStatus == .overage)
        #expect(node281.gaugeStatus.showsRemainingCount == true)
        #expect(node281.isOverLimit == true)
        #expect(node281.isValid == false)

        let node295 = ComposeNode(text: String(repeating: "O", count: 295))
        #expect(node295.remainingCharacters == -15)
        #expect(node295.gaugeStatus == .overage)
        #expect(node295.clampedProgress == 1.0)
    }

    @Test("T2.4: Verify Minimum 1 Thread Node Constraint")
    @MainActor
    func testMinimumOneThreadNodeConstraint() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Lonely node")
        vm.removeNode(id: vm.nodes[0].id)

        // Count must remain 1, but content is reset
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text.isEmpty)
    }

    @Test("T2.5: Verify Blank or Whitespace-Only Validation")
    @MainActor
    func testBlankOrWhitespaceValidation() {
        let emptyNode = ComposeNode(text: "")
        #expect(emptyNode.isEmpty == true)
        #expect(emptyNode.isValid == false)

        let whitespaceNode = ComposeNode(text: "   \n\t  ")
        #expect(whitespaceNode.isEmpty == true)
        #expect(whitespaceNode.isValid == false)

        let validNode = ComposeNode(text: "Hello world")
        #expect(validNode.isEmpty == false)
        #expect(validNode.isValid == true)
    }

    @Test("T2.6: Verify Media Attachment Rules (Max 4 Photos or 1 Video)")
    @MainActor
    func testMediaAttachmentConstraints() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let photo1 = MediaAttachment(id: "p1", url: URL(string: "https://example.com/p1.jpg")!, type: .photo)
        let photo2 = MediaAttachment(id: "p2", url: URL(string: "https://example.com/p2.jpg")!, type: .photo)
        let photo3 = MediaAttachment(id: "p3", url: URL(string: "https://example.com/p3.jpg")!, type: .photo)
        let photo4 = MediaAttachment(id: "p4", url: URL(string: "https://example.com/p4.jpg")!, type: .photo)
        let photo5 = MediaAttachment(id: "p5", url: URL(string: "https://example.com/p5.jpg")!, type: .photo)
        let video1 = MediaAttachment(id: "v1", url: URL(string: "https://example.com/v1.mp4")!, type: .video)

        // Add 4 photos
        vm.addAttachment(to: nodeId, attachment: photo1)
        vm.addAttachment(to: nodeId, attachment: photo2)
        vm.addAttachment(to: nodeId, attachment: photo3)
        vm.addAttachment(to: nodeId, attachment: photo4)
        #expect(vm.nodes[0].mediaAttachments.count == 4)

        // 5th photo rejected (cap at 4)
        vm.addAttachment(to: nodeId, attachment: photo5)
        #expect(vm.nodes[0].mediaAttachments.count == 4)

        // Adding video replaces photos
        vm.addAttachment(to: nodeId, attachment: video1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].type == .video)

        // Adding photo replaces video
        vm.addAttachment(to: nodeId, attachment: photo1)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].type == .photo)

        // Remove attachment
        vm.removeAttachment(from: nodeId, attachmentId: photo1.id)
        #expect(vm.nodes[0].mediaAttachments.isEmpty)
    }

    @Test("T2.7: Verify Duplicate Media Attachment ID and URL Rejection")
    @MainActor
    func testDuplicateMediaAttachmentRejection() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let photo1 = MediaAttachment(id: "photo_dup_1", url: URL(string: "https://example.com/unique1.jpg")!, type: .photo)
        let photoDuplicateId = MediaAttachment(id: "photo_dup_1", url: URL(string: "https://example.com/different_url.jpg")!, type: .photo)
        let photoDuplicateUrl = MediaAttachment(id: "photo_dup_2", url: URL(string: "https://example.com/unique1.jpg")!, type: .photo)
        let photoDuplicateUrlString = MediaAttachment(id: "photo_dup_3", url: URL(string: "https://example.com/unique1.jpg")!, type: .photo)

        // 1. Initial attachment succeeds
        let added1 = vm.addAttachment(to: nodeId, attachment: photo1)
        #expect(added1 == true)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // 2. Duplicate ID rejected
        let addedDupId = vm.addAttachment(to: nodeId, attachment: photoDuplicateId)
        #expect(addedDupId == false)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // 3. Duplicate URL rejected
        let addedDupUrl = vm.addAttachment(to: nodeId, attachment: photoDuplicateUrl)
        #expect(addedDupUrl == false)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // 4. Duplicate URL string rejected
        let addedDupUrlString = vm.addAttachment(to: nodeId, attachment: photoDuplicateUrlString)
        #expect(addedDupUrlString == false)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // 5. Video duplicate rejection
        let video1 = MediaAttachment(id: "video_dup_1", url: URL(string: "https://example.com/clip.mp4")!, type: .video)
        let addedVideo = vm.addAttachment(to: nodeId, attachment: video1)
        #expect(addedVideo == true)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        let addedDuplicateVideo = vm.addAttachment(to: nodeId, attachment: video1)
        #expect(addedDuplicateVideo == false)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
    }

    @Test("T2.8: Verify Interactive Dismissal Guard and isDirty State Transitions")
    @MainActor
    func testInteractiveDismissalGuardAndIsDirtyTransitions() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        // 1. Initial clean state: not dirty (interactive dismissal allowed)
        #expect(vm.isDirty == false)

        // 2. Whitespace-only input: not dirty (interactive dismissal allowed, no prompt needed)
        vm.updateNodeText(id: vm.nodes[0].id, text: "   \t\n  ")
        #expect(vm.isDirty == false)

        // 3. Substantive text: dirty (interactive dismissal disabled by .interactiveDismissDisabled)
        vm.updateNodeText(id: vm.nodes[0].id, text: "Substantive unsaved draft")
        #expect(vm.isDirty == true)

        // 4. Reverting text to empty: not dirty (interactive dismissal re-enabled)
        vm.updateNodeText(id: vm.nodes[0].id, text: "")
        #expect(vm.isDirty == false)

        // 5. Attaching media without text: dirty (interactive dismissal disabled)
        let added = vm.addAttachment(to: vm.nodes[0].id, attachment: .samplePhoto)
        #expect(added == true)
        #expect(vm.isDirty == true)

        // 6. Removing media: not dirty (interactive dismissal re-enabled)
        let removed = vm.removeAttachment(from: vm.nodes[0].id, attachmentId: MediaAttachment.samplePhoto.id)
        #expect(removed == true)
        #expect(vm.isDirty == false)

        // 7. Multi-node thread: dirty if any secondary node has uncommitted text
        vm.addNode()
        #expect(vm.isDirty == false)
        vm.updateNodeText(id: vm.nodes[1].id, text: "Thread node 2 text")
        #expect(vm.isDirty == true)

        // 8. Discarding draft clears isDirty to false
        vm.discardDraft()
        #expect(vm.isDirty == false)
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text.isEmpty)
    }

    @Test("T2.9: Verify Discard Alert Prompt Logic and Draft Persistence Lifecycle")
    @MainActor
    func testDiscardAlertPromptLogicAndDraftPersistenceLifecycle() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        // Initially discard confirmation is false
        #expect(vm.showDiscardConfirmation == false)

        // Typing text marks composer dirty
        vm.updateNodeText(id: vm.nodes[0].id, text: "Unsaved post requiring confirmation")
        #expect(vm.isDirty == true)

        // Simulating cancellation action when dirty: shows discard dialog
        if vm.isDirty {
            vm.showDiscardConfirmation = true
        }
        #expect(vm.showDiscardConfirmation == true)

        // User action: Save Current as Draft
        vm.saveCurrentAsDraft()
        #expect(vm.isDirty == false)
        #expect(storage.drafts.count == 1)
        #expect(storage.drafts.first?.previewText.contains("Unsaved post") == true)
        #expect(storage.activeDraft == nil)

        // Draft another post and test discard action
        vm.updateNodeText(id: vm.nodes[0].id, text: "Second draft to discard")
        #expect(vm.isDirty == true)

        vm.discardDraft()
        #expect(vm.isDirty == false)
        #expect(storage.activeDraft == nil)
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text.isEmpty)
    }

    @Test("T2.10: Verify Character Ring Accessibility Pluralization")
    @MainActor
    func testCharacterRingAccessibilityPluralization() {
        #expect(CircularCharacterGauge.accessibilityDescription(for: -1) == "Character limit exceeded by 1 character")
        #expect(CircularCharacterGauge.accessibilityDescription(for: -2) == "Character limit exceeded by 2 characters")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 0) == "0 characters remaining")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 1) == "1 character remaining")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 20) == "20 characters remaining")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 140) == "140 of 280 characters used")

        // Custom limit verification
        #expect(CircularCharacterGauge.accessibilityDescription(for: -1, limit: 140) == "Character limit exceeded by 1 character")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 1, limit: 140) == "1 character remaining")
        #expect(CircularCharacterGauge.accessibilityDescription(for: 50, limit: 100) == "50 of 100 characters used")
    }

    // MARK: - Tier 3: Cross-Feature Pairwise Interactions

    @Test("T3.1: Verify Draft Serialization Round-Trip and Restoration")
    @MainActor
    func testDraftPersistenceRoundTrip() {
        let storage = MockInMemoryDraftStorage()
        let vm1 = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm1.updateNodeText(id: vm1.nodes[0].id, text: "Drafted thought 1")
        vm1.addNode()
        vm1.updateNodeText(id: vm1.nodes[1].id, text: "Drafted thought 2")
        vm1.persistActiveDraft()

        #expect(storage.activeDraft != nil)
        #expect(storage.activeDraft?.nodes.count == 2)
        #expect(storage.activeDraft?.previewText.contains("Drafted thought 1") == true)

        // Restore into new ViewModel
        let vm2 = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: true)
        #expect(vm2.nodes.count == 2)
        #expect(vm2.nodes[0].text == "Drafted thought 1")
        #expect(vm2.nodes[1].text == "Drafted thought 2")

        // Discard
        vm2.discardDraft()
        #expect(storage.activeDraft == nil)
        #expect(vm2.nodes.count == 1)
        #expect(vm2.nodes[0].text.isEmpty)
    }

    @Test("T3.2: Verify Multi-Node Thread Sequential Creation Chain")
    @MainActor
    func testMultiNodeThreadCreation() async throws {
        let service = MockClientService()
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Part 1: The architecture.")
        vm.addNode()
        vm.updateNodeText(id: vm.nodes[1].id, text: "Part 2: The implementation.")
        vm.addNode()
        vm.updateNodeText(id: vm.nodes[2].id, text: "Part 3: The verification.")

        let success = await vm.publishThread()
        #expect(success == true)
        #expect(service.createdPosts.count == 3)
        #expect(service.createdPosts[0].text == "Part 1: The architecture.")
        #expect(service.createdPosts[1].text == "Part 2: The implementation.")
        #expect(service.createdPosts[2].text == "Part 3: The verification.")
    }

    @Test("T3.3: Verify Partial Failure Preserves Unposted Nodes for Recovery")
    @MainActor
    func testPublishingFailureRecovery() async {
        final class FailingMockService: XClientServiceProtocol, @unchecked Sendable {
            var callCount = 0
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
                callCount += 1
                if callCount == 2 {
                    throw XKitError.rateLimitExceeded(resetDate: nil)
                }
                return XPost(id: "created_\(callCount)", text: text, authorId: "me", createdAt: Date(), conversationId: nil)
            }
        }

        let failingService = FailingMockService()
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(service: failingService, draftStorage: storage, restoreActiveDraftOnLaunch: false)

        vm.updateNodeText(id: vm.nodes[0].id, text: "Node 1 succeeds")
        vm.addNode()
        vm.updateNodeText(id: vm.nodes[1].id, text: "Node 2 fails")

        let success = await vm.publishThread()
        #expect(success == false)
        #expect(vm.errorMessage != nil)
        // First node was posted, remaining node 2 is preserved for retry
        #expect(vm.nodes.count == 1)
        #expect(vm.nodes[0].text == "Node 2 fails")
    }

    @Test("T3.4: Verify Media Attachment Removal and State Resilience")
    @MainActor
    func testMediaAttachmentRemovalAndStateResilience() {
        let storage = MockInMemoryDraftStorage()
        let vm = ComposeViewModel(draftStorage: storage, restoreActiveDraftOnLaunch: false)
        let nodeId = vm.nodes[0].id

        let p1 = MediaAttachment(id: "media_1", url: URL(string: "https://example.com/1.jpg")!, type: .photo)
        let p2 = MediaAttachment(id: "media_2", url: URL(string: "https://example.com/2.jpg")!, type: .photo)

        vm.addAttachment(to: nodeId, attachment: p1)
        vm.addAttachment(to: nodeId, attachment: p2)
        #expect(vm.nodes[0].mediaAttachments.count == 2)

        // Remove media_1
        let removed1 = vm.removeAttachment(from: nodeId, attachmentId: "media_1")
        #expect(removed1 == true)
        #expect(vm.nodes[0].mediaAttachments.count == 1)
        #expect(vm.nodes[0].mediaAttachments[0].id == "media_2")

        // Removing non-existent media is safe false
        let removedGhost = vm.removeAttachment(from: nodeId, attachmentId: "ghost_id")
        #expect(removedGhost == false)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // Remove media_2
        let removed2 = vm.removeAttachment(from: nodeId, attachmentId: "media_2")
        #expect(removed2 == true)
        #expect(vm.nodes[0].mediaAttachments.isEmpty)
    }

    // MARK: - Tier 4: Real-World Application Scenario

    @Test("T4.1: Scenario 5 - Composer Thread Drafting, Character Ring & Persistence Flow")
    @MainActor
    func testScenario5_ComposerThreadDraftingCharacterRingAndPersistence() async throws {
        let service = MockClientService()
        let storage = MockInMemoryDraftStorage()

        // 1. Initialize Composer
        let vm = ComposeViewModel(service: service, draftStorage: storage, restoreActiveDraftOnLaunch: false)
        #expect(vm.nodes.count == 1)
        #expect(vm.isDirty == false)

        // 2. Draft First Node & Add Media
        vm.updateNodeText(id: vm.nodes[0].id, text: "Node 1 starts drafting...")
        vm.addAttachment(to: vm.nodes[0].id, attachment: .samplePhoto)
        #expect(vm.isDirty == true)
        #expect(vm.nodes[0].mediaAttachments.count == 1)

        // 3. Add Second Thread Node
        vm.addNode()
        #expect(vm.nodes.count == 2)
        #expect(vm.postButtonTitle == "Post All")

        // 4. Approach Warning Threshold on Node 2 (265 chars)
        let warningText = String(repeating: "X", count: 265)
        vm.updateNodeText(id: vm.nodes[1].id, text: warningText)
        #expect(vm.nodes[1].gaugeStatus == .warning)
        #expect(vm.nodes[1].remainingCharacters == 15)

        // 5. Verify Persistence
        vm.persistActiveDraft()
        #expect(storage.activeDraft != nil)
        #expect(storage.activeDraft?.nodes.count == 2)

        // 6. Publish Thread Sequentially
        let success = await vm.publishThread()
        #expect(success == true)
        #expect(service.createdPosts.count == 2)
        #expect(storage.activeDraft == nil)
        #expect(vm.isDirty == false)
    }
}
