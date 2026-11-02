import SwiftUI

/// Shown once, right after the learner turns Extra on.
struct OmniExtraWelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private let night = Color(hex: 0x10142A)
    private let card = Color(hex: 0x1B2140)
    private let line = Color(hex: 0x2B3457)
    private let muted = Color(hex: 0xA6AFC8)

    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            sparkles

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                OmniExtraLogo(size: 132)
                    .shadow(color: OmniExtraStyle.violet.opacity(0.35), radius: 30)
                    .offset(y: animate && !reduceMotion ? -6 : 0)

                OmniExtraChip(large: true)
                    .padding(.top, 36)

                Text("Chào mừng đến\nOmninary Extraordinary")
                    .font(.omniDisplay(30))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)

                Text("Từ hôm nay, Omni học cách bạn học.")
                    .font(.omniBody(14))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)

                VStack(spacing: 10) {
                    benefit("calendar", tint: Color(hex: 0x8CC6FF), title: "Lịch ôn riêng cho từng từ", detail: "Ôn đúng lúc sắp quên")
                    benefit("waveform.path.ecg", tint: Color(hex: 0xC9B8FF), title: "Hồ sơ 5 kỹ năng", detail: "Luyện thêm đúng chỗ còn yếu")
                    benefit("heart.fill", tint: Color(hex: 0xFF8A84), title: "Tim vô hạn", detail: "Học bao lâu tuỳ bạn")
                }
                .padding(.top, 32)

                Spacer(minLength: 24)

                Button("Bắt đầu học") { dismiss() }
                    .buttonStyle(OmniPrimaryButtonStyle())
                    .accessibilityIdentifier("extra-welcome-start")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { animate = true }
        }
    }

    private func benefit(_ icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.omniBody(14, weight: 700))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.omniBody(12))
                    .foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// A few stars that twinkle out of step with each other.
    private var sparkles: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { index, star in
                Image(systemName: "sparkle")
                    .font(.system(size: star.size, weight: .black))
                    .foregroundStyle(star.color)
                    .opacity(reduceMotion ? 0.7 : (animate == (index % 2 == 0) ? 1 : 0.25))
                    .scaleEffect(reduceMotion ? 1 : (animate == (index % 2 == 0) ? 1 : 0.7))
                    .position(x: w * star.x, y: star.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, color: Color)] = [
        (0.18, 110, 14, Color(hex: 0xE8B93A)),
        (0.80, 80, 10, Color(hex: 0xC9B8FF)),
        (0.74, 260, 12, Color(hex: 0x8CC6FF)),
        (0.26, 276, 8, Color(hex: 0xE8B93A))
    ]
}

/// Night pixel Omnicon ("Omnipixel_night") used on every Extraordinary sales and welcome surface.
struct OmniExtraLogo: View {
    let size: CGFloat

    var body: some View {
        Image("OmniPixel")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .omniExtraEdge(radius: size * 0.26, lineWidth: max(1.5, size / 46))
            .accessibilityHidden(true)
    }
}

/// One page, no scrolling: what Ditandnary has next to Extraordinary, two plans, one green button.
/// It closes by swiping down; there is no "later" button.
struct ExtraordinaryUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var interfaceModeRaw: String

    enum UpgradePlan {
        case monthly
        case annual
    }
    @State private var selectedPlan: UpgradePlan = .annual
    @State private var isActivating = false
    @State private var activationError = ""

    private let night = Color(hex: 0x10142A)
    private let card = Color(hex: 0x1B2140)
    private let line = Color(hex: 0x2B3457)
    private let muted = Color(hex: 0xA6AFC8)

    private static let rows: [(feature: String, ditan: String?, extra: String?)] = [
        ("Lượt học mỗi ngày", "5 lượt", "Vô hạn"),
        ("Lịch ôn tập", "Cố định", "Thích ứng"),
        ("Hồ sơ 5 kỹ năng", nil, nil),
        ("Khôi phục chuỗi", nil, nil),
        ("Omnicons độc quyền", nil, nil),
        ("Điểm Omni", "x1", "+20%")
    ]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, max(0.7, proxy.size.height / 800))
            VStack(spacing: 0) {
                // Free height is shared above and below the comparison, so the page sits balanced.
                Spacer(minLength: 16)

                OmniExtraLogo(size: 132 * scale)
                    .shadow(color: OmniExtraStyle.violet.opacity(0.35), radius: 30)

                OmniExtraChip(large: true)
                    .padding(.top, 12 * scale)

                Text("Omninary Extraordinary")
                    .font(.omniDisplay(26 * scale))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 6 * scale)
                    .accessibilityAddTraits(.isHeader)

                Text("Omni học cách bạn học.")
                    .font(.omniBody(14))
                    .foregroundStyle(muted)

                comparison(scale: scale)
                    .padding(.top, 18 * scale)

                Spacer(minLength: 12)
                    .frame(maxHeight: 40)

                plans(scale: scale)

                if !activationError.isEmpty {
                    Text(activationError)
                        .font(.omniBody(12))
                        .foregroundStyle(Color(hex: 0xFF8A84))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                Button(action: activate) {
                    HStack(spacing: 8) {
                        if isActivating { ProgressView().tint(.white) }
                        Text("Nâng cấp Extraordinary")
                    }
                    .frame(height: 34 * scale)
                }
                .buttonStyle(OmniPrimaryButtonStyle())
                .disabled(isActivating)
                .padding(.top, 16 * scale)
                .accessibilityIdentifier("upgrade-activate")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(night.ignoresSafeArea())
        .overlay(alignment: .top) {
            OmniExtraSparkles(stars: OmniExtraSparkles.sheet)
                .frame(height: 200)
        }
        .environment(\.colorScheme, .dark)
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extra-upgrade-sheet")
    }

    // MARK: Comparison

    private func comparison(scale: CGFloat) -> some View {
        let rowHeight = 40 * scale
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text("Ditandnary")
                    .font(.omniBody(11, weight: 700))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 80)
                HStack(spacing: 3) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color(hex: 0xE8B93A))
                    Text("Extraordinary")
                        .font(.omniBody(11, weight: 800))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 112)
            }
            .frame(height: 36 * scale)

            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    Text(row.feature)
                        .font(.omniBody(13, weight: 600))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.leading, 14)
                    Spacer(minLength: 4)
                    cell(row.ditan, extra: false)
                        .frame(width: 80)
                    cell(row.extra, extra: true)
                        .frame(width: 112)
                }
                .frame(height: rowHeight)
                .overlay(alignment: .top) {
                    if index > 0 { Rectangle().fill(line).frame(height: 1) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.feature): Ditandnary \(row.ditan ?? "không có"), Extraordinary \(row.extra ?? "có")")
            }
        }
        .padding(.bottom, 4)
        .background(alignment: .trailing) {
            // The Extraordinary column stands out with the Extra edge.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0x232A52))
                .omniExtraEdge(radius: 14)
                .frame(width: 100)
                .padding(.vertical, 6)
                .padding(.trailing, 6)
        }
        .background(card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(line, lineWidth: 1))
    }

    @ViewBuilder
    private func cell(_ value: String?, extra: Bool) -> some View {
        if let value {
            Text(value)
                .font(.omniBody(12, weight: extra ? 800 : 500))
                .foregroundStyle(extra ? .white : muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if extra {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(hex: 0x34B45A))
        } else {
            Text("—")
                .font(.omniBody(13, weight: 700))
                .foregroundStyle(Color(hex: 0x4A5478))
        }
    }

    // MARK: Plans

    private func plans(scale: CGFloat) -> some View {
        HStack(spacing: 10) {
            planTile(.annual, title: "1 năm", price: "499.000đ", detail: "~41.500đ / tháng", badge: "Tiết kiệm 48%", scale: scale)
                .accessibilityIdentifier("upgrade-plan-annual")
            planTile(.monthly, title: "1 tháng", price: "79.000đ", detail: "mỗi tháng", badge: nil, scale: scale)
                .accessibilityIdentifier("upgrade-plan-monthly")
        }
        .padding(.top, 10)
    }

    private func planTile(_ plan: UpgradePlan, title: String, price: String, detail: String, badge: String?, scale: CGFloat) -> some View {
        let selected = selectedPlan == plan
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedPlan = plan }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.omniBody(13, weight: 700))
                    .foregroundStyle(muted)
                Text(price)
                    .font(.omniDisplay(22 * scale))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.omniBody(11))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16 * scale)
            .padding(.bottom, 10 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card, in: shape)
            .overlay {
                if selected {
                    shape.strokeBorder(OmniExtraStyle.edge, lineWidth: 2)
                } else {
                    shape.strokeBorder(line, lineWidth: 2)
                }
            }
            .overlay(alignment: .topLeading) {
                if let badge {
                    Text(badge)
                        .font(.omniBody(10, weight: 800))
                        .foregroundStyle(Color(hex: 0x3A2A05))
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Color(hex: 0xE8B93A), in: Capsule())
                        .offset(x: 12, y: -10)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "Đã chọn" : "Chưa chọn")
    }

    private func activate() {
        guard !isActivating else { return }
        isActivating = true
        activationError = ""
        Task {
            do {
                try await OmniExtraordinaryManager.shared.activateAccess(days: selectedPlan == .annual ? 365 : 30)
                await MainActor.run {
                    interfaceModeRaw = AppInterfaceMode.extraordinary.rawValue
                    isActivating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    activationError = "Không thể kích hoạt Extraordinary: \(error.localizedDescription)"
                    isActivating = false
                }
            }
        }
    }
}

/// Small stars that twinkle out of step with each other; positions are fractions of the space they fill.
struct OmniExtraSparkles: View {
    typealias Star = (x: CGFloat, y: CGFloat, size: CGFloat, color: UInt32)
    let stars: [Star]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    static let sheet: [Star] = [(0.16, 0.30, 12, 0xE8B93A), (0.82, 0.22, 9, 0xC9B8FF), (0.78, 0.66, 10, 0x8CC6FF), (0.24, 0.80, 7, 0xE8B93A)]
    // kept to the card's top and bottom edges so they never sit on the text
    static let card: [Star] = [(0.62, 0.13, 8, 0xE8B93A), (0.80, 0.88, 6, 0xC9B8FF), (0.93, 0.16, 7, 0x8CC6FF), (0.46, 0.89, 5, 0xE8B93A)]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(stars.enumerated()), id: \.offset) { index, star in
                let on = reduceMotion || lit == index.isMultiple(of: 2)
                Image(systemName: "sparkle")
                    .font(.system(size: star.size, weight: .black))
                    .foregroundStyle(Color(hex: star.color))
                    .opacity(on ? 0.95 : 0.25)
                    .scaleEffect(on ? 1 : 0.7)
                    .position(x: proxy.size.width * star.x, y: proxy.size.height * star.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { lit = true }
        }
    }
}
