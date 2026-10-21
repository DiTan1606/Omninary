import Foundation
import SwiftUI

@MainActor
final class OmniLearningHeartManager: ObservableObject {
    static let shared = OmniLearningHeartManager()

    static let defaultDailyHearts = 5
    @Published private(set) var remainingHearts = defaultDailyHearts
    @Published private(set) var resetDate: String?
    @Published private(set) var resetCountdownString = ""

    private var resetAt: Date?
    private var countdownTimer: Timer?
    private var isRefreshingAfterReset = false

    private init() {}

    var isExtra: Bool {
        OmniExtraordinaryManager.shared.isActive
    }

    var canStudy: Bool { isExtra || remainingHearts > 0 }

    /// Server data is authoritative. The app keeps only this observable display state.
    func syncFromRemote(remainingHearts: Int?, resetDate: String?, resetAt: String? = nil) {
        guard let remainingHearts else { return }
        self.remainingHearts = max(0, remainingHearts)
        self.resetDate = resetDate

        if let resetAt {
            self.resetAt = Self.parseISO8601(resetAt)
        }
        updateCountdown()
        updateCountdownTimer()
    }

    func applyActionResult(_ result: OmniActionResult) {
        syncFromRemote(remainingHearts: result.remaining_hearts, resetDate: nil)
    }

    func refreshHearts() async {
        guard AuthManager.shared.currentUser != nil else { return }

        do {
            let state = try await OmniRewardRepository.fetchLearningAccessState()
            syncFromRemote(
                remainingHearts: state.remaining_hearts,
                resetDate: state.reset_date,
                resetAt: state.reset_at
            )
        } catch {
            // Keep the last server-confirmed value. Starting or settling a session
            // still performs the same authoritative check on the server.
        }
    }

    func applySettlement(_ result: VocabularyLearningSettlementResult) {
        syncFromRemote(
            remainingHearts: result.remaining_hearts,
            resetDate: result.reset_date,
            resetAt: result.reset_at
        )
    }

    private func updateCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        guard !isExtra, remainingHearts == 0, let resetAt, resetAt > Date() else {
            if remainingHearts > 0 || isExtra {
                resetCountdownString = ""
            }
            return
        }

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
    }

    private func updateCountdown() {
        guard !isExtra, remainingHearts == 0, let resetAt else {
            resetCountdownString = ""
            return
        }

        let seconds = max(0, Int(ceil(resetAt.timeIntervalSinceNow)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        resetCountdownString = String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)

        guard seconds == 0, !isRefreshingAfterReset else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        isRefreshingAfterReset = true
        Task {
            await refreshHearts()
            isRefreshingAfterReset = false
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }()
    }
}
