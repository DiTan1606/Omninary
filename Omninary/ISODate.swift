import Foundation

/// Supabase timestamps arrive with or without fractional seconds. Formatters are costly to
/// create, so both variants are built once and shared (date(from:) is thread-safe).
enum ISODate {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain = ISO8601DateFormatter()

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    static func string(_ date: Date = Date()) -> String { plain.string(from: date) }
}
