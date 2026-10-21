import Foundation
import SwiftUI

@MainActor
final class OmniDoublePointsManager: ObservableObject {
    static let shared = OmniDoublePointsManager()

    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var countdownString = "00:00:00"
    private var expiresAt: Date?
    private var timer: Timer?

    private init() {}

    func checkStatus() {
        guard let expiresAt, expiresAt > Date() else {
            clearDisplay()
            return
        }
        remainingSeconds = max(0, Int(expiresAt.timeIntervalSinceNow))
        countdownString = Self.countdown(remainingSeconds)
        isActive = true
    }

    func activate(userId: String?) {
        Task {
            do {
                let result = try await OmniRewardRepository.useOmniItem("double_points")
                syncFromRemote(untilDateString: result.double_points_until)
            } catch {
                print("Không thể kích hoạt Gấp đôi Canxi: \(error.localizedDescription)")
            }
        }
    }

    func syncFromRemote(untilDateString: String?) {
        timer?.invalidate()
        timer = nil
        guard let untilDateString, let date = Self.parseISO8601(untilDateString), date > Date() else {
            clearDisplay()
            return
        }
        expiresAt = date
        checkStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkStatus() }
        }
    }

    func applyActionResult(_ result: OmniActionResult) {
        guard let until = result.double_points_until else { return }
        syncFromRemote(untilDateString: until)
    }

    private func clearDisplay() {
        timer?.invalidate()
        timer = nil
        expiresAt = nil
        isActive = false
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

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6: (a, r, g, b) = (255, value >> 16, value >> 8 & 0xFF, value & 0xFF)
        case 8: (a, r, g, b) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
