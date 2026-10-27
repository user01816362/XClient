import Foundation
import Combine

/// Represents an authenticated or stored user account in XClient.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let avatarURL: URL?
    public let token: String
    public let isGuest: Bool
    public let createdAt: Date

    public init(
        id: String,
        username: String,
        displayName: String,
        avatarURL: URL? = nil,
        token: String,
        isGuest: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.token = token
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

    public func continueAsGuest() {
        let guestSession = GuestSession(guestToken: "gt_\(UUID().uuidString.prefix(12))")
        currentState = .guest(guestSession)
        userDefaults.set(true, forKey: isGuestKey)
        userDefaults.removeObject(forKey: activeAccountIdKey)
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
