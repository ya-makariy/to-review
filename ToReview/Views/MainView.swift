import SwiftUI
import ToReviewCore

/// Main window: accounts in the sidebar, incoming / outgoing PRs in the detail pane.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .all
    @State private var editor: EditorTarget?
    @State private var removing: Account?
    @State private var showOutgoing = true

    enum SidebarItem: Hashable {
        case all
        case account(UUID)
    }

    enum EditorTarget: Identifiable {
        case add
        case edit(Account)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let account): account.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showOutgoing) {
                    Label("Show outgoing", systemImage: "arrow.up")
                }
                .help("Show pull requests you authored")

                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isSyncing)
                .keyboardShortcut("r")
                .help("Refresh now")

                Button { editor = .add } label: {
                    Label("Add account", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .help("Add a GitHub or GitLab account")

                Button { model.openSettings() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                .help("Settings")
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .add: AccountEditorSheet(account: nil)
            case .edit(let account): AccountEditorSheet(account: account)
            }
        }
        .confirmationDialog(
            "Remove \(removing?.title ?? "account")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { account in
            Button("Remove", role: .destructive) {
                model.remove(account)
                if selection == .account(account.id) { selection = .all }
            }
        } message: { _ in
            Text("The stored token is deleted from the Keychain. Pull requests from this account disappear from the lists and widgets.")
        }
        .onChange(of: model.accounts.count) { _, _ in
            if case .account(let id) = selection, !model.accounts.contains(where: { $0.id == id }) {
                selection = .all
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                Label {
                    HStack {
                        Text("All accounts")
                        Spacer()
                        Counts(incoming: model.incomingCount, outgoing: model.outgoingCount, hasUnseen: model.hasUnseen)
                    }
                } icon: {
                    Image(systemName: "tray.full")
                }
                .tag(SidebarItem.all)
            }

            Section("Accounts") {
                ForEach(model.accounts) { account in
                    AccountRow(account: account, snapshot: model.accountSnapshot(account.id))
                        .tag(SidebarItem.account(account.id))
                        .contextMenu {
                            Button("Edit…") { editor = .edit(account) }
                            Button("Refresh") { Task { await model.refresh(only: [account.id]) } }
                            Divider()
                            Button("Remove…", role: .destructive) { removing = account }
                        }
                }
                if model.accounts.isEmpty {
                    Button { editor = .add } label: {
                        Label("Add account…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        let scope = scopedAccounts
        if model.accounts.isEmpty {
            ContentUnavailableView {
                Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Connect a GitHub or GitLab account to see pull requests waiting for your review.")
            } actions: {
                Button("Add account") { editor = .add }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StatusBanners(accountID: selectedAccountID) { editor = .edit($0) }

                    PRSection(title: "Incoming", systemImage: "arrow.down",
                              prs: scope.flatMap(\.incoming).sorted { $0.updatedAt > $1.updatedAt },
                              emptyText: "Nothing to review 🎉",
                              fields: model.settings.listFields)

                    if showOutgoing {
                        PRSection(title: "Outgoing", systemImage: "arrow.up",
                                  prs: scope.flatMap(\.outgoing).sorted { $0.updatedAt > $1.updatedAt },
                                  emptyText: "You have no open pull requests",
                                  fields: model.settings.listFields)
                    }

                    if let generated = scope.compactMap(\.status.lastSuccess).max() {
                        Text("Updated \(generated, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(20)
            }
            .navigationTitle(detailTitle)
            .navigationSubtitle(detailSubtitle)
        }
    }

    private var selectedAccountID: UUID? {
        if case .account(let id) = selection { return id }
        return nil
    }

    private var scopedAccounts: [AccountSnapshot] {
        if let id = selectedAccountID {
            return model.snapshot.accounts.filter { $0.account.id == id }
        }
        return model.snapshot.accounts
    }

    private var detailTitle: String {
        if let id = selectedAccountID, let account = model.accounts.first(where: { $0.id == id }) {
            return account.title
        }
        return "All accounts"
    }

    private var detailSubtitle: String {
        let scope = scopedAccounts
        let incoming = scope.reduce(0) { $0 + $1.incoming.count }
        let outgoing = scope.reduce(0) { $0 + $1.outgoing.count }
        return "\(incoming) to review · \(outgoing) yours"
    }
}

// MARK: - Pieces

private struct AccountRow: View {
    let account: Account
    let snapshot: AccountSnapshot?

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(url: account.avatarURL, name: account.displayName, size: 24)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.background, lineWidth: 1.5))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(account.title).lineLimit(1)
                Text("\(account.kind.displayName) · \(account.host)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let snapshot {
                Counts(incoming: snapshot.incoming.count, outgoing: snapshot.outgoing.count, hasUnseen: snapshot.hasUnseen)
            }
        }
        .opacity(account.isEnabled ? 1 : 0.5)
    }

    private var statusColor: Color {
        switch snapshot?.status {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        case .neverSynced, nil: .gray
        }
    }
}

private struct Counts: View {
    let incoming: Int
    let outgoing: Int
    let hasUnseen: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("↓\(incoming)")
                .overlay(alignment: .topTrailing) {
                    if hasUnseen { Circle().fill(.red).frame(width: 5, height: 5).offset(x: 4, y: -2) }
                }
            Text("↑\(outgoing)").foregroundStyle(.secondary)
        }
        .font(.caption.monospacedDigit())
    }
}

private struct PRSection: View {
    let title: String
    let systemImage: String
    let prs: [PullRequest]
    let emptyText: String
    let fields: DisplayFields

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Text("\(prs.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if prs.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                GlassEffectContainer(spacing: 10) {
                    LazyVStack(spacing: 8) {
                        ForEach(prs) { pr in
                            PRRow(pr: pr, fields: fields)
                        }
                    }
                }
            }
        }
    }
}
