import Foundation
import SwiftUI

@MainActor
final class OmniExtraordinaryManager: ObservableObject {
    static let shared = OmniExtraordinaryManager()

    @Published private(set) var isTrialActive = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var countdownString = "00:00:00"
    @Published private(set) var expiresAt: Date?
    @Published private(set) var isSimulationActive = false
    private var timer: Timer?
    private var remoteExpiresAt: Date?
    /// A missing date is only meaningful after the profile has answered from Supabase.
    /// Before then, preserve the current presentation instead of briefly treating a
    /// valid remote entitlement as expired.
    private var hasLoadedRemoteEntitlement = false

    private init() {}

    var isActive: Bool { isTrialActive }

    func checkStatus() {
        guard let expiresAt else {
            guard isSimulationActive || hasLoadedRemoteEntitlement else { return }
            applyExpiry(nil, isSimulation: isSimulationActive)
            return
        }

        guard expiresAt > Date() else {
            applyExpiry(nil, isSimulation: isSimulationActive)
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
        remoteExpiresAt = untilDateString.flatMap(Self.parseISO8601)
        applyExpiry(remoteExpiresAt, isSimulation: false)
    }

    /// Local-only simulator state. It never writes entitlement data back to Supabase.
    func simulateTrialNearExpiry(seconds: Int = 5, userId: String? = nil) {
        applyExpiry(Date().addingTimeInterval(Double(seconds)), isSimulation: true)
    }

    /// Returns the UI to the last server-confirmed entitlement without changing Supabase.
    func restoreRemotePresentation() {
        guard hasLoadedRemoteEntitlement else {
            timer?.invalidate()
            timer = nil
            isSimulationActive = false
            expiresAt = nil
            return
        }
        applyExpiry(remoteExpiresAt, isSimulation: false)
    }

    private func applyExpiry(_ date: Date?, isSimulation: Bool) {
        timer?.invalidate()
        timer = nil
        isSimulationActive = isSimulation
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

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }()
    }
}
