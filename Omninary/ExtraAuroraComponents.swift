import SwiftUI

enum ExtraAuroraPalette {
    static let obsidian = Color(red: 0.025, green: 0.020, blue: 0.070)
    static let deepBlue = Color(red: 0.035, green: 0.080, blue: 0.20)
    static let ice = Color(red: 0.30, green: 0.78, blue: 1.0)
    static let iceCyan = ice
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

/// Thanh thao tác nổi mô phỏng kính lỏng của iOS, dùng trên các danh sách cần
/// tìm kiếm nhanh và thêm nội dung mà không chiếm chỗ trên thanh điều hướng.
struct LiquidGlassMenuAction {
    let title: String
    let systemImage: String
    let action: () -> Void
}

struct LiquidGlassBottomActionBar: View {
    @Binding var searchText: String
    let searchPrompt: String
    let addAccessibilityLabel: String
    let addAction: () -> Void
    var addMenuItems: [LiquidGlassMenuAction] = []

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Kính lỏng hệ thống có độ trong và khúc xạ như thanh điều hướng.
                GlassEffectContainer(spacing: AppSpacing.item) {
                    controls(useSystemGlass: true)
                }
            } else {
                controls(useSystemGlass: false)
            }
        }
        .padding(.horizontal, AppSpacing.page)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func controls(useSystemGlass: Bool) -> some View {
        HStack(spacing: AppSpacing.item) {
            searchField
                .liquidGlassCapsule(useSystemGlass: useSystemGlass)

            addButton
                .liquidGlassCircle(useSystemGlass: useSystemGlass)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(searchPrompt, text: $searchText)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Xóa tìm kiếm")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    @ViewBuilder
    private var addButton: some View {
        if addMenuItems.isEmpty {
            Button(action: addAction) { addLabel }
                .accessibilityLabel(addAccessibilityLabel)
        } else {
            Menu {
                ForEach(addMenuItems, id: \.title) { item in
                    Button(item.title, systemImage: item.systemImage, action: item.action)
                }
            } label: { addLabel }
            .accessibilityLabel(addAccessibilityLabel)
        }
    }

    private var addLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
    }

}

extension View {
    func liquidGlassCapsule(useSystemGlass: Bool) -> some View {
        appActionBar(.capsule, useSystemGlass: useSystemGlass)
    }

    func liquidGlassCircle(useSystemGlass: Bool) -> some View {
        appActionBar(.circle, useSystemGlass: useSystemGlass)
    }

}

extension View {
    func vocabularySheetStyle(isExtra: Bool) -> some View {
        self
            .preferredColorScheme(isExtra ? .dark : nil)
            .tint(isExtra ? ExtraAuroraPalette.ice : .blue)
            .presentationBackground {
                if isExtra { AuroraBackdrop() }
                else { Color(UIColor.systemGroupedBackground) }
            }
    }
}
