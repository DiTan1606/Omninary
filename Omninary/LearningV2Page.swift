import SwiftUI

/// The learning activities in their teaching order, with pixel scenes.
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
        Item(widget: .grammar, scene: "grammar", title: "Học ngữ pháp", text: "Học ngữ pháp cùng giáo sư Gram"),
        Item(widget: .listening, scene: "listen", title: "Luyện nghe", text: "Nghe từng câu và chép lại."),
        Item(widget: .shadowing, scene: "shadow", title: "Luyện nói", text: "Nghe mẫu, nói theo, nói đúng âm và đúng ngữ điệu.")
    ]

    /// Three cards fill the opening viewport; the fourth is reached by scrolling.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmniPageTitle("Learning")
            GeometryReader { viewport in
                let cardHeight = max(128, (viewport.size.height - 24 - 12) / 3)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(items, id: \.widget) { item in
                            Button { onOpen(item.widget) } label: { card(item) }
                                .buttonStyle(LearningV2CardPressStyle())
                                .frame(height: cardHeight)
                                .accessibilityIdentifier("learning-v2-\(item.scene)")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -8)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .omniStatusBarBackdrop()
        .background { PixelSkyBackground() }
    }

    private func card(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // the scene fills whatever height the card gets, cropped from the middle
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if item.widget == .grammar {
                        GrammarLearningScene()
                    } else {
                        Image("learn-\(item.scene)-\(palette.night ? "night" : "day")")
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    }
                }
                .clipped()
                .accessibilityHidden(true)
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
        .frame(maxHeight: .infinity)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(palette.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .omniCardShadow(radius: 22)
    }
}

private struct LearningV2CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
