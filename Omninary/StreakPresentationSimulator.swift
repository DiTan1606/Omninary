import Foundation
import Combine

/// Local clock and state machine; never writes real account data or spends points.
@MainActor
final class StreakPresentationSimulator: ObservableObject {
    static let shared = StreakPresentationSimulator()
    enum FlameState: Equatable { case lit, dimmed, lost }
    @Published private(set) var isActive = false
    @Published private(set) var displayedDays = 7
    @Published private(set) var recoverableDays = 7
    @Published private(set) var flameState: FlameState = .dimmed
    @Published private(set) var winterShieldIsReady = false
    @Published private(set) var restoreWindowExpiresAt: Date?
    @Published private(set) var statusMessage = "Chuỗi 7 ngày chưa học hôm nay."
    @Published private(set) var requiresLearningAfterFreeze = false
    @Published private(set) var restoredToday = false
    @Published private(set) var lastFreezeAt: Date?
    @Published private(set) var simulatedNow: Date
    private var protectedThrough: Date
    private var learnedDates: Set<String> = []
    private var iceDates: Set<String> = []
    private var rescueDates: Set<String> = []
    private var timer: Timer?
    private var lastTick = Date()
    private var isExtraAccount = true
    private(set) var lastActionWasRepeat = false

    init(now: Date = Date()) {
        simulatedNow = now
        protectedThrough = StreakClock.calendar.date(byAdding: .day, value: -1,
                                                    to: StreakClock.calendar.startOfDay(for: now))!
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        let realNow = Date()
        defer { lastTick = realNow }
        guard isActive else { return }
        let oldDay = StreakClock.dayKey(simulatedNow)
        simulatedNow = simulatedNow.addingTimeInterval(realNow.timeIntervalSince(lastTick))
        if oldDay != StreakClock.dayKey(simulatedNow) {
            winterShieldIsReady = iceDates.contains(StreakClock.dayKey(simulatedNow))
            flameState = learnedDates.contains(StreakClock.dayKey(simulatedNow)) ? .lit : (displayedDays > 0 ? .dimmed : .lost)
        }
        refresh()
    }
    var isFlameLit: Bool { flameState == .lit }
    var isFlameDimmed: Bool { flameState == .dimmed }
    var isStreakLost: Bool { flameState == .lost }
    var hasActiveRestoreWindow: Bool {
        isExtraAccount && displayedDays == 0 && recoverableDays > 0 &&
        (restoreWindowExpiresAt.map { $0 > simulatedNow } ?? false)
    }
    var restoreCountdownString: String { StreakClock.countdown(until: restoreWindowExpiresAt, now: simulatedNow) }
    var freezeCountdownString: String {
        winterShieldIsReady ? StreakClock.countdown(until: StreakClock.nextMidnight(simulatedNow), now: simulatedNow) : "00:00:00"
    }
    var freezeDisabledReason: String? {
        if displayedDays <= 0 { return "Cần có chuỗi lớn hơn 0" }
        if isFlameLit { return "Hôm nay đã giữ chuỗi" }
        if winterShieldIsReady { return "Đang đóng băng" }
        if restoredToday { return "Phải học hôm nay sau khi cứu chuỗi" }
        if requiresLearningAfterFreeze { return "Phải học sau lần đóng băng trước" }
        if let lastFreezeAt, simulatedNow < lastFreezeAt.addingTimeInterval(7 * 86_400) { return "Chưa đủ 7 ngày từ lần dùng trước" }
        return nil
    }
    func setExtraAccess(_ enabled: Bool) { lastActionWasRepeat = false; isExtraAccount = enabled; refresh() }
    func keepStreak() {
        isActive = true
        lastActionWasRepeat = false
        guard !isFlameLit else {
            lastActionWasRepeat = true
            statusMessage = "Phiên thứ hai: chuỗi không tăng; quay về trang học, không chạy hiệu ứng."
            NotificationCenter.default.post(name: .returnToLearningTab, object: nil)
            return
        }
        let previous = displayedDays
        let wasFrozen = winterShieldIsReady
        displayedDays += 1
        recoverableDays = displayedDays
        protectedThrough = StreakClock.calendar.startOfDay(for: simulatedNow)
        learnedDates.insert(StreakClock.dayKey(simulatedNow))
        iceDates.remove(StreakClock.dayKey(simulatedNow))
        winterShieldIsReady = false
        restoreWindowExpiresAt = nil
        requiresLearningAfterFreeze = false
        restoredToday = false
        flameState = .lit
        statusMessage = "Đã học lần đầu hôm nay: chuỗi \(displayedDays) ngày, chuỗi lưu \(recoverableDays)."
        StreakActionPresenter.shared.enqueue(.learning, previousDays: previous, newDays: displayedDays,
            wasFrozen: wasFrozen, date: simulatedNow, isSimulation: true)
    }
    func showUnkeptStreak() {
        isActive = true
        if isFlameLit { advanceDay() }
        else { statusMessage = "Hiển thị trạng thái hiện tại, không chạy hiệu ứng." }
    }
    func forgetStreak() { advanceDay() }
    func advanceDay() {
        isActive = true
        simulatedNow = StreakClock.nextMidnight(simulatedNow)
        winterShieldIsReady = false
        flameState = displayedDays > 0 ? .dimmed : .lost
        refresh()
        statusMessage = "Đã sang \(StreakClock.dayKey(simulatedNow)). Chuỗi \(displayedDays), chuỗi lưu \(recoverableDays)."
    }
    func advanceSevenDays() {
        for _ in 0..<7 { advanceDay() }
    }
    func expireRestoreWindow() {
        if let expiry = restoreWindowExpiresAt { simulatedNow = expiry; refresh() }
    }
    private func refresh() {
        let today = StreakClock.calendar.startOfDay(for: simulatedNow)
        let lossDay = StreakClock.calendar.date(byAdding: .day, value: 2, to: protectedThrough)!
        if displayedDays > 0 && today >= lossDay {
            let expiry = StreakClock.calendar.date(byAdding: .day, value: 3, to: protectedThrough)!
            if isExtraAccount && recoverableDays > 0 && !restoredToday && expiry > simulatedNow {
                recoverableDays = displayedDays
                restoreWindowExpiresAt = expiry
            } else { recoverableDays = 0; restoreWindowExpiresAt = nil }
            displayedDays = 0
            flameState = .lost
            restoredToday = false
        }
        if displayedDays == 0 && (!isExtraAccount || !(restoreWindowExpiresAt.map { $0 > simulatedNow } ?? false)) {
            recoverableDays = 0
            restoreWindowExpiresAt = nil
        }
    }
    func useFireKeeper(isExtra: Bool) {
        isActive = true
        setExtraAccess(isExtra)
        guard hasActiveRestoreWindow else { statusMessage = "Không có quyền cứu chuỗi còn hiệu lực."; return }
        let missedDay = StreakClock.calendar.date(byAdding: .day, value: 1, to: protectedThrough)!
        let rescuedDayKey = StreakClock.dayKey(missedDay)
        rescueDates.insert(rescuedDayKey)
        let saved = recoverableDays
        displayedDays = saved
        recoverableDays = 0
        restoreWindowExpiresAt = nil
        protectedThrough = StreakClock.calendar.date(byAdding: .day, value: -1,
            to: StreakClock.calendar.startOfDay(for: simulatedNow))!
        restoredToday = true
        flameState = .dimmed
        winterShieldIsReady = false
        statusMessage = "Đã cứu \(saved) ngày. Phải học trước 0 giờ ngày mai; không thể đóng băng hoặc cứu tiếp nếu bỏ học."
        StreakActionPresenter.shared.enqueue(.restore, previousDays: 0, newDays: saved, date: simulatedNow, rescuedDayKey: rescuedDayKey, isSimulation: true)
    }
    func useWinterShield() {
        isActive = true
        guard freezeDisabledReason == nil else { statusMessage = freezeDisabledReason!; return }
        winterShieldIsReady = true
        lastFreezeAt = simulatedNow
        requiresLearningAfterFreeze = true
        protectedThrough = StreakClock.calendar.startOfDay(for: simulatedNow)
        iceDates.insert(StreakClock.dayKey(simulatedNow))
        statusMessage = "Đã đóng băng đến 0 giờ ngày mai. Cần học sau lần đóng băng và chờ đủ 7 ngày để dùng lại."
        StreakActionPresenter.shared.enqueue(.freeze, previousDays: displayedDays, newDays: displayedDays,
            date: simulatedNow, isSimulation: true)
    }
    func setStreak(days: Int) {
        isActive = true
        StreakActionPresenter.shared.clear()
        displayedDays = max(0, days)
        recoverableDays = displayedDays
        flameState = displayedDays > 0 ? .dimmed : .lost
        winterShieldIsReady = false
        restoreWindowExpiresAt = nil
        restoredToday = false
        requiresLearningAfterFreeze = false
        lastFreezeAt = nil
        learnedDates = []
        if displayedDays > 0 {
            for offset in 1...min(displayedDays, 366) {
                let date = StreakClock.calendar.date(byAdding: .day, value: -offset, to: simulatedNow)!
                learnedDates.insert(StreakClock.dayKey(date))
            }
        }
        iceDates = []
        rescueDates = []
        protectedThrough = StreakClock.calendar.date(byAdding: .day, value: -1,
            to: StreakClock.calendar.startOfDay(for: simulatedNow))!
        statusMessage = "Chuỗi \(displayedDays) màu xám, chưa học hôm nay."
    }
    func simulateMilestone(targetDays: Int) {
        guard [10, 30, 100, 200, 300].contains(targetDays) else { return }
        setStreak(days: targetDays - 1)
        keepStreak()
    }
    func resetSimulation() { simulatedNow = Date(); setStreak(days: 7) }
    func clearSimulation() {
        resetSimulation()
        isActive = false
        StreakActionPresenter.shared.clear()
        statusMessage = "Đang hiển thị dữ liệu thật."
    }
    func activityLogs(merging realLogs: [String: Bool]) -> [String: Bool] {
        guard isActive else { return realLogs }
        return Dictionary(uniqueKeysWithValues: learnedDates.map { ($0, true) })
    }
    func rescuedDates(merging realDates: Set<String>) -> Set<String> { isActive ? rescueDates : realDates }
    func frozenDates(merging realDates: Set<String>) -> Set<String> { isActive ? iceDates : realDates }
}
