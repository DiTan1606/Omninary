import SwiftUI

@main struct OmninaryApp: App {
    @StateObject private var auth = AuthManager.shared

    init() {
        // Register the notification delegate; ask permission when the user enables reminders.
        _ = NotificationManager.shared
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LearningInteractionUITestReset") {
            var cards: [LearningWidgetPlacement] = []
            let fullGrid = ProcessInfo.processInfo.arguments.contains("-LearningInteractionUITestFullGrid")
            let size: LearningWidgetSize = fullGrid ? .fourByFour : .twoByTwo
            cards = LearningGridLayout.add("vocabulary", size: size, to: cards)
            cards = LearningGridLayout.add("listening", size: size, to: cards)
            if fullGrid {
                cards = LearningGridLayout.add("shadowing", size: size, to: cards)
            }
            if let data = try? JSONEncoder().encode(cards),
               let raw = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(raw, forKey: "learning_dashboard_layout_v2")
            }
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITesting") && ProcessInfo.processInfo.arguments.contains("-LayoutRefinementUITest") {
                ContentView()
            } else if ProcessInfo.processInfo.arguments.contains("-UITesting") && ProcessInfo.processInfo.arguments.contains("-DesignConsistencyUITest") {
                DesignConsistencyPreview()
            } else if ProcessInfo.processInfo.arguments.contains("-UITesting") && ProcessInfo.processInfo.arguments.contains("-InterfacePolishUITest") {
                InterfacePolishPreview()
            } else {
                appContent
            }
#else
            appContent
#endif
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if showsSettingTest {
            SettingView()
        } else if showsVocabularyWorkspaceTest {
            VocabularyWorkspacePreview()
        } else if showsLearningInteractionTest {
            LearningView()
        } else if auth.isCheckingAuth {
            VStack {
                ProgressView("Đang kiểm tra đăng nhập...")
            }
        } else if auth.isAuthenticated {
            ContentView()
        } else {
            AuthView()
        }
    }

    private var showsLearningInteractionTest: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-LearningInteractionUITest")
#else
        false
#endif
    }
    private var showsSettingTest: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITesting") && ProcessInfo.processInfo.arguments.contains("-SettingUITest")
#else
        false
#endif
    }
    private var showsVocabularyWorkspaceTest: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-VocabularyWorkspaceUITest")
#else
        false
#endif
    }
}
