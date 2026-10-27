import SwiftUI

/// View model managing onboarding and login UI interaction state.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var showingLoginModal: Bool = false
    @Published public var isCreatingAccount: Bool = false
    @Published public var usernameInput: String = ""
    @Published public var displayNameInput: String = ""
    @Published public var passwordInput: String = ""
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

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isCreatingAccount ? "Create your account" : "To get started, first enter your phone, email, or @username")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)

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

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    Button {
                        submitAuth()
                    } label: {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(palette.background)
                            } else {
                                Text(isCreatingAccount ? "Sign up" : "Log in")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(viewModel.usernameInput.isEmpty ? palette.borderDefault : palette.textPrimary)
                        .foregroundStyle(palette.background)
                        .clipShape(Capsule())
                    }
                    .disabled(viewModel.usernameInput.isEmpty || viewModel.isLoading)
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
}
