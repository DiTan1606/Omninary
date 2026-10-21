import Foundation
import SwiftUI

@MainActor
final class OmniStreakRestoreManager: ObservableObject {
    static let shared = OmniStreakRestoreManager()
    @Published private(set) var savedStreak = 0
    @Published private(set) var expiresAt: Date?
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var countdownString = "00:00:00"
    private var timer: Timer?

    private init() {}

    var hasActiveRestoreWindow: Bool {
        savedStreak > 0 && (expiresAt?.timeIntervalSinceNow ?? 0) > 0
    }

    func canRestore(isExtra: Bool, currentEffectiveStreak: Int) -> Bool {
        isExtra && currentEffectiveStreak == 0 && hasActiveRestoreWindow
    }

    /// The server owns both the saved streak and its expiry. This object only
    /// exposes the current, observable representation to SwiftUI.
    func syncFromRemote(savedStreakCount: Int?, currentStreak: Int, expiresAtString: String?) {
        timer?.invalidate()
        timer = nil

        guard let expiresAtString,
              let parsedExpiresAt = Self.parseISO8601(expiresAtString),
              parsedExpiresAt > Date(),
              (savedStreakCount ?? 0) > 0,
              currentStreak == 0 else {
            clearDisplay()
            return
        }

        savedStreak = max(0, savedStreakCount ?? 0)
        expiresAt = parsedExpiresAt
        checkStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
        NotificationManager.shared.notifyStreakRestoreAvailable(expiresAt: parsedExpiresAt)
    }

    func checkStatus() {
        guard let expiresAt, expiresAt > Date(), savedStreak > 0 else {
            clearDisplay()
            return
        }
        remainingSeconds = max(0, Int(expiresAt.timeIntervalSinceNow))
        countdownString = Self.countdown(remainingSeconds)
    }

    private func clearDisplay() {
        timer?.invalidate()
        timer = nil
        savedStreak = 0
        expiresAt = nil
        remainingSeconds = 0
        countdownString = "00:00:00"
    }

    private static func countdown(_ seconds: Int) -> String {
        String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
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
