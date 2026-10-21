import SwiftUI

// MARK: - Omni Coin View
struct OmniCoinView: View {
    var size: CGFloat = 22
    var showShadow: Bool = true

    var body: some View {
        Image("OmniPointCoin")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: showShadow ? Color.orange.opacity(0.3) : .clear, radius: size * 0.15, y: size * 0.08)
    }
}

// MARK: - Omni Point Badge Style
enum OmniPointBadgeStyle {
    case inline
    case pill
    case prominent
}

// MARK: - Omni Point Badge
struct OmniPointBadge: View {
    let points: Int
    var style: OmniPointBadgeStyle = .inline
    var isExtra: Bool = false

    var body: some View {
        switch style {
        case .inline:
            HStack(spacing: 4) {
                OmniCoinView(size: 15, showShadow: false)
                Text("\(points)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(isExtra ? ExtraAuroraPalette.champagne : Color.orange)
            }

        case .pill:
            HStack(spacing: 5) {
                OmniCoinView(size: 16, showShadow: true)
                Text("\(points)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isExtra ? ExtraAuroraPalette.champagne : Color.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isExtra ? Color.white.opacity(0.08) : Color.orange.opacity(0.12))
            )

        case .prominent:
            HStack(spacing: 6) {
                OmniCoinView(size: 24, showShadow: true)
                Text("\(points)")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(isExtra ? ExtraAuroraPalette.champagne : Color.orange)
                Text("điểm")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OmniCoinView(size: 64)
        OmniPointBadge(points: 1250, style: .prominent)
        OmniPointBadge(points: 1250, style: .pill)
        OmniPointBadge(points: 1250, style: .inline)
    }
    .padding()
    .background(Color.black)
}
