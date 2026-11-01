import Foundation

/// Reads and writes `snapshot.json` in the shared directory.
public struct SnapshotStore: Sendable {
    private let file: JSONFile<Snapshot>

    public init(directory: URL = SharedStorage.directoryOrTemporary()) {
        file = JSONFile(directory: directory, name: "snapshot.json")
    }

    public var url: URL { file.url }

    public func load() -> Snapshot {
        guard let snapshot = file.read() else { return .empty }
        return snapshot.version == Snapshot.currentVersion ? snapshot : .empty
    }

    public func save(_ snapshot: Snapshot) throws {
        try file.write(snapshot)
    }
}
