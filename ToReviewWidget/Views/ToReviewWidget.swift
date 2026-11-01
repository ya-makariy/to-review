import SwiftUI
import ToReviewCore
import WidgetKit

struct ToReviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SharedStorage.widgetKind, intent: WidgetConfigIntent.self, provider: SnapshotTimelineProvider()) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ToReview")
        .description("Pull requests waiting for your review across GitHub and GitLab.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetRootView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReviewEntry

    var body: some View {
        if entry.snapshot.accounts.isEmpty && !entry.isPlaceholder {
            EmptyAccountsView()
        } else {
            switch family {
            case .systemSmall: SmallWidgetView(entry: entry)
            case .systemMedium: MediumWidgetView(entry: entry)
            default: LargeWidgetView(entry: entry)
            }
        }
    }
}

private struct EmptyAccountsView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add an account in ToReview")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared pieces

struct CounterView: View {
    let symbol: String
    let count: Int
    let caption: String
    var badge = false
    var prominent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: prominent ? 14 : 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.system(size: prominent ? 34 : 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Circle().fill(.red).frame(width: 8, height: 8).offset(x: 6, y: 2)
                        }
                    }
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetHeader: View {
    let entry: ReviewEntry

    var body: some View {
        HStack(spacing: 4) {
            if let page = entry.page {
                Button(intent: CycleAccountIntent(step: -1)) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                Text(entry.scopeTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button(intent: CycleAccountIntent(step: 1)) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Next account, \(page.index + 1) of \(page.count)")
            } else {
                Text(entry.scopeTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            if entry.hasProblems {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct WidgetFooter: View {
    let entry: ReviewEntry

    var body: some View {
        if entry.isStale, let last = entry.lastSuccess {
            Text("Updated \(last, format: .relative(presentation: .named)) · open ToReview to refresh")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else if entry.isStale {
            Text("Open ToReview to refresh")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

struct WidgetPRRow: View {
    let pr: PullRequest
    let fields: DisplayFields
    let unseen: Bool

    var body: some View {
        Link(destination: pr.url) {
            HStack(alignment: .top, spacing: 6) {
                Text(pr.kind == .github ? "GH" : "GL")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(pr.kind == .github ? Color(red: 0.14, green: 0.16, blue: 0.19) : Color(red: 0.99, green: 0.43, blue: 0.14), in: .rect(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(pr.shortReference)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if fields.showCIStatus, pr.ciStatus != .none {
                            Image(systemName: ciSymbol)
                                .font(.system(size: 8))
                                .foregroundStyle(ciColor)
                        }
                        Spacer(minLength: 0)
                        if fields.showUpdatedAt {
                            Text(pr.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(pr.title)
                        .font(.system(size: 11, weight: unseen ? .semibold : .regular))
                        .lineLimit(1)
                    if fields.showAuthor || fields.showApprovals || fields.showComments {
                        HStack(spacing: 6) {
                            if fields.showAuthor {
                                HStack(spacing: 3) {
                                    WidgetAvatar(url: pr.author.avatarURL, name: pr.author.displayName, size: 11)
                                    Text(pr.author.displayName).lineLimit(1)
                                }
                            }
                            if fields.showApprovals { Label("\(pr.approvalsCount)", systemImage: "checkmark.seal") }
                            if fields.showComments { Label("\(pr.commentsCount)", systemImage: "bubble.left") }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var ciSymbol: String {
        switch pr.ciStatus {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .pending, .running: "clock.fill"
        case .canceled, .skipped, .none: "slash.circle"
        }
    }

    private var ciColor: Color {
        switch pr.ciStatus {
        case .success: .green
        case .failure: .red
        case .pending, .running: .orange
        case .canceled, .skipped, .none: .secondary
        }
    }
}

struct WidgetAvatar: View {
    let url: URL?
    let name: String
    let size: CGFloat

    var body: some View {
        if let local = AvatarCache().cachedURL(for: url), let image = NSImage(contentsOf: local) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color(hue: Initials.hue(for: name), saturation: 0.45, brightness: 0.75))
                Text(Initials.make(from: name))
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Families

/// Two-line PR row for the small widget: reference + title only.
struct MiniPRRow: View {
    let pr: PullRequest
    let unseen: Bool

    var body: some View {
        Link(destination: pr.url) {
            HStack(spacing: 4) {
                Circle()
                    .fill(unseen ? Color.red : Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                Text(pr.shortReference)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(pr.title)
                    .font(.system(size: 9, weight: unseen ? .semibold : .regular))
                    .lineLimit(1)
            }
        }
    }
}

struct SmallWidgetView: View {
    let entry: ReviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(entry: entry)
            if !entry.incoming.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.incoming.prefix(2)) { pr in
                        MiniPRRow(pr: pr, unseen: isUnseen(pr))
                    }
                }
            }
            Spacer(minLength: 0)
            if entry.mode == .incomingOnly {
                CounterView(symbol: "arrow.down", count: entry.incoming.count, caption: "to review", badge: entry.hasUnseen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .bottom) {
                    CounterView(symbol: "arrow.down", count: entry.incoming.count, caption: "to review", badge: entry.hasUnseen)
                    Spacer()
                    CounterView(symbol: "arrow.up", count: entry.outgoing.count, caption: "yours", prominent: false)
                }
            }
            WidgetFooter(entry: entry)
        }
    }

    private func isUnseen(_ pr: PullRequest) -> Bool {
        entry.scope.first { $0.account.id == pr.accountID }?.unseenIncomingIDs.contains(pr.id) ?? false
    }
}

struct MediumWidgetView: View {
    let entry: ReviewEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(entry: entry)
                Spacer(minLength: 0)
                CounterView(symbol: "arrow.down", count: entry.incoming.count, caption: "to review", badge: entry.hasUnseen)
                if entry.mode == .incomingAndOutgoing {
                    CounterView(symbol: "arrow.up", count: entry.outgoing.count, caption: "yours", prominent: false)
                }
                WidgetFooter(entry: entry)
            }
            .frame(width: 110, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if entry.incoming.isEmpty {
                    Text("Nothing to review 🎉")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(entry.incoming.prefix(3)) { pr in
                        WidgetPRRow(pr: pr, fields: entry.fields, unseen: isUnseen(pr))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func isUnseen(_ pr: PullRequest) -> Bool {
        entry.scope.first { $0.account.id == pr.accountID }?.unseenIncomingIDs.contains(pr.id) ?? false
    }
}

struct LargeWidgetView: View {
    let entry: ReviewEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                WidgetHeader(entry: entry)
                    .frame(maxWidth: 180)
                Spacer()
                HStack(spacing: 14) {
                    CounterView(symbol: "arrow.down", count: entry.incoming.count, caption: "to review", badge: entry.hasUnseen, prominent: false)
                    if entry.mode == .incomingAndOutgoing {
                        CounterView(symbol: "arrow.up", count: entry.outgoing.count, caption: "yours", prominent: false)
                    }
                }
            }

            sectionLabel("Incoming", "arrow.down")
            if entry.incoming.isEmpty {
                Text("Nothing to review 🎉").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.incoming.prefix(incomingLimit)) { pr in
                    WidgetPRRow(pr: pr, fields: entry.fields, unseen: isUnseen(pr))
                }
                if entry.incoming.count > incomingLimit {
                    Text("+\(entry.incoming.count - incomingLimit) more").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }

            if entry.mode == .incomingAndOutgoing {
                sectionLabel("Outgoing", "arrow.up")
                if entry.outgoing.isEmpty {
                    Text("No open pull requests").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entry.outgoing.prefix(3)) { pr in
                        WidgetPRRow(pr: pr, fields: entry.fields, unseen: false)
                    }
                }
            }
            Spacer(minLength: 0)
            WidgetFooter(entry: entry)
        }
    }

    private var incomingLimit: Int { entry.mode == .incomingOnly ? 8 : 5 }

    private func sectionLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func isUnseen(_ pr: PullRequest) -> Bool {
        entry.scope.first { $0.account.id == pr.accountID }?.unseenIncomingIDs.contains(pr.id) ?? false
    }
}

#Preview("Small", as: .systemSmall) {
    ToReviewWidget()
} timeline: {
    ReviewEntry.sample(mode: .incomingAndOutgoing)
    ReviewEntry.sample(mode: .incomingOnly)
}

#Preview("Medium", as: .systemMedium) {
    ToReviewWidget()
} timeline: {
    ReviewEntry.sample(mode: .incomingAndOutgoing)
}

#Preview("Large", as: .systemLarge) {
    ToReviewWidget()
} timeline: {
    ReviewEntry.sample(mode: .incomingAndOutgoing)
}
