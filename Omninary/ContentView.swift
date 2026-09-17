import SwiftUI

extension Foundation.Notification.Name {
    static let openLearningTab = Self("openLearningTab")
}

enum UserTab: Hashable {
    case home
    case library
    case learning
    case setting
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
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    var body: some View {
        Group {
            if interfaceMode == .extraordinary {
                ExtraordinaryUserContentView()
            } else {
                LegacyContentView()
            }
        }
        .preferredColorScheme(interfaceMode.usesDarkTheme ? .dark : nil)
        .tint(interfaceMode.usesDarkTheme ? Color.cyan : Color.blue)
        .task {
            await synchronizeDevelopmentIcon()
        }
        .onChange(of: interfaceModeRaw) { _, _ in
            Task {
                await synchronizeDevelopmentIcon()
            }
        }
    }

    private func synchronizeDevelopmentIcon() async {
        // Quyền Extra tạm thời được mô phỏng bằng bộ chọn phát triển.
        // Khi có thanh toán, thay biểu thức này bằng quyền do máy chủ xác minh.
        await AppIconManager.synchronize(
            hasExtraordinaryAccess: interfaceMode == .extraordinary
        )
    }
}

private struct LegacyContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedUserTab: UserTab = .home
    
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
                
                BlankTabView(title: "Library")
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(UserTab.library)
                
                BlankTabView(title: "Learning")
                    .tabItem {
                        Label("Learning", systemImage: "graduationcap")
                    }
                    .tag(UserTab.learning)
                
                SettingView()
                    .tabItem {
                        Label("Setting", systemImage: "gear")
                    }
                    .tag(UserTab.setting)
                
            }
        }
    }
}


private struct ExtraordinaryUserContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedUserTab: UserTab = .home

    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            ZStack(alignment: .bottom) {
                AuroraBackdrop()

                Group {
                    switch selectedUserTab {
                    case .home:
                        OmninaryHomeView()
                    case .library:
                        BlankTabView(title: "Library")
                    case .learning:
                        BlankTabView(title: "Learning")
                    case .setting:
                        SettingView()
                    }
                }
                .padding(.bottom, 82)

                ExtraAuroraTabBar(selectedTab: $selectedUserTab)
            }
        }
    }
}

private struct AdminWebOnlyView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var isSigningOut = false
    @State private var errorMessage = ""

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
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
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
