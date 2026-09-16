import SwiftUI

@main struct OmninaryApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        if !ProcessInfo.processInfo.arguments.contains("-UITesting") {
            NotificationManager.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            if auth.isCheckingAuth {
                VStack {
                    ProgressView("Đang kiểm tra đăng nhập...")
                }
            } else if auth.isAuthenticated {
                ContentView()
            } else {
                AuthView()
            }
        }
    }
}
