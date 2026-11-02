import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshPendingReminderBranding()
    }

    private func refreshPendingReminderBranding() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            guard let existingRequest = requests.first(where: { $0.identifier == "daily_reminder" }),
                  existingRequest.content.title != "Omninary",
                  let updatedContent = existingRequest.content.mutableCopy() as? UNMutableNotificationContent else {
                return
            }

            updatedContent.title = "Omninary"
            let updatedRequest = UNNotificationRequest(
                identifier: existingRequest.identifier,
                content: updatedContent,
                trigger: existingRequest.trigger
            )
            center.add(updatedRequest)
        }
    }
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if !granted, let error {
                print("Lỗi yêu cầu quyền thông báo: \(error)")
            }
        }
    }
    
    // 1. Nhắc nhở học mỗi ngày (Tính năng chính)
    func scheduleDailyReminder(at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Omninary"
        content.body = "Đã đến giờ học từ vựng rồi, vào app học ngay thôi! 🔥"
        content.sound = .default
        content.userInfo = ["type": "daily_reminder"]
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        
        // Adding the same identifier replaces the old reminder only after scheduling succeeds.
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelDailyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        center.removeDeliveredNotifications(withIdentifiers: ["daily_reminder"])
    }

    /// Shows the rescue-window alert once for each server-issued expiry. The
    /// expiry itself remains authoritative on Supabase; this is presentation.
    @MainActor
    func notifyStreakRestoreAvailable(expiresAt: Date) {
        let formatter = ISO8601DateFormatter()
        let expiryKey = formatter.string(from: expiresAt)
        let defaultsKey = streakRestoreNotificationKey
        guard UserDefaults.standard.string(forKey: defaultsKey) != expiryKey else { return }
        UserDefaults.standard.set(expiryKey, forKey: defaultsKey)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak_restore_available"])
        let content = UNMutableNotificationContent()
        content.title = "Ngọn lửa cần được giữ"
        content.body = "Bạn còn \(StreakClock.countdown(until: expiresAt)) để dùng Người giữ lửa và khôi phục chuỗi học."
        content.sound = .default
        content.userInfo = ["type": "streak_restore_available"]

        let request = UNNotificationRequest(
            identifier: "streak_restore_available",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    /// Schedules the 00:00 warning that will be relevant only if the user does
    /// not complete the following calendar day. A later study session replaces
    /// this request with the next possible break.
    @MainActor
    func schedulePotentialStreakRestoreAlert(afterLearningOn date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let startOfLearningDay = calendar.startOfDay(for: date)
        guard let lossDate = calendar.date(byAdding: .day, value: 2, to: startOfLearningDay),
              let expiryDate = calendar.date(byAdding: .day, value: 3, to: startOfLearningDay),
              lossDate > Date() else { return }

        let formatter = ISO8601DateFormatter()
        UserDefaults.standard.set(formatter.string(from: expiryDate), forKey: streakRestoreNotificationKey)

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak_restore_available"])
        let content = UNMutableNotificationContent()
        content.title = "Ngọn lửa vừa tắt"
        content.body = "Bạn có 24 giờ để dùng Người giữ lửa và cứu chuỗi học."
        content.sound = .default
        content.userInfo = ["type": "streak_restore_available"]
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lossDate)
        let request = UNNotificationRequest(
            identifier: "streak_restore_available",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.add(request)
    }

    @MainActor
    private var streakRestoreNotificationKey: String {
        "notified_streak_restore_expiry_" + (AuthManager.shared.currentUser?.id.uuidString ?? "guest")
    }

    @MainActor
    func cancelPotentialStreakRestoreAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["streak_restore_available"])
    }
    
    // Hiển thị thông báo khi app đang mở
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // Khi thông báo thực sự nổ ra (kể cả khi đang mở app), ta có thể log thêm nếu muốn
        let content = notification.request.content
        print("Thông báo đang hiển thị: \(content.title)")
        
        completionHandler([.banner, .sound, .badge])
    }
    
    // Xử lý khi người dùng nhấn vào thông báo
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        // Có thể điều hướng người dùng đến trang cụ thể ở đây
        completionHandler()
    }
}
