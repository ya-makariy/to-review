import SwiftUI
import ToReviewCore

/// `↓ 3• ↑ 2` — counters with a red dot when there are unseen incoming PRs.
struct StatusBarLabel: View {
    let model: AppModel
    var onWidthChange: (CGFloat) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Counter(symbol: "arrow.down", count: model.incomingCount, hasBadge: model.hasUnseen)
            if model.settings.statusBarMode == .incomingAndOutgoing {
                Counter(symbol: "arrow.up", count: model.outgoingCount, hasBadge: false)
            }
            if model.snapshot.hasErrors || model.snapshot.hasWarnings {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.snapshot.hasErrors ? .red : .orange)
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: onWidthChange)
        .animation(.snappy, value: model.incomingCount)
        .animation(.snappy, value: model.outgoingCount)
        .accessibilityLabel("\(model.incomingCount) incoming, \(model.outgoingCount) outgoing pull requests")
    }

    private struct Counter: View {
        let symbol: String
        let count: Int
        let hasBadge: Bool

        var body: some View {
            HStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .overlay(alignment: .topTrailing) {
                        if hasBadge {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                                .offset(x: 5, y: -3)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
            }
            .foregroundStyle(count == 0 ? .secondary : .primary)
        }
    }
}
