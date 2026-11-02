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
