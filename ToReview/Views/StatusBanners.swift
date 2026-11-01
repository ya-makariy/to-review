import SwiftUI
import ToReviewCore

/// Warning / error strips for accounts whose last sync failed.
struct StatusBanners: View {
    @Environment(AppModel.self) private var model
    var accountID: UUID? = nil
    var compact = false
    var onEdit: ((Account) -> Void)? = nil

    private var troubled: [AccountSnapshot] {
        model.snapshot.accounts.filter { snap in
            (accountID == nil || snap.account.id == accountID) && !snap.status.isHealthy && snap.status != .neverSynced
        }
    }

    var body: some View {
        ForEach(troubled) { snap in
            let isError = if case .error = snap.status { true } else { false }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isError ? .red : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isError ? "\(snap.account.title): connection failed" : "\(snap.account.title): showing cached data")
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    Text(snap.status.errorMessage ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 3)
                    if !isError, let last = snap.status.lastSuccess {
                        Text("Last successful sync \(last, format: .relative(presentation: .named))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if let onEdit {
                    Button("Edit…") { onEdit(snap.account) }
                        .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isError ? Color.red : Color.orange).opacity(0.12), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder((isError ? Color.red : Color.orange).opacity(0.35)))
        }
    }
}
