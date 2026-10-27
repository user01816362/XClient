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

    public init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        token: String,
        csrfToken: String? = nil,
        authType: AuthType = .oauth2,
        isGuest: Bool = false,
        createdAt: Date = Date()
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
        } else if isGuest {
            self.currentState = .guest(GuestSession(guestToken: "gt_active_session"))
        } else if let firstAccount = accounts.first {
            self.currentState = .authenticated(firstAccount)
        } else {
            // Default to demo/seed preview account if first launch, or unauthenticated
            let seedAccount = Account(
                id: "seed_liquidglass_1",
                username: "liquidglass",
                displayName: "Liquid Glass",
                avatarURL: URL(string: "https://abs.twimg.com/sticky/default_profile_images/default_profile_normal.png"),
                token: "oauth_mock_liquidglass_2026",
                csrfToken: nil,
                authType: .oauth2,
                isGuest: false
            )
            self.storedAccounts = [seedAccount]
            self.currentState = .authenticated(seedAccount)
            self.saveAccounts()
        }
    }

    // MARK: - Actions

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

    /// Continues as an anonymous guest user, activating a live guest token asynchronously.
    public func continueAsGuest() {
        let tempSession = GuestSession(guestToken: "gt_\(UUID().uuidString.prefix(12))")
        currentState = .guest(tempSession)
        userDefaults.set(true, forKey: isGuestKey)
        userDefaults.removeObject(forKey: activeAccountIdKey)

        Task {
            await activateLiveGuestToken()
        }
    }

    /// Queries the real Twitter guest token activation endpoint.
    public func activateLiveGuestToken() async {
        do {
            let transport = URLSessionTransport()
            let service = GraphQLTimelineService(transport: transport)
            let liveToken = try await service.activateGuestToken()
            let liveSession = GuestSession(guestToken: liveToken)
            self.currentState = .guest(liveSession)
        } catch {
            // Retain existing guest session if activation was throttled or offline
        }
    }

    public func switchToAccount(id: String) {
        guard let account = storedAccounts.first(where: { $0.id == id }) else { return }
        currentState = .authenticated(account)
        userDefaults.set(account.id, forKey: activeAccountIdKey)
        userDefaults.set(false, forKey: isGuestKey)
        isShowingAccountSwitcher = false
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
                userDefaults.set(false, forKey: isGuestKey)
            }
        }
    }

    public func logoutAll() {
        storedAccounts.removeAll()
        saveAccounts()
        currentState = .unauthenticated
        userDefaults.removeObject(forKey: activeAccountIdKey)
        userDefaults.set(false, forKey: isGuestKey)
        isShowingAccountSwitcher = false
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(storedAccounts) {
            userDefaults.set(data, forKey: accountsKey)
        }
    }
}
