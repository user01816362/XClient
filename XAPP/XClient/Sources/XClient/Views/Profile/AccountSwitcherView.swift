import SwiftUI

/// View model managing account switcher presentation state.
@MainActor
public final class AccountSwitcherViewModel: ObservableObject {
    @Published public var showingAddAccountSheet: Bool = false
    @Published public var isCreatingAccount: Bool = false

    public init() {}
}

/// Account switcher drawer/sheet displaying active and stored accounts with switching and logout controls.
@MainActor
public struct AccountSwitcherView: View {
    @ObservedObject public var sessionManager: SessionManager
    @StateObject private var viewModel: AccountSwitcherViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var palette

    public init(sessionManager: SessionManager = .shared, viewModel: AccountSwitcherViewModel = AccountSwitcherViewModel()) {
        self.sessionManager = sessionManager
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                palette.secondaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 12) {
                            // 1. Account List
                            ForEach(sessionManager.storedAccounts) { account in
                                let isActive = sessionManager.currentState.activeAccount?.id == account.id

                                Button {
                                    sessionManager.switchToAccount(id: account.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 14) {
                                        // Avatar
                                        Circle()
                                            .fill(palette.accent.opacity(0.18))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Text(String(account.displayName.prefix(1)).uppercased())
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundStyle(palette.accent)
                                            )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.displayName)
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(palette.textPrimary)

                                            Text("@\(account.username)")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(palette.textSecondary)
                                        }

                                        Spacer()

                                        if isActive {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(palette.accent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(isActive ? palette.secondaryBackground : palette.background)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .strokeBorder(isActive ? palette.accent.opacity(0.3) : palette.borderDefault, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Divider()
                                .padding(.vertical, 8)

                            // 2. Action: Add existing account
                            Button {
                                viewModel.isCreatingAccount = false
                                viewModel.showingAddAccountSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Add an existing account")
                                        .font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            // 3. Action: Create new account
                            Button {
                                viewModel.isCreatingAccount = true
                                viewModel.showingAddAccountSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Create a new account")
                                        .font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                }
                                .foregroundStyle(palette.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            // 4. Logout Actions
                            if let active = sessionManager.currentState.activeAccount {
                                Divider()
                                    .padding(.vertical, 8)

                                Button {
                                    sessionManager.logout(id: active.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Log out of @\(active.username)")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }

                            if sessionManager.storedAccounts.count > 1 {
                                Button {
                                    sessionManager.logoutAll()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 18, weight: .semibold))
                                        Text("Log out of all accounts")
                                            .font(.system(size: 16, weight: .semibold))
                                        Spacer()
                                    }
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Accounts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                }
            }
            .sheet(isPresented: $viewModel.showingAddAccountSheet) {
                LoginSheetView(isCreatingAccount: viewModel.isCreatingAccount, sessionManager: sessionManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
