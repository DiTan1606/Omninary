import SwiftUI

enum ExtraAuroraPalette {
    static let obsidian = Color(red: 0.012, green: 0.022, blue: 0.045)
    static let deepBlue = Color(red: 0.025, green: 0.10, blue: 0.19)
    static let ice = Color(red: 0.33, green: 0.90, blue: 1.0)
    static let electricBlue = Color(red: 0.27, green: 0.48, blue: 1.0)
    static let champagne = Color(red: 0.91, green: 0.79, blue: 0.50)
}

struct AuroraBackdrop: View {
    var body: some View {
        ZStack {
            ExtraAuroraPalette.obsidian

            Circle()
                .fill(
                    RadialGradient(
                        colors: [ExtraAuroraPalette.electricBlue.opacity(0.34), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -150, y: -330)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [ExtraAuroraPalette.ice.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: 175, y: 260)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct ExtraAuroraTabBar: View {
    @Binding var selectedTab: UserTab

    private let tabs: [(UserTab, String, String)] = [
        (.home, "Home", "house.fill"),
        (.library, "Library", "books.vertical.fill"),
        (.learning, "Learning", "sparkles"),
        (.setting, "Setting", "gearshape.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.0) { tab, title, icon in
                Button {
                    withAnimation(.snappy(duration: 0.32)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : Color.white.opacity(0.56))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selectedTab == tab {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [ExtraAuroraPalette.electricBlue.opacity(0.92), ExtraAuroraPalette.ice.opacity(0.72)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: ExtraAuroraPalette.ice.opacity(0.35), radius: 10, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .padding(6)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(ExtraAuroraPalette.ice.opacity(0.14)), in: Capsule())
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
        }
        .shadow(color: Color.black.opacity(0.45), radius: 22, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }
}
