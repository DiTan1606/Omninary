// Compile with AppNotifications.swift, StreakActionPresenter.swift and StreakPresentationSimulator.swift.
import Foundation

@main
struct StreakSimulatorChecks {
    @MainActor static func main() {
        let now = StreakClock.parse("2026-09-25T05:00:00Z")!
        let s = StreakPresentationSimulator(now: now)
        var checks = 0
        func verify(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        s.setStreak(days: 3)
        verify(!s.isFlameLit && s.displayedDays == 3, "Initial state is gray without animation")
        verify(StreakActionPresenter.shared.consume(isSimulation: true) == nil, "Loading a scenario has no action")
        s.advanceDay()
        verify(s.displayedDays == 0 && s.recoverableDays == 3 && s.hasActiveRestoreWindow, "Missing day opens rescue")
        s.useFireKeeper(isExtra: true)
        verify(s.displayedDays == 3 && s.recoverableDays == 0 && !s.isFlameLit, "Rescue remains gray")
        verify(s.freezeDisabledReason != nil, "Cannot freeze rescued streak")
        s.advanceDay()
        verify(s.displayedDays == 0 && s.recoverableDays == 0 && !s.hasActiveRestoreWindow, "No second rescue after missed study")
        s.resetSimulation(); s.setStreak(days: 3)
        s.useWinterShield()
        verify(s.winterShieldIsReady && s.displayedDays == 3, "Freezing does not add a day")
        s.advanceDay()
        verify(!s.winterShieldIsReady && s.displayedDays == 3, "Ice melts next midnight, streak survives")
        verify(s.freezeDisabledReason != nil, "Cannot freeze consecutively")
        s.advanceDay()
        verify(s.hasActiveRestoreWindow && s.recoverableDays == 3, "Miss after frozen day opens rescue")
        s.expireRestoreWindow()
        verify(!s.hasActiveRestoreWindow && s.recoverableDays == 0, "Rescue expires exactly")
        s.resetSimulation(); s.setStreak(days: 3); s.useWinterShield(); s.keepStreak()
        verify(s.displayedDays == 4 && !s.winterShieldIsReady && !s.requiresLearningAfterFreeze, "Learning replaces ice")
        verify(s.freezeDisabledReason != nil, "Learning does not bypass seven-day cooldown")
        _ = StreakActionPresenter.shared.consume(isSimulation: true)
        s.keepStreak()
        verify(s.displayedDays == 4 && s.lastActionWasRepeat, "Second session does not increment")
        verify(StreakActionPresenter.shared.consume(isSimulation: true) == nil, "Second session does not animate")
        for _ in 0..<7 { s.advanceDay(); s.keepStreak() }
        s.advanceDay()
        verify(s.freezeDisabledReason == nil, "Can freeze again after seven days and study")
        for target in [10, 30, 100, 200, 300] {
            s.simulateMilestone(targetDays: target)
            let action = StreakActionPresenter.shared.consume(isSimulation: true)
            verify(action?.previousDays == target - 1 && action?.newDays == target, "Correct milestone request")
            verify(StreakActionPresenter.shared.consume(isSimulation: true) == nil, "Action plays once")
        }
        s.resetSimulation(); s.setExtraAccess(false); s.advanceDay()
        verify(!s.hasActiveRestoreWindow && s.recoverableDays == 0, "Normal account cannot rescue")
        let example = StreakPresentationSimulator(now: StreakClock.parse("2026-09-29T05:00:00Z")!)
        example.setStreak(days: 9)
        example.advanceDay()
        verify(example.rescuedDates(merging: []).isEmpty, "Missing alone does not mark red")
        example.useFireKeeper(isExtra: true)
        let rescueAction = StreakActionPresenter.shared.consume(isSimulation: true)
        verify(rescueAction?.rescuedDayKey == "2026-09-29", "Restoration animation targets the missed day")
        verify(example.rescuedDates(merging: []) == ["2026-09-29"], "September 29 is red")
        verify(example.activityLogs(merging: [:])["2026-09-29"] != true, "Rescued day is not marked studied")
        example.keepStreak()
        verify(example.displayedDays == 10 && example.activityLogs(merging: [:])["2026-09-30"] == true,
               "September 30 learned session reaches ten")
        verify(example.rescuedDates(merging: []) == ["2026-09-29"], "Red survives learning and milestone")
        let boundary = StreakPresentationSimulator(now: StreakClock.parse("2026-09-30T05:00:00Z")!)
        boundary.setStreak(days: 9); boundary.advanceDay(); boundary.useFireKeeper(isExtra: true)
        verify(boundary.rescuedDates(merging: []) == ["2026-09-30"], "October rescue marks September missed day")
        boundary.resetSimulation()
        verify(boundary.rescuedDates(merging: []).isEmpty, "Reset clears mock evidence")
        print("\(checks) simulator checks passed.")
    }
}
