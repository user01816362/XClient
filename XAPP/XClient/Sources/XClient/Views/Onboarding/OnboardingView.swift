import SwiftUI
import XKitTransport
import XKitAPI
import XKitModels

/// View model managing onboarding and login UI interaction state.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var showingLoginModal: Bool = false
    @Published public var isCreatingAccount: Bool = false
    @Published public var authModeTab: Int = 0 // 0: Standard, 1: Real X Platform Session
    @Published public var usernameInput: String = ""
    @Published public var displayNameInput: String = ""
    @Published public var passwordInput: String = ""
    @Published public var authTokenInput: String = ""
    @Published public var ct0Input: String = ""
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {}
}

/// Onboarding splash and welcome screen matching the official X app flow and Apple HIG.
@MainActor
public struct OnboardingView: View {
    @ObservedObject private var sessionManager: SessionManager
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.colorPalette) private var palette

    public init(sessionManager: SessionManager = .shared, viewModel: OnboardingViewModel = OnboardingViewModel()) {
        self.sessionManager = sessionManager
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            // Subtle ambient Liquid Glass illumination
            RadialGradient(
                gradient: Gradient(colors: [
                    palette.accent.opacity(0.12),
                    Color.clear
                ]),
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Logo
                HStack {
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                }
                .padding(.top, 48)

                Spacer()

                // Welcome Header
                VStack(alignment: .leading, spacing: 14) {
                    Text("See what’s happening in the world right now.")
                        .font(.system(size: 34, weight: .heavy, design: .default))
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(2)

                    Text("Join today.")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)

                Spacer()

                // Action Buttons
                VStack(spacing: 14) {
                    // 1. Create Account
                    Button {
                        viewModel.isCreatingAccount = true
                        viewModel.showingLoginModal = true
                    } label: {
                        Text("Create account")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(palette.textPrimary)
                            .foregroundStyle(palette.background)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // 2. Sign In
                    Button {
                        viewModel.isCreatingAccount = false
                        viewModel.showingLoginModal = true
                    } label: {
                        Text("Sign in")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                Capsule()
                                    .strokeBorder(palette.borderDefault, lineWidth: 1)
                            )
                            .foregroundStyle(palette.textPrimary)
                    }
                    .buttonStyle(.plain)

                    // 3. Guest Browsing
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            sessionManager.continueAsGuest()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Continue as guest")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $viewModel.showingLoginModal) {
            LoginSheetView(
                isCreatingAccount: viewModel.isCreatingAccount,
                sessionManager: sessionManager,
                viewModel: viewModel
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Modal authentication sheet allowing account entry or creation.
@MainActor
public struct LoginSheetView: View {
    public let isCreatingAccount: Bool
    @ObservedObject public var sessionManager: SessionManager
    @ObservedObject public var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var palette

    public init(
        isCreatingAccount: Bool = false,
        sessionManager: SessionManager = .shared,
        viewModel: OnboardingViewModel = OnboardingViewModel()
    ) {
        self.isCreatingAccount = isCreatingAccount
        self.sessionManager = sessionManager
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                palette.secondaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Picker("Login Mode", selection: $viewModel.authModeTab) {
                        Text("Standard").tag(0)
                        Text("Real X Session").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 12)

                    if viewModel.authModeTab == 0 {
                        // Standard / Demo Flow
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isCreatingAccount ? "Create your account" : "To get started, enter your username or email")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isCreatingAccount {
                            TextField("Display name", text: $viewModel.displayNameInput)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(palette.background)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                        }

                        TextField("Username or email", text: $viewModel.usernameInput)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))

                        SecureField("Password", text: $viewModel.passwordInput)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                    } else {
                        // Real X Platform Session
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Connect Real X Account")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(palette.textPrimary)

                            Text("Enter your X handle and web session cookies to connect directly to the live X API.")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("@username", text: $viewModel.usernameInput)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))

                        SecureField("auth_token cookie", text: $viewModel.authTokenInput)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))

                        TextField("ct0 / csrf cookie", text: $viewModel.ct0Input)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    Button {
                        if viewModel.authModeTab == 1 {
                            submitLiveSessionAuth()
                        } else {
                            submitAuth()
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(palette.background)
                            } else {
                                Text(viewModel.authModeTab == 1 ? "Connect Live Account" : (isCreatingAccount ? "Sign up" : "Log in"))
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(isSubmitDisabled ? palette.borderDefault : palette.textPrimary)
                        .foregroundStyle(palette.background)
                        .clipShape(Capsule())
                    }
                    .disabled(isSubmitDisabled)
                    .buttonStyle(.plain)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(isCreatingAccount ? "Sign Up" : "Log In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var isSubmitDisabled: Bool {
        if viewModel.isLoading { return true }
        if viewModel.authModeTab == 1 {
            return viewModel.usernameInput.isEmpty || viewModel.authTokenInput.isEmpty || viewModel.ct0Input.isEmpty
        }
        return viewModel.usernameInput.isEmpty
    }

    private func submitAuth() {
        viewModel.isLoading = true
        viewModel.errorMessage = nil

        let sanitized = viewModel.usernameInput.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = viewModel.displayNameInput.isEmpty ? sanitized.capitalized : viewModel.displayNameInput

        let account = Account(
            id: "user_\(sanitized.lowercased())",
            username: sanitized.lowercased(),
            displayName: resolvedDisplayName,
            avatarURL: URL(string: "https://abs.twimg.com/sticky/default_profile_images/default_profile_normal.png"),
            token: "token_\(UUID().uuidString)",
            isGuest: false
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            sessionManager.login(as: account)
            viewModel.isLoading = false
            dismiss()
        }
    }

    private func submitLiveSessionAuth() {
        viewModel.isLoading = true
        viewModel.errorMessage = nil

        let sanitizedUser = viewModel.usernameInput.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let authToken = viewModel.authTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let ct0 = viewModel.ct0Input.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let transport = URLSessionTransport()
                let service = GraphQLTimelineService(transport: transport)
                let liveUser = try await service.fetchUserByScreenName(
                    screenName: sanitizedUser,
                    authToken: authToken,
                    csrfToken: ct0
                )

                let account = Account(
                    id: liveUser.id,
                    username: liveUser.username,
                    displayName: liveUser.name,
                    avatarURL: liveUser.profileImageUrl.flatMap(URL.init),
                    token: authToken,
                    csrfToken: ct0,
                    authType: .webSession,
                    isGuest: false
                )
                sessionManager.login(as: account)
                viewModel.isLoading = false
                dismiss()
            } catch {
                sessionManager.loginWithCookieSession(
                    authToken: authToken,
                    ct0: ct0,
                    username: sanitizedUser
                )
                viewModel.isLoading = false
                dismiss()
            }
        }
    }
}
