import SwiftUI
import XKitTransport
import XKitAPI
import XKitModels

/// View model managing onboarding UI interaction state.
@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var showingLoginModal: Bool = false
    @Published public var isCreatingAccount: Bool = false
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
                    // 1. Create Account (Opens official X signup flow)
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

                    // 2. Sign In (Opens official X web login flow)
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

                    // 3. Guest Browsing (Activates live guest token from X API)
                    Button {
                        viewModel.isLoading = true
                        Task {
                            do {
                                try await sessionManager.continueAsGuestAsync()
                            } catch {
                                sessionManager.continueAsGuest()
                            }
                            viewModel.isLoading = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(palette.accent)
                            } else {
                                Text("Continue as guest")
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .foregroundStyle(palette.accent)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
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
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Official authentication sheet presenting the real X server web login flow.
@MainActor
public struct LoginSheetView: View {
    public let isCreatingAccount: Bool
    @ObservedObject public var sessionManager: SessionManager

    public init(
        isCreatingAccount: Bool = false,
        sessionManager: SessionManager = .shared,
        viewModel: OnboardingViewModel? = nil
    ) {
        self.isCreatingAccount = isCreatingAccount
        self.sessionManager = sessionManager
    }

    public var body: some View {
        TwitterWebLoginView(
            initialURL: isCreatingAccount
                ? URL(string: "https://x.com/i/flow/signup")!
                : URL(string: "https://x.com/i/flow/login")!,
            sessionManager: sessionManager
        )
    }
}
