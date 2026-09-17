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
