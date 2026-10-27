//
//  ProfileView.swift
//  XClient
//
//  User Profile Surface featuring Parallax Banner Header, Dynamic Avatar Collapse,
//  User Identity Block, Sticky Liquid Glass Subtab Picker, and Post/Media Feeds.
//  100% Swift 6 strict concurrency compliance.
//

import SwiftUI
import XKitModels

/// Unified profile surface presenting banner parallax, avatar morphing, identity metadata,
/// sticky subtab selector, and social feeds with 100% Swift 6 concurrency compliance.
public struct ProfileView: View {
    @StateObject private var viewModel: ProfileViewModel
    @EnvironmentObject private var coordinator: TabBarCoordinator
    @EnvironmentObject private var navigationState: AppNavigationState
    @Environment(\.colorPalette) private var palette
    @Environment(\.openURL) private var openURL

    @Namespace private var subtabNamespace

    private let bannerBaseHeight: CGFloat = 150.0
    private let largeAvatarSize: CGFloat = 76.0

    public init(userId: String? = nil, viewModel: ProfileViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ProfileViewModel(userId: userId))
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                // MARK: 1. Main Scrolling Canvas
                ScrollView {
                    VStack(spacing: 0) {
                        // Scroll Offset Geometry Tracker
                        GeometryReader { geo in
                            let minY = geo.frame(in: .named("profile_coordinate_space")).minY
                            Color.clear
                                .preference(key: ProfileScrollOffsetPreferenceKey.self, value: -minY)
                        }
                        .frame(height: 0)
                        .id("profile_top_anchor")

                        // Parallax Banner Container
                        ParallaxBannerHeader(
                            headerImageUrl: viewModel.userProfile?.headerImageUrl,
                            baseHeight: bannerBaseHeight,
                            scrollOffsetY: viewModel.scrollOffsetY
                        )

                        // Identity Block & Collapsing Avatar
                        ProfileIdentityBlock(
                            userProfile: viewModel.userProfile,
                            actionMode: viewModel.actionMode,
                            scrollOffsetY: viewModel.scrollOffsetY,
                            largeAvatarSize: largeAvatarSize,
                            onToggleFollow: { viewModel.toggleFollow() },
                            onMentionTap: { username in
                                navigationState.push(route: .userProfile(userId: username))
                            },
                            onHashtagTap: { _ in
                                // Future hashtag feed seam
                            },
                            onURLTap: { url in
                                openURL(url)
                            }
                        )

                        // Sticky Pinned Subtab Picker & Feed Rows
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ProfileFeedContent(
                                    viewModel: viewModel,
                                    navigationState: navigationState
                                )
                            } header: {
                                ProfileSubtabPicker(
                                    selectedSubtab: $viewModel.selectedSubtab,
                                    namespace: subtabNamespace
                                )
                            }
                        }
                    }
                }
                .coordinateSpace(name: "profile_coordinate_space")
                .onPreferenceChange(ProfileScrollOffsetPreferenceKey.self) { offset in
                    self.viewModel.scrollOffsetY = offset
                }
                .refreshable {
                    await viewModel.refreshProfile()
                }

                // MARK: 2. Morphing Inline Navigation Bar
                ProfileNavigationBar(
                    userProfile: viewModel.userProfile,
                    postsCount: viewModel.postsCount,
                    scrollOffsetY: viewModel.scrollOffsetY,
                    canPop: !navigationState.currentPath.isEmpty,
                    onBack: {
                        navigationState.pop()
                    }
                )

                // MARK: 3. Loading & Error Overlays
                if viewModel.isLoadingProfile && viewModel.userProfile == nil {
                    ProfileLoadingOverlay()
                } else if viewModel.userProfile == nil && !viewModel.isLoadingProfile {
                    ProfileErrorOverlay(
                        errorMessage: viewModel.errorMessage,
                        onRetry: { Task { await viewModel.loadProfile() } }
                    )
                }
            }
            .background(palette.background)
            // MARK: 4. TabBarCoordinator Scroll-To-Top Observer
            .onChange(of: coordinator.scrollToTopTriggers[.profile]) { _, _ in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    proxy.scrollTo("profile_top_anchor", anchor: .top)
                }
            }
            // MARK: 5. TabBarCoordinator Rapid Double-Tap Refresh
            .onReceive(coordinator.refreshPublisher) { destination in
                if destination == .profile {
                    Task { await viewModel.refreshProfile() }
                }
            }
        }
        .onAppear {
            viewModel.attach(navigationState: navigationState)
            viewModel.onAppear()
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

// MARK: - PreferenceKey for Scroll Coordinate Tracking
private struct ProfileScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0.0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Parallax Banner Header Component
public struct ParallaxBannerHeader: View {
    public let headerImageUrl: URL?
    public let baseHeight: CGFloat
    public let scrollOffsetY: CGFloat
    @Environment(\.colorPalette) private var palette

    public init(headerImageUrl: URL?, baseHeight: CGFloat, scrollOffsetY: CGFloat) {
        self.headerImageUrl = headerImageUrl
        self.baseHeight = baseHeight
        self.scrollOffsetY = scrollOffsetY
    }

    public static func effectiveHeight(baseHeight: CGFloat, scrollOffsetY: CGFloat) -> CGFloat {
        ProfileGeometry.effectiveBannerHeight(baseHeight: baseHeight, scrollOffsetY: scrollOffsetY)
    }

    public static func effectiveOffset(scrollOffsetY: CGFloat) -> CGFloat {
        ProfileGeometry.effectiveBannerOffset(scrollOffsetY: scrollOffsetY)
    }

    public var body: some View {
        let effectiveHeight = Self.effectiveHeight(baseHeight: baseHeight, scrollOffsetY: scrollOffsetY)
        let effectiveOffset = Self.effectiveOffset(scrollOffsetY: scrollOffsetY)

        ZStack {
            if let url = headerImageUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        defaultBannerGradient
                    @unknown default:
                        defaultBannerGradient
                    }
                }
            } else {
                defaultBannerGradient
            }
        }
        .frame(height: effectiveHeight)
        .clipped()
        .offset(y: effectiveOffset)
    }

    private var defaultBannerGradient: some View {
        LinearGradient(
            colors: [palette.accent.opacity(0.85), Color(hex: 0x7856FF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - User Identity Block Component
public struct ProfileIdentityBlock: View {
    @Environment(\.colorPalette) private var palette

    public let userProfile: UserProfile?
    public let actionMode: ProfileActionMode
    public let scrollOffsetY: CGFloat
    public let largeAvatarSize: CGFloat
    public let onToggleFollow: () -> Void
    public let onMentionTap: (String) -> Void
    public let onHashtagTap: (String) -> Void
    public let onURLTap: (URL) -> Void

    public init(
        userProfile: UserProfile?,
        actionMode: ProfileActionMode,
        scrollOffsetY: CGFloat,
        largeAvatarSize: CGFloat,
        onToggleFollow: @escaping () -> Void,
        onMentionTap: @escaping (String) -> Void,
        onHashtagTap: @escaping (String) -> Void,
        onURLTap: @escaping (URL) -> Void
    ) {
        self.userProfile = userProfile
        self.actionMode = actionMode
        self.scrollOffsetY = scrollOffsetY
        self.largeAvatarSize = largeAvatarSize
        self.onToggleFollow = onToggleFollow
        self.onMentionTap = onMentionTap
        self.onHashtagTap = onHashtagTap
        self.onURLTap = onURLTap
    }

    public static func avatarScale(for scrollOffsetY: CGFloat) -> CGFloat {
        ProfileGeometry.avatarScale(for: scrollOffsetY)
    }

    public static func avatarOpacity(for scrollOffsetY: CGFloat) -> CGFloat {
        ProfileGeometry.avatarOpacity(for: scrollOffsetY)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action & Avatar Row
            HStack(alignment: .bottom) {
                // Collapsing Large Avatar
                if let user = userProfile?.user {
                    let avatarScale = Self.avatarScale(for: scrollOffsetY)
                    let avatarOpacity = Self.avatarOpacity(for: scrollOffsetY)

                    AvatarImage(author: user, size: largeAvatarSize)
                        .overlay(Circle().strokeBorder(palette.background, lineWidth: 3.5))
                        .scaleEffect(avatarScale)
                        .opacity(avatarOpacity)
                        .offset(y: -largeAvatarSize * 0.45)
                        .padding(.bottom, -largeAvatarSize * 0.45)
                }

                Spacer()

                // Header Action Button (Follow / Edit)
                switch actionMode {
                case .currentUser:
                    Button(action: {}) {
                        Text("Edit Profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .strokeBorder(palette.borderDefault, lineWidth: 1.0)
                            )
                    }
                    .buttonStyle(.plain)

                case .otherUser(let isFollowing):
                    Button(action: onToggleFollow) {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isFollowing ? palette.textPrimary : Color.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(isFollowing ? palette.secondaryBackground : palette.accent)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isFollowing ? palette.borderDefault : Color.clear, lineWidth: 1.0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            // Name & Verification Badge
            if let user = userProfile?.user {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(user.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(palette.textPrimary)

                        let badge = VerificationBadgeType.resolve(from: user)
                        if badge != .none {
                            VerificationBadgeView(badgeType: badge)
                        }
                    }

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Bio Text with Parsed Entities
            if let bio = userProfile?.bio, !bio.isEmpty {
                let attributedBio = PostEntityParser.makeAttributedString(text: bio, accentColor: palette.accent)
                Text(attributedBio)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(3)
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "xclient" {
                            if url.host == "user" {
                                onMentionTap(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                                return .handled
                            } else if url.host == "hashtag" {
                                onHashtagTap(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                                return .handled
                            }
                        } else {
                            onURLTap(url)
                            return .handled
                        }
                        return .handled
                    })
            }

            // Metadata Row (Location, Website, Joined Date)
            HStack(spacing: 14) {
                if let location = userProfile?.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }

                if let website = userProfile?.websiteUrl {
                    Button(action: { onURLTap(website) }) {
                        Label(website.host ?? website.absoluteString, systemImage: "link")
                            .font(.footnote)
                            .foregroundStyle(palette.accent)
                    }
                    .buttonStyle(.plain)
                }

                if let profile = userProfile {
                    Label(profile.joinedDateString, systemImage: "calendar")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, 2)

            // Stats Row (Following & Followers)
            if let profile = userProfile {
                HStack(spacing: 18) {
                    HStack(spacing: 4) {
                        Text(UserProfile.formatCount(profile.followingCount))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("Following")
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }

                    HStack(spacing: 4) {
                        Text(UserProfile.formatCount(profile.followersCount))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                        Text("Followers")
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Sticky Liquid Glass Subtab Picker
public struct ProfileSubtabPicker: View {
    @Binding public var selectedSubtab: ProfileSubtab
    public var namespace: Namespace.ID
    @Environment(\.colorPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(selectedSubtab: Binding<ProfileSubtab>, namespace: Namespace.ID) {
        self._selectedSubtab = selectedSubtab
        self.namespace = namespace
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(ProfileSubtab.allCases) { subtab in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedSubtab = subtab
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(subtab.title)
                                .font(.subheadline.weight(selectedSubtab == subtab ? .bold : .medium))
                                .foregroundStyle(selectedSubtab == subtab ? palette.textPrimary : palette.textSecondary)
                                .padding(.top, 12)

                            // Active Spring Indicator Line
                            ZStack {
                                if selectedSubtab == subtab {
                                    Capsule()
                                        .fill(palette.accent)
                                        .frame(height: 3)
                                        .matchedGeometryEffect(id: "active_subtab_pill", in: namespace)
                                } else {
                                    Color.clear
                                        .frame(height: 3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(subtab.title) tab")
                    .accessibilityAddTraits(selectedSubtab == subtab ? [.isButton, .isSelected] : .isButton)
                }
            }
            .background {
                if reduceTransparency {
                    palette.background
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
            }

            Divider()
                .background(palette.borderSubtle)
        }
    }
}

// MARK: - Feed Content Switcher (Posts vs Media Grid)
public struct ProfileFeedContent: View {
    @ObservedObject public var viewModel: ProfileViewModel
    public let navigationState: AppNavigationState
    @Environment(\.colorPalette) private var palette

    private let mediaGridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    public init(viewModel: ProfileViewModel, navigationState: AppNavigationState) {
        self.viewModel = viewModel
        self.navigationState = navigationState
    }

    public var body: some View {
        Group {
            if viewModel.isLoadingFeed && viewModel.isFeedEmpty {
                ProgressView()
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            } else if viewModel.isFeedEmpty {
                ProfileSubtabEmptyView(
                    subtab: viewModel.selectedSubtab,
                    username: viewModel.userProfile?.user.username ?? "user"
                )
            } else if viewModel.selectedSubtab == .media {
                // Responsive 3-Column Media Grid
                LazyVGrid(columns: mediaGridColumns, spacing: 2) {
                    ForEach(viewModel.mediaItems) { item in
                        ProfileMediaGridCell(item: item) {
                            navigationState.push(route: .mediaLightbox(url: item.attachment.url))
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                // Reverse-Chronological Post Feed Rows
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.currentPosts) { post in
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

                        Divider()
                            .background(palette.borderSubtle)
                    }
                }
            }
        }
    }
}

// MARK: - Media Grid Cell Component
public struct ProfileMediaGridCell: View {
    public let item: ProfileMediaItem
    public let onTap: () -> Void
    @Environment(\.colorPalette) private var palette

    public init(item: ProfileMediaItem, onTap: @escaping () -> Void) {
        self.item = item
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.attachment.previewUrl ?? item.attachment.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Rectangle()
                            .fill(palette.secondaryBackground)
                    @unknown default:
                        Rectangle()
                            .fill(palette.secondaryBackground)
                    }
                }

                // Video Indicator Badge
                if item.attachment.type == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        if let dur = item.attachment.durationSeconds {
                            Text(formatDuration(dur))
                                .font(.caption2.bold())
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(Color.white)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(6)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .aspectRatio(1.0, contentMode: .fit)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Morphing Navigation Bar Component
public struct ProfileNavigationBar: View {
    public let userProfile: UserProfile?
    public let postsCount: Int
    public let scrollOffsetY: CGFloat
    public let canPop: Bool
    public let onBack: () -> Void
    @Environment(\.colorPalette) private var palette

    public init(
        userProfile: UserProfile?,
        postsCount: Int,
        scrollOffsetY: CGFloat,
        canPop: Bool = true,
        onBack: @escaping () -> Void
    ) {
        self.userProfile = userProfile
        self.postsCount = postsCount
        self.scrollOffsetY = scrollOffsetY
        self.canPop = canPop
        self.onBack = onBack
    }

    public var body: some View {
        let navBarOpacity = ProfileGeometry.navigationBarOpacity(for: scrollOffsetY)

        HStack(spacing: 12) {
            // Floating Back Button (rendered when pushed)
            if canPop {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(navBarOpacity > 0.5 ? palette.textPrimary : Color.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(navBarOpacity > 0.5 ? palette.secondaryBackground : Color.black.opacity(0.55))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            // Inline Morphing Identity
            if let user = userProfile?.user {
                HStack(spacing: 8) {
                    AvatarImage(author: user, size: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name)
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)

                        Text("\(postsCount) posts")
                            .font(.caption2)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .opacity(navBarOpacity)
            }

            Spacer()

            // Overflow Actions Button
            Menu {
                Button {
                    SessionManager.shared.isShowingAccountSwitcher = true
                } label: {
                    Label("Switch Accounts", systemImage: "person.2")
                }
                Button(action: {}) {
                    Label("Share Profile", systemImage: "square.and.arrow.up")
                }
                Button(action: {}) {
                    Label("Copy Link to Profile", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(navBarOpacity > 0.5 ? palette.textPrimary : Color.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(navBarOpacity > 0.5 ? palette.secondaryBackground : Color.black.opacity(0.55))
                    )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if navBarOpacity > 0.05 {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(navBarOpacity)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .background(palette.borderSubtle.opacity(navBarOpacity))
                    }
            }
        }
    }
}

// MARK: - Empty & Error Overlays
public struct ProfileSubtabEmptyView: View {
    public let subtab: ProfileSubtab
    public let username: String

    public init(subtab: ProfileSubtab, username: String) {
        self.subtab = subtab
        self.username = username
    }

    public var body: some View {
        ContentUnavailableView(
            "No \(subtab.title) Yet",
            systemImage: subtab.emptyStateIcon,
            description: Text(subtab.emptyDescription(for: username))
        )
        .padding(.vertical, 40)
    }
}

public struct ProfileLoadingOverlay: View {
    public init() {}
    public var body: some View {
        ProgressView("Loading Profile...")
            .font(.subheadline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
    }
}

public struct ProfileErrorOverlay: View {
    public let errorMessage: String?
    public let onRetry: () -> Void

    public init(errorMessage: String?, onRetry: @escaping () -> Void) {
        self.errorMessage = errorMessage
        self.onRetry = onRetry
    }

    public var body: some View {
        ContentUnavailableView {
            Label("Unable to Load Profile", systemImage: "exclamationmark.triangle")
        } description: {
            Text(errorMessage ?? "An unexpected error occurred while loading this profile.")
        } actions: {
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
