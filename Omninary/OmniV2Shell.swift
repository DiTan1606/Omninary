import SwiftUI

/// New interface shell: four tabs (Home, Learning, My Omni, Setting) under a floating pixel tab bar.
/// Library is gone here; its two parts live in Learning (Luyện nghe) and Nhà nghiên cứu (Bộ từ).
struct OmniV2ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Binding var selectedUserTab: UserTab
    @State private var vocabularyLearningRequest: UUID?
    @StateObject private var tabBar = OmniTabBarState()

    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            TabView(selection: $selectedUserTab) {
                OmninaryHomeView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.home)
                LearningView(openVocabularyRequest: vocabularyLearningRequest)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.learning)
                ProfileView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.myOmni)
                SettingView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.setting)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The bar shows on each tab's first page only; pushed screens get the whole height.
                if tabBar.isRootVisible(selectedUserTab) {
                    OmniPixelTabBar(selection: $selectedUserTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tabBar.isRootVisible(selectedUserTab))
            .environmentObject(tabBar)
            .onAppear {
                if selectedUserTab == .library { selectedUserTab = .learning }
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnToHomeAfterLearning)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                selectedUserTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToMyOmniTab)) { _ in
                selectedUserTab = .myOmni
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

struct OmniPixelTabBar: View {
    @Environment(\.omniPalette) private var palette
    @Binding var selection: UserTab

    private let items: [(tab: UserTab, title: String, icon: String)] = [
        (.home, "Home", "home"),
        (.learning, "Learning", "book"),
        (.myOmni, "My Omni", "omni"),
        (.setting, "Setting", "gear")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.tab) { item in
                let active = selection == item.tab
                Button {
                    if selection != item.tab {
                        if OmniSoundSettings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
                        selection = item.tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        PixelIcon(item.icon, size: 24)
                            .saturation(active ? 1 : 0.15)
                            .opacity(active ? 1 : 0.7)
                            .scaleEffect(active ? 1.08 : 1)
                        Text(item.title)
                            .font(.omniBody(11, weight: active ? 800 : 600))
                            .foregroundStyle(active ? palette.selected : palette.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(palette.selected.opacity(palette.night ? 0.22 : 0.12))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(6)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.line, lineWidth: 1))
        .shadow(color: palette.shadow, radius: 12, y: 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
        .padding(.top, 10)
        .background(alignment: .bottom) {
            // Fade the page out under the bar so scrolled content does not show beneath it.
            LinearGradient(colors: [palette.background.opacity(0), palette.background, palette.background],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}

/// Temporary floating switch to flip between the old and the new interface for comparison.
struct OmniInterfaceCompareToggle: View {
    @AppStorage(OmniInterfaceVersion.storageKey) private var v2Enabled = true
    @State private var offsetY: CGFloat = 0
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            v2Enabled.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("Cũ").fontWeight(v2Enabled ? .regular : .heavy).opacity(v2Enabled ? 0.6 : 1)
                Image(systemName: "arrow.left.arrow.right")
                Text("Mới").fontWeight(v2Enabled ? .heavy : .regular).opacity(v2Enabled ? 1 : 0.6)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .offset(y: offsetY + drag)
        .gesture(
            DragGesture(minimumDistance: 6)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in offsetY += value.translation.height }
        )
        .padding(.trailing, 6)
        .accessibilityLabel(v2Enabled ? "Đang xem giao diện mới. Bấm để xem giao diện cũ" : "Đang xem giao diện cũ. Bấm để xem giao diện mới")
    }
}

/// Tracks whether each tab is showing its first page, so the tab bar can step aside on pushed screens.
@MainActor
final class OmniTabBarState: ObservableObject {
    @Published private var rootVisible: [UserTab: Bool] = [:]
    func isRootVisible(_ tab: UserTab) -> Bool { rootVisible[tab] ?? true }
    func set(_ tab: UserTab, visible: Bool) {
        if rootVisible[tab] != visible { rootVisible[tab] = visible }
    }
}

private struct OmniTabRootModifier: ViewModifier {
    @EnvironmentObject private var tabBar: OmniTabBarState
    let tab: UserTab
    func body(content: Content) -> some View {
        content
            // The floating bar does not reach into the tab's scroll view, so leave room under the content.
            .safeAreaPadding(.bottom, 84)
            .onAppear { tabBar.set(tab, visible: true) }
            .onDisappear { tabBar.set(tab, visible: false) }
    }
}

private struct OmniTabRootIfPresent: ViewModifier {
    @Environment(\.omniV2) private var v2
    let tab: UserTab
    func body(content: Content) -> some View {
        if v2 { content.modifier(OmniTabRootModifier(tab: tab)) } else { content }
    }
}

extension View {
    /// Marks the first page of a tab in the new interface.
    func omniTabRoot(_ tab: UserTab) -> some View { modifier(OmniTabRootIfPresent(tab: tab)) }
}
