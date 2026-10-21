import Foundation

/// Ephemeral actions, never recreated by a remote refresh or persisted at launch.
@MainActor
final class StreakActionPresenter {
    static let shared = StreakActionPresenter()
    enum Kind { case learning, freeze, restore }
    struct Request {
        let kind: Kind
        let previousDays: Int
        let newDays: Int
        let wasFrozen: Bool
        let dayKey: String
        let rescuedDayKey: String?
        let isSimulation: Bool
    }
    private var pending: Request?

    func enqueue(_ kind: Kind, previousDays: Int, newDays: Int, wasFrozen: Bool = false,
                 date: Date = Date(), rescuedDayKey: String? = nil, isSimulation: Bool = false) {
        let missedDay = kind == .restore
            ? (rescuedDayKey ?? StreakClock.dayKey(StreakClock.calendar.date(byAdding: .day, value: -1, to: date)!))
            : nil
        pending = Request(kind: kind, previousDays: previousDays, newDays: newDays,
                          wasFrozen: wasFrozen, dayKey: StreakClock.dayKey(date), rescuedDayKey: missedDay, isSimulation: isSimulation)
    }
    func consume(isSimulation: Bool) -> Request? {
        defer { pending = nil }
        guard pending?.isSimulation == isSimulation else { return nil }
        return pending
    }
    func clear() { pending = nil }
}

enum StreakClock {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return value
    }
    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }
    static func parseDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: value)
    }
    static func nextMidnight(_ date: Date = Date()) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    static func countdown(until date: Date?, now: Date = Date()) -> String {
        let seconds = max(0, Int(date?.timeIntervalSince(now) ?? 0))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}
