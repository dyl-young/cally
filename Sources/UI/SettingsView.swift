import SwiftUI
import ServiceManagement
import AppKit

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

            if !appState.calendars.isEmpty {
                Section("Calendars") {
                    ForEach(appState.calendars, id: \.id) { cal in
                        CalendarToggleRow(calendar: cal)
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
        .frame(width: 480, height: 480)
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
            get: { appState.selectedCalendarIDs.contains(calendar.id) },
            set: { isOn in
                var s = appState.selectedCalendarIDs
                if isOn { s.insert(calendar.id) } else { s.remove(calendar.id) }
                appState.selectedCalendarIDs = s
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
