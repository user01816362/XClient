//
//  ComposeViewModel.swift
//  XClient
//
//  MainActor ViewModel managing multi-node post composition, character limit metrics,
//  media attachments, resilient draft persistence, and sequential publishing.
//  100% Swift 6 strict concurrency compliance.
//

import Foundation
import SwiftUI
import XKitModels

/// Threshold states for the character count circular progress gauge.
public enum CharacterGaugeStatus: Sendable, Equatable {
    case normal      // < 260 chars (remaining > 20) -> Standard accent ring, numeric text hidden
    case warning     // 260...279 chars (remaining 1...20) -> Amber warning ring, numeric countdown visible
    case atLimit     // 280 chars (remaining 0) -> Red ring, "0" visible
    case overage     // > 280 chars (remaining < 0) -> Destructive red ring, negative count visible (e.g. "-4")

    public static func evaluate(count: Int, limit: Int = 280, warningThreshold: Int = 260) -> CharacterGaugeStatus {
        if count < warningThreshold {
            return .normal
        } else if count < limit {
            return .warning
        } else if count == limit {
            return .atLimit
        } else {
            return .overage
        }
    }

    public var showsRemainingCount: Bool {
        switch self {
        case .normal: return false
        case .warning, .atLimit, .overage: return true
        }
    }
}

/// Represents a single post node within a composer thread.
public struct ComposeNode: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public var text: String
    public var mediaAttachments: [MediaAttachment]

    public static let maxCharacterLimit: Int = 280
    public static let warningThreshold: Int = 260 // remaining <= 20

    public init(
        id: UUID = UUID(),
        text: String = "",
        mediaAttachments: [MediaAttachment] = []
    ) {
        self.id = id
        self.text = text
        self.mediaAttachments = mediaAttachments
    }

    // MARK: - Character Metrics
    public var characterCount: Int {
        text.count
    }

    public var remainingCharacters: Int {
        Self.maxCharacterLimit - characterCount
    }

    public var progressRatio: Double {
        guard Self.maxCharacterLimit > 0 else { return 0.0 }
        return Double(characterCount) / Double(Self.maxCharacterLimit)
    }

    public var clampedProgress: Double {
        min(1.0, max(0.0, progressRatio))
    }

    public var isOverLimit: Bool {
        characterCount > Self.maxCharacterLimit
    }

    public var isWarning: Bool {
        characterCount >= Self.warningThreshold && characterCount < Self.maxCharacterLimit
    }

    public var gaugeStatus: CharacterGaugeStatus {
        CharacterGaugeStatus.evaluate(
            count: characterCount,
            limit: Self.maxCharacterLimit,
            warningThreshold: Self.warningThreshold
        )
    }

    // MARK: - Validity
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaAttachments.isEmpty
    }

    public var isValid: Bool {
        !isEmpty && !isOverLimit
    }
}

/// Persisted composer state representing an in-progress draft or thread.
public struct ComposeDraft: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var nodes: [ComposeNode]
    public var lastModifiedDate: Date

    public init(id: UUID = UUID(), nodes: [ComposeNode], lastModifiedDate: Date = Date()) {
        self.id = id
        self.nodes = nodes
        self.lastModifiedDate = lastModifiedDate
    }

    public var previewText: String {
        for node in nodes {
            let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return String(trimmed.prefix(60)) }
        }
        return "Empty draft"
    }
}

/// Abstract storage interface for draft persistence, facilitating isolated unit testing.
public protocol DraftStorageProtocol: Sendable {
    func saveActiveDraft(_ draft: ComposeDraft)
    func loadActiveDraft() -> ComposeDraft?
    func clearActiveDraft()
    func listDrafts() -> [ComposeDraft]
    func saveDraftToList(_ draft: ComposeDraft)
    func deleteDraft(id: UUID)
}

/// Default UserDefaults-backed draft storage.
public final class UserDefaultsDraftStorage: DraftStorageProtocol, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let activeDraftKey = "xclient.compose.active_draft"
    private let savedDraftsKey = "xclient.compose.saved_drafts"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func saveActiveDraft(_ draft: ComposeDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        userDefaults.set(data, forKey: activeDraftKey)
    }

    public func loadActiveDraft() -> ComposeDraft? {
        guard let data = userDefaults.data(forKey: activeDraftKey),
              let draft = try? JSONDecoder().decode(ComposeDraft.self, from: data) else {
            return nil
        }
        return draft
    }

    public func clearActiveDraft() {
        userDefaults.removeObject(forKey: activeDraftKey)
    }

    public func listDrafts() -> [ComposeDraft] {
        guard let data = userDefaults.data(forKey: savedDraftsKey),
              let list = try? JSONDecoder().decode([ComposeDraft].self, from: data) else {
            return []
        }
        return list.sorted { $0.lastModifiedDate > $1.lastModifiedDate }
    }

    public func saveDraftToList(_ draft: ComposeDraft) {
        var existing = listDrafts().filter { $0.id != draft.id }
        existing.insert(draft, at: 0)
        if let data = try? JSONEncoder().encode(existing) {
            userDefaults.set(data, forKey: savedDraftsKey)
        }
    }

    public func deleteDraft(id: UUID) {
        let existing = listDrafts().filter { $0.id != id }
        if let data = try? JSONEncoder().encode(existing) {
            userDefaults.set(data, forKey: savedDraftsKey)
        }
    }
}

/// Publishing status enumeration for progress tracking.
public enum ComposePublishStatus: Sendable, Equatable {
    case idle
    case publishing(currentNodeIndex: Int, totalNodes: Int)
    case success(publishedPostIds: [String])
    case failure(error: String, failedNodeIndex: Int)
}

/// MainActor coordinator managing post composition and threading.
@MainActor
public final class ComposeViewModel: ObservableObject, Sendable {
    // MARK: - Thread State
    @Published public var nodes: [ComposeNode] = [ComposeNode()]
    @Published public var activeNodeId: UUID = UUID()
    @Published public var publishStatus: ComposePublishStatus = .idle
    @Published public var errorMessage: String? = nil
    @Published public var showDiscardConfirmation: Bool = false
    @Published public var isDraftsListPresented: Bool = false

    // MARK: - Dependencies
    public let service: any XClientServiceProtocol
    public let draftStorage: any DraftStorageProtocol
    public let currentUser: XUser

    // MARK: - Initialization
    @MainActor
    public init(
        service: (any XClientServiceProtocol)? = nil,
        draftStorage: any DraftStorageProtocol = UserDefaultsDraftStorage(),
        currentUser: XUser? = nil,
        restoreActiveDraftOnLaunch: Bool = true
    ) {
        self.service = service ?? XClientService()
        self.draftStorage = draftStorage
        if let user = currentUser {
            self.currentUser = user
        } else if let active = SessionManager.shared.currentState.activeAccount {
            self.currentUser = XUser(
                id: active.id,
                name: active.displayName,
                username: active.username,
                profileImageUrl: active.avatarURL?.absoluteString
            )
        } else {
            self.currentUser = MockDataProvider.shared.currentUser
        }

        if restoreActiveDraftOnLaunch, let activeDraft = draftStorage.loadActiveDraft(), !activeDraft.nodes.isEmpty {
            self.nodes = activeDraft.nodes
            self.activeNodeId = activeDraft.nodes.first?.id ?? UUID()
        } else {
            let initialNode = ComposeNode()
            self.nodes = [initialNode]
            self.activeNodeId = initialNode.id
        }
    }

    // MARK: - Computed Properties
    public var activeNode: ComposeNode {
        nodes.first { $0.id == activeNodeId } ?? nodes.first ?? ComposeNode()
    }

    public var isDirty: Bool {
        nodes.contains { !$0.isEmpty }
    }

    public var isThreadValid: Bool {
        guard !nodes.isEmpty else { return false }
        return nodes.allSatisfy { $0.isValid }
    }

    public var isPublishing: Bool {
        if case .publishing = publishStatus { return true }
        return false
    }

    public var postButtonTitle: String {
        nodes.count > 1 ? "Post All" : "Post"
    }

    // MARK: - Thread Manipulation
    public func addNode() {
        let newNode = ComposeNode()
        nodes.append(newNode)
        activeNodeId = newNode.id
        persistActiveDraft()
    }

    public func removeNode(id: UUID) {
        guard nodes.count > 1 else {
            // Reset the single node rather than leaving 0 nodes
            if let first = nodes.first {
                nodes[0] = ComposeNode(id: first.id, text: "", mediaAttachments: [])
            }
            persistActiveDraft()
            return
        }

        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes.remove(at: index)
            if activeNodeId == id {
                let nextIndex = min(index, nodes.count - 1)
                activeNodeId = nodes[nextIndex].id
            }
        }
        persistActiveDraft()
    }

    public func updateNodeText(id: UUID, text: String) {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes[index].text = text
            persistActiveDraft()
        }
    }

    // MARK: - Media Attachment Management
    @discardableResult
    public func addAttachment(to nodeId: UUID, attachment: MediaAttachment) -> Bool {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return false }
        var currentAttachments = nodes[index].mediaAttachments

        // Reject duplicate media attachment by ID or URL (checking URL object and absoluteString)
        if currentAttachments.contains(where: {
            $0.id == attachment.id ||
            $0.url == attachment.url ||
            $0.url.absoluteString == attachment.url.absoluteString
        }) {
            return false
        }

        // Enforce media count constraints: max 4 photos, or 1 video/gif
        if attachment.type == .video || attachment.type == .animatedGif {
            currentAttachments = [attachment] // Replaces all photos with single video
        } else {
            currentAttachments.removeAll { $0.type == .video || $0.type == .animatedGif }
            guard currentAttachments.count < 4 else {
                return false // Photo limit (max 4) reached
            }
            currentAttachments.append(attachment)
        }

        nodes[index].mediaAttachments = currentAttachments
        persistActiveDraft()
        return true
    }

    @discardableResult
    public func removeAttachment(from nodeId: UUID, attachmentId: String) -> Bool {
        guard let index = nodes.firstIndex(where: { $0.id == nodeId }) else { return false }
        let initialCount = nodes[index].mediaAttachments.count
        nodes[index].mediaAttachments.removeAll { $0.id == attachmentId }
        guard nodes[index].mediaAttachments.count != initialCount else { return false }
        persistActiveDraft()
        return true
    }

    // MARK: - Draft Management
    public func persistActiveDraft() {
        if isDirty {
            let draft = ComposeDraft(nodes: nodes)
            draftStorage.saveActiveDraft(draft)
        } else {
            draftStorage.clearActiveDraft()
        }
    }

    public func saveCurrentAsDraft() {
        guard isDirty else { return }
        let draft = ComposeDraft(nodes: nodes)
        draftStorage.saveDraftToList(draft)
        draftStorage.clearActiveDraft()
        resetComposer()
    }

    public func restoreDraft(_ draft: ComposeDraft) {
        guard !draft.nodes.isEmpty else { return }
        self.nodes = draft.nodes
        self.activeNodeId = draft.nodes.first?.id ?? UUID()
        persistActiveDraft()
    }

    public func discardDraft() {
        draftStorage.clearActiveDraft()
        resetComposer()
    }

    public func resetComposer() {
        let initial = ComposeNode()
        nodes = [initial]
        activeNodeId = initial.id
        publishStatus = .idle
        errorMessage = nil
    }

    // MARK: - Sequential Publish Workflow
    public func publishThread() async -> Bool {
        guard isThreadValid, !isPublishing else { return false }

        errorMessage = nil
        publishStatus = .publishing(currentNodeIndex: 0, totalNodes: nodes.count)

        var publishedIds: [String] = []

        for (index, node) in nodes.enumerated() {
            publishStatus = .publishing(currentNodeIndex: index, totalNodes: nodes.count)
            do {
                let createdPost = try await service.createPost(text: node.text)
                publishedIds.append(createdPost.id)
            } catch {
                self.errorMessage = "Failed to post node \(index + 1): \(error.localizedDescription)"
                self.publishStatus = .failure(error: error.localizedDescription, failedNodeIndex: index)

                if index > 0 {
                    self.nodes.removeSubrange(0..<index)
                    if let first = self.nodes.first {
                        self.activeNodeId = first.id
                    }
                    persistActiveDraft()
                }
                return false
            }
        }

        publishStatus = .success(publishedPostIds: publishedIds)
        draftStorage.clearActiveDraft()
        resetComposer()
        return true
    }
}
