//
//  TimelineView.swift
//  XClient
//
//  Reverse-chronological feed with pull-to-refresh, floating Prominent Liquid Glass
//  unread pill button ("↑ N new posts"), and TabBarCoordinator scroll-to-top integration.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import Combine

/// Reverse-chronological timeline feed surface with background polling unread buffer and pull-to-refresh.
public struct TimelineView: View {
    @StateObject private var viewModel: TimelineViewModel
    @EnvironmentObject private var coordinator: TabBarCoordinator
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.colorPalette) private var palette

    public init(viewModel: TimelineViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? TimelineViewModel())
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                // MARK: 1. Primary Scrolling Feed
                ScrollView {
                    // Invisible top scroll anchor
                    Color.clear
                        .frame(height: 0)
                        .id("timeline_top_anchor")

                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.posts) { post in
                            TimelinePostRow(post: post, viewModel: viewModel)
                                .id(post.id)

                            Divider()
                                .background(palette.borderSubtle)
                        }

                        // Infinite scroll pagination trigger
                        if !viewModel.posts.isEmpty {
                            Color.clear
                                .frame(height: 40)
                                .onAppear {
                                    Task { await viewModel.loadMore() }
                                }
                        }

                        // Bottom loading indicator
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .refreshable {
                    await viewModel.refreshTimeline()
                }

                // MARK: 2. Floating Prominent Liquid Glass Unread Pill
                if viewModel.unreadCount > 0 {
                    UnreadPillButton(count: viewModel.unreadCount) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("timeline_top_anchor", anchor: .top)
                        }
                        viewModel.flushUnreadBuffer()
                    }
                    .padding(.top, 12)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.85)),
                            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                        )
                    )
                    .zIndex(100)
                }

                // MARK: 3. Full-Screen Empty & Loading State Overlays
                if viewModel.isLoading && viewModel.posts.isEmpty {
                    TimelineLoadingPlaceholder()
                } else if viewModel.posts.isEmpty && !viewModel.isLoading {
                    TimelineEmptyStateView(errorMessage: viewModel.errorMessage) {
                        Task { await viewModel.fetchTimeline() }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.unreadCount)
            // MARK: 4. TabBarCoordinator Scroll-To-Top Observer
            .onChange(of: coordinator.scrollToTopTriggers[.timeline]) { _, _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    proxy.scrollTo("timeline_top_anchor", anchor: .top)
                }
                viewModel.flushUnreadBuffer()
            }
            // MARK: 5. TabBarCoordinator Rapid Double-Tap Refresh Observer
            .onReceive(coordinator.refreshPublisher) { destination in
                if destination == .timeline {
                    Task { await viewModel.refreshTimeline() }
                }
            }
        }
        .onAppear {
            viewModel.attach(navigationState: navigationState)
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .background(palette.background)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    SessionManager.shared.isShowingAccountSwitcher = true
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .principal) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(palette.textPrimary)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isShowingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $viewModel.isShowingSearchSheet) {
            NavigationStack {
                SearchExploreView(service: viewModel.service)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Floating Unread Pill Component

public struct UnreadPillButton: View {
    public let count: Int
    public let action: () -> Void
    @Environment(\.colorPalette) private var palette

    public init(count: Int, action: @escaping () -> Void) {
        self.count = count
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.bold())
                Text("\(count) new \(count == 1 ? "post" : "posts")")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .liquidGlassCapsule(style: .prominent, intensity: 1.0)
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
        .accessibilityLabel("\(count) new posts available. Tap to scroll to top and view.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Post Row Presentation

public struct TimelinePostRow: View {
    public let post: PostItem
    @ObservedObject public var viewModel: TimelineViewModel
    @EnvironmentObject private var navigationState: AppNavigationState

    public init(post: PostItem, viewModel: TimelineViewModel) {
        self.post = post
        self.viewModel = viewModel
    }

    public var body: some View {
        PostCardView(
            post: post,
            onSelectPost: { postId in
                navigationState.push(route: .postDetail(postId: postId))
            },
            onSelectProfile: { userId in
                navigationState.push(route: .userProfile(userId: userId))
            },
            onReply: { postItem in
                navigationState.presentSheet(.composer(draftId: nil, replyToPostId: postItem.id))
            },
            onRepostToggle: { _ in
                viewModel.toggleRepost(for: post)
            },
            onLikeToggle: { _ in
                viewModel.toggleLike(for: post)
            },
            onBookmarkToggle: { _ in
                viewModel.toggleBookmark(for: post)
            },
            onMediaTap: { media in
                navigationState.push(route: .mediaLightbox(url: media.url))
            }
        )
    }
}

// MARK: - State Placeholders

public struct TimelineLoadingPlaceholder: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            ProgressView("Loading Timeline...")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct TimelineEmptyStateView: View {
    public let errorMessage: String?
    public let onRetry: () -> Void

    public init(errorMessage: String?, onRetry: @escaping () -> Void) {
        self.errorMessage = errorMessage
        self.onRetry = onRetry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(
                errorMessage != nil ? "Unable to Load Timeline" : "No Posts Yet",
                systemImage: errorMessage != nil ? "exclamationmark.triangle" : "tray"
            )
        } description: {
            Text(errorMessage ?? "When people you follow post updates, they will appear here.")
        } actions: {
            if errorMessage != nil {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
