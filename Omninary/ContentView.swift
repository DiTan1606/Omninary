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

struct ContentView: View {
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
