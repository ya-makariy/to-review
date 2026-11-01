import AppIntents
import ToReviewCore
import WidgetKit

enum WidgetMode: String, AppEnum {
    case incomingAndOutgoing
    case incomingOnly

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Counters")
    static let caseDisplayRepresentations: [WidgetMode: DisplayRepresentation] = [
        .incomingAndOutgoing: "Incoming and outgoing",
        .incomingOnly: "Incoming only",
    ]
}

/// An account the user can pin a widget to. Backed by the shared account list.
struct AccountEntity: AppEntity, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Account")
    static let defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    init(_ account: Account) {
        id = account.id
        title = account.title
        subtitle = "\(account.kind.displayName) · \(account.host)"
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        SettingsStore().loadAccounts().filter { identifiers.contains($0.id) }.map(AccountEntity.init)
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        SettingsStore().loadAccounts().map(AccountEntity.init)
    }
}

/// Per-widget configuration (long-press → Edit Widget).
struct WidgetConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "ToReview"
    static let description = IntentDescription("Pull requests waiting for your review.")

    @Parameter(title: "Account", description: "Leave empty to page through all accounts.")
    var account: AccountEntity?

    @Parameter(title: "Counters", default: .incomingAndOutgoing)
    var mode: WidgetMode
}

/// Interactive ‹ › buttons in the small widget. The page index lives in shared defaults
/// so every widget instance in "all accounts" mode moves together.
struct CycleAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Next account"
    static let isDiscoverable = false

    @Parameter(title: "Step")
    var step: Int

    init() { step = 1 }
    init(step: Int) { self.step = step }

    func perform() async throws -> some IntentResult {
        let pages = WidgetPaging.pageCount()
        guard pages > 0 else { return .result() }
        let next = ((WidgetPaging.currentIndex() + step) % pages + pages) % pages
        WidgetPaging.setIndex(next)
        return .result()
    }
}

enum WidgetPaging {
    private struct State: Codable, Sendable { var pageIndex = 0 }
    private static var file: JSONFile<State> { JSONFile(directory: SharedStorage.directoryOrTemporary(), name: "widget-state.json") }

    /// Page 0 is "All accounts"; pages 1…n are individual accounts.
    static func pageCount() -> Int {
        let accounts = SettingsStore().loadAccounts().filter(\.isEnabled)
        return accounts.isEmpty ? 0 : accounts.count + 1
    }

    static func currentIndex() -> Int {
        file.read()?.pageIndex ?? 0
    }

    static func setIndex(_ index: Int) {
        file.writeOrLog(State(pageIndex: index))
    }
}
