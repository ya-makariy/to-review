import SwiftUI
import ToReviewCore

/// Add or edit an account. Credentials are verified against the API before saving.
struct AccountEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let account: Account?

    @State private var kind: ProviderKind = .github
    @State private var hostText = "https://github.com"
    @State private var label = ""
    @State private var method: AuthMethod = .personalAccessToken
    @State private var token = ""
    @State private var isEnabled = true

    @State private var phase: Phase = .idle
    @State private var identity: ProviderIdentity?
    @State private var credential: Credential?
    @State private var deviceAuth: DeviceAuthorization?
    @State private var deviceTask: Task<Void, Never>?

    enum Phase: Equatable {
        case idle
        case verifying
        case waitingForBrowser
        case verified
        case failed(String)
    }

    private var isEditing: Bool { account != nil }

    private var baseURL: URL? {
        var text = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    private var isCloudHost: Bool { baseURL?.host() == kind.defaultBaseURL.host() }
    private var oauthClientID: String? { model.settings.oauthClientID(for: kind) }
    private var deviceFlowAvailable: Bool { isCloudHost && oauthClientID != nil }

    /// Editing without touching the token keeps the stored credential.
    private var canSave: Bool {
        if isEditing, token.isEmpty, method == account?.authMethod, baseURL == account?.baseURL { return true }
        return phase == .verified && identity != nil && credential != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isEditing ? "Edit account" : "Add account")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 14)

            Form {
                Section {
                    Picker("Provider", selection: $kind) {
                        ForEach(ProviderKind.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isEditing)
                    .onChange(of: kind) { _, new in
                        if hostText == kind.defaultBaseURL.absoluteString || hostText.isEmpty || hostText == ProviderKind.allCases.first(where: { $0 != new })?.defaultBaseURL.absoluteString {
                            hostText = new.defaultBaseURL.absoluteString
                        }
                        resetVerification()
                    }

                    TextField("Host", text: $hostText, prompt: Text("https://gitlab.company.com"))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .onChange(of: hostText) { _, _ in resetVerification() }

                    TextField("Label (optional)", text: $label, prompt: Text("Work"))
                }

                Section("Authentication") {
                    Picker("Method", selection: $method) {
                        Text("Personal access token").tag(AuthMethod.personalAccessToken)
                        if deviceFlowAvailable {
                            Text("Sign in with browser").tag(AuthMethod.oauthDevice)
                        }
                    }
                    .onChange(of: method) { _, _ in resetVerification() }

                    switch method {
                    case .personalAccessToken:
                        SecureField("Token", text: $token, prompt: Text(isEditing ? "Leave empty to keep the current token" : "glpat-… / ghp_…"))
                            .onChange(of: token) { _, _ in resetVerification() }
                        Text(kind.requiredScopesHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .oauthDevice:
                        if let deviceAuth, phase == .waitingForBrowser {
                            DeviceCodeView(auth: deviceAuth)
                        } else {
                            Text("You'll get a one-time code to enter on \(kind.defaultBaseURL.host() ?? "the website").")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isCloudHost, oauthClientID == nil, method == .personalAccessToken {
                        Text("Browser sign-in needs an OAuth client id. Add one in Settings → Accounts.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    HStack {
                        verifyButton
                        Spacer()
                        verificationStatus
                    }
                    if isEditing {
                        Toggle("Enabled", isOn: $isEnabled)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                if isEditing {
                    Text("Added \(account!.createdAt, format: .dateTime.day().month().year())")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Cancel") { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: load)
        .onDisappear { deviceTask?.cancel() }
    }

    // MARK: Verification UI

    @ViewBuilder
    private var verifyButton: some View {
        switch method {
        case .personalAccessToken:
            Button("Verify") { Task { await verifyToken() } }
                .disabled(token.isEmpty || baseURL == nil || phase == .verifying)
        case .oauthDevice:
            if phase == .waitingForBrowser {
                Button("Cancel sign-in") { deviceTask?.cancel(); resetVerification() }
            } else {
                Button("Sign in…") { startDeviceFlow() }
                    .disabled(baseURL == nil || phase == .verifying)
            }
        }
    }

    @ViewBuilder
    private var verificationStatus: some View {
        switch phase {
        case .idle:
            if isEditing, let account {
                Label("Signed in as \(account.username)", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
        case .verifying, .waitingForBrowser:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(phase == .verifying ? "Checking…" : "Waiting for approval…")
                    .foregroundStyle(.secondary)
            }
        case .verified:
            if let identity {
                HStack(spacing: 6) {
                    AvatarView(url: identity.avatarURL, name: identity.name ?? identity.login, size: 18)
                    Text(identity.name.map { "\($0) (@\(identity.login))" } ?? "@\(identity.login)")
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    // MARK: Logic

    private func load() {
        guard let account else { return }
        kind = account.kind
        hostText = account.baseURL.absoluteString
        label = account.label ?? ""
        method = account.authMethod
        isEnabled = account.isEnabled
    }

    private func resetVerification() {
        if phase != .idle { phase = .idle }
        identity = nil
        credential = nil
        deviceAuth = nil
    }

    private func verifyToken() async {
        guard let baseURL else { return }
        phase = .verifying
        do {
            let id = try await ProviderFactory.validate(kind: kind, baseURL: baseURL, token: token)
            identity = id
            credential = Credential(accessToken: token)
            phase = .verified
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func startDeviceFlow() {
        guard let baseURL, let clientID = oauthClientID else { return }
        phase = .verifying
        deviceTask = Task {
            let flow = DeviceFlow(kind: kind, baseURL: baseURL, clientID: clientID)
            do {
                let auth = try await flow.start()
                deviceAuth = auth
                phase = .waitingForBrowser
                NSWorkspace.shared.open(auth.verificationURLComplete ?? auth.verificationURL)
                let cred = try await flow.waitForToken(auth)
                phase = .verifying
                let id = try await ProviderFactory.validate(kind: kind, baseURL: baseURL, token: cred.accessToken)
                identity = id
                credential = cred
                phase = .verified
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let baseURL else { return }
        do {
            if var existing = account {
                existing.baseURL = baseURL
                existing.label = label.isEmpty ? nil : label
                existing.authMethod = method
                existing.isEnabled = isEnabled
                if let identity {
                    existing.username = identity.login
                    existing.displayName = identity.name ?? identity.login
                    existing.avatarURL = identity.avatarURL
                }
                try model.update(existing, credential: credential)
            } else if let identity, let credential {
                let new = Account(
                    kind: kind, baseURL: baseURL, authMethod: method,
                    username: identity.login, displayName: identity.name ?? identity.login,
                    avatarURL: identity.avatarURL, label: label.isEmpty ? nil : label
                )
                try model.add(new, credential: credential)
            }
            dismiss()
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func cancel() {
        deviceTask?.cancel()
        dismiss()
    }
}

/// Shows the one-time code the user must enter in the browser.
private struct DeviceCodeView: View {
    let auth: DeviceAuthorization

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter this code in your browser:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(auth.userCode)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(auth.userCode, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy code")
                Spacer()
                Button("Open browser") {
                    NSWorkspace.shared.open(auth.verificationURLComplete ?? auth.verificationURL)
                }
            }
            Text("Expires \(auth.expiresAt, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
