import SwiftUI
import ToReviewCore

/// The three settings panes; `WindowManager` hosts them in an `NSTabViewController`
/// with toolbar-style tabs so the window looks like a native preferences window.
enum SettingsPane: CaseIterable {
    case general, display, accounts

    var title: String {
        switch self {
        case .general: "General"
        case .display: "Display"
        case .accounts: "Accounts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .display: "list.bullet.rectangle"
        case .accounts: "person.2"
        }
    }

    @MainActor @ViewBuilder
    func view() -> some View {
        switch self {
        case .general: GeneralSettings()
        case .display: DisplaySettings()
        case .accounts: AccountsSettings()
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Sync") {
                Picker("Check for updates every", selection: $model.settings.pollInterval) {
                    ForEach(PollInterval.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Hide pull requests I already approved", isOn: $model.settings.hideApprovedByMe)
            }
            Section("Status bar") {
                Picker("Show", selection: $model.settings.statusBarMode) {
                    ForEach(StatusBarMode.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                Toggle("Notify about new pull requests", isOn: $model.settings.notificationsEnabled)
                Text("Widgets read the data this app fetches. Keep it running (or launching at login) so they stay fresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DisplaySettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("App and popover") {
                FieldToggles(fields: $model.settings.listFields)
            }
            Section("Widgets") {
                FieldToggles(fields: $model.settings.widgetFields)
            }
            Section {
                Text("Source, project, number and title are always shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private struct FieldToggles: View {
        @Binding var fields: DisplayFields

        var body: some View {
            Toggle("Author", isOn: $fields.showAuthor)
            Toggle("CI status", isOn: $fields.showCIStatus)
            Toggle("Time since last update", isOn: $fields.showUpdatedAt)
            Toggle("Approvals", isOn: $fields.showApprovals)
            Toggle("Comments", isOn: $fields.showComments)
        }
    }
}

struct AccountsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Account?
    @State private var adding = false
    @State private var githubClientID = ""
    @State private var gitlabClientID = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ForEach(model.accounts) { account in
                    HStack {
                        AvatarView(url: account.avatarURL, name: account.displayName, size: 22)
                        VStack(alignment: .leading) {
                            Text(account.title)
                            Text("\(account.kind.displayName) · \(account.host) · \(account.authMethod == .oauthDevice ? "OAuth" : "Token")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit…") { editing = account }
                            .controlSize(.small)
                    }
                }
                Button { adding = true } label: { Label("Add account…", systemImage: "plus") }
            } header: {
                Text("Accounts")
            }

            Section {
                TextField("GitHub client id", text: $githubClientID, prompt: Text("Iv1.…"))
                    .onSubmit(saveClientIDs)
                TextField("GitLab client id", text: $gitlabClientID, prompt: Text("64 hex characters"))
                    .onSubmit(saveClientIDs)
                Button("Save client ids", action: saveClientIDs)
            } header: {
                Text("OAuth client ids (browser sign-in)")
            } footer: {
                Text("Register an OAuth app with device flow enabled on github.com / gitlab.com and paste its client id here. Personal access tokens work without this. See README for the steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            githubClientID = model.settings.githubOAuthClientID ?? ""
            gitlabClientID = model.settings.gitlabOAuthClientID ?? ""
        }
        .sheet(item: $editing) { AccountEditorSheet(account: $0) }
        .sheet(isPresented: $adding) { AccountEditorSheet(account: nil) }
    }

    private func saveClientIDs() {
        model.settings.githubOAuthClientID = githubClientID.trimmingCharacters(in: .whitespaces)
        model.settings.gitlabOAuthClientID = gitlabClientID.trimmingCharacters(in: .whitespaces)
    }
}
