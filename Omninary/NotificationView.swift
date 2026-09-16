import SwiftUI

struct NotificationView: View {
    @State private var notifications: [Notification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView("Đang tải thông báo...")
            } else if notifications.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Chưa có thông báo nào.")
                        .foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(notifications) { notification in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(notification.title)
                                    .font(.headline)
                                    .foregroundColor(notification.is_read ? .secondary : .primary)
                                
                                Spacer()
                                
                                if !notification.is_read {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            
                            Text(notification.content)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let dateStr = notification.created_at {
                                Text(formatDate(dateStr))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !notification.is_read {
                                markAsRead(notification)
                            }
                        }
                    }
                    .onDelete(perform: deleteNotification)
                }
                .refreshable {
                    await fetchNotifications()
                }
            }
        }
        .navigationTitle("Thông báo")
        .onAppear {
            Task { await fetchNotifications() }
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    @MainActor
    private func fetchNotifications() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
        
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await NotificationRepository.fetchUserNotifications(userId: userId)
            
            // Lọc chỉ hiện những thông báo đã đến giờ hoặc đã qua
            let now = Date()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let formatter2 = ISO8601DateFormatter()
            
            let filtered = fetched.filter { notification in
                guard let dateStr = notification.created_at,
                      let date = formatter.date(from: dateStr) ?? formatter2.date(from: dateStr) else {
                    return true // Nếu không có ngày thì cứ hiện
                }
                return date <= now
            }
            
            notifications = filtered
        } catch {
            errorMessage = "Không tải được thông báo: \(error.localizedDescription)"
        }
    }
    
    private func markAsRead(_ notification: Notification) {
        Task {
            do {
                try await NotificationRepository.markAsRead(id: notification.id)
                
                await fetchNotifications()
            } catch {
                errorMessage = "Không thể đánh dấu thông báo đã đọc: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteNotification(at offsets: IndexSet) {
        let ids = offsets.map { notifications[$0].id }
        Task { await deleteNotifications(ids: ids) }
    }

    @MainActor
    private func deleteNotifications(ids: [String]) async {
        var firstError: Error?

        for id in ids {
            do {
                try await NotificationRepository.delete(id: id)
                notifications.removeAll { $0.id == id }
            } catch {
                firstError = error
                break
            }
        }

        if let firstError {
            errorMessage = "Không thể xoá thông báo: \(firstError.localizedDescription)"
            await fetchNotifications()
        }
    }
    
    func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter2 = ISO8601DateFormatter()
        
        guard let date = formatter.date(from: dateStr) ?? formatter2.date(from: dateStr) else {
            return dateStr
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "HH:mm, dd/MM/yyyy"
        return outputFormatter.string(from: date)
    }
}
