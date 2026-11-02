import SwiftUI

/// New interface shell: five tabs (Home, Streak, Learning, My Omni, Setting) above a docked tab bar.
/// Library is gone here; its two parts live in Learning (Luyện nghe) and Nhà nghiên cứu (Bộ từ).
struct OmniV2ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Binding var selectedUserTab: UserTab
    @State private var vocabularyLearningRequest: UUID?
    @State private var learningOpenRequest: LearningOpenRequest?
    @StateObject private var tabBar = OmniTabBarState()

    var body: some View {
        if auth.isAdmin {
            AdminWebOnlyView()
        } else {
            TabView(selection: $selectedUserTab) {
                OmniSkyHomeView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.home)
                // The streak card and the calendar heatmap, which used to be the Home page.
                OmninaryHomeView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(UserTab.streak)
                LearningView(openVocabularyRequest: vocabularyLearningRequest, openRequest: learningOpenRequest)
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
            .onChange(of: selectedUserTab, initial: true) { _, tab in tabBar.switched(to: tab) }
            .onAppear {
                if selectedUserTab == .library { selectedUserTab = .learning }
                if selectedUserTab == .explore { selectedUserTab = .home }
            }
            // The day's first lesson lights the flame on its own full screen; rescues and freezes still
            // play on the Streak tab, where the flame lives and which shows the new streak afterwards.
            .onReceive(NotificationCenter.default.publisher(for: .returnToHomeAfterLearning)) { _ in
                selectedUserTab = .streak
                // once the lesson has slid away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { OmniIgniteCenter.shared.showPending() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
                selectedUserTab = .streak
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToStreakTab)) { _ in
                selectedUserTab = .streak
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLearningWidget)) { note in
                guard let raw = note.object as? String, let widget = LearningDashboardWidget(rawValue: raw) else { return }
                learningOpenRequest = LearningOpenRequest(widget: widget)
                selectedUserTab = .learning
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
    @EnvironmentObject private var tabBar: OmniTabBarState
    @Binding var selection: UserTab

    private let items: [(tab: UserTab, title: String)] = [
        (.home, "Home"),
        (.streak, "Streak"),
        (.learning, "Learning"),
        (.myOmni, "My Omni"),
        (.setting, "Setting")
    ]

    /// Icons only: the selected tab gets a filled icon inside a tinted rounded box,
    /// and Learning is a solid 3D key in the middle, level with the others.
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let active = selection == item.tab
                Button {
                    if selection != item.tab {
                        if OmniSoundSettings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
                        // mark the new tab first, so the page being left never reads as covered
                        tabBar.switched(to: item.tab)
                        selection = item.tab
                    }
                } label: {
                    Group {
                        if item.tab == .learning { learningKey } else { sideKey(item.tab, active: active) }
                    }
                    .frame(maxWidth: .infinity)
                    // tall enough to hold the square Learning key with its 3D edge
                    .frame(height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            palette.card
                .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
                .shadow(color: palette.cardShadow, radius: 10, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }

    private func sideKey(_ tab: UserTab, active: Bool) -> some View {
        let tint = palette.versionTint
        return OmniTabIcon(tab: tab, active: active)
            .foregroundStyle(active ? tint : palette.muted)
            .frame(width: 26, height: 26)
            .frame(width: 54, height: 44)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(palette.night ? 0.16 : 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.4), lineWidth: 1.5))
                }
            }
    }

    private var learningKey: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Image(systemName: "book.fill")
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(palette.cta, in: shape)
            .background(palette.ctaShadow, in: shape.offset(y: 5))
            // key and its 3D edge together sit centred inside the bar's row
            .offset(y: -2.5)
    }
}

/// Tracks whether each tab is showing its first page, so the tab bar can step aside on pushed screens.
@MainActor
final class OmniTabBarState: ObservableObject {
    @Published private var rootVisible: [UserTab: Bool] = [:]
    /// The tab on screen.
    private(set) var selected: UserTab = .home
    /// Root pages on screen right now, from their own appear and disappear calls.
    private var onScreen: [UserTab: Bool] = [:]
    private var lastSwitch = Date.distantPast

    func isRootVisible(_ tab: UserTab) -> Bool { rootVisible[tab] ?? true }

    func switched(to tab: UserTab) {
        selected = tab
        lastSwitch = Date()
    }

    func rootAppeared(_ tab: UserTab) {
        onScreen[tab] = true
        set(tab, visible: true)
    }

    /// TabView sends appear and disappear late and out of order when tabs are tapped quickly, so the
    /// bar asks the tab's own navigation stack instead: it hides only while a page is pushed on it.
    /// `depth` is that stack's page count, or nil when it could not be found.
    func rootDisappeared(_ tab: UserTab, depth: @escaping () -> Int?) {
        onScreen[tab] = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.selected == tab, self.onScreen[tab] != true else { return }
            if let depth = depth() {
                if depth > 1 { self.set(tab, visible: false) }
            } else if Date().timeIntervalSince(self.lastSwitch) > 0.6 {
                self.set(tab, visible: false)
            }
        }
    }

    private func set(_ tab: UserTab, visible: Bool) {
        if rootVisible[tab] != visible { rootVisible[tab] = visible }
    }
}

private struct OmniTabRootModifier: ViewModifier {
    @EnvironmentObject private var tabBar: OmniTabBarState
    @State private var probe = OmniNavProbe()
    let tab: UserTab
    func body(content: Content) -> some View {
        content
            // The docked bar does not reach into the tab's scroll view, so leave room under the content.
            .safeAreaPadding(.bottom, 76)
            .background { OmniNavProbeView(probe: probe).allowsHitTesting(false) }
            .onAppear { tabBar.rootAppeared(tab) }
            .onDisappear { [probe] in tabBar.rootDisappeared(tab) { probe.navigation?.viewControllers.count } }
    }
}

/// An empty view inside a tab's first page that remembers the UIKit navigation controller around it,
/// so the tab bar can tell a pushed page from a tab switch.
final class OmniNavProbe: UIView {
    weak var navigation: UINavigationController?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let nav = next as? UINavigationController { navigation = nav; return }
            responder = next
        }
    }
}

private struct OmniNavProbeView: UIViewRepresentable {
    let probe: OmniNavProbe
    func makeUIView(context: Context) -> OmniNavProbe { probe }
    func updateUIView(_ uiView: OmniNavProbe, context: Context) {}
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

// MARK: - Swipe from the left edge to go back

/// The new pages hide the navigation bar, which also switches off iOS's swipe-from-the-left-edge
/// to go back. Re-enable it for every pushed page (never on a stack's first page).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }
        if let inner = OmniEdgeSwipe.innerBackView, inner.window != nil,
           let top = topViewController?.view, inner.isDescendant(of: top) { return false }
        return true
    }
}

/// A page with its own inner screens (the grammar lesson) sets this to the view that takes the
/// edge swipe, so swiping steps back one inner screen instead of closing the whole page.
@MainActor enum OmniEdgeSwipe {
    static weak var innerBackView: UIView?
}

// MARK: - Tab bar icons

/// Rounded line icons for the tab bar, filled when the tab is selected (SF Symbols, plus the Omni ring).
struct OmniTabIcon: View {
    let tab: UserTab
    let active: Bool

    var body: some View {
        switch tab {
        case .myOmni:
            OmniRingIcon(active: active)
        default:
            Image(systemName: symbol + (active ? ".fill" : ""))
                .font(.system(size: 21, weight: active ? .semibold : .regular))
        }
    }

    private var symbol: String {
        switch tab {
        case .home: "house"
        case .streak: "flame"
        case .explore: "safari"
        case .learning, .library: "book"
        case .setting: "gearshape"
        case .myOmni: "circle"
        }
    }
}

/// The Omninary logo ring as a tab icon: one long arc and four shorter ones, separated by small gaps.
struct OmniRingIcon: View {
    let active: Bool
    /// Arc lengths of the logo ring, going clockwise, in units of a 24-point icon.
    private static let arcs: [CGFloat] = [17, 3.5, 5, 7.5, 10.5]
    private static let gap: CGFloat = 1.8

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / 24
            let radius: CGFloat = 8
            let total = Self.arcs.reduce(0, +) + Self.gap * CGFloat(Self.arcs.count)
            ZStack {
                ForEach(Self.arcs.indices, id: \.self) { i in
                    let start = Self.arcs[..<i].reduce(0, +) + Self.gap * CGFloat(i)
                    Circle()
                        .trim(from: start / total, to: (start + Self.arcs[i]) / total)
                        .stroke(style: StrokeStyle(lineWidth: (active ? 4.2 : 3) * unit, lineCap: .butt))
                        .frame(width: radius * 2 * unit, height: radius * 2 * unit)
                }
            }
            // the long arc sits on the upper left, as in the logo
            .rotationEffect(.degrees(-210))
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}
