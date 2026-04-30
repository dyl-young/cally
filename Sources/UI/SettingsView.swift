import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Account") {
                if let account = appState.currentAccount {
                    LabeledContent("Signed in") { Text(account.email) }
                    Button("Sign out") {
                        Task { await SignInController.signOut(appState: appState) }
                    }
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                    Button("Sign in with Google") {
                        Task { await SignInController.signIn(appState: appState) }
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        do {
                            if value {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin.toggle()
                        }
                    }
                Toggle("Notify 1 minute before meetings", isOn: $appState.notificationsEnabled)
            }

            if let last = appState.lastSyncDate {
                Section {
                    LabeledContent("Last sync") {
                        Text(last, style: .relative)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}
