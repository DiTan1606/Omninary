import SwiftUI
import UserNotifications

struct SettingView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var auth = AuthManager.shared
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @AppStorage("daily_reminder_minutes") private var reminderMinutes = 20 * 60
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? Date()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isUpdatingReminder = false
    @State private var isLoadingReminder = false
    @State private var isSigningOut = false
    @State private var showSignOutConfirmation = false
    @State private var alertMessage: String?
    @AppStorage(OmniAppearanceMode.storageKey) private var appearanceRaw = OmniAppearanceMode.auto.rawValue
    @AppStorage(OmniSoundSettings.musicKey) private var musicEnabled = true
    @AppStorage(OmniSoundSettings.effectsKey) private var effectsEnabled = true
    @AppStorage(OmniSoundSettings.hapticsKey) private var hapticsEnabled = true
    @Environment(\.omniV2) private var v2
    @Environment(\.omniPalette) private var palette

    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    private var accent: Color { v2 ? palette.selected : (isExtra ? ExtraAuroraPalette.ice : .blue) }
    private var secondaryText: Color { v2 ? palette.muted : (isExtra ? .white.opacity(0.65) : .secondary) }
    private var notificationsAllowed: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional || notificationStatus == .ephemeral
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if v2 { PixelSkyBackground() }
                else if isExtra { AuroraBackdrop() }
                else { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
                ScrollView {
                    VStack(alignment: .leading, spacing: v2 ? 14 : AppSpacing.cardGap) {
                        if v2 {
                            Text("Setting")
                                .font(.omniDisplay(32, weight: 800))
                                .foregroundStyle(palette.text)
                                .padding(.top, 14)
                                .padding(.bottom, 2)
                        }
                        reminderCard
                        if v2 {
                            appearanceCard
                            soundCard
                        }
#if DEBUG
                        developmentInterfaceCard
#endif
                        signOutButton
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
            .omniStatusBarBackdrop()
            .omniTabRoot(.setting)
            .environment(\.colorScheme, v2 ? (palette.night ? .dark : .light) : (isExtra ? .dark : .light))
            .navigationTitle("Setting")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(v2 ? .hidden : .automatic, for: .navigationBar)
            .task { await refreshReminder() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshReminder() } }
            }
            .alert("Đăng xuất khỏi Omninary?", isPresented: $showSignOutConfirmation) {
                Button("Đăng xuất", role: .destructive) { Task { await signOut() } }
                Button("Huỷ", role: .cancel) { }
            } message: {
                Text("Bạn có thể đăng nhập lại để tiếp tục học.")
            }
            .alert("Thông báo", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("Đóng", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .preferredColorScheme(v2 ? ((palette.night || isExtra) ? .dark : .light) : (isExtra ? .dark : nil))
    }

    private var appearanceCard: some View {
        settingsCard("Giao diện sáng/tối", subtitle: "Tự động: sáng từ 6:00 đến 18:00, tối sau 18:00.", icon: "circle.lefthalf.filled", color: accent) {
            Picker("Giao diện", selection: $appearanceRaw) {
                Text("Tự động theo giờ").tag(OmniAppearanceMode.auto.rawValue)
                Text("Luôn sáng").tag(OmniAppearanceMode.light.rawValue)
                Text("Luôn tối").tag(OmniAppearanceMode.dark.rawValue)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-appearance-mode")
        }
    }

    private var soundCard: some View {
        settingsCard("Âm thanh và rung", subtitle: "Nhạc nền, hiệu ứng âm thanh và rung khi học.", icon: "speaker.wave.2.fill", color: accent) {
            Toggle(isOn: $musicEnabled) { Text("Nhạc nền").font(v2 ? .omniBody(15, weight: 600) : .subheadline.weight(.semibold)) }
                .tint(accent)
            Divider().overlay(v2 ? palette.line : .clear)
            Toggle(isOn: $effectsEnabled) { Text("Hiệu ứng âm thanh").font(v2 ? .omniBody(15, weight: 600) : .subheadline.weight(.semibold)) }
                .tint(accent)
            Divider().overlay(v2 ? palette.line : .clear)
            Toggle(isOn: $hapticsEnabled) { Text("Rung").font(v2 ? .omniBody(15, weight: 600) : .subheadline.weight(.semibold)) }
                .tint(accent)
        }
        .accessibilityIdentifier("settings-sound")
    }

    private var reminderCard: some View {
        settingsCard("Nhắc nhở học tập", subtitle: "Dành một chút thời gian mỗi ngày cho việc học.", icon: "bell.badge.fill", color: accent) {
            Toggle(isOn: Binding(get: { reminderEnabled }, set: { enabled in
                Task { await updateReminder(enabled: enabled, at: reminderTime) }
            })) {
                Text("Nhắc học hằng ngày").font(v2 ? .omniBody(15, weight: 600) : .subheadline.weight(.semibold))
            }
            .tint(accent)
            .disabled(isUpdatingReminder || isLoadingReminder)
            .accessibilityIdentifier("settings-daily-reminder")

            if reminderEnabled {
                Divider()
                DatePicker("Giờ nhắc học", selection: Binding(get: { reminderTime }, set: { date in
                    Task { await updateReminder(enabled: true, at: date) }
                }), displayedComponents: .hourAndMinute)
                .font(.subheadline)
                .disabled(isUpdatingReminder || isLoadingReminder)
            }
            if isUpdatingReminder {
                ProgressView("Đang cập nhật lời nhắc…").font(.caption)
            }
            if notificationStatus == .denied {
                Text("Thông báo đang bị tắt. Cho phép Omninary gửi thông báo trong cài đặt thiết bị để nhận lời nhắc.")
                    .font(.caption).foregroundStyle(secondaryText)
            }
        }
    }

#if DEBUG
    private var developmentInterfaceCard: some View {
        settingsCard("Giao diện thử nghiệm", subtitle: "Đang dùng \(isExtra ? "Extra" : "Ditan"). Chỉ hiển thị trong bản phát triển.", icon: "circle.lefthalf.filled", color: accent) {
            Button {
                UserDefaults.standard.set(true, forKey: "development_interface_preview_enabled")
                interfaceModeRaw = isExtra ? AppInterfaceMode.ditandnary.rawValue : AppInterfaceMode.extraordinary.rawValue
            } label: {
                Label("Chuyển sang \(isExtra ? "Ditan" : "Extra")", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .secondary))
            .accessibilityIdentifier("settings-switch-interface")
        }
    }
#endif

    private var signOutButton: some View {
        Button(role: .destructive) { showSignOutConfirmation = true } label: {
            HStack {
                Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                Spacer()
                if isSigningOut { ProgressView().tint(AppSemanticColor.destructive) }
            }
        }
        .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .destructive))
        .disabled(isSigningOut)
        .accessibilityIdentifier("settings-sign-out")
    }

    private func settingsCard<Content: View>(_ title: String, subtitle: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(v2 ? .omniBody(16.5, weight: 800) : AppTypography.cardTitle)
                    Text(subtitle).font(v2 ? .omniBody(12.5, weight: 500) : .caption).foregroundStyle(secondaryText)
                }
                Spacer(minLength: 0)
            }
            content()
        }
        .foregroundStyle(v2 ? palette.text : (isExtra ? .white : .primary))
        .modifier(SettingCardSurface(v2: v2, isExtra: isExtra))
    }

    @MainActor
    private func refreshReminder() async {
        guard !isUpdatingReminder, !isLoadingReminder else { return }
        isLoadingReminder = true
        defer { isLoadingReminder = false }
        let center = UNUserNotificationCenter.current()
        notificationStatus = await center.notificationSettings().authorizationStatus
        let requests = await center.pendingNotificationRequests()
        reminderEnabled = requests.contains { $0.identifier == "daily_reminder" }
        if let trigger = requests.first(where: { $0.identifier == "daily_reminder" })?.trigger as? UNCalendarNotificationTrigger,
           let hour = trigger.dateComponents.hour, let minute = trigger.dateComponents.minute,
           let time = Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) {
            reminderTime = time
            reminderMinutes = hour * 60 + minute
        } else if let time = Calendar.current.date(from: DateComponents(hour: reminderMinutes / 60, minute: reminderMinutes % 60)) {
            reminderTime = time
        }
    }

    @MainActor
    private func updateReminder(enabled: Bool, at time: Date) async {
        guard !isUpdatingReminder, !isLoadingReminder else { return }
        isUpdatingReminder = true
        defer { isUpdatingReminder = false }
        if !enabled {
            NotificationManager.shared.cancelDailyReminder()
            reminderEnabled = false
            return
        }
        do {
            let center = UNUserNotificationCenter.current()
            notificationStatus = await center.notificationSettings().authorizationStatus
            if notificationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                notificationStatus = await center.notificationSettings().authorizationStatus
            }
            guard notificationsAllowed else {
                alertMessage = "Hãy cho phép thông báo trong cài đặt thiết bị để bật nhắc học hằng ngày."
                return
            }
            try await NotificationManager.shared.scheduleDailyReminder(at: time)
            reminderTime = time
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            reminderMinutes = (components.hour ?? 20) * 60 + (components.minute ?? 0)
            reminderEnabled = true
        } catch {
            alertMessage = "Chưa thể đặt lời nhắc học. Vui lòng thử lại."
        }
    }

    @MainActor
    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do { try await auth.signOut() }
        catch { alertMessage = "Chưa thể đăng xuất. Vui lòng kiểm tra kết nối và thử lại." }
    }
}

private struct SettingCardSurface: ViewModifier {
    let v2: Bool
    let isExtra: Bool
    func body(content: Content) -> some View {
        if v2 {
            content.omniCard(padding: AppSpacing.card, radius: 22)
        } else {
            content
                .padding(AppSpacing.card)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appSurface(.card, isExtra: isExtra)
        }
    }
}
