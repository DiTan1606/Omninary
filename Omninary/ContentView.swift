import SwiftUI

extension Foundation.Notification.Name {
    static let openLearningTab = Self("openLearningTab")
}

private enum UserTab {
    case home
    case library
    case learning
    case setting
    case profile
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
        switch interfaceMode {
        case .legacy:
            LegacyContentView()
        case .ditandnary, .extraordinary:
            VersionPlaceholderView(interfaceModeRaw: $interfaceModeRaw, mode: interfaceMode)
        }
    }
}

private struct LegacyContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedUserTab: UserTab = .home
    @State private var vocabularyLearningRequest: UUID?
    
    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            TabView(selection: $selectedUserTab) {
                HomeView()
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
                        Label("Profile", systemImage: "person")
                    }
                    .tag(UserTab.profile)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLearningTab)) { _ in
                selectedUserTab = .learning
                vocabularyLearningRequest = UUID()
            }
        }
    }
}


private struct VersionPlaceholderView: View {
    @Binding var interfaceModeRaw: String
    let mode: AppInterfaceMode

    var body: some View {
        NavigationStack {
            ZStack {
            (mode.usesDarkTheme ? Color.black : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(mode.wordmarkAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 110)
                    .accessibilityLabel(mode.title)

                Text(mode.previewMessage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(mode.usesDarkTheme ? Color.white : Color.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(AppInterfaceMode.allCases) { availableMode in
                        Button {
                            interfaceModeRaw = availableMode.rawValue
                        } label: {
                            Label(
                                availableMode.title,
                                systemImage: availableMode == mode ? "checkmark" : "circle"
                            )
                        }
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(mode.usesDarkTheme ? Color.white : Color.primary)
                }
                .accessibilityLabel("Chuyển giao diện phát triển")
            }
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
