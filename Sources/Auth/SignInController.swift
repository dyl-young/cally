import Foundation

@MainActor
enum SignInController {
    static func addAccount(appState: AppState) async {
        appState.addingAccount = true
        appState.addAccountError = nil
        defer { appState.addingAccount = false }
        do {
            let result = try await GoogleAuth.shared.signIn()
            result.account.save()
            if !appState.accounts.contains(where: { $0.id == result.account.id }) {
                appState.accounts.append(result.account)
            }
            appState.accountsNeedingReconnect.remove(result.account.id)
        } catch {
            appState.addAccountError = error.localizedDescription
        }
    }

    static func removeAccount(_ account: GoogleAccount, appState: AppState) async {
        await GoogleAuth.shared.signOut(account: account)
        appState.accounts.removeAll { $0.id == account.id }
        appState.selectedCalendars = appState.selectedCalendars.filter { $0.accountID != account.id }
        appState.accountsNeedingReconnect.remove(account.id)
        if appState.accounts.isEmpty {
            EventCache.clear()
            appState.events = []
        }
    }
}
