import SwiftUI
import UserNotifications

struct SettingView: View {
    @AppStorage("daily_reminder_enabled") private var isReminderEnabled = true
    @State private var selectedTime = Date()

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Thông báo")) {
                    Toggle("Nhắc nhở học mỗi ngày", isOn: $isReminderEnabled)
                        .onChange(of: isReminderEnabled) { _, newValue in
                            updateReminderSchedule(enabled: newValue, time: selectedTime)
                        }
                    
                    if isReminderEnabled {
                        DatePicker("Thời gian nhắc nhở", selection: $selectedTime, displayedComponents: .hourAndMinute)
                            .onChange(of: selectedTime) { _, newValue in
                                updateReminderSchedule(enabled: true, time: newValue)
                                saveTime(newValue)
                            }
                    }
                }

                Section(header: Text("Lịch ôn tập")) {
                    ForEach(DitanaryReviewSchedule.visiblePlan, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("Chuẩn Omninary được cố định để giữ đúng nhịp học ngắt quãng.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                
                Section(header: Text("Thông tin")) {
                    HStack {
                        Text("Phiên bản")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Phát triển bởi")
                        Spacer()
                        Text("Omninary Team")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .onAppear {
                loadSavedTime()
                NotificationManager.shared.requestPermission()
            }
        }
    }
    
    func updateReminderSchedule(enabled: Bool, time: Date) {
        if enabled {
            NotificationManager.shared.scheduleDailyReminder(at: time)
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily_reminder"])
        }
    }
    
    func saveTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if let hour = components.hour, let minute = components.minute {
            UserDefaults.standard.set(hour, forKey: "reminder_hour")
            UserDefaults.standard.set(minute, forKey: "reminder_minute")
            UserDefaults.standard.set(true, forKey: "reminder_set_flag")
        }
    }
    
    func loadSavedTime() {
        let hour = UserDefaults.standard.integer(forKey: "reminder_hour")
        let minute = UserDefaults.standard.integer(forKey: "reminder_minute")
        let hasSet = UserDefaults.standard.bool(forKey: "reminder_set_flag")
        
        // Mặc định là 21:00 nếu chưa bao giờ cài đặt
        let finalHour = hasSet ? hour : 21
        let finalMinute = hasSet ? minute : 0
        
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
        components.hour = finalHour
        components.minute = finalMinute
        
        if let date = Calendar.current.date(from: components) {
            selectedTime = date
            if !hasSet {
                saveTime(date)
                if isReminderEnabled {
                    NotificationManager.shared.scheduleDailyReminder(at: date)
                }
            }
        }
    }
}
