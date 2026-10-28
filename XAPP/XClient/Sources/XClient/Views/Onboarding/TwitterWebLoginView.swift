import SwiftUI
#if canImport(WebKit)
import WebKit
#endif
import XKitTransport
import XKitAPI
import XKitModels

/// View model governing the official X WebKit authentication flow and cookie extraction.
@MainActor
public final class TwitterWebLoginViewModel: ObservableObject {
    @Published public var isLoadingPage: Bool = true
    @Published public var isAuthenticating: Bool = false
    @Published public var statusMessage: String = "Connecting to X servers..."
    @Published public var errorMessage: String? = nil
    @Published public var showManualFallback: Bool = false

    @Published public var manualUsername: String = ""
    @Published public var manualAuthToken: String = ""
    @Published public var manualCt0: String = ""

    public init() {}
}

/// Multiplatform WebKit view presenting the real official X login and signup flow.
/// Intercepts authentic session cookies (`auth_token` and `ct0`) and provisions genuine accounts.
@MainActor
public struct TwitterWebLoginView: View {
    public let initialURL: URL
    @ObservedObject public var sessionManager: SessionManager
    @StateObject private var viewModel: TwitterWebLoginViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var palette

    public init(
        initialURL: URL = URL(string: "https://x.com/i/flow/login")!,
        sessionManager: SessionManager = .shared,
        viewModel: TwitterWebLoginViewModel = TwitterWebLoginViewModel()
    ) {
        self.initialURL = initialURL
        self.sessionManager = sessionManager
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                palette.background
                    .ignoresSafeArea()

                #if canImport(WebKit)
                if !viewModel.showManualFallback {
                    VStack(spacing: 0) {
                        if viewModel.isLoadingPage || viewModel.isAuthenticating {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(palette.accent)
                                .frame(height: 2)
                        }

                        PlatformWebViewRepresentable(
                            url: initialURL,
                            isLoading: $viewModel.isLoadingPage,
                            onAuthSuccess: { authToken, ct0, screenName, userId, rawCookies in
                                handleAuthenticationSuccess(
                                    authToken: authToken,
                                    ct0: ct0,
                                    screenName: screenName,
                                    userId: userId,
                                    rawCookies: rawCookies
                                )
                            }
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
                } else {
                    manualCookieFallbackView
                }
                #else
                manualCookieFallbackView
                #endif

                // Overlay when authenticating the intercepted session
                if viewModel.isAuthenticating {
                    ZStack {
                        Color.black.opacity(0.65)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(palette.accent)
                                .scaleEffect(1.2)

                            Text(viewModel.statusMessage)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)

                            Text("Securely syncing your real X account profile...")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(palette.borderDefault, lineWidth: 1)
                        )
                        .padding(32)
                    }
                    .transition(.opacity)
                }
            }
            .alert("Sign in could not be completed", isPresented: Binding(
                get: { viewModel.errorMessage != nil && !viewModel.showManualFallback },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .navigationTitle(viewModel.showManualFallback ? "Session Credentials" : "Sign In to X")
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

                #if canImport(WebKit)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.showManualFallback.toggle()
                        }
                    } label: {
                        Text(viewModel.showManualFallback ? "Web Login" : "Manual Cookies")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.accent)
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Manual Fallback View

    private var manualCookieFallbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Direct Live X Session")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.textPrimary)

                    Text("If web verification is blocked by bot challenge or you prefer headless authentication, provide your live X session cookies directly.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("X Handle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        TextField("@username", text: $viewModel.manualUsername)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Token (auth_token cookie)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        SecureField("40-character hex auth_token", text: $viewModel.manualAuthToken)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CSRF Token (ct0 cookie)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        TextField("ct0 token", text: $viewModel.manualCt0)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding()
                            .background(palette.secondaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(palette.borderDefault, lineWidth: 1))
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button {
                    let sanitizedUser = viewModel.manualUsername.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanToken = viewModel.manualAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanCt0 = viewModel.manualCt0.trimmingCharacters(in: .whitespacesAndNewlines)
                    handleAuthenticationSuccess(
                        authToken: cleanToken,
                        ct0: cleanCt0,
                        screenName: sanitizedUser.isEmpty ? nil : sanitizedUser,
                        userId: nil
                    )
                } label: {
                    HStack {
                        if viewModel.isAuthenticating {
                            ProgressView()
                                .tint(palette.background)
                        } else {
                            Text("Connect Account")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isManualSubmitDisabled ? palette.borderDefault : palette.textPrimary)
                    .foregroundStyle(palette.background)
                    .clipShape(Capsule())
                }
                .disabled(isManualSubmitDisabled)
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(24)
        }
    }

    private var isManualSubmitDisabled: Bool {
        viewModel.isAuthenticating || viewModel.manualAuthToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.manualCt0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Auth Interception Handler

    private func handleAuthenticationSuccess(
        authToken: String,
        ct0: String,
        screenName: String?,
        userId: String?,
        rawCookies: String? = nil
    ) {
        guard !viewModel.isAuthenticating else { return }
        viewModel.isAuthenticating = true
        viewModel.statusMessage = "Authenticated with X! Syncing profile..."
        viewModel.errorMessage = nil

        Task {
            do {
                let service = GraphQLTimelineService(transport: URLSessionTransport())
                // A public profile lookup does not prove that these cookies belong to that user.
                let user = try await service.verifyCredentials(
                    authToken: authToken, csrfToken: ct0, userId: userId, rawCookies: rawCookies
                )
                guard !user.id.isEmpty, !user.username.isEmpty,
                      userId == nil || userId == user.id else {
                    viewModel.isAuthenticating = false
                    viewModel.errorMessage = "The X session could not be matched to an account. Please try signing in again."
                    return
                }
                let account = Account(
                    id: user.id, username: user.username, displayName: user.name,
                    avatarURL: user.profileImageUrl.flatMap(URL.init), token: authToken,
                    csrfToken: ct0, authType: .webSession, rawCookieHeader: rawCookies
                )
                sessionManager.login(as: account)
                viewModel.isAuthenticating = false
                dismiss()
            } catch {
                viewModel.isAuthenticating = false
                viewModel.errorMessage = "X could not verify this session. Please check your connection and try signing in again."
            }
        }
    }
}

// MARK: - Multiplatform WebKit Representable

#if canImport(WebKit)

#if os(iOS)
import UIKit

public struct PlatformWebViewRepresentable: UIViewRepresentable {
    public let url: URL
    @Binding public var isLoading: Bool
    public let onAuthSuccess: (String, String, String?, String?, String?) -> Void

    public init(
        url: URL,
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?, String?) -> Void
    ) {
        self.url = url
        _isLoading = isLoading
        self.onAuthSuccess = onAuthSuccess
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView: webView)

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {}

    public func makeCoordinator() -> WebCoordinator {
        WebCoordinator(isLoading: $isLoading, onAuthSuccess: onAuthSuccess)
    }
}

#elseif os(macOS)
import AppKit

public struct PlatformWebViewRepresentable: NSViewRepresentable {
    public let url: URL
    @Binding public var isLoading: Bool
    public let onAuthSuccess: (String, String, String?, String?, String?) -> Void

    public init(
        url: URL,
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?, String?) -> Void
    ) {
        self.url = url
        _isLoading = isLoading
        self.onAuthSuccess = onAuthSuccess
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.attach(webView: webView)

        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        webView.load(request)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {}

    public func makeCoordinator() -> WebCoordinator {
        WebCoordinator(isLoading: $isLoading, onAuthSuccess: onAuthSuccess)
    }
}

#endif

@MainActor
public final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    private var isLoadingBinding: Binding<Bool>
    private let onAuthSuccess: (String, String, String?, String?, String?) -> Void
    private weak var webView: WKWebView?
    private var isAuthCaptured: Bool = false
    private var cookieStore: WKHTTPCookieStore?
    private var pollingTask: Task<Void, Never>?

    public init(
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?, String?) -> Void
    ) {
        self.isLoadingBinding = isLoading
        self.onAuthSuccess = onAuthSuccess
        super.init()
    }

    deinit {
        pollingTask?.cancel()
    }

    public func attach(webView: WKWebView) {
        self.webView = webView
        let store = webView.configuration.websiteDataStore.httpCookieStore
        self.cookieStore = store
        store.add(self)

        // Periodic polling check every 2 seconds to ensure no cookie is missed
        self.pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self = self, !self.isAuthCaptured, let store = self.cookieStore else { break }
                await self.checkCookies(in: store)
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Keep provider sign-in in this same isolated session when it asks for a new window.
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoadingBinding.wrappedValue = true
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoadingBinding.wrappedValue = false
        if let store = cookieStore {
            Task { @MainActor in
                await self.checkCookies(in: store)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoadingBinding.wrappedValue = false
    }

    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            await self.checkCookies(in: cookieStore)
        }
    }

    private func checkCookies(in store: WKHTTPCookieStore) async {
        guard !isAuthCaptured else { return }

        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        guard !isAuthCaptured else { return }
        // Keep the token, CSRF value, and identity from the same root cookie domain.
        // Combining cookies from x.com and twitter.com can mix unrelated sessions.
        let domains = ["x.com", "twitter.com"]
        var selected: [HTTPCookie] = []
        var token: String?
        var csrf: String?
        for domain in domains {
            let scoped = cookies.filter {
                let host = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain && ($0.expiresDate == nil || $0.expiresDate! > Date())
            }
            if let auth = scoped.first(where: { $0.name == "auth_token" && !$0.value.isEmpty }),
               let ct0 = scoped.first(where: { $0.name == "ct0" && !$0.value.isEmpty }) {
                selected = scoped
                token = auth.value
                csrf = ct0.value
                break
            }
        }
        guard let token, let csrf else { return }
        var userId: String?
        if let twid = selected.first(where: { $0.name == "twid" })?.value {
            let clean = (twid.removingPercentEncoding ?? twid)
                .replacingOccurrences(of: "u=", with: "")
                .replacingOccurrences(of: "\"", with: "")
            if !clean.isEmpty && clean.allSatisfy(\.isNumber) { userId = clean }
        }

        isAuthCaptured = true
        pollingTask?.cancel()
        pollingTask = nil

        let rawCookies = selected
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")

        // The authenticated credentials endpoint resolves the account identity.
        onAuthSuccess(token, csrf, nil, userId, rawCookies)
    }
}

#endif
