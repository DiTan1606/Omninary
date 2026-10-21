import SwiftUI

struct NotificationView: View {
    var onDismiss: (() -> Void)? = nil
    @State private var notifications: [Notification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var body: some View {
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView("Đang tải thông báo...")
                    .foregroundStyle(isExtra ? .white : .primary)
            } else if notifications.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 60))
                        .foregroundColor(isExtra ? Color.white.opacity(0.4) : .secondary)
                    Text("Chưa có thông báo nào.")
                        .foregroundColor(isExtra ? Color.white.opacity(0.6) : .secondary)
                }
            } else {
                List {
                    ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
                        let isBottom = (index == notifications.count - 1)
                        Button {
                            if !notification.is_read { markAsRead(notification) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(notification.title)
                                        .font(AppTypography.cardTitle)
                                        .foregroundColor(
                                            isExtra
                                                ? (notification.is_read ? Color.white.opacity(0.5) : .white)
                                                : (notification.is_read ? .secondary : .primary)
                                        )
                                
                                    Spacer()
                                
                                    if !notification.is_read {
                                        Circle()
                                            .fill(isExtra ? ExtraAuroraPalette.ice : Color.blue)
                                            .frame(width: 8, height: 8)
                                            .shadow(color: isExtra ? ExtraAuroraPalette.ice.opacity(0.6) : Color.clear, radius: 4)
                                    }
                                }
                            
                                Text(notification.content)
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                            
                                if let dateStr = notification.created_at {
                                    Text(formatDate(dateStr))
                                        .font(.caption2)
                                        .foregroundColor(isExtra ? Color.white.opacity(0.45) : .gray)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.automatic)
                        .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                        .listRowSeparator(isBottom ? .hidden : .visible, edges: .bottom)
                        .listRowSeparator(.hidden, edges: .top)
                        .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                    }
                    .onDelete(perform: deleteNotification)
                }
                .scrollContentBackground(isExtra ? .hidden : .automatic)
                .refreshable {
                    await fetchNotifications()
                }
            }
        }
        .background {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle("Thông báo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let onDismiss {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Trang chủ")
                        }
                        .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    }
                }
            }
        }
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
