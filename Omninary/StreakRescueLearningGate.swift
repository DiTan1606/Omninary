import SwiftUI

/// Explain the irreversible choice before a learning session consumes its old rescue window.
private struct StreakRescueLearningGate: ViewModifier {
    let onLeave: () -> Void
    @State private var checking = true
    @State private var showChoice = false
    @State private var errorMessage: String?
    @State private var savedDays = 0

    func body(content: Content) -> some View {
        content
            .disabled(checking || showChoice)
            .overlay {
                if checking { ProgressView("Đang kiểm tra chuỗi…").padding().background(.regularMaterial, in: Capsule()) }
            }
            .task {
                if StreakPresentationSimulator.shared.isActive {
                    errorMessage = "Hãy đưa ứng dụng về dữ liệu thật trong Cài đặt trước khi học."
                    return
                }
                guard let userId = AuthManager.shared.currentUser?.id.uuidString else { checking = false; return }
                do { try await OmniStreakFreezeManager.shared.refreshFromRemote(userId: userId) }
                catch { errorMessage = "Chưa thể kiểm tra chuỗi. \(error.localizedDescription)"; return }
                let restore = OmniStreakRestoreManager.shared
                savedDays = restore.savedStreak
                showChoice = restore.hasActiveRestoreWindow
                checking = false
            }
            .alert("Chuỗi cũ đang chờ được cứu", isPresented: $showChoice) {
                Button("Cứu chuỗi với 1.000 điểm") {
                    checking = true
                    Task { @MainActor in
                        do {
                            let result = try await OmniRewardRepository.useOmniItem("restore_streak")
                            OmniStreakFreezeManager.shared.applyActionResult(result)
                            if let points = result.new_points { UserDefaults.standard.set(points, forKey: "omni_reward_points") }
                            NotificationManager.shared.cancelPotentialStreakRestoreAlert()
                            StreakActionPresenter.shared.enqueue(.restore, previousDays: 0,
                                newDays: result.streak_count ?? savedDays, rescuedDayKey: result.streak_rescued_date)
                            checking = false
                            onLeave()
                            NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
                        } catch { checking = false; errorMessage = error.localizedDescription }
                    }
                }
                Button("Học và bắt đầu chuỗi mới") { checking = false }
                Button("Để sau", role: .cancel) { onLeave() }
            } message: {
                Text("Chuỗi \(savedDays) ngày vẫn còn hạn cứu. Nếu hoàn thành phiên học trước khi cứu, chuỗi sẽ bắt đầu lại từ 1 và chuỗi cũ không còn khôi phục được.")
            }
            .alert("Chưa thể cứu chuỗi", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Thử lại") {
                    errorMessage = nil
                    Task { @MainActor in
                        guard let uid = AuthManager.shared.currentUser?.id.uuidString else { onLeave(); return }
                        do {
                            try await OmniStreakFreezeManager.shared.refreshFromRemote(userId: uid)
                            savedDays = OmniStreakRestoreManager.shared.savedStreak
                            showChoice = OmniStreakRestoreManager.shared.hasActiveRestoreWindow
                            checking = false
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                Button("Để sau", role: .cancel) { onLeave() }
            } message: { Text(errorMessage ?? "") }
    }
}

extension View {
    func streakRescueWarning(onLeave: @escaping () -> Void) -> some View {
        modifier(StreakRescueLearningGate(onLeave: onLeave))
    }
}
