import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            accountsSection

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
        .frame(width: 520, height: 560)
    }

    @ViewBuilder
    private var accountsSection: some View {
        if appState.accounts.isEmpty {
            Section("Accounts") {
                Button {
                    Task { await SignInController.addAccount(appState: appState) }
                } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(appState.addingAccount)
                if let err = appState.addAccountError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        } else {
            ForEach(appState.accounts) { account in
                AccountSection(account: account)
            }
            Section {
                Button {
                    Task { await SignInController.addAccount(appState: appState) }
                } label: {
                    Label("Add Google account", systemImage: "plus.circle")
                }
                .disabled(appState.addingAccount)
                if let err = appState.addAccountError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}

private struct AccountSection: View {
    let account: GoogleAccount
    @EnvironmentObject var appState: AppState

    var body: some View {
        Section(account.email) {
            if appState.accountsNeedingReconnect.contains(account.id) {
                Button("Reconnect") {
                    Task { await SignInController.addAccount(appState: appState) }
                }
                .buttonStyle(.borderedProminent)
            }

            ForEach(appState.calendarsForAccount(account.id), id: \.ref) { cal in
                CalendarToggleRow(calendar: cal)
            }

            Button("Sign out") {
                Task { await SignInController.removeAccount(account, appState: appState) }
            }
        }
    }
}

private struct CalendarToggleRow: View {
    let calendar: GoogleCalendarSummary
    @EnvironmentObject var appState: AppState

    var body: some View {
        Toggle(isOn: binding) {
            HStack(spacing: 8) {
                Circle()
                    .fill(swatch)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(calendar.summary)
                    if calendar.primary == true {
                        Text("Primary")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { appState.selectedCalendars.contains(calendar.ref) },
            set: { isOn in
                var s = appState.selectedCalendars
                if isOn { s.insert(calendar.ref) } else { s.remove(calendar.ref) }
                appState.selectedCalendars = s
            }
        )
    }

    private var swatch: Color {
        if let hex = calendar.backgroundColor, let nsColor = NSColor(hex: hex) {
            return Color(nsColor)
        }
        return .accentColor
    }
}
