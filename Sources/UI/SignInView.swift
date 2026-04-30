import SwiftUI

struct SignInView: View {
    @EnvironmentObject var appState: AppState
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Cally")
                .font(.title2.weight(.semibold))
            Text("Your meetings, in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await SignInController.signIn(appState: appState) }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text(isSigningIn ? "Signing in…" : "Sign in with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSigningIn)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onChange(of: appState.lastSyncError) { _, value in
            error = value
        }
    }

    var isSigningIn: Bool {
        if case .signingIn = appState.authStatus { return true }
        return false
    }
}

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
