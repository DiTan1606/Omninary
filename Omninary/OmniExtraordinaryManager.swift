import Foundation
import SwiftUI

@MainActor
final class OmniExtraordinaryManager: ObservableObject {
    static let shared = OmniExtraordinaryManager()

    @Published private(set) var isTrialActive = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var countdownString = "00:00:00"
    @Published private(set) var expiresAt: Date?
    private var timer: Timer?
    /// A missing date is only meaningful after the profile has answered from Supabase.
    /// Before then, preserve the current presentation instead of briefly treating a
    /// valid remote entitlement as expired.
    private var hasLoadedRemoteEntitlement = false

    private init() {}

    var isActive: Bool { isTrialActive }

    func checkStatus() {
        guard let expiresAt else {
            guard hasLoadedRemoteEntitlement else { return }
            applyExpiry(nil)
            return
        }

        guard expiresAt > Date() else {
            applyExpiry(nil)
            return
        }

        isTrialActive = true
        remainingSeconds = max(0, Int(expiresAt.timeIntervalSinceNow))
        countdownString = Self.countdown(remainingSeconds)
    }

    func activateAccess(days: Int) async throws {
        let result = try await OmniRewardRepository.activateExtraordinaryAccess(days: days)
        syncFromRemote(untilDateString: result.extraordinary_trial_until)
    }

    func syncFromRemote(untilDateString: String?) {
        hasLoadedRemoteEntitlement = true
        applyExpiry(untilDateString.flatMap(Self.parseISO8601))
    }

    private func applyExpiry(_ date: Date?) {
        timer?.invalidate()
        timer = nil
        expiresAt = date
        guard let date, date > Date() else {
            isTrialActive = false
            remainingSeconds = 0
            countdownString = "00:00:00"
            synchronizeInterface(.ditandnary)
            NotificationCenter.default.post(name: NSNotification.Name("OmniExtraordinaryTrialChanged"), object: nil)
            return
        }

        isTrialActive = true
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        remainingSeconds = seconds
        countdownString = Self.countdown(seconds)
        synchronizeInterface(.extraordinary)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
        NotificationCenter.default.post(name: NSNotification.Name("OmniExtraordinaryTrialChanged"), object: nil)
    }

    private func synchronizeInterface(_ mode: AppInterfaceMode) {
#if DEBUG
        // Chỉ giữ lựa chọn giao diện thử nghiệm; quyền sử dụng vẫn đồng bộ như cũ.
        guard !UserDefaults.standard.bool(forKey: "development_interface_preview_enabled") else { return }
#endif
        UserDefaults.standard.set(mode.rawValue, forKey: "development_interface_mode")
    }

    private static func countdown(_ totalSeconds: Int) -> String {
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        if days > 0 { return String(format: "%dd %02dh", days, hours) }
        return String(format: "%02d:%02d:%02d", hours, (totalSeconds % 3_600) / 60, totalSeconds % 60)
    }

    private static func parseISO8601(_ value: String) -> Date? { ISODate.parse(value) }
}
