import SwiftUI



enum UserTab: Hashable {
    case home
    case library
    case learning
    case setting
    case myOmni
}


enum AppInterfaceMode: String, CaseIterable, Identifiable {
    case legacy
    case ditandnary
    case extraordinary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .legacy: "Phiên bản cũ"
        case .ditandnary: "Ditandnary"
        case .extraordinary: "Extraordinary"
        }
    }

    var previewMessage: String {
        "Đây là giao diện của phiên bản \(title)."
    }

    var wordmarkAsset: String {
        switch self {
        case .legacy, .ditandnary: "DitandnaryWordmark"
        case .extraordinary: "ExtraordinaryWordmark"
        }
    }

    var usesDarkTheme: Bool {
        self == .extraordinary
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @AppStorage(OmniInterfaceVersion.storageKey) private var v2Enabled = true
    @State private var selectedUserTab: UserTab = .home

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    var body: some View {
        Group {
            if v2Enabled {
                OmniV2ContentView(selectedUserTab: $selectedUserTab)
            } else if interfaceMode == .extraordinary {
                ExtraordinaryUserContentView(selectedUserTab: $selectedUserTab)
            } else {
                LegacyContentView(selectedUserTab: $selectedUserTab)
            }
        }
        .overlay(alignment: .trailing) {
            OmniInterfaceCompareToggle()
                .padding(.top, 220)
        }
        .modifier(OmniV2Root(isExtra: interfaceMode == .extraordinary))
#if DEBUG
        .onAppear {
            // Screenshot runs: `-OmniStartTab learning` opens a tab directly.
            switch UserDefaults.standard.string(forKey: "OmniStartTab") {
            case "learning": selectedUserTab = .learning
            case "myOmni": selectedUserTab = .myOmni
            case "setting": selectedUserTab = .setting
            default: break
            }
        }
#endif
        .task {
            await synchronizeDevelopmentIcon()
            await refreshStreak()
            // Keep an open screen current at midnight in the server's time zone.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
            while !Task.isCancelled {
                guard let nextDay = calendar.date(byAdding: .day, value: 1,
                                                  to: calendar.startOfDay(for: Date())) else { return }
                let delay = max(1, nextDay.timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
                await refreshStreak()
            }
        }
        .onReceive(StreakPresentationSimulator.shared.$isActive) { active in
            if !active { Task { await refreshStreak() } }
        }
        .onChange(of: interfaceModeRaw) { _, _ in
            Task {
                await synchronizeDevelopmentIcon()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // The system icon dialog itself changes scene activity. Do not request another
            // icon change when that dialog closes; synchronize on launch or mode changes only.
            OmniDoublePointsManager.shared.checkStatus()
            OmniExtraordinaryManager.shared.checkStatus()
            Task {
                await refreshStreak()
                await OmniLearningHeartManager.shared.refreshHearts()
            }
        }
    }

    private func refreshStreak() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
        await OmniStreakFreezeManager.shared.syncFromRemote(userId: userId)
    }

    private func synchronizeDevelopmentIcon() async {
        // Giao diện Extra phản ánh quyền đã đồng bộ từ máy chủ.
        await AppIconManager.synchronize(
            hasExtraordinaryAccess: interfaceMode == .extraordinary
        )
    }
}

private struct LegacyContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Binding var selectedUserTab: UserTab
    @State private var vocabularyLearningRequest: UUID?

    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            TabView(selection: $selectedUserTab) {
                OmninaryHomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(UserTab.home)

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(UserTab.library)

                LearningView(openVocabularyRequest: vocabularyLearningRequest)
                    .tabItem {
                        Label("Learning", systemImage: "graduationcap")
                    }
                    .tag(UserTab.learning)

                SettingView()
                    .tabItem {
                        Label("Setting", systemImage: "gear")
                    }
                    .tag(UserTab.setting)

                ProfileView()
                    .tabItem {
                        Label("My Omni", systemImage: "person.crop.circle")
                    }
                    .tag(UserTab.myOmni)
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToHomeAfterLearning)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToLearningTab)) { _ in
                selectedUserTab = .learning
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLearningTab)) { _ in
                vocabularyLearningRequest = UUID()
                selectedUserTab = .learning
            }
        }
    }
}

private struct ExtraordinaryUserContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Binding var selectedUserTab: UserTab
    @State private var vocabularyLearningRequest: UUID?

    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            TabView(selection: $selectedUserTab) {
                OmninaryHomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(UserTab.home)

                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical.fill")
                    }
                    .tag(UserTab.library)

                LearningView(openVocabularyRequest: vocabularyLearningRequest)
                    .tabItem {
                        Label("Learning", systemImage: "sparkles")
                    }
                    .tag(UserTab.learning)

                SettingView()
                    .tabItem {
                        Label("Setting", systemImage: "gearshape.fill")
                    }
                    .tag(UserTab.setting)

                ProfileView()
                    .tabItem {
                        Label("My Omni", systemImage: "person.crop.circle.fill")
                    }
                    .tag(UserTab.myOmni)
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToHomeAfterLearning)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToLearningTab)) { _ in
                selectedUserTab = .learning
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLearningTab)) { _ in
                vocabularyLearningRequest = UUID()
                selectedUserTab = .learning
            }
            .background {
                AuroraBackdrop()
            }
        }
    }
}

struct AdminWebOnlyView: View {
    @ObservedObject private var auth = AuthManager.shared
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var isSigningOut = false
    @State private var errorMessage = ""
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 58))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("Tài khoản admin")
                    .font(.title2.bold())

                Text("Dashboard admin trên iOS đã được tắt. Vui lòng dùng admin-web để quản trị Omninary.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await signOut() }
            } label: {
                HStack {
                    if isSigningOut {
                        ProgressView()
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    Text(isSigningOut ? "Đang đăng xuất..." : "Đăng xuất")
                }
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .destructive))
            .disabled(isSigningOut)
        }
        .padding(28)
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }

        do {
            try await auth.signOut()
        } catch {
            errorMessage = "Đăng xuất thất bại: \(error.localizedDescription)"
        }
    }
}
