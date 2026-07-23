import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 460)
    }
}

struct AccountSettingsView: View {
    @Environment(Library.self) private var library

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Form {
            if let account = library.account {
                LabeledContent("Signed in as", value: account.email)
                LabeledContent("Membership") {
                    Text(account.membershipActive ? (account.membershipPlan ?? "Active").capitalized : "Lapsed")
                        .foregroundStyle(account.membershipActive ? .green : .orange)
                }

                Button("Sign Out") {
                    Task { await library.signOut() }
                }
            } else {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                } footer: {
                    Text("Your Chandlery membership unlocks every app in the catalog.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Sign In", action: signIn)
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || email.isEmpty || password.isEmpty)

                    if isWorking { ProgressView().controlSize(.small) }
                }
            }

            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    private func signIn() {
        guard !isWorking else { return }

        isWorking = true
        error = nil

        Task {
            error = await library.signIn(email: email, password: password)

            if error == nil { password = "" }

            isWorking = false
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(Library.self) private var library
    @State private var preferences = Preferences.shared

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                TextField("Server", text: $preferences.serverURLString)
                    .onSubmit { Task { await library.refresh() } }
            } footer: {
                Text("Where the catalog lives. Point this at your local Chandlery while developing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Install apps into", selection: $preferences.installLocation) {
                    ForEach(Preferences.InstallLocation.allCases) { location in
                        Text(location.title).tag(location)
                    }
                }

                Toggle("Check for updates automatically", isOn: $preferences.checkForUpdatesAutomatically)
                Toggle("Launch Purser at login", isOn: $preferences.launchAtLogin)
                Toggle("Also remove settings when uninstalling", isOn: $preferences.removeDataOnUninstall)
            }

            Section {
                LabeledContent("Catalog") {
                    Text("\(library.apps.count) apps")
                }

                LabeledContent("Last synced") {
                    Text(library.lastSyncedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                }

                Button("Sync Now") {
                    Task { await library.refresh() }
                }
                .disabled(library.isSyncing)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
