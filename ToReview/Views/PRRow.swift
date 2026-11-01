import SwiftUI
import ToReviewCore

/// One pull request as a glass card. Fields beyond reference + title are controlled by `DisplayFields`.
struct PRRow: View {
    @Environment(AppModel.self) private var model
    let pr: PullRequest
    let fields: DisplayFields
    var compact = false

    private var isUnseen: Bool {
        model.accountSnapshot(pr.accountID)?.unseenIncomingIDs.contains(pr.id) ?? false
    }

    var body: some View {
        Button { model.open(pr) } label: {
            HStack(alignment: .top, spacing: 10) {
                ProviderBadge(kind: pr.kind)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(compact ? pr.shortReference : pr.reference)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        if pr.isDraft {
                            Text("Draft")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if fields.showUpdatedAt {
                            Text(pr.updatedAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(pr.title)
                        .font(compact ? .callout : .body)
                        .fontWeight(isUnseen ? .semibold : .regular)
                        .lineLimit(compact ? 1 : 2)
                        .multilineTextAlignment(.leading)

                    if fields.showAuthor || fields.showCIStatus || fields.showApprovals || fields.showComments {
                        HStack(spacing: 10) {
                            if fields.showAuthor { AuthorView(author: pr.author) }
                            if fields.showCIStatus { CIBadge(status: pr.ciStatus) }
                            if fields.showApprovals {
                                Label("\(pr.approvalsCount)", systemImage: pr.approvedByMe ? "checkmark.seal.fill" : "checkmark.seal")
                                    .foregroundStyle(pr.approvalsCount > 0 ? .green : .secondary)
                            }
                            if fields.showComments {
                                Label("\(pr.commentsCount)", systemImage: "bubble.left")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if isUnseen {
                    Circle().fill(.red).frame(width: 6, height: 6).offset(x: 3)
                }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        .help(pr.url.absoluteString)
        .contextMenu {
            Button("Open in Browser") { model.open(pr) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            }
        }
    }
}

struct ProviderBadge: View {
    let kind: ProviderKind

    var body: some View {
        Text(kind == .github ? "GH" : "GL")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(kind == .github ? Color(red: 0.14, green: 0.16, blue: 0.19) : Color(red: 0.99, green: 0.43, blue: 0.14), in: .rect(cornerRadius: 6))
            .accessibilityLabel(kind.displayName)
    }
}

struct AuthorView: View {
    let author: PRAuthor

    var body: some View {
        HStack(spacing: 4) {
            AvatarView(url: author.avatarURL, name: author.displayName, size: 14)
            Text(author.displayName)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}

struct AvatarView: View {
    let url: URL?
    var name: String = ""
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let local = AvatarCache().cachedURL(for: url), let image = NSImage(contentsOf: local) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let url {
                // Public hosts (github.com, gitlab.com) work without the cache; private ones
                // are filled in after the next sync downloads them with the account token.
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        InitialsAvatar(name: name, size: size)
                    }
                }
            } else {
                InitialsAvatar(name: name, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Colored circle with initials, used when no image is available (private GitLab, no avatar set).
struct InitialsAvatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color(hue: Initials.hue(for: name), saturation: 0.45, brightness: 0.75))
            Text(Initials.make(from: name))
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct CIBadge: View {
    let status: CIStatus

    var body: some View {
        if status != .none {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
                .labelStyle(.iconOnly)
                .help("CI: \(title)")
        }
    }

    private var title: String {
        switch status {
        case .success: "passed"
        case .failure: "failed"
        case .pending: "pending"
        case .running: "running"
        case .canceled: "canceled"
        case .skipped: "skipped"
        case .none: ""
        }
    }

    private var symbol: String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .pending: "clock"
        case .running: "circle.dotted.circle"
        case .canceled: "slash.circle"
        case .skipped: "forward.circle"
        case .none: ""
        }
    }

    private var color: Color {
        switch status {
        case .success: .green
        case .failure: .red
        case .pending, .running: .orange
        case .canceled, .skipped, .none: .secondary
        }
    }
}
