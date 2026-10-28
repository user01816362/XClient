//
//  ComposeView.swift
//  XClient
//
//  Modern Post Composer modal sheet featuring multi-node thread creation,
//  circular character count ring gauge, media attachment preview, and resilient draft persistence.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

/// Circular character count gauge with threshold visualization.
public struct CircularCharacterGauge: View {
    @Environment(\.colorPalette) private var palette

    public let characterCount: Int
    public let limit: Int
    public let warningThreshold: Int
    public let size: CGFloat
    public let lineWidth: CGFloat

    public init(
        characterCount: Int,
        limit: Int = 280,
        warningThreshold: Int = 260,
        size: CGFloat = 30,
        lineWidth: CGFloat = 2.5
    ) {
        self.characterCount = characterCount
        self.limit = limit
        self.warningThreshold = warningThreshold
        self.size = size
        self.lineWidth = lineWidth
    }

    private var remaining: Int {
        limit - characterCount
    }

    private var progress: Double {
        guard limit > 0 else { return 0 }
        return Double(min(characterCount, limit)) / Double(limit)
    }

    private var status: CharacterGaugeStatus {
        CharacterGaugeStatus.evaluate(count: characterCount, limit: limit, warningThreshold: warningThreshold)
    }

    private var ringColor: Color {
        switch status {
        case .normal:
            return palette.accent
        case .warning:
            return palette.warning
        case .atLimit, .overage:
            return palette.destructive
        }
    }

    private var textColor: Color {
        switch status {
        case .normal:
            return palette.textSecondary
        case .warning:
            return palette.warning
        case .atLimit, .overage:
            return palette.destructive
        }
    }

    public var body: some View {
        ZStack {
            // Background Track
            Circle()
                .stroke(
                    status == .overage ? palette.destructive.opacity(0.2) : palette.borderSubtle,
                    lineWidth: lineWidth
                )

            // Progress Fill Arc
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: progress)

            // Numeric countdown text (rendered when remaining <= 20)
            if status.showsRemainingCount {
                Text("\(remaining)")
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Computes accessibility description for remaining character count and limit.
    public static func accessibilityDescription(for remaining: Int, limit: Int = 280) -> String {
        let characterCount = limit - remaining
        if remaining < 0 {
            let overage = -remaining
            let noun = overage == 1 ? "character" : "characters"
            return "Character limit exceeded by \(overage) \(noun)"
        } else if remaining <= 20 {
            let noun = remaining == 1 ? "character" : "characters"
            return "\(remaining) \(noun) remaining"
        } else {
            return "\(characterCount) of \(limit) characters used"
        }
    }

    private var accessibilityDescription: String {
        Self.accessibilityDescription(for: remaining, limit: limit)
    }
}

/// Modal composer view supporting multi-node threads and draft management.
public struct ComposeView: View {
    @StateObject private var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var palette

    public var onDismiss: (() -> Void)?

    public init(viewModel: ComposeViewModel? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ComposeViewModel())
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Error banner if any
                        if let error = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(palette.destructive)
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                            }
                            .padding(10)
                            .background(palette.destructive.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        // Thread Nodes
                        ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                            nodeRow(index: index, node: node)
                        }

                        // Bottom spacer for toolbar clearance
                        Spacer()
                            .frame(height: 80)
                    }
                    .padding(.top, 12)
                }

                // Accessory Toolbar docked at bottom
                accessoryToolbar
            }
            .background(palette.background)
            .navigationTitle("New Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        handleCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 12) {
                        CircularCharacterGauge(
                            characterCount: viewModel.activeNode.characterCount,
                            limit: ComposeNode.maxCharacterLimit,
                            warningThreshold: ComposeNode.warningThreshold,
                            size: 24,
                            lineWidth: 2.0
                        )

                        Button(action: {
                            Task {
                                let success = await viewModel.publishThread()
                                if success {
                                    handleDismiss()
                                }
                            }
                        }) {
                            if viewModel.isPublishing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(viewModel.postButtonTitle)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(viewModel.isThreadValid ? palette.accent : palette.accent.opacity(0.4))
                                    )
                            }
                        }
                        .disabled(!viewModel.isThreadValid || viewModel.isPublishing)
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [.command])
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 620, minHeight: 420, idealHeight: 560)
        #endif
        .interactiveDismissDisabled(viewModel.isDirty)
        .confirmationDialog(
            "Save Draft?",
            isPresented: $viewModel.showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Draft") {
                viewModel.saveCurrentAsDraft()
                handleDismiss()
            }
            Button("Discard Draft", role: .destructive) {
                viewModel.discardDraft()
                handleDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes in this post.")
        }
        .sheet(isPresented: $viewModel.isDraftsListPresented) {
            DraftsListView(
                draftStorage: viewModel.draftStorage,
                onSelectDraft: { draft in
                    viewModel.restoreDraft(draft)
                    viewModel.isDraftsListPresented = false
                },
                onDismiss: {
                    viewModel.isDraftsListPresented = false
                }
            )
        }
    }

    // MARK: - Node Row Layout
    private func nodeRow(index: Int, node: ComposeNode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: Avatar + Thread Connector Line
            VStack(spacing: 4) {
                AvatarImage(author: viewModel.currentUser, size: 38)

                if index < viewModel.nodes.count - 1 {
                    Rectangle()
                        .fill(palette.borderSubtle)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 2)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 38)

            // Right column: Content input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.currentUser.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)

                    Text("@\(viewModel.currentUser.username)")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)

                    Spacer()

                    if viewModel.nodes.count > 1 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                viewModel.removeNode(id: node.id)
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove post from thread")
                    }
                }

                // Text input area
                TextField(
                    index == 0 ? "What's happening?" : "Add another post",
                    text: Binding(
                        get: { node.text },
                        set: {
                            viewModel.activeNodeId = node.id
                            viewModel.updateNodeText(id: node.id, text: $0)
                        }
                    ),
                    axis: .vertical
                )
                .font(.body)
                .lineLimit(3...12)
                .textFieldStyle(.plain)
                .onTapGesture {
                    viewModel.activeNodeId = node.id
                }

                // Media Attachment Strip
                if !node.mediaAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(node.mediaAttachments) { attachment in
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: attachment.previewUrl ?? attachment.url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        default:
                                            Rectangle()
                                                .fill(palette.secondaryBackground)
                                                .overlay {
                                                    Image(systemName: "photo")
                                                        .foregroundStyle(palette.textTertiary)
                                                }
                                        }
                                    }
                                    .frame(width: 120, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(palette.borderSubtle, lineWidth: 1)
                                    )

                                    if attachment.type == .video {
                                        VStack {
                                            Spacer()
                                            HStack(spacing: 4) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 8))
                                                if let duration = attachment.durationSeconds {
                                                    Text(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
                                                        .font(.caption2.bold())
                                                }
                                            }
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Capsule())
                                            .padding(4)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Button(action: {
                                        viewModel.removeAttachment(from: node.id, attachmentId: attachment.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                    .accessibilityLabel("Remove attachment")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Bottom Accessory Toolbar
    private var accessoryToolbar: some View {
        HStack(spacing: 16) {
            Spacer()

            Button(action: {
                viewModel.isDraftsListPresented = true
            }) {
                Text("Drafts")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)

            CircularCharacterGauge(
                characterCount: viewModel.activeNode.characterCount,
                limit: ComposeNode.maxCharacterLimit,
                warningThreshold: ComposeNode.warningThreshold,
                size: 28,
                lineWidth: 2.5
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.groupedBackground)
        .overlay(alignment: .top) {
            Divider().background(palette.borderSubtle)
        }
    }

    // MARK: - Actions
    private func handleCancel() {
        if viewModel.isDirty {
            viewModel.showDiscardConfirmation = true
        } else {
            handleDismiss()
        }
    }

    private func handleDismiss() {
        onDismiss?()
        dismiss()
    }
}

// MARK: - Drafts List View
@MainActor
public final class DraftsListViewModel: ObservableObject, Sendable {
    @Published public var drafts: [ComposeDraft] = []
    public init() {}
}

public struct DraftsListView: View {
    public let draftStorage: any DraftStorageProtocol
    public let onSelectDraft: (ComposeDraft) -> Void
    public let onDismiss: () -> Void
    @Environment(\.colorPalette) private var palette
    @StateObject private var listModel = DraftsListViewModel()

    public init(
        draftStorage: any DraftStorageProtocol,
        onSelectDraft: @escaping (ComposeDraft) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.draftStorage = draftStorage
        self.onSelectDraft = onSelectDraft
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Group {
                if listModel.drafts.isEmpty {
                    ContentUnavailableView(
                        "No Drafts",
                        systemImage: "doc.text",
                        description: Text("Saved drafts will appear here.")
                    )
                } else {
                    List {
                        ForEach(listModel.drafts) { draft in
                            Button(action: { onSelectDraft(draft) }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.previewText)
                                        .font(.body)
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(2)

                                    HStack {
                                        Text("\(draft.nodes.count) \(draft.nodes.count == 1 ? "post" : "posts")")
                                            .font(.caption2)
                                            .foregroundStyle(palette.textSecondary)

                                        Spacer()

                                        Text(draft.lastModifiedDate, style: .date)
                                            .font(.caption2)
                                            .foregroundStyle(palette.textTertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                draftStorage.deleteDraft(id: listModel.drafts[index].id)
                            }
                            listModel.drafts = draftStorage.listDrafts()
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .onAppear {
                listModel.drafts = draftStorage.listDrafts()
            }
        }
    }
}
