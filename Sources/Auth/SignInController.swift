import Foundation

@MainActor
enum SignInController {
    static func signIn(appState: AppState) async {
        appState.authStatus = .signingIn
        do {
            let result = try await GoogleAuth.shared.signIn()
            appState.authStatus = .signedIn(account: result.account)
            appState.lastSyncError = nil
        } catch {
            appState.authStatus = .signedOut
            appState.lastSyncError = error.localizedDescription
        }
    }

    static func signOut(appState: AppState) async {
        if let account = appState.currentAccount {
            await GoogleAuth.shared.signOut(account: account)
        }
        EventCache.clear()
        appState.events = []
        appState.authStatus = .signedOut
    }
}
