import Foundation
import Combine
import XKitTransport
import XKitAPI

/// Supported authentication modes for accounts in XClient.
public enum AuthType: String, Codable, Hashable, Sendable {
    case oauth2
    case webSession
    case guest
}

/// Represents an authenticated or stored user account in XClient.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let avatarURL: URL?
    public let token: String
    public let csrfToken: String?
    public let authType: AuthType
    public let isGuest: Bool
    public let createdAt: Date
    public let rawCookieHeader: String?

    public init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        token: String,
        csrfToken: String? = nil,
        authType: AuthType = .oauth2,
        isGuest: Bool = false,
        createdAt: Date = Date(),
        rawCookieHeader: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.token = token
        self.csrfToken = csrfToken
        self.authType = authType
        self.isGuest = isGuest
        self.createdAt = createdAt
        self.rawCookieHeader = rawCookieHeader
    }
}

/// Represents an active guest session using reverse-engineered guest tokens.
public struct GuestSession: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let guestToken: String
    public let activatedAt: Date

    public init(id: String = UUID().uuidString, guestToken: String, activatedAt: Date = Date()) {
        self.id = id
        self.guestToken = guestToken
        self.activatedAt = activatedAt
    }
}

/// Represents the high-level authentication session lifecycle of XClient.
public enum SessionState: Equatable, Sendable {
    case unauthenticated
    case guest(GuestSession)
    case authenticated(Account)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    public var isGuest: Bool {
        if case .guest = self { return true }
        return false
    }

    public var activeAccount: Account? {
        if case .authenticated(let account) = self { return account }
        return nil
    }

    public var activeGuestToken: String? {
        if case .guest(let session) = self { return session.guestToken }
        return nil
    }
}

/// Core authentication and multi-account state manager for XClient.
/// Fully thread-safe and isolated to `@MainActor` in Swift 6.
@MainActor
public final class SessionManager: ObservableObject, Sendable {
    public static let shared = SessionManager()

    @Published public private(set) var currentState: SessionState
    @Published public private(set) var storedAccounts: [Account]
    @Published public var isShowingLoginSheet: Bool = false
    @Published public var isShowingAccountSwitcher: Bool = false

    private let userDefaults: UserDefaults
    private let accountsKey = "com.xproject.xclient.storedAccounts"
    private let activeAccountIdKey = "com.xproject.xclient.activeAccountId"
    private let isGuestKey = "com.xproject.xclient.isGuestSession"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // 1. Load accounts from storage
        var accounts: [Account] = []
        if let data = userDefaults.data(forKey: accountsKey),
           let decoded = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = decoded
        }
        self.storedAccounts = accounts

        // 2. Determine initial state
        let activeId = userDefaults.string(forKey: activeAccountIdKey)
        let isGuest = userDefaults.bool(forKey: isGuestKey)

        if let activeId = activeId, let account = accounts.first(where: { $0.id == activeId }) {
            self.currentState = .authenticated(account)
            if account.username == "x_user" || account.displayName == "Not Me" || account.username.isEmpty {
                Task { [weak self] in
                    await self?.refreshActiveAccountInfo()
                }
            }
        } else if let firstAccount = accounts.first {
            self.currentState = .authenticated(firstAccount)
            if firstAccount.username == "x_user" || firstAccount.displayName == "Not Me" || firstAccount.username.isEmpty {
                Task { [weak self] in
                    await self?.refreshActiveAccountInfo()
                }
            }
        } else if isGuest, let savedGuestToken = userDefaults.string(forKey: "com.xproject.xclient.activeGuestToken"), !savedGuestToken.isEmpty {
            self.currentState = .guest(GuestSession(guestToken: savedGuestToken))
        } else {
            // Clean production first launch: show official OnboardingView
            self.storedAccounts = []
            self.currentState = .unauthenticated
        }
    }

    // MARK: - Actions

    public func updateActiveAccount(username: String, displayName: String, avatarURL: URL? = nil) {
        guard case .authenticated(let current) = currentState else { return }
        let updated = Account(
            id: current.id,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL ?? current.avatarURL,
            token: current.token,
            csrfToken: current.csrfToken,
            authType: current.authType,
            isGuest: current.isGuest,
            createdAt: current.createdAt,
            rawCookieHeader: current.rawCookieHeader
        )
        login(as: updated)
    }

    /// Automatically syncs user credentials with X if username or displayName is a placeholder
    public func refreshActiveAccountInfo() async {
        guard case .authenticated(let account) = currentState, account.authType == .webSession else { return }
        let transport = URLSessionTransport()
        let graphql = GraphQLTimelineService(transport: transport)

        // 1. Try UserByRestId if numeric id is available
        if !account.id.isEmpty, !account.id.starts(with: "user_") {
            if let user = try? await graphql.fetchUserByRestId(
                userId: account.id,
                authToken: account.token,
                csrfToken: account.csrfToken ?? "",
                rawCookies: account.rawCookieHeader
            ), !user.username.isEmpty {
                updateActiveAccount(
                    username: user.username,
                    displayName: user.name,
                    avatarURL: user.profileImageUrl.flatMap(URL.init)
                )
                return
            }
        }

        // 2. Try verifyCredentials
        if let user = try? await graphql.verifyCredentials(
            authToken: account.token,
            csrfToken: account.csrfToken ?? "",
            userId: account.id,
            rawCookies: account.rawCookieHeader
        ), !user.username.isEmpty {
            updateActiveAccount(
                username: user.username,
                displayName: user.name,
                avatarURL: user.profileImageUrl.flatMap(URL.init)
            )
            return
        }
    }

    public func login(as account: Account) {
        if let index = storedAccounts.firstIndex(where: { $0.id == account.id }) {
            storedAccounts[index] = account
        } else {
            storedAccounts.append(account)
        }
        currentState = .authenticated(account)
        userDefaults.set(account.id, forKey: activeAccountIdKey)
        userDefaults.set(false, forKey: isGuestKey)
        saveAccounts()
        isShowingLoginSheet = false

        XClientService.shared.updateCredentials(
            token: account.token,
            currentUserId: account.id,
            csrfToken: account.csrfToken
        )
    }

    /// Logs in using official web session cookie credentials (`auth_token` and `ct0`).
    public func loginWithCookieSession(
        authToken: String,
        ct0: String,
        username: String,
        displayName: String? = nil
    ) {
        let cleanUsername = username.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuth = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCsrf = ct0.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (displayName?.isEmpty ?? true) ? cleanUsername.capitalized : (displayName ?? cleanUsername)

        let account = Account(
            id: "user_\(cleanUsername.lowercased())",
            username: cleanUsername.lowercased(),
            displayName: name,
            avatarURL: URL(string: "https://abs.twimg.com/sticky/default_profile_images/default_profile_normal.png"),
            token: cleanAuth,
            csrfToken: cleanCsrf,
            authType: .webSession,
            isGuest: false
        )
        login(as: account)
    }

    private let activeGuestTokenKey = "com.xproject.xclient.activeGuestToken"

    /// Continues as an anonymous guest user, activating a live guest token from X servers.
    public func continueAsGuest() {
        let tempSession = GuestSession(guestToken: userDefaults.string(forKey: activeGuestTokenKey) ?? "")
        currentState = .guest(tempSession)
        userDefaults.set(true, forKey: isGuestKey)
        userDefaults.removeObject(forKey: activeAccountIdKey)

        Task {
            await activateLiveGuestToken()
        }
    }

    /// Asynchronously activates a live Twitter/X guest token and transitions session state.
    @discardableResult
    public func continueAsGuestAsync() async throws -> String {
        let transport = URLSessionTransport()
        let service = GraphQLTimelineService(transport: transport)
        let liveToken = try await service.activateGuestToken()
        let liveSession = GuestSession(guestToken: liveToken)
        self.currentState = .guest(liveSession)
        self.userDefaults.set(true, forKey: isGuestKey)
        self.userDefaults.set(liveToken, forKey: activeGuestTokenKey)
        self.userDefaults.removeObject(forKey: activeAccountIdKey)
        return liveToken
    }

    /// Queries the real Twitter/X guest token activation endpoint (`POST https://api.twitter.com/1.1/guest/activate.json`).
    public func activateLiveGuestToken() async {
        do {
            let transport = URLSessionTransport()
            let service = GraphQLTimelineService(transport: transport)
            let liveToken = try await service.activateGuestToken()
            let liveSession = GuestSession(guestToken: liveToken)
            self.currentState = .guest(liveSession)
            self.userDefaults.set(liveToken, forKey: activeGuestTokenKey)
        } catch {
            // Keep existing guest state if offline
        }
    }

    public func switchToAccount(id: String) {
        guard let account = storedAccounts.first(where: { $0.id == id }) else { return }
        currentState = .authenticated(account)
        userDefaults.set(account.id, forKey: activeAccountIdKey)
        userDefaults.set(false, forKey: isGuestKey)
        isShowingAccountSwitcher = false

        XClientService.shared.updateCredentials(
            token: account.token,
            currentUserId: account.id,
            csrfToken: account.csrfToken
        )
    }

    public func logout(id: String) {
        storedAccounts.removeAll { $0.id == id }
        saveAccounts()

        if case .authenticated(let current) = currentState, current.id == id {
            if let next = storedAccounts.first {
                switchToAccount(id: next.id)
            } else {
                currentState = .unauthenticated
                userDefaults.removeObject(forKey: activeAccountIdKey)
                userDefaults.removeObject(forKey: activeGuestTokenKey)
                userDefaults.set(false, forKey: isGuestKey)
            }
        }
    }

    public func logoutAll() {
        storedAccounts.removeAll()
        saveAccounts()
        currentState = .unauthenticated
        userDefaults.removeObject(forKey: activeAccountIdKey)
        userDefaults.removeObject(forKey: activeGuestTokenKey)
        userDefaults.set(false, forKey: isGuestKey)
        isShowingAccountSwitcher = false
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(storedAccounts) {
            userDefaults.set(data, forKey: accountsKey)
        }
    }
}
