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
            if granted {
                print("Quyền thông báo đã được cấp")
            } else if let error = error {
                print("Lỗi yêu cầu quyền thông báo: \(error)")
            }
        }
    }
    
    // 1. Nhắc nhở học mỗi ngày (Tính năng chính)
    func scheduleDailyReminder(at date: Date) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        
        let content = UNMutableNotificationContent()
        content.title = "Omninary"
        content.body = "Đã đến giờ học từ vựng rồi, vào app học ngay thôi! 🔥"
        content.sound = .default
        content.userInfo = ["type": "daily_reminder"]
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_reminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if error == nil {
                print("Đã đặt lịch nhắc nhở hàng ngày thành công")
            }
        }
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
