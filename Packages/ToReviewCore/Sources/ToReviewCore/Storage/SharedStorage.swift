import Foundation
import os

/// Location and coders for the files shared between the app and the widget.
///
/// Both processes are sandboxed and ad-hoc signed, so an App Group is unavailable
/// (macOS denies the container without a provisioning profile). Instead both
/// entitlements carry a `temporary-exception.files.home-relative-path.read-write`
/// for `~/Library/Application Support/ToReview/`, and everything shared is a JSON
/// file in that directory.
public enum SharedStorage {
    public static let appBundleID = "com.ya-makariy.toreview"
    public static let widgetKind = "ToReviewWidget"
    /// Must match the path in both `.entitlements` files.
    public static let relativePath = "Library/Application Support/ToReview"

    public static let log = Logger(subsystem: appBundleID, category: "core")

    /// `~/Library/Application Support/ToReview`, created on first use.
    /// Uses the real home directory: inside the sandbox `NSHomeDirectory()` points at the container.
    public static func directoryURL() throws -> URL {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        let url = URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Falls back to a temp directory when the shared one is unavailable (unit tests, broken install).
    public static func directoryOrTemporary() -> URL {
        if let url = try? directoryURL() { return url }
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("ToReview", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Tiny helper: one `Codable` value per JSON file, written atomically.
public struct JSONFile<Value: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(directory: URL, name: String) {
        self.url = directory.appendingPathComponent(name)
    }

    public func read() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try SharedStorage.makeDecoder().decode(Value.self, from: data)
        } catch {
            SharedStorage.log.error("Decode failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public func write(_ value: Value) throws {
        let data = try SharedStorage.makeEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// Logs instead of throwing — for callers where a failed write isn't actionable.
    public func writeOrLog(_ value: Value) {
        do { try write(value) } catch {
            SharedStorage.log.error("Write failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
