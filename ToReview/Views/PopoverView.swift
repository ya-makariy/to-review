import SwiftUI
import ToReviewCore

/// Compact list shown from the status item.
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    let windows: WindowManager

    private let limit = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.accounts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: .sectionHeaders) {
                        StatusBanners(compact: true)
                        section("Incoming", prs: model.snapshot.allIncoming, systemImage: "arrow.down")
                        if model.settings.statusBarMode == .incomingAndOutgoing {
                            section("Outgoing", prs: model.snapshot.allOutgoing, systemImage: "arrow.up")
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .frame(minHeight: 240, maxHeight: 620)
    }

    private var header: some View {
        HStack {
            Label("\(model.incomingCount) to review", systemImage: "arrow.down")
            Label("\(model.outgoingCount) yours", systemImage: "arrow.up")
                .foregroundStyle(.secondary)
            Spacer()
            if model.isSyncing {
                ProgressView().controlSize(.small)
            } else if model.snapshot.generatedAt > .distantPast {
                Text(model.snapshot.generatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func section(_ title: String, prs: [PullRequest], systemImage: String) -> some View {
        Section {
            if prs.isEmpty {
                Text(title == "Incoming" ? "Nothing to review 🎉" : "No open pull requests")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                GlassEffectContainer(spacing: 8) {
                    VStack(spacing: 6) {
                        ForEach(prs.prefix(limit)) { pr in
                            PRRow(pr: pr, fields: model.settings.listFields, compact: true)
                        }
                    }
                }
                if prs.count > limit {
                    Button("Show all \(prs.count)…") { windows.showMain() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        } header: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(prs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Add an account to get started")
                .font(.callout)
            Button("Open ToReview") { windows.showMain() }
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.isSyncing)
            Spacer()
            Button("Open ToReview") { windows.showMain() }
            Button { windows.showSettings() } label: { Image(systemName: "gearshape") }
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit ToReview")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
