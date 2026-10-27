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
                            onAuthSuccess: { authToken, ct0, screenName, userId in
                                handleAuthenticationSuccess(
                                    authToken: authToken,
                                    ct0: ct0,
                                    screenName: screenName,
                                    userId: userId
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
        userId: String?
    ) {
        guard !viewModel.isAuthenticating else { return }
        viewModel.isAuthenticating = true
        viewModel.statusMessage = "Authenticated with X! Syncing profile..."
        viewModel.errorMessage = nil

        Task {
            var resolvedScreenName = screenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var resolvedDisplayName: String? = nil
            var resolvedAvatarURL: URL? = nil
            var resolvedUserId = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // 1. Fetch genuine user profile from X GraphQL
            if !resolvedScreenName.isEmpty {
                do {
                    let transport = URLSessionTransport()
                    let service = GraphQLTimelineService(transport: transport)
                    let liveUser = try await service.fetchUserByScreenName(
                        screenName: resolvedScreenName,
                        authToken: authToken,
                        csrfToken: ct0
                    )
                    resolvedUserId = liveUser.id
                    resolvedScreenName = liveUser.username
                    resolvedDisplayName = liveUser.name
                    resolvedAvatarURL = liveUser.profileImageUrl.flatMap(URL.init)
                } catch {
                    // Non-fatal, continue with extracted credentials
                }
            }

            // 2. Default fallbacks if screen_name was not immediately extractable from DOM
            if resolvedUserId.isEmpty {
                resolvedUserId = resolvedScreenName.isEmpty ? "user_\(UUID().uuidString.prefix(8))" : "user_\(resolvedScreenName.lowercased())"
            }
            if resolvedScreenName.isEmpty {
                resolvedScreenName = "x_user"
            }
            let displayName = resolvedDisplayName ?? resolvedScreenName

            let account = Account(
                id: resolvedUserId,
                username: resolvedScreenName,
                displayName: displayName,
                avatarURL: resolvedAvatarURL ?? URL(string: "https://abs.twimg.com/sticky/default_profile_images/default_profile_normal.png"),
                token: authToken,
                csrfToken: ct0,
                authType: .webSession,
                isGuest: false
            )

            await MainActor.run {
                sessionManager.login(as: account)
                viewModel.isAuthenticating = false
                dismiss()
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
    public let onAuthSuccess: (String, String, String?, String?) -> Void

    public init(
        url: URL,
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?) -> Void
    ) {
        self.url = url
        _isLoading = isLoading
        self.onAuthSuccess = onAuthSuccess
    }

    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
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
    public let onAuthSuccess: (String, String, String?, String?) -> Void

    public init(
        url: URL,
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?) -> Void
    ) {
        self.url = url
        _isLoading = isLoading
        self.onAuthSuccess = onAuthSuccess
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
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
public final class WebCoordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    private var isLoadingBinding: Binding<Bool>
    private let onAuthSuccess: (String, String, String?, String?) -> Void
    private weak var webView: WKWebView?
    private var isAuthCaptured: Bool = false
    private var cookieStore: WKHTTPCookieStore?
    private var pollingTask: Task<Void, Never>?

    public init(
        isLoading: Binding<Bool>,
        onAuthSuccess: @escaping (String, String, String?, String?) -> Void
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

        var authToken: String?
        var csrfToken: String?
        var userId: String?

        for cookie in cookies {
            let domain = cookie.domain.lowercased()
            guard domain.contains("x.com") || domain.contains("twitter.com") else { continue }

            if cookie.name == "auth_token" && !cookie.value.isEmpty {
                authToken = cookie.value
            } else if cookie.name == "ct0" && !cookie.value.isEmpty {
                csrfToken = cookie.value
            } else if cookie.name == "twid" && !cookie.value.isEmpty {
                let clean = cookie.value
                    .replacingOccurrences(of: "u%3D", with: "")
                    .replacingOccurrences(of: "u=", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                userId = clean
            }
        }

        guard let token = authToken, let csrf = csrfToken else {
            return
        }

        isAuthCaptured = true
        pollingTask?.cancel()
        pollingTask = nil

        // Try extracting screen_name from page DOM
        var screenName: String?
        if let webView = self.webView {
            let js = """
            (function() {
                try {
                    var m = document.documentElement.outerHTML.match(/"screen_name":"([^"]+)"/);
                    if (m && m[1]) return m[1];
                    var u = document.documentElement.outerHTML.match(/"username":"([^"]+)"/);
                    if (u && u[1]) return u[1];
                } catch(e) {}
                return "";
            })()
            """
            screenName = await withCheckedContinuation { continuation in
                webView.evaluateJavaScript(js) { result, _ in
                    let name = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (name?.isEmpty ?? true) ? nil : name)
                }
            }
        }

        onAuthSuccess(token, csrf, screenName, userId)
    }
}

#endif
