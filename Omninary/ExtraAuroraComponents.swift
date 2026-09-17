import SwiftUI

enum ExtraAuroraPalette {
    static let obsidian = Color(red: 0.025, green: 0.020, blue: 0.070)
    static let deepBlue = Color(red: 0.035, green: 0.080, blue: 0.20)
    static let ice = Color(red: 0.30, green: 0.78, blue: 1.0)
    static let electricBlue = Color(red: 0.34, green: 0.39, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.30, blue: 0.98)
    static let champagne = Color(red: 0.91, green: 0.79, blue: 0.50)
}

struct AuroraBackdrop: View {
    var body: some View {
        LinearGradient(
                colors: [ExtraAuroraPalette.deepBlue, ExtraAuroraPalette.obsidian, ExtraAuroraPalette.violet.opacity(0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        // Decorative shapes inherit the background bounds, never its layout size.
        .overlay {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [ExtraAuroraPalette.electricBlue.opacity(0.28), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .offset(x: -150, y: -330)
        }
        .overlay {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [ExtraAuroraPalette.violet.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: 185, y: 190)
        }
        .overlay {
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipped()
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
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.white.opacity(0.13))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .padding(6)
        .modifier(ExtraLiquidGlassSurface())
        .shadow(color: Color.black.opacity(0.45), radius: 22, y: 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

private struct ExtraLiquidGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(ExtraAuroraPalette.deepBlue.opacity(0.24)),
                    in: .rect(cornerRadius: 28)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}
