#if DEBUG
import SwiftUI

/// Dữ liệu cục bộ để kiểm tra các thành phần, không thay đổi dữ liệu tài khoản.
struct DesignConsistencyPreview: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var actionCount = 0
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    private var theme: AppTheme { AppTheme(isExtra: isExtra) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    VStack(alignment: .leading, spacing: AppSpacing.item) {
                        Label("Tiến độ học tập", systemImage: "chart.bar.xaxis").font(AppTypography.cardTitle)
                        Text("Đã bấm \(actionCount) lần").font(AppTypography.metric).accessibilityIdentifier("design-action-count")
                        Text("Thẻ lớn dùng chung khoảng cách và phân cấp chữ ở cả hai giao diện.")
                            .font(AppTypography.body).foregroundStyle(theme.secondaryText)
                    }
                    .padding(AppSpacing.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.card, isExtra: isExtra)

                    HStack(spacing: AppSpacing.item) {
                        Image(systemName: "books.vertical.fill").foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text("Bộ từ hôm nay").font(AppTypography.cardTitle)
                            Text("12 từ đang học").font(AppTypography.metadata).foregroundStyle(theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(theme.accent)
                    }
                    .padding(AppSpacing.row)
                    .appSurface(.row, isExtra: isExtra)

                    VStack(alignment: .leading, spacing: AppSpacing.item) {
                        Text("Chi tiết bài học").font(AppTypography.destinationTitle)
                        Text("Thẻ chi tiết có bề mặt riêng, cùng kiểu chữ và khoảng cách với các trang tương đương.")
                            .font(AppTypography.body).foregroundStyle(theme.secondaryText)
                    }
                    .padding(AppSpacing.card)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appSurface(.detail, isExtra: isExtra)

                    AppStatusLabel(title: "Đã hoàn thành", icon: "checkmark.circle.fill", tint: AppSemanticColor.success)
                    AppStatusLabel(title: "Cần ôn tập", icon: "exclamationmark.circle.fill", tint: AppSemanticColor.attention)
                    Button("Đang xử lý") { }
                        .buttonStyle(AppActionButtonStyle(isExtra: isExtra)).disabled(true)
                        .accessibilityIdentifier("design-disabled-action")
                    Button("Xóa mục mẫu", role: .destructive) { actionCount = 0 }
                        .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .destructive))
                }
                .padding(AppSpacing.page)
            }
            .background {
                if isExtra { AuroraBackdrop() }
                else { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: AppSpacing.item) { actions }
                    } else {
                        HStack(spacing: AppSpacing.item) { actions }
                    }
                }
                .padding(AppSpacing.page)
                .appActionBar()
            }
            .navigationTitle("Thiết kế chung")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(isExtra ? .dark : nil)
    }

    @ViewBuilder private var actions: some View {
        Button("Nghe lại") { actionCount = 0 }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .secondary))
            .accessibilityIdentifier("design-secondary-action")
        Button("Tiếp tục") { actionCount += 1 }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
            .accessibilityIdentifier("design-primary-action")
    }
}
#endif
