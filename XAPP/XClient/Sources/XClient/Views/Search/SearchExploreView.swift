//
//  SearchExploreView.swift
//  XClient
//
//  Search & Explore surface for discovering trending topics,
//  querying live tweets via X GraphQL, and exploring communities.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

@MainActor
public final class SearchViewModel: ObservableObject, Sendable {
    public let service: any XClientServiceProtocol

    @Published public var searchQuery: String = ""
    @Published public var searchResults: [PostItem] = []
    @Published public var isSearching: Bool = false
    @Published public var selectedTrend: String? = nil
    @Published public var errorMessage: String? = nil

    public static let suggestedTrends = [
        "#Swift6",
        "#LiquidGlass",
        "Apple",
        "iOS 17",
        "SwiftUI",
        "OpenSource",
        "#WWDC"
    ]

    public init(service: (any XClientServiceProtocol)? = nil) {
        self.service = service ?? XClientService()
    }

    public func executeSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let paginated = try await service.searchPosts(query: trimmed, cursor: nil, maxResults: 20)
            let items = paginated.data.map { postWire in
                let author = MockDataProvider.shared.users[postWire.authorId ?? ""] ?? XUser(
                    id: postWire.authorId ?? "usr_unknown",
                    name: "User",
                    username: "user"
                )
                var item = PostItem(post: postWire, author: author)
                item.isLiked = MockDataProvider.shared.userLikes[MockDataProvider.shared.currentUser.id]?.contains(postWire.id) ?? false
                item.isBookmarked = MockDataProvider.shared.bookmarks.contains(where: { $0.id == postWire.id })
                return item
            }
            self.searchResults = items
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isSearching = false
    }
}

@MainActor
public struct SearchExploreView: View {
    @StateObject private var viewModel: SearchViewModel
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.colorPalette) private var palette

    public init(service: (any XClientServiceProtocol)? = nil) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(service: service))
    }

    public var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search Input Header
                searchBarHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                // Trending Chips Carousel
                trendingChipsBar
                    .padding(.bottom, 8)

                Divider()
                    .overlay(palette.borderDefault)

                // Results or Explore State
                if viewModel.isSearching {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching X...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.searchResults) { post in
                                VStack(spacing: 0) {
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
                                        onMediaTap: { media in
                                            navigationState.push(route: .mediaLightbox(url: media.url))
                                        }
                                    )

                                    Divider()
                                        .overlay(palette.borderDefault.opacity(0.6))
                                }
                            }
                        }
                    }
                } else if !viewModel.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "No Results Found",
                        systemImage: "magnifyingglass",
                        description: Text("No posts found matching \"\(viewModel.searchQuery)\".")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    // Empty state: Explore suggestions
                    explorePlaceholder
                }
            }
        }
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Search Bar Header

    @ViewBuilder
    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(palette.textSecondary)

                TextField("Search X", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task {
                            await viewModel.executeSearch(query: viewModel.searchQuery)
                        }
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(palette.secondaryBackground)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(palette.borderDefault, lineWidth: 1))
        }
    }

    // MARK: - Trending Chips

    @ViewBuilder
    private var trendingChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchViewModel.suggestedTrends, id: \.self) { trend in
                    Button {
                        viewModel.searchQuery = trend
                        viewModel.selectedTrend = trend
                        Task {
                            await viewModel.executeSearch(query: trend)
                        }
                    } label: {
                        Text(trend)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                viewModel.searchQuery == trend
                                    ? palette.accent
                                    : palette.secondaryBackground
                            )
                            .foregroundStyle(
                                viewModel.searchQuery == trend
                                    ? .white
                                    : palette.textPrimary
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(palette.borderDefault, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Explore Placeholder

    @ViewBuilder
    private var explorePlaceholder: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(palette.accent.opacity(0.8))

            VStack(spacing: 6) {
                Text("Explore what's happening")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.textPrimary)

                Text("Search for keywords, topics, or hashtags to find real posts on X.")
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}
