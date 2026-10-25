import SwiftUI

/// The new Learning page: Học từ vựng, Luyện nghe, Luyện nói, each a card with a pixel scene.
struct LearningV2Page: View {
    @Environment(\.omniPalette) private var palette
    let onOpen: (LearningDashboardWidget) -> Void

    private struct Item {
        let widget: LearningDashboardWidget
        let scene: String
        let title: String
        let text: String
    }

    private let items: [Item] = [
        Item(widget: .vocabulary, scene: "vocab", title: "Học từ vựng", text: "Ôn tập đúng từ, đúng lúc, đúng kỹ năng."),
        Item(widget: .listening, scene: "listen", title: "Luyện nghe", text: "Nghe từng câu và chép lại."),
        Item(widget: .shadowing, scene: "shadow", title: "Luyện nói", text: "Nghe mẫu, nói theo, nói đúng âm và đúng ngữ điệu.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Learning")
                    .font(.omniDisplay(32, weight: 800))
                    .foregroundStyle(palette.text)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                ForEach(items, id: \.widget) { item in
                    Button { onOpen(item.widget) } label: { card(item) }
                        .buttonStyle(LearningV2CardPressStyle())
                        .accessibilityIdentifier("learning-v2-\(item.scene)")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .omniStatusBarBackdrop()
        .background { PixelSkyBackground() }
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("learn-\(item.scene)-\(palette.night ? "night" : "day")")
                .resizable()
                .interpolation(.none)
                .aspectRatio(240 / 68, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.omniDisplay(21, weight: 800))
                        .foregroundStyle(palette.text)
                    Text(item.text)
                        .font(.omniBody(13.5, weight: 500))
                        .foregroundStyle(palette.muted)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(palette.cta, in: Circle())
                    .background(palette.ctaShadow, in: Circle().offset(y: 3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(palette.line, lineWidth: 1))
        .shadow(color: palette.shadow, radius: 9, y: 6)
    }
}

private struct LearningV2CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
