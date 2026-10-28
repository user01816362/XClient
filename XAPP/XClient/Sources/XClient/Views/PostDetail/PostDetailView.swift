//
//  PostDetailView.swift
//  XClient
//
//  Rich multiplatform focal tweet surface with conversation threading,
//  social mutations, high-resolution media zoom, and Liquid Glass reply bar.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

@MainActor
public struct PostDetailView: View {
    @StateObject private var viewModel: PostDetailViewModel
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.colorPalette) private var palette

    public init(postId: String, service: (any XClientServiceProtocol)? = nil) {
        _viewModel = StateObject(wrappedValue: PostDetailViewModel(postId: postId, service: service))
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            palette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let post = viewModel.focalPost {
                        focalPostSection(post)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        Divider()
                            .overlay(palette.borderDefault)
                            .padding(.vertical, 12)

                        // Replies section
                        repliesSection
                            .padding(.bottom, 80) // Padding for sticky bottom bar
                    } else if viewModel.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading thread...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ContentUnavailableView(
                            "Post Unavailable",
                            systemImage: "bubble.left.and.exclamationmark",
                            description: Text(viewModel.errorMessage ?? "This post may have been deleted or is unavailable.")
                        )
                        .padding(.top, 60)
                    }
                }
            }
            .refreshable {
                await viewModel.loadPostDetail()
            }

            // Sticky Bottom Reply Bar
            if viewModel.focalPost != nil {
                liquidGlassReplyBar
            }
        }
        .navigationTitle("Post")
        .alert("Unable to complete action", isPresented: Binding(
            get: { viewModel.focalPost != nil && viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.loadPostDetail()
        }
    }

    // MARK: - Focal Post Section

    @ViewBuilder
    private func focalPostSection(_ post: PostItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Author header
            HStack(spacing: 12) {
                Button {
                    navigationState.push(route: .userProfile(userId: post.author.id))
                } label: {
                    AsyncImage(url: post.author.profileImageUrl.flatMap(URL.init)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Circle().fill(palette.accent.opacity(0.15))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(palette.accent)
                                )
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(palette.borderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(post.author.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(palette.textPrimary)

                        if post.author.verified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.accent)
                        }
                    }

                    Text("@\(post.author.username)")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer()

                Button {
                    // Action sheet or more options
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Large Body Text
            Text(post.text)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(palette.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)

            // Media attachments
            if !post.mediaAttachments.isEmpty {
                ForEach(post.mediaAttachments) { media in
                    Button {
                        navigationState.push(route: .mediaLightbox(url: media.url))
                    } label: {
                        AsyncImage(url: media.url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(palette.secondaryBackground)
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(palette.borderDefault, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Quoted post
            if let quoted = post.quotedPost?.postItem {
                QuotedCardView(post: quoted)
                    .onTapGesture {
                        navigationState.push(route: .postDetail(postId: quoted.id))
                    }
            }

            // Timestamp and metadata
            HStack(spacing: 6) {
                Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)

                Text("•")
                    .foregroundStyle(palette.textSecondary)

                Text("Liquid Glass for iOS")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
            .padding(.top, 4)

            Divider()
                .overlay(palette.borderDefault)

            // Metric Counters
            HStack(spacing: 20) {
                if post.repostCount > 0 {
                    metricItem(count: post.repostCount, label: "Reposts")
                }
                if post.likeCount > 0 {
                    metricItem(count: post.likeCount, label: "Likes")
                }
                if post.bookmarkCount > 0 {
                    metricItem(count: post.bookmarkCount, label: "Bookmarks")
                }
            }
            .padding(.vertical, 2)

            Divider()
                .overlay(palette.borderDefault)

            // Interactive Action Buttons
            HStack {
                actionButton(icon: "bubble.left", count: post.replyCount, color: palette.textSecondary) {
                    // Focus reply field
                }

                Spacer()

                actionButton(icon: "arrow.2.squarepath", count: post.repostCount, color: post.isReposted ? .green : palette.textSecondary) {
                    viewModel.toggleRepost()
                }

                Spacer()

                actionButton(icon: post.isLiked ? "heart.fill" : "heart", count: post.likeCount, color: post.isLiked ? .pink : palette.textSecondary) {
                    viewModel.toggleLike()
                }

                Spacer()

                actionButton(icon: post.isBookmarked ? "bookmark.fill" : "bookmark", count: post.bookmarkCount, color: post.isBookmarked ? palette.accent : palette.textSecondary) {
                    viewModel.toggleBookmark()
                }

                Spacer()

                Button {
                    // Share
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16))
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
    }

    private func metricItem(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func actionButton(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(color)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Replies Section

    @ViewBuilder
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.replies.isEmpty {
                Text("Replies")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                ForEach(viewModel.replies) { reply in
                    VStack(spacing: 0) {
                        PostCardView(
                            post: reply,
                            onSelectPost: { replyId in
                                navigationState.push(route: .postDetail(postId: replyId))
                            },
                            onSelectProfile: { userId in
                                navigationState.push(route: .userProfile(userId: userId))
                            },
                            onReply: { postItem in
                                navigationState.presentSheet(.composer(draftId: nil, replyToPostId: postItem.id))
                            },
                            onMediaTap: { media in
                                navigationState.push(route: .mediaLightbox(url: media.url))
                            }
                        )

                        Divider()
                            .overlay(palette.borderDefault.opacity(0.6))
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 32))
                        .foregroundStyle(palette.textSecondary.opacity(0.4))
                    Text("Be the first to reply")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
    }

    // MARK: - Liquid Glass Sticky Reply Bar

    @ViewBuilder
    private var liquidGlassReplyBar: some View {
        HStack(spacing: 10) {
            TextField("Post your reply...", text: $viewModel.replyText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(palette.background.opacity(0.8))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderDefault, lineWidth: 1))

            Button {
                Task {
                    await viewModel.submitReply()
                }
            } label: {
                HStack {
                    if viewModel.isSubmittingReply {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Reply")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(viewModel.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? palette.borderDefault : palette.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(viewModel.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmittingReply)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    VStack {
                        Divider().overlay(palette.borderDefault)
                        Spacer()
                    }
                )
        )
    }
}
