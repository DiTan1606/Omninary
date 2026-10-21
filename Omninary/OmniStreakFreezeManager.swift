import Foundation
import SwiftUI
import Supabase

@MainActor
final class OmniStreakFreezeManager: ObservableObject {
    static let shared = OmniStreakFreezeManager()

    @Published private(set) var isFrozenToday = false
    @Published private(set) var isLearnedToday = false
    @Published private(set) var currentStreak = 0
    @Published private(set) var rescuedDates: Set<String> = []
    @Published private(set) var frozenDates: Set<String> = []
    private var lastLearningDate: String?
    @Published private(set) var freezeUsedAt: Date?
    @Published private(set) var freezeRequiresLearning = false
    @Published private(set) var restoredOn: String?
    @Published private(set) var freezeCountdown = "00:00:00"
    private var timer: Timer?

    private static let vietnamTimeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    private static var vietnamCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = vietnamTimeZone
        return calendar
    }

    private init() {
        // Remove data left behind by the retired Developer simulator.
        [
            "development_streak_preview_enabled",
            "development_streak_preview_days",
            "development_streak_preview_is_learned",
            "development_streak_preview_freeze_today",
            "development_streak_preview_saved_days"
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    private var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = Self.vietnamTimeZone
        return formatter.string(from: Date())
    }

    var freezeDisabledReason: String? {
        if currentStreak <= 0 { return "Cần có chuỗi lớn hơn 0" }
        if isLearnedToday { return "Hôm nay đã giữ chuỗi" }
        if isFrozenToday { return "Đang đóng băng bảo vệ chuỗi" }
        if restoredOn != nil { return "Phải học hôm nay sau khi cứu chuỗi" }
        if freezeRequiresLearning { return "Phải học sau lần đóng băng trước" }
        if let freezeUsedAt, freezeUsedAt.addingTimeInterval(7 * 86_400) > Date() {
            return "Chưa đủ 7 ngày từ lần dùng trước"
        }
        return nil
    }

    var effectiveStreak: Int { currentStreak }
    var isFlameLit: Bool { isLearnedToday && effectiveStreak > 0 }

    func checkStatus() {
        isLearnedToday = lastLearningDate == today && currentStreak > 0
        isFrozenToday = frozenDates.contains(today) && !isLearnedToday
        freezeCountdown = isFrozenToday ? StreakClock.countdown(until: StreakClock.nextMidnight()) : "00:00:00"
        if isFlameLit { isFrozenToday = false; frozenDates.remove(today) }
    }

    func syncFromRemote(freezeDateString: String?) {
        frozenDates.remove(today)
        if let freezeDateString { frozenDates.insert(freezeDateString) }
        checkStatus()
        isFrozenToday = freezeDateString == today && !isFlameLit
    }

    func syncFromRemote(userId: String) async {
        try? await refreshFromRemote(userId: userId)
    }

    func refreshFromRemote(userId: String) async throws {
        guard !StreakPresentationSimulator.shared.isActive else {
            throw NSError(domain: "OmninaryStreak", code: 409,
                userInfo: [NSLocalizedDescriptionKey: "Hãy đưa ứng dụng về dữ liệu thật trong Cài đặt trước khi học."])
        }
        let stats = try await UserProgressRepository.refreshStreakState()
        applyRemoteState(stats)
        if let dates = try? await supabase.from("streak_freeze_history")
            .select("date").eq("user_id", value: userId).execute().value as [FrozenDay] {
            frozenDates = Set(dates.map(\.date))
            checkStatus()
        }
        if let dates = try? await supabase.from("streak_restore_history")
            .select("date").eq("user_id", value: userId).execute().value as [FrozenDay] {
            rescuedDates = Set(dates.map(\.date))
        }
    }

    private struct FrozenDay: Decodable { let date: String }

    func applyActionResult(_ result: OmniActionResult) {
        if let day = result.streak_rescued_date { rescuedDates.insert(day) }
        applyRemoteState(.init(streak_count: result.streak_count ?? currentStreak,
            saved_streak_count: result.saved_streak_count ?? 0,
            last_learning_date: result.last_learning_date,
            streak_freeze_date: result.streak_freeze_date,
            streak_restore_expires_at: result.streak_restore_expires_at,
            streak_protected_through: result.streak_protected_through,
            streak_freeze_used_at: result.streak_freeze_used_at,
            streak_freeze_requires_learning: result.streak_freeze_requires_learning,
            streak_restored_on: result.streak_restored_on))
    }

    func applyRemoteState(_ stats: UserProgressRepository.StreakStateResult) {
        freezeUsedAt = StreakClock.parse(stats.streak_freeze_used_at)
        freezeRequiresLearning = stats.streak_freeze_requires_learning ?? false
        restoredOn = stats.streak_restored_on
        currentStreak = stats.streak_count
        lastLearningDate = stats.last_learning_date
        OmniStreakRestoreManager.shared.syncFromRemote(
            savedStreakCount: stats.saved_streak_count,
            currentStreak: stats.streak_count,
            expiresAtString: stats.streak_restore_expires_at
        )
        syncFromRemote(freezeDateString: stats.streak_freeze_date)
        if stats.is_extra == false || stats.streak_restored_on != nil {
            NotificationManager.shared.cancelPotentialStreakRestoreAlert()
        } else if stats.is_extra == true, currentStreak > 0,
                  let anchor = StreakClock.parseDay(stats.streak_protected_through) {
            NotificationManager.shared.schedulePotentialStreakRestoreAlert(afterLearningOn: anchor)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
    }

}
