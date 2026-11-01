import Foundation

public extension PRAuthor {
    /// Up to two letters for a placeholder avatar, e.g. "Vladislav Girin" → "VG", "erin" → "E".
    var initials: String { Initials.make(from: displayName) }
}

public extension Account {
    var initials: String { Initials.make(from: displayName.isEmpty ? username : displayName) }
}

public enum Initials {
    public static func make(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" || $0 == "_" })
            .filter { !$0.isEmpty }
        let letters = parts.prefix(2).compactMap { $0.first }
        if letters.isEmpty { return "?" }
        return String(letters).uppercased()
    }

    /// Deterministic hue (0...1) so the same person always gets the same color.
    public static func hue(for name: String) -> Double {
        let hash = name.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return Double(abs(hash) % 360) / 360
    }
}
