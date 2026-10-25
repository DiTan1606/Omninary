import SwiftUI

/// Quy ước chung cho hai giao diện; màu nền và hiệu ứng vẫn phụ thuộc chủ đề.
enum AppSpacing {
    static let page: CGFloat = 16
    /// Chuẩn lấy từ khoảng cách giữa hai thẻ điều hướng của Thư viện.
    static let cardGap: CGFloat = 20
    /// Lưới 4 cột cần gọn hơn khoảng cách giữa các thẻ lớn của trang.
    static let learningGridGap: CGFloat = 12
    static let section = cardGap
    static let card: CGFloat = 20
    static let row: CGFloat = 16
    static let item: CGFloat = 12
    static let inline: CGFloat = 8
    static let compact: CGFloat = 4
}

enum AppTypography {
    static let cardTitle = Font.headline.weight(.semibold)
    static let destinationTitle = Font.title3.weight(.bold)
    static let detailTitle = Font.title.weight(.bold)
    static let body = Font.subheadline
    static let label = Font.subheadline.weight(.semibold)
    static let metadata = Font.caption
    static let action = Font.headline.weight(.semibold)
    static let metric = Font.title2.weight(.bold)
}

struct AppTheme {
    let isExtra: Bool
    var accent: Color { isExtra ? ExtraAuroraPalette.ice : .blue }
    var primary: Color { isExtra ? ExtraAuroraPalette.electricBlue : .blue }
    var text: Color { isExtra ? .white : .primary }
    var secondaryText: Color { isExtra ? .white.opacity(0.68) : .secondary }
    var primaryGradient: LinearGradient {
        LinearGradient(colors: isExtra ? [ExtraAuroraPalette.electricBlue, ExtraAuroraPalette.violet] : [.blue, Color(red: 0.12, green: 0.32, blue: 0.78)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AppSemanticColor {
    static let success = adaptive(light: UIColor(red: 0.10, green: 0.46, blue: 0.24, alpha: 1), dark: .systemGreen)
    static let attention = adaptive(light: UIColor(red: 0.68, green: 0.32, blue: 0.03, alpha: 1), dark: .systemOrange)
    static let error = destructive
    static let destructive = adaptive(light: UIColor(red: 0.78, green: 0.16, blue: 0.14, alpha: 1), dark: .systemRed)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

enum AppSurfaceKind: CaseIterable {
    case card, row, detail

    var cornerRadius: CGFloat {
        switch self {
        case .card: 24
        case .row: 18
        case .detail: 26
        }
    }
    var padding: CGFloat {
        switch self {
        case .card, .detail: AppSpacing.card
        case .row: AppSpacing.row
        }
    }
}

struct AppSurfaceBackground: View {
    let kind: AppSurfaceKind
    let isExtra: Bool
    var tint: Color? = nil
    var grouped = false
    @Environment(\.omniV2) private var v2
    @Environment(\.omniExtra) private var omniExtra
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: grouped ? 0 : kind.cornerRadius, style: .continuous)
        // New interface: the dark flag picks the night palette so text colours chosen for it stay readable.
        // Screens not yet redrawn colour text by the system scheme, so a dark scheme means the night palette too.
        let palette = OmniPalette(night: isExtra || colorScheme == .dark, extra: omniExtra)
        Group {
            if v2 {
                shape.fill(kind == .row ? palette.panel : palette.card)
                    .overlay { if !grouped { shape.stroke(palette.line, lineWidth: 1) } }
            } else if isExtra {
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(0.11), (tint ?? ExtraAuroraPalette.violet).opacity(0.08), ExtraAuroraPalette.deepBlue.opacity(0.28)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay { if !grouped { shape.stroke(Color.white.opacity(0.12), lineWidth: 1) } }
            } else {
                shape.fill(Color(UIColor.secondarySystemGroupedBackground))
                    .overlay { if !grouped { shape.stroke(Color.primary.opacity(0.045), lineWidth: 1) } }
            }
        }
        .shadow(color: v2 ? (kind == .row ? .clear : palette.shadow) : .black.opacity(kind == .row ? 0 : (isExtra ? 0.25 : 0.05)),
                radius: kind == .detail ? 18 : 12, y: kind == .detail ? 8 : 4)
        .allowsHitTesting(false)
    }
}

enum AppActionBarShape { case capsule, circle, docked }

/// Một bề mặt thanh thao tác, dùng dạng nổi hoặc gắn ở đáy màn hình.
struct AppActionBarSurface: ViewModifier {
    let shape: AppActionBarShape
    var useSystemGlass = true
    var prominentGlass = false
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }

    @ViewBuilder func body(content: Content) -> some View {
        switch shape {
        case .capsule: floating(content, in: Capsule())
        case .circle: floating(content, in: Circle())
        case .docked:
            content
                .background(isExtra ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground)))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.primary.opacity(isExtra ? 0.15 : 0.08)).frame(height: 1).allowsHitTesting(false)
                }
        }
    }

    @ViewBuilder private func floating<S: Shape>(_ content: Content, in shape: S) -> some View {
        if #available(iOS 26.0, *), useSystemGlass {
            if prominentGlass {
                content.glassEffect(.regular.interactive(), in: shape)
                    .shadow(color: .black.opacity(isExtra ? 0.18 : 0.08), radius: 12, y: 4)
            } else {
                content.glassEffect(.clear.interactive(), in: shape)
                    .shadow(color: .black.opacity(isExtra ? 0.18 : 0.08), radius: 12, y: 4)
            }
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay { shape.stroke(Color.primary.opacity(isExtra ? 0.15 : 0.08), lineWidth: 1).allowsHitTesting(false) }
                .shadow(color: .black.opacity(isExtra ? 0.18 : 0.08), radius: 12, y: 4)
        }
    }
}

enum AppButtonEmphasis { case primary, secondary, destructive }

struct AppActionButtonStyle: ButtonStyle {
    let isExtra: Bool
    var emphasis: AppButtonEmphasis = .primary
    var expands = true
    var isAvailable = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let theme = AppTheme(isExtra: isExtra)
        let canAct = isEnabled && isAvailable
        configuration.label
            .font(AppTypography.action)
            .multilineTextAlignment(.center)
            .foregroundStyle(emphasis == .primary ? (canAct ? Color.white : theme.secondaryText) : (emphasis == .destructive ? AppSemanticColor.destructive : theme.accent))
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.item)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 52)
            .background(AppButtonBackground(isExtra: isExtra, emphasis: emphasis, enabled: canAct))
            .contentShape(RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous))
            .opacity(canAct ? (configuration.isPressed ? 0.82 : 1) : 0.55)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

private struct AppButtonBackground: View {
    let isExtra: Bool
    let emphasis: AppButtonEmphasis
    let enabled: Bool
    @Environment(\.omniV2) private var v2
    @Environment(\.omniExtra) private var omniExtra
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let theme = AppTheme(isExtra: isExtra)
        // Screens not yet redrawn colour text by the system scheme, so a dark scheme means the night palette too.
        let palette = OmniPalette(night: isExtra || colorScheme == .dark, extra: omniExtra)
        if v2 && emphasis == .primary {
            RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
                .fill(enabled ? palette.cta : palette.muted.opacity(0.25))
                .background(
                    RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
                        .fill(enabled ? palette.ctaShadow : .clear)
                        .offset(y: 3)
                )
                .allowsHitTesting(false)
        } else {
        RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
            .fill(emphasis == .primary
                ? (enabled ? AnyShapeStyle(theme.primaryGradient) : AnyShapeStyle(Color.secondary.opacity(isExtra ? 0.3 : 0.16)))
                : AnyShapeStyle((emphasis == .destructive ? AppSemanticColor.destructive : theme.accent).opacity(0.1)))
            .allowsHitTesting(false)
        }
    }
}

/// Dùng khi nhãn thao tác đã chứa kích thước riêng, ví dụ nút đếm ngược của thẻ từ.
struct AppActionFill: ViewModifier {
    let isExtra: Bool
    var enabled = true
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content.frame(minHeight: 52).background(AppButtonBackground(isExtra: isExtra, emphasis: .primary, enabled: enabled && isEnabled))
    }
}

struct AppStatusLabel: View {
    let title: String
    let icon: String
    let tint: Color
    var body: some View {
        Label(title, systemImage: icon)
            .font(AppTypography.label)
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.item)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous))
    }
}

extension View {
    func appSurface(_ kind: AppSurfaceKind, isExtra: Bool, tint: Color? = nil) -> some View {
        background(AppSurfaceBackground(kind: kind, isExtra: isExtra, tint: tint))
            .contentShape(RoundedRectangle(cornerRadius: kind.cornerRadius, style: .continuous))
    }
    func appActionBar(_ shape: AppActionBarShape = .docked, useSystemGlass: Bool = true, prominentGlass: Bool = false) -> some View {
        modifier(AppActionBarSurface(shape: shape, useSystemGlass: useSystemGlass, prominentGlass: prominentGlass))
    }
}

/// Thanh tải nổi; cả trạng thái đang tải và đã tải dùng cùng bề mặt kính.
struct AppFloatingDownloadBar: View {
    let title: String
    let isWorking: Bool
    let isComplete: Bool
    let isExtra: Bool
    let action: () -> Void

    private var tint: Color { isComplete ? AppSemanticColor.success : AppTheme(isExtra: isExtra).accent }

    var body: some View {
        Group {
            if isComplete {
                label.appActionBar(.capsule, prominentGlass: true)
                    .accessibilityIdentifier("explore-download-complete")
            } else {
                Button(action: action) {
                    label.appActionBar(.capsule, prominentGlass: true)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityIdentifier("explore-download-action")
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, AppSpacing.item)
        .padding(.bottom, AppSpacing.inline)
    }

    private var label: some View {
        HStack(spacing: AppSpacing.inline) {
            if isWorking { ProgressView().tint(tint) }
            else { Image(systemName: isComplete ? "checkmark.circle.fill" : "arrow.down.circle.fill") }
            Text(title).multilineTextAlignment(.center)
        }
        .font(AppTypography.action)
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.card)
        .padding(.vertical, AppSpacing.item)
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Capsule())
    }
}
