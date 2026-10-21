import SwiftUI

// MARK: - My Omni Popup Type
enum MyOmniPopupType: Identifiable, Equatable {
    case icons
    case item(OmniShopItem)

    var id: String {
        switch self {
        case .icons: return "icons"
        case .item(let item): return item.id
        }
    }

    static func == (lhs: MyOmniPopupType, rhs: MyOmniPopupType) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProfileView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var heartManager = OmniLearningHeartManager.shared
    @ObservedObject private var doublePointsManager = OmniDoublePointsManager.shared
    @ObservedObject private var freezeManager = OmniStreakFreezeManager.shared
    @ObservedObject private var streakSimulator = StreakPresentationSimulator.shared
    @ObservedObject private var extraManager = OmniExtraordinaryManager.shared
    @ObservedObject private var restoreManager = OmniStreakRestoreManager.shared
    @ObservedObject private var iconCatalog = OmniIconCatalog.shared
    @ObservedObject private var itemCatalog = OmniItemCatalog.shared
    @State private var lightningPulse = false
    @State private var heartRechargePulse = false
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @AppStorage("equipped_omni_icon_id") private var equippedIconId = "ditandnary_classic"
    @AppStorage("unlocked_omni_icon_ids") private var unlockedIconIdsRaw = "ditandnary_classic,extraordinary_aurora"
    @AppStorage("omni_reward_points") private var omniPoints = 1250

    @State private var isEditingName = false
    @State private var newDisplayName = ""
    @State private var isSavingName = false

    @State private var showUpgradeSheet = false
    @State private var showTopUpSheet = false
    @State private var isSigningOut = false
    @State private var errorMessage = ""

    // Center Popups
    @State private var activePopup: MyOmniPopupType? = nil
    @State private var selectedPopupIconID: String?
    @State private var selectedOmniconCategory = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showTopUpInAlert = false
    @State private var isApplyingItem = false

    @GestureState private var isPressingProfileCard = false
    @State private var isDragonAwakened = false
    @State private var isChronoAwakened = false
    @State private var isSolarAwakened = false


    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    private var effectiveStreak: Int {
        streakSimulator.isActive ? streakSimulator.displayedDays : freezeManager.currentStreak
    }

    private var isFreezeActive: Bool {
        streakSimulator.isActive
            ? streakSimulator.winterShieldIsReady && !streakSimulator.isFlameLit
            : freezeManager.isFrozenToday && !freezeManager.isFlameLit
    }

    private var canRestoreStreak: Bool {
        streakSimulator.isActive
            ? isExtra && streakSimulator.hasActiveRestoreWindow
            : restoreManager.canRestore(isExtra: isExtra && extraManager.isActive, currentEffectiveStreak: effectiveStreak)
    }

    private var freezeCountdown: String {
        streakSimulator.isActive ? streakSimulator.freezeCountdownString : freezeManager.freezeCountdown
    }

    private var restoreDisplayDays: Int {
        streakSimulator.isActive ? streakSimulator.recoverableDays : restoreManager.savedStreak
    }

    private var restoreCountdown: String {
        streakSimulator.isActive ? streakSimulator.restoreCountdownString : restoreManager.countdownString
    }

    private var unlockedIds: Set<String> {
        Set(unlockedIconIdsRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    private func isIconUnlocked(_ item: OmniIconItem) -> Bool {
        if item.id == "ditandnary_classic" { return true }
        if item.isExtraExclusive && !isExtra { return false }
        if item.id == "omni_mythic_imperial_chrono" {
            return unlockedIds.contains(item.id) || isExtra
        }
        if let streakReq = item.streakDaysRequired {
            return effectiveStreak >= streakReq || unlockedIds.contains(item.id)
        }
        return unlockedIds.contains(item.id)
    }

    private var ownedIcons: [OmniIconItem] {
        iconCatalog.items.filter { isIconUnlocked($0) }
    }

    private var effectiveEquippedId: String {
        if !isExtra {
            return "ditandnary_classic"
        }
        if equippedIconId == "ditandnary_classic" {
            return "extraordinary_aurora"
        }
        return equippedIconId
    }

    private var currentAvatarAssetName: String {
        if !isExtra {
            return "OmniIconDitandnary"
        }
        return iconCatalog.item(for: effectiveEquippedId)?.assetName ?? "OmniIconExtraordinary"
    }

    private var isDragonEquipped: Bool {
        effectiveEquippedId == "omni_mythic_jade_dragon"
    }

    private var isChronoEquipped: Bool {
        effectiveEquippedId == "omni_mythic_imperial_chrono"
    }

    private var isSolarEquipped: Bool {
        effectiveEquippedId == "omni_mythic_solar_system"
    }

    private func checkAndPersistStreakUnlocks() {
        guard !streakSimulator.isActive else { return }
        let uid = auth.currentUser?.id.uuidString
        iconCatalog.checkAndUnlockStreakIcons(userId: uid)
    }

    private var selectedPopupIcon: OmniIconItem? {
        if let selectedPopupIconID, let selected = iconCatalog.item(for: selectedPopupIconID) { return selected }
        return iconCatalog.items.first
    }

    private func selectIcon(_ item: OmniIconItem) {
        selectedPopupIconID = item.id
        selectedOmniconCategory = item.category
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(spacing: AppSpacing.cardGap) {
                        profileCard
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("my-omni-profile-card")
                        if !isExtra {
                            extraordinaryUpgradeCard
                                .accessibilityIdentifier("my-omni-upgrade-card")
                        }
                        omniPointsCard
                            .accessibilityIdentifier("my-omni-points-card")
                    }
                    .padding()
                }

                // Popup ở giữa màn hình
                centerPopupOverlay
            }
            .navigationTitle("My Omni")
            .background {
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                ExtraordinaryUpgradeSheet(interfaceModeRaw: $interfaceModeRaw)
            }
            .sheet(isPresented: $showTopUpSheet) {
                OmniPointsTopUpSheet(omniPoints: $omniPoints)
            }
            .alert("Đổi tên hiển thị", isPresented: $isEditingName) {
                TextField("Tên hiển thị mới", text: $newDisplayName)
                Button("Hủy", role: .cancel) { }
                Button(isSavingName ? "Đang lưu..." : "Lưu") {
                    Task { await updateDisplayName() }
                }
                .disabled(isSavingName || newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Nhập tên bạn muốn hiển thị trong ứng dụng.")
            }
            .alert("Thông báo", isPresented: $showAlert) {
                if showTopUpInAlert {
                    Button("Nạp điểm") {
                        showTopUpSheet = true
                    }
                    Button("Để sau", role: .cancel) { }
                } else {
                    Button("OK", role: .cancel) { }
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                checkAndPersistStreakUnlocks()
                Task { await heartManager.refreshHearts() }
                doublePointsManager.checkStatus()
                freezeManager.checkStatus()
                extraManager.checkStatus()
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    lightningPulse = true
                }
                if !isExtra {
                    equippedIconId = "ditandnary_classic"
                    if let first = iconCatalog.items.first { selectIcon(first) }
                }
            }
            .onChange(of: interfaceModeRaw) { _, newMode in
                let isNowExtra = (newMode == AppInterfaceMode.extraordinary.rawValue)
                if !isNowExtra {
                    equippedIconId = "ditandnary_classic"
                    if let first = iconCatalog.items.first { selectIcon(first) }
                }
            }
            .task {
                if let uid = auth.currentUser?.id.uuidString {
                    await OmniRewardRepository.syncServerToLocal(userId: uid)
                    await freezeManager.syncFromRemote(userId: uid)
                }
                let didLoadCatalog = await iconCatalog.refresh()
                _ = await itemCatalog.refresh()
                if didLoadCatalog, selectedPopupIconID == nil, let first = iconCatalog.items.first {
                    selectIcon(first)
                }
            }
        }
    }

    // MARK: - Profile Card
    private var profileCard: some View {
        VStack(spacing: 16) {
            // Phần thông tin người dùng
            HStack(spacing: 16) {
                // Avatar: Chạm vào mở pop-up biểu tượng Omnicon
                Button {
                    if let equipped = iconCatalog.item(for: effectiveEquippedId) ?? iconCatalog.items.first {
                        selectIcon(equipped)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        activePopup = .icons
                    }
                } label: {
                    if isDragonEquipped {
                        LivingDragonOmniconView(isAwakened: isDragonAwakened, size: 70, cornerRadius: 18)
                            .shadow(
                                color: isDragonAwakened ? Color(red: 1.0, green: 0.84, blue: 0.2).opacity(0.8) : (isExtra ? ExtraAuroraPalette.electricBlue.opacity(0.35) : Color.black.opacity(0.12)),
                                radius: isDragonAwakened ? 14 : 8,
                                y: isDragonAwakened ? 0 : 3
                            )
                            .scaleEffect(isDragonAwakened ? 1.05 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDragonAwakened)
                    } else if isChronoEquipped {
                        LivingChronoOmniconView(isAwakened: isChronoAwakened, mode: .liveVietnamTime, size: 70, cornerRadius: 18)
                            .shadow(
                                color: isChronoAwakened ? Color(red: 1.0, green: 0.84, blue: 0.2).opacity(0.85) : (isExtra ? Color(red: 1.0, green: 0.75, blue: 0.15).opacity(0.4) : Color.black.opacity(0.15)),
                                radius: isChronoAwakened ? 16 : 8,
                                y: isChronoAwakened ? 0 : 3
                            )
                            .scaleEffect(isChronoAwakened ? 1.05 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isChronoAwakened)
                    } else if isSolarEquipped {
                        LivingSolarOmniconView(isAwakened: isSolarAwakened, size: 70, cornerRadius: 18)
                            .shadow(
                                color: isSolarAwakened ? Color(red: 0.96, green: 0.62, blue: 0.04).opacity(0.85) : (isExtra ? Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.4) : Color.black.opacity(0.15)),
                                radius: isSolarAwakened ? 16 : 8,
                                y: isSolarAwakened ? 0 : 3
                            )
                            .scaleEffect(isSolarAwakened ? 1.05 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSolarAwakened)
                    } else {
                        Image(currentAvatarAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 70, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: isExtra ? ExtraAuroraPalette.electricBlue.opacity(0.35) : Color.black.opacity(0.12), radius: 8, y: 3)
                    }
                }
                .buttonStyle(.plain)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(auth.displayName)
                            .font(AppTypography.destinationTitle)
                            .foregroundStyle(isExtra ? Color.white : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Button {
                            newDisplayName = auth.displayName
                            isEditingName = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(isExtra ? ExtraAuroraPalette.ice.opacity(0.7) : Color.blue.opacity(0.8))
                        }
                    }

                    if let email = auth.currentUser?.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(isExtra ? Color.white.opacity(0.55) : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 4)

                // Lượt học còn lại trong ngày (<icon trái tim>: 05 / vô cực)
                learningHeartsBadge
            }

            // Dấu gạch ngăn cách
            Rectangle()
                .fill(isExtra ? Color.white.opacity(0.22) : Color.secondary.opacity(0.25))
                .frame(height: 1)

            // Dưới dấu gạch: 5 vật phẩm (Extra - Tim - Băng - Sét - Lửa)
            HStack(spacing: 0) {
                // 1. Extra (Trải nghiệm phi thường)
                if let item = itemCatalog.item(for: "extraordinary_trial") {
                    extraordinaryQuickActionButton(item: item) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activePopup = .item(item)
                        }
                    }
                }

                Spacer(minLength: 4)

                // 2. Tim (Trái tim bên lề)
                if let item = itemCatalog.item(for: "extra_heart") {
                    learningHeartQuickActionButton(
                        iconName: "heart.fill",
                        title: "Tim",
                        colors: item.iconColors,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                activePopup = .item(item)
                            }
                        }
                    )
                }

                Spacer(minLength: 4)

                // 3. Băng (Mùa đông không lạnh)
                if let item = itemCatalog.item(for: "streak_freeze") {
                    streakFreezeQuickActionButton(item: item) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activePopup = .item(item)
                        }
                    }
                }

                Spacer(minLength: 4)

                // 4. Sét (Gấp đôi Canxi)
                if let item = itemCatalog.item(for: "double_points") {
                    doublePointsQuickActionButton(item: item) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activePopup = .item(item)
                        }
                    }
                }

                Spacer(minLength: 4)

                // 5. Lửa (Người giữ lửa)
                if let item = itemCatalog.item(for: "restore_streak") {
                    streakRestoreQuickActionButton(item: item) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            activePopup = .item(item)
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        .myOmniCardStyle(isExtra: isExtra)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isPressingProfileCard) { value, state, _ in
                    switch value {
                    case .second(true, _):
                        state = true
                    default:
                        state = false
                    }
                }
        )
        .onChange(of: isPressingProfileCard) { _, isPressing in
            if isDragonEquipped {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isDragonAwakened = isPressing
                }
                if isPressing {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } else if isChronoEquipped {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isChronoAwakened = isPressing
                }
                if isPressing {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            } else if isSolarEquipped {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSolarAwakened = isPressing
                }
                if isPressing {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
        }
    }

    // MARK: - Learning Hearts Badge (<icon trái tim>: 05 / vô cực)
    private var learningHeartsBadge: some View {
        Button {
            if let heartItem = itemCatalog.item(for: "extra_heart") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    activePopup = .item(heartItem)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.red)

                if isExtra {
                    Image(systemName: "infinity")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color.white)
                } else {
                    Text(heartManager.remainingHearts == 0 && !heartManager.resetCountdownString.isEmpty
                         ? heartManager.resetCountdownString
                         : String(format: "%02d", heartManager.remainingHearts))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(heartManager.remainingHearts > 0 ? (isExtra ? Color.white : Color.primary) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        isExtra
                            ? Color.white.opacity(0.12)
                            : Color.red.opacity(0.08)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isExtra ? Color.white.opacity(0.2) : Color.red.opacity(0.22),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Item Quick Action Button
    private func itemQuickActionButton(
        iconName: String,
        title: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 4, y: 2)

                    Image(systemName: iconName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                }

                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : Color.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// Khi đã hết lượt, Trái tim bên lề trở thành lời nhắc trực quan để hồi lượt.
    private func learningHeartQuickActionButton(
        iconName: String,
        title: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        let needsRecharge = !heartManager.isExtra && heartManager.remainingHearts == 0

        return Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(needsRecharge ? Color.white.opacity(0.9) : Color.white.opacity(0.25), lineWidth: needsRecharge ? 1.8 : 1)
                        )
                        .shadow(
                            color: needsRecharge ? Color.cyan.opacity(heartRechargePulse ? 0.9 : 0.48) : (colors.first?.opacity(0.35) ?? .clear),
                            radius: needsRecharge ? (heartRechargePulse ? 10 : 5) : 4,
                            y: 2
                        )
                        .shadow(color: needsRecharge ? Color.yellow.opacity(heartRechargePulse ? 0.65 : 0.25) : .clear, radius: needsRecharge ? 6 : 0, y: 0)

                    Image(systemName: iconName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: needsRecharge ? Color.white : .clear, radius: needsRecharge ? 4 : 0)
                        .scaleEffect(needsRecharge && heartRechargePulse ? 1.12 : 1)
                }

                Text(needsRecharge ? "Hồi lượt" : title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(needsRecharge ? (isExtra ? ExtraAuroraPalette.ice : Color.blue) : (isExtra ? ExtraAuroraPalette.champagne : Color.primary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onAppear {
            guard needsRecharge else { return }
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                heartRechargePulse = true
            }
        }
        .onChange(of: needsRecharge) { _, isEmpty in
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                heartRechargePulse = isEmpty
            }
        }
    }

    // MARK: - Extraordinary Trial Quick Action Button (♾️ Trải nghiệm phi thường)
    private func extraordinaryQuickActionButton(
        item: OmniShopItem,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if extraManager.isTrialActive {
                        // Hiệu ứng hào quang tím / aurora phát sáng khi đang kích hoạt dùng thử
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "8B5CF6"), Color(hex: "A855F7"), Color(hex: "EC4899")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white, Color(hex: "C4B5FD"), Color.white],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Color(hex: "8B5CF6").opacity(0.6), radius: 6, y: 0)
                            .shadow(color: Color(hex: "EC4899").opacity(0.35), radius: 4, y: 2)

                        Image(systemName: "infinity")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                            .shadow(color: Color(hex: "C4B5FD"), radius: 4)
                    } else {
                        // Trạng thái bình thường
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: item.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: item.iconColors.first?.opacity(0.35) ?? .clear, radius: 4, y: 2)

                        Image(systemName: "infinity")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Tag đồng hồ đếm ngược hoặc tên nhãn "Extra"
                if extraManager.isTrialActive {
                    HStack(spacing: 2) {
                        Image(systemName: "infinity")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundColor(Color(hex: "8B5CF6"))
                        Text(extraManager.countdownString)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isExtra ? Color(hex: "E9D5FF") : Color(hex: "6D28D9"))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color(hex: "7C3AED").opacity(0.3) : Color(hex: "EDE9FE"))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "A78BFA").opacity(isExtra ? 0.6 : 0.4), lineWidth: 0.8)
                    )
                } else {
                    Text("Extra")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Double Points Quick Action Button (⚡ Gấp đôi Canxi)
    private func doublePointsQuickActionButton(
        item: OmniShopItem,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if doublePointsManager.isActive {
                        // Hiệu ứng viền vàng phát sáng & xung nhịp sấm sét
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "F59E0B"), Color(hex: "EAB308"), Color(hex: "FDE047")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.yellow, Color.white, Color.yellow],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Color.yellow.opacity(lightningPulse ? 0.9 : 0.55), radius: lightningPulse ? 8 : 4, y: 0)
                            .shadow(color: Color.orange.opacity(0.4), radius: 6, y: 2)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                            .shadow(color: Color.yellow, radius: 4)
                            .scaleEffect(lightningPulse ? 1.15 : 0.94)
                    } else {
                        // Trạng thái bình thường chưa kích hoạt
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: item.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: item.iconColors.first?.opacity(0.35) ?? .clear, radius: 4, y: 2)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Tag đồng hồ đếm ngược hoặc tên vật phẩm
                if doublePointsManager.isActive {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundColor(Color.orange)
                        Text(doublePointsManager.countdownString)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isExtra ? Color.yellow : Color(hex: "B45309"))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color.yellow.opacity(0.2) : Color.yellow.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.yellow.opacity(isExtra ? 0.5 : 0.35), lineWidth: 0.8)
                    )
                } else {
                    Text("Sét")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak Freeze Quick Action Button (❄️ Mùa đông không lạnh)
    private func streakFreezeQuickActionButton(
        item: OmniShopItem,
        action: @escaping () -> Void
    ) -> some View {
        let isFreezeActive = self.isFreezeActive
        return Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if isFreezeActive {
                        // Hiệu ứng băng phát sáng & viền xanh băng tuyết
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "06B6D4"), Color(hex: "38BDF8"), Color(hex: "E0F2FE")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white, Color(hex: "38BDF8"), Color.white],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Color(hex: "06B6D4").opacity(0.7), radius: 6, y: 0)
                            .shadow(color: Color(hex: "0284C7").opacity(0.4), radius: 4, y: 2)

                        Image(systemName: "snowflake")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                            .shadow(color: Color(hex: "38BDF8"), radius: 4)
                    } else {
                        // Trạng thái bình thường chưa kích hoạt hoặc đã học hôm nay
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: item.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: item.iconColors.first?.opacity(0.35) ?? .clear, radius: 4, y: 2)

                        Image(systemName: "snowflake")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Tag trạng thái hoặc tên vật phẩm
                if isFreezeActive {
                    HStack(spacing: 2) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundColor(Color(hex: "0284C7"))
                        Text(freezeCountdown)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(isExtra ? Color(hex: "38BDF8") : Color(hex: "0369A1"))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color(hex: "0284C7").opacity(0.3) : Color(hex: "E0F2FE"))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "38BDF8").opacity(isExtra ? 0.6 : 0.4), lineWidth: 0.8)
                    )
                } else {
                    Text(isFreezeActive ? freezeCountdown : "Băng")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak Restore Quick Action Button (🔥 Người giữ lửa)
    private func streakRestoreQuickActionButton(
        item: OmniShopItem,
        action: @escaping () -> Void
    ) -> some View {
        let canRestore = canRestoreStreak

        return Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    if canRestore {
                        // Hiệu ứng ngọn lửa hồi sinh phát sáng viền cam đỏ
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "DC2626"), Color(hex: "EA580C"), Color(hex: "F97316")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white, Color(hex: "FDBA74"), Color.white],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: Color(hex: "EA580C").opacity(0.8), radius: 6, y: 0)
                            .shadow(color: Color(hex: "DC2626").opacity(0.4), radius: 4, y: 2)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.white)
                            .shadow(color: Color(hex: "FDBA74"), radius: 4)
                    } else {
                        // Trạng thái bình thường
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: item.iconColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: item.iconColors.first?.opacity(0.35) ?? .clear, radius: 4, y: 2)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Tag trạng thái hoặc tên nhãn "Lửa"
                if canRestore {
                    HStack(spacing: 2) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundColor(Color(hex: "EA580C"))
                        Text(restoreCountdown)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isExtra ? Color(hex: "FED7AA") : Color(hex: "C2410C"))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color(hex: "EA580C").opacity(0.3) : Color(hex: "FFEDD5"))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "FB923C").opacity(isExtra ? 0.6 : 0.4), lineWidth: 0.8)
                    )
                } else {
                    Text("Lửa")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extraordinary Upgrade Card (Dành riêng cho Ditandnary - nằm dưới thẻ thông tin)
    private var extraordinaryUpgradeCard: some View {
        Button {
            showUpgradeSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.purple.opacity(0.3), radius: 6, y: 2)

                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Nâng cấp Extraordinary")
                        .font(AppTypography.cardTitle)
                        .foregroundColor(.primary)

                    Text("Mở khoá phiên bản phi thường của Omninary")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.secondary.opacity(0.7))
            }
            .myOmniCardStyle(isExtra: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Omni Points Card (Điểm thưởng Omni)
    private var omniPointsCard: some View {
        Button {
            showTopUpSheet = true
        } label: {
            HStack(spacing: 14) {
                OmniCoinView(size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Điểm thưởng Omni")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : Color.blue)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(omniPoints)")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(isExtra ? ExtraAuroraPalette.champagne : Color.orange)

                        Text("điểm")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Nạp điểm")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isExtra ? ExtraAuroraPalette.ice.opacity(0.85) : Color.blue.opacity(0.85))

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isExtra ? Color.white.opacity(0.5) : Color.blue.opacity(0.6))
                }
            }
            .myOmniCardStyle(isExtra: isExtra)
        }
        .buttonStyle(.plain)
    }

    private func updateDisplayName() async {
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await auth.updateDisplayName(newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines))
            isEditingName = false
        } catch {
            errorMessage = "Cập nhật tên thất bại: \(error.localizedDescription)"
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await auth.signOut()
        } catch {
            errorMessage = "Đăng xuất thất bại: \(error.localizedDescription)"
        }
    }

    // MARK: - Center Modal Popups
    @ViewBuilder
    private var centerPopupOverlay: some View {
        if let popup = activePopup {
            ZStack {
                // Dimmed Backdrop
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            activePopup = nil
                        }
                    }

                // Centered Box
                VStack(spacing: 0) {
                    switch popup {
                    case .icons:
                        iconsPopupContent
                    case .item(let shopItem):
                        itemPopupContent(shopItem)
                    }
                }
                .padding(20)
                .frame(maxWidth: 340)
                .appSurface(.detail, isExtra: isExtra)
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activePopup)
            .zIndex(100)
        }
    }

    // MARK: - Item Popup Content (Tại chỗ dùng, tại chỗ mua)
    @ViewBuilder
    private func itemPopupContent(_ item: OmniShopItem) -> some View {
        VStack(spacing: 16) {
            // Close Button
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activePopup = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
                }
            }

            // Biểu tượng vật phẩm
            ZStack {
                let isDoubleActive = (item.id == "double_points" && doublePointsManager.isActive)
                let isFreezeActive = (item.id == "streak_freeze" && self.isFreezeActive)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDoubleActive
                                ? [Color(hex: "F59E0B"), Color(hex: "EAB308"), Color(hex: "FDE047")]
                                : (isFreezeActive
                                    ? [Color(hex: "06B6D4"), Color(hex: "38BDF8"), Color(hex: "E0F2FE")]
                                    : item.iconColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isDoubleActive
                                    ? LinearGradient(colors: [.yellow, .white, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : (isFreezeActive
                                        ? LinearGradient(colors: [.white, Color(hex: "38BDF8"), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        : LinearGradient(colors: [Color.white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                                lineWidth: (isDoubleActive || isFreezeActive) ? 2 : 1
                            )
                    )
                    .shadow(
                        color: isDoubleActive ? Color.yellow.opacity(0.7) : (isFreezeActive ? Color(hex: "06B6D4").opacity(0.7) : (item.iconColors.first?.opacity(0.4) ?? .clear)),
                        radius: 10,
                        y: 4
                    )

                Image(systemName: item.iconName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(isDoubleActive ? (lightningPulse ? 1.12 : 0.95) : 1.0)
            }

            // Tên & Mô tả
            VStack(spacing: 6) {
                Text(item.name)
                    .font(AppTypography.destinationTitle)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)

                Text(itemDescription(for: item))
                    .font(.caption)
                    .foregroundStyle(
                        item.id == "restore_streak" && canRestoreStreak
                            ? (isExtra ? Color(hex: "FDBA74") : Color(hex: "EA580C"))
                            : (AppTheme(isExtra: isExtra).secondaryText)
                    )
                    .fontWeight(
                        item.id == "restore_streak" && canRestoreStreak
                            ? .semibold
                            : .regular
                    )
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if item.id == "double_points" && doublePointsManager.isActive {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.yellow)

                        Text("Đang nhân đôi x2 — Còn \(doublePointsManager.countdownString)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isExtra ? Color.yellow : Color(hex: "B45309"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color.yellow.opacity(0.2) : Color.yellow.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.yellow.opacity(isExtra ? 0.45 : 0.35), lineWidth: 0.8)
                    )
                    .padding(.top, 2)
                } else if item.id == "streak_freeze" && isFreezeActive {
                    HStack(spacing: 5) {
                        Image(systemName: "snowflake")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(hex: "0284C7"))

                        Text("Đang đóng băng — còn \(freezeCountdown)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isExtra ? Color(hex: "38BDF8") : Color(hex: "0369A1"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color(hex: "0284C7").opacity(0.3) : Color(hex: "E0F2FE"))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: "38BDF8").opacity(isExtra ? 0.6 : 0.4), lineWidth: 0.8)
                    )
                    .padding(.top, 2)
                } else if item.id == "restore_streak" && canRestoreStreak {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.orange)

                        Text("Cứu \(restoreDisplayDays) ngày — còn \(restoreCountdown)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isExtra ? Color(hex: "FDBA74") : Color(hex: "C2410C"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isExtra ? Color.orange.opacity(0.2) : Color.orange.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(isExtra ? 0.45 : 0.35), lineWidth: 0.8)
                    )
                    .padding(.top, 2)
                }
            }

            // Nút hành động trực tiếp
            itemActionButton(for: item)
        }
    }

    private func itemDescription(for item: OmniShopItem) -> String {
        switch item.id {
        case "extra_heart":
            return "Dùng 1 tim để cộng 1 lượt học."
        case "double_points":
            return "Nhân đôi điểm thưởng cho đến hết ngày."
        case "streak_freeze":
            return "Bảo vệ chuỗi đến trước 0 giờ ngày mai. Mỗi 7 ngày dùng một lần và phải học sau lần đóng băng trước."
        case "restore_streak":
            if canRestoreStreak {
                return "Chuỗi \(restoreDisplayDays) ngày đang chờ được cứu. Quyền này hết hạn sau \(restoreCountdown)."
            } else {
                return "Khôi phục chuỗi đã mất gần nhất khi bị gián đoạn (Đặc quyền Extra)."
            }
        case "extraordinary_trial":
            return item.subtitle
        default:
            return item.subtitle
        }
    }

    @ViewBuilder
    private func itemActionButton(for item: OmniShopItem) -> some View {
        switch item.id {
        case "extra_heart":
            if isExtra {
                grayDisabledButton(text: "Đã vô hạn lượt học")
            } else {
                versionButton(text: "Dùng với 50 điểm thưởng Omni") {
                    handleUseItem(item: item, successMessage: "Đã cộng 1 lượt học vào tài khoản của bạn.")
                }
            }

        case "double_points":
            if doublePointsManager.isActive {
                grayDisabledButton(text: "Đang kích hoạt (x2 điểm thưởng)")
            } else {
                versionButton(text: "Dùng với 150 điểm thưởng Omni") {
                    handleUseItem(item: item, successMessage: "Đã nhân đôi điểm thưởng Omni cho đến hết ngày!")
                }
            }

        case "streak_freeze":
            let reason = streakSimulator.isActive ? streakSimulator.freezeDisabledReason : freezeManager.freezeDisabledReason
            if let reason {
                grayDisabledButton(text: reason)
            } else {
                versionButton(text: streakSimulator.isActive ? "Mô phỏng đóng băng" : "Dùng với 300 điểm thưởng Omni") {
                    if streakSimulator.isActive {
                        streakSimulator.useWinterShield()
                        activePopup = nil
                        NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
                    } else {
                        handleUseItem(item: item, successMessage: "Đã đóng băng bảo vệ chuỗi hôm nay!")
                    }
                }
            }

        case "extraordinary_trial":
            if isExtra && !extraManager.isTrialActive {
                grayDisabledButton(text: "Đã nâng cấp Extraordinary")
            } else if extraManager.isTrialActive {
                grayDisabledButton(text: "Đang kích hoạt (\(extraManager.countdownString))")
            } else {
                versionButton(text: "Dùng với 1000 điểm thưởng Omni") {
                    handleUseItem(item: item, successMessage: "Đã kích hoạt 3 ngày trải nghiệm Extraordinary!")
                }
            }

        case "restore_streak":
            if isExtra {
                let canRestore = canRestoreStreak

                if canRestore {
                    versionButton(text: "Dùng với 1000 điểm thưởng Omni") {
                        if streakSimulator.isActive {
                            streakSimulator.useFireKeeper(isExtra: isExtra)
                            activePopup = nil
                            NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
                        } else {
                            handleUseItem(item: item, successMessage: "Đã khôi phục chuỗi của bạn. Hãy hoàn thành bài học hôm nay để thắp sáng ngọn lửa.")
                        }
                    }
                } else {
                    grayDisabledButton(text: effectiveStreak > 0 ? "Chuỗi chưa cần khôi phục" : "Không có chuỗi còn hạn để cứu")
                }
            } else {
                // Ditan: "Nâng cấp Extraordinary" - màu xanh tím
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activePopup = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showUpgradeSheet = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.subheadline.weight(.bold))
                        Text("Nâng cấp Extraordinary")
                            .fontWeight(.bold)
                    }
                    .font(AppTypography.cardTitle)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .modifier(AppActionFill(isExtra: isExtra))
                }
            }

        default:
            EmptyView()
        }
    }

    private func handleUseItem(item: OmniShopItem, successMessage: String) {
        guard !streakSimulator.isActive else {
            activePopup = nil
            showTopUpInAlert = false
            alertMessage = "Đang mô phỏng chuỗi trên giao diện nên vật phẩm thật không được sử dụng."
            showAlert = true
            return
        }
        guard !isApplyingItem else { return }
        isApplyingItem = true
        Task {
            do {
                let result = try await OmniRewardRepository.useOmniItem(item.id)
                await MainActor.run {
                    if let points = result.new_points { omniPoints = points }
                    heartManager.applyActionResult(result)
                    doublePointsManager.applyActionResult(result)
                    if let until = result.extraordinary_trial_until {
                        extraManager.syncFromRemote(untilDateString: until)
                    }
                    freezeManager.applyActionResult(result)
                    if item.id == "streak_freeze" || item.id == "restore_streak" {
                        let kind: StreakActionPresenter.Kind = item.id == "streak_freeze" ? .freeze : .restore
                        StreakActionPresenter.shared.enqueue(kind,
                            previousDays: kind == .restore ? 0 : freezeManager.currentStreak,
                            newDays: freezeManager.currentStreak, rescuedDayKey: result.streak_rescued_date)
                        if item.id == "streak_freeze", extraManager.isActive {
                            NotificationManager.shared.schedulePotentialStreakRestoreAlert(afterLearningOn: Date())
                        } else if item.id == "restore_streak" {
                            NotificationManager.shared.cancelPotentialStreakRestoreAlert()
                        }
                    }
                    isApplyingItem = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeOut(duration: 0.2)) { activePopup = nil }
                    showTopUpInAlert = false
                    if item.id == "streak_freeze" || item.id == "restore_streak" {
                        NotificationCenter.default.post(name: .switchToHomeTab, object: nil)
                    } else {
                        alertMessage = successMessage
                        showAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    isApplyingItem = false
                    showTopUpInAlert = false
                    alertMessage = "Không thể dùng vật phẩm: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    // MARK: - Icons Popup Content (Phân chia danh mục & Mua / Trang bị tại chỗ)
    @ViewBuilder
    private var iconsPopupContent: some View {
        if let selectedPopupIcon {
        let categoryItems = iconCatalog.items.filter { $0.category == selectedOmniconCategory }

        VStack(spacing: 14) {
            // Header
            HStack {
                Text("Biểu tượng Omnicon")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)

                Spacer()

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activePopup = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
                }
            }

            // Bộ chọn danh mục: Dropdown Menu
            Menu {
                ForEach(iconCatalog.categories, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedOmniconCategory = category
                            if let firstInCat = iconCatalog.items.first(where: { $0.category == category }) {
                                selectIcon(firstInCat)
                            }
                        }
                    } label: {
                        HStack {
                            Text(category)
                            if category == selectedOmniconCategory {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Danh mục:")
                        .font(.subheadline)
                        .foregroundColor(isExtra ? Color.white.opacity(0.7) : Color.secondary)

                    Text(selectedOmniconCategory)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(isExtra ? .white : .primary)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.ice : Color.blue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isExtra ? Color.white.opacity(0.08) : Color(uiColor: .tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isExtra ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
                )
            }

            // Lưới icon theo danh mục đã chọn (3 cột, không gian đủ 2 hàng, cuộn lên xuống để xem thêm)
            if categoryItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26))
                        .foregroundColor(isExtra ? Color.white.opacity(0.25) : Color.secondary.opacity(0.35))
                    Text("Chưa có biểu tượng trong danh mục này")
                        .font(.subheadline)
                        .foregroundColor(isExtra ? Color.white.opacity(0.4) : Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 165)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(categoryItems) { item in
                            let isSelected = (item.id == selectedPopupIcon.id)
                            let isEquipped = (item.id == effectiveEquippedId)

                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectIcon(item)
                                }
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    omniconThumbnail(for: item)
                                        .frame(width: 66, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(
                                                    isSelected
                                                        ? (isExtra ? ExtraAuroraPalette.ice : Color.blue)
                                                        : Color.clear,
                                                    lineWidth: isSelected ? 2.5 : 0
                                                )
                                        )
                                        .shadow(
                                            color: isSelected
                                                ? (isExtra ? ExtraAuroraPalette.ice.opacity(0.5) : Color.blue.opacity(0.35))
                                                : Color.black.opacity(0.08),
                                            radius: isSelected ? 6 : 2,
                                            y: 2
                                        )

                                    if isEquipped {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                                            .background(Circle().fill(Color.white).padding(2))
                                            .offset(x: 4, y: 4)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(height: 165)
            }

            // Tên biểu tượng đang chọn (Chỉ hiển thị tên, không hiển thị mô tả)
            if !categoryItems.isEmpty {
                Text(selectedPopupIcon.name)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)
                    .padding(.vertical, 2)

                // Nút hành động cố định dưới pop-up
                omniconActionButton
            } else {
                Text(" ")
                    .font(AppTypography.cardTitle)
                    .padding(.vertical, 2)

                grayDisabledButton(text: "Chưa có biểu tượng")
            }
        }
        } else {
            ProgressView("Đang tải Omnicon...")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private func omniconThumbnail(for item: OmniIconItem) -> some View {
        if item.id == "omni_mythic_jade_dragon" {
            LivingDragonOmniconView(isAwakened: false, size: 66, cornerRadius: 16)
        } else if item.id == "omni_mythic_imperial_chrono" {
            LivingChronoOmniconView(isAwakened: false, mode: .liveVietnamTime, size: 66, cornerRadius: 16)
        } else if item.id == "omni_mythic_solar_system" {
            LivingSolarOmniconView(isAwakened: false, size: 66, cornerRadius: 16)
        } else {
            Image(item.assetName)
                .resizable()
                .scaledToFit()
        }
    }

    @ViewBuilder
    private var omniconActionButton: some View {
        if let selectedPopupIcon {
        let isCurrentlyEquipped = (selectedPopupIcon.id == effectiveEquippedId)
        let isUnlocked = isIconUnlocked(selectedPopupIcon)

        if isCurrentlyEquipped {
            if isExtra,
               let expectedName = AppIconManager.alternateIconName(for: selectedPopupIcon.id),
               UIApplication.shared.alternateIconName != expectedName {
                versionButton(text: "Thử đổi biểu tượng ứng dụng") {
                    withAnimation(.easeOut(duration: 0.2)) { activePopup = nil }
                    Task { await retryAppIcon(named: expectedName) }
                }
            } else {
                grayDisabledButton(text: "Đang trang bị")
            }
        } else if !isExtra {
            // Ditan: chọn cái nào cũng là "Nâng cấp Extraordinary" - màu xanh tím
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    activePopup = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showUpgradeSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.subheadline.weight(.bold))
                    Text("Nâng cấp Extraordinary")
                        .fontWeight(.bold)
                }
                .font(AppTypography.action)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .modifier(AppActionFill(isExtra: isExtra))
            }
        } else {
            // Extra:
            if isUnlocked {
                // Đã sở hữu - Trang bị thôi: màu xanh tím
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        activePopup = nil
                    }
                    Task {
                        await equipIcon(selectedPopupIcon)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                        Text("Đã sở hữu - Trang bị thôi")
                            .fontWeight(.bold)
                    }
                    .font(AppTypography.action)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .modifier(AppActionFill(isExtra: isExtra))
                }
            } else if let reqStreak = selectedPopupIcon.streakDaysRequired, effectiveStreak < reqStreak {
                // Cần đạt chuỗi ... ngày: màu xám
                grayDisabledButton(text: "Cần đạt chuỗi \(reqStreak) ngày")
            } else if let points = selectedPopupIcon.pointsRequired {
                // Mua với ... điểm thưởng Omni: màu xanh tím (cỡ chữ subheadline gọn gàng)
                Button {
                    handleBuyIconWithPoints(selectedPopupIcon, cost: points)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                        Text(points == 0 ? "Nhận miễn phí" : "Mua với \(points) điểm thưởng Omni")
                            .fontWeight(.bold)
                    }
                    .font(AppTypography.action)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .modifier(AppActionFill(isExtra: isExtra))
                }
            } else {
                grayDisabledButton(text: "Chưa mở khóa")
            }
        }
        } else {
            EmptyView()
        }
    }

    private func handleBuyIconWithPoints(_ item: OmniIconItem, cost: Int) {
        if omniPoints < cost {
            alertMessage = "Bạn không đủ điểm thưởng Omni. Cần \(cost) điểm, hiện có \(omniPoints) điểm."
            showTopUpInAlert = true
            showAlert = true
            return
        }

        Task {
            do {
                guard let uid = auth.currentUser?.id.uuidString else {
                    throw NSError(domain: "Omninary", code: 401, userInfo: [NSLocalizedDescriptionKey: "Phiên đăng nhập đã hết hạn."])
                }
                let result = try await OmniRewardRepository.redeemOmniIcon(userId: uid, iconId: item.id, cost: cost)
                guard result.success else {
                    let fallbackMessage = cost == 0 ? "Không thể nhận Omnicon." : "Không thể mua Omnicon."
                    throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: result.message ?? fallbackMessage])
                }
                let profile = try await OmniRewardRepository.fetchOmniProfile(userId: uid)
                await MainActor.run {
                    if let points = result.new_points { omniPoints = points }
                    if let icons = profile?.unlocked_omni_icons {
                        unlockedIconIdsRaw = icons.joined(separator: ",")
                    }
                }
                await equipIcon(item)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) { activePopup = nil }
                    showTopUpInAlert = false
                }
            } catch {
                await MainActor.run {
                    showTopUpInAlert = false
                    alertMessage = cost == 0
                        ? "Không thể nhận Omnicon: \(error.localizedDescription)"
                        : "Không thể mua Omnicon: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func grayDisabledButton(text: String) -> some View {
        Text(text)
            .font(AppTypography.label)
            .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
            .padding(.horizontal, AppSpacing.row)
            .padding(.vertical, AppSpacing.item)
            .frame(maxWidth: .infinity, minHeight: 52)
            .modifier(AppActionFill(isExtra: isExtra, enabled: false))
    }

    private func versionButton(text: String, action: @escaping () -> Void) -> some View {
        Button(text, action: action)
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
    }

    private func equipIcon(_ item: OmniIconItem) async {
        guard let uid = auth.currentUser?.id.uuidString else {
            alertMessage = "Phiên đăng nhập đã hết hạn."
            showAlert = true
            return
        }

        let appIconName: String?
        if isExtra && item.id != AppIconManager.ditandnaryIconId {
            guard let bundledName = AppIconManager.alternateIconName(for: item.id) else {
                alertMessage = "Omnicon này chưa có biểu tượng ứng dụng được đóng gói."
                showAlert = true
                return
            }
            appIconName = bundledName
        } else {
            appIconName = nil
        }

        // Lưu vào local trước để đảm bảo trạng thái avatar không bị gián đoạn
        equippedIconId = item.id
        UserDefaults.standard.set(item.id, forKey: "equipped_omni_icon_id")

        var unlockedSet = Set(unlockedIconIdsRaw.split(separator: ",").map(String.init))
        unlockedSet.insert(item.id)
        unlockedIconIdsRaw = unlockedSet.joined(separator: ",")
        UserDefaults.standard.set(unlockedIconIdsRaw, forKey: "unlocked_omni_icon_ids")

        do {
            try await OmniRewardRepository.updateEquippedIcon(userId: uid, iconId: item.id)
        } catch {
            print("updateEquippedIcon warning: \(error.localizedDescription)")
            if item.id != "omni_mythic_imperial_chrono" && !isExtra {
                alertMessage = "Không thể trang bị Omnicon: \(error.localizedDescription)"
                showAlert = true
                return
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        do {
            // Chỉ Extraordinary mới được đổi ảnh icon ngoài giao diện thôi, còn Ditandnary thì không
            try await AppIconManager.setAppIcon(named: appIconName)
        } catch {
            alertMessage = "Đã trang bị trong ứng dụng, nhưng chưa đổi được biểu tượng trên màn hình chính: \(error.localizedDescription) Chạm vào Omnicon này để thử lại."
            showAlert = true
        }
    }

    private func retryAppIcon(named iconName: String) async {
        do {
            try await AppIconManager.setAppIcon(named: iconName)
        } catch {
            alertMessage = "Chưa đổi được biểu tượng trên màn hình chính: \(error.localizedDescription) Bạn có thể chạm vào Omnicon này để thử lại."
            showAlert = true
        }
    }
}

// MARK: - My Omni Card Style Modifier
private struct MyOmniCardModifier: ViewModifier {
    let isExtra: Bool
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.card)
            .appSurface(.card, isExtra: isExtra)
            .contentShape(RoundedRectangle(cornerRadius: AppSurfaceKind.card.cornerRadius, style: .continuous))
    }
}

fileprivate extension View {
    func myOmniCardStyle(isExtra: Bool) -> some View {
        modifier(MyOmniCardModifier(isExtra: isExtra))
    }
}

// MARK: - Omni Points Top-Up Sheet
struct OmniPointsTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @Binding var omniPoints: Int

    @State private var selectedPackage: TopUpPackage = TopUpPackage.packages[1]
    @State private var isProcessing = false
    @State private var showSuccessAlert = false
    @State private var alertMessage = ""

    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    struct TopUpPackage: Identifiable {
        let id: String
        let points: Int
        let priceString: String
        let bonusBadge: String?

        static let packages: [TopUpPackage] = [
            TopUpPackage(id: "pkg_1000", points: 1000, priceString: "19.000đ", bonusBadge: nil),
            TopUpPackage(id: "pkg_2400", points: 2400, priceString: "39.000đ", bonusBadge: "+20%"),
            TopUpPackage(id: "pkg_5400", points: 5400, priceString: "79.000đ", bonusBadge: "+30%"),
            TopUpPackage(id: "pkg_12000", points: 12000, priceString: "159.000đ", bonusBadge: "+40%")
        ]
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header Card
                        VStack(spacing: 10) {
                            OmniCoinView(size: 64)

                            Text("Điểm thưởng Omni")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(isExtra ? Color.white : Color.primary)

                            Text("Điểm Omni dùng để mở khóa Omnicon và dùng ngay các vật phẩm hỗ trợ học tập.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            HStack(spacing: 6) {
                                Text("Số dư hiện tại:")
                                    .font(.caption)
                                    .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
                                Text("\(omniPoints) điểm")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(isExtra ? ExtraAuroraPalette.champagne : Color.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isExtra ? ExtraAuroraPalette.violet.opacity(0.25) : Color.blue.opacity(0.1))
                                    .overlay(
                                        Capsule().stroke(isExtra ? ExtraAuroraPalette.ice.opacity(0.4) : Color.blue.opacity(0.25), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.top, 12)

                        Spacer(minLength: 16)

                        // Packages List
                        VStack(spacing: AppSpacing.cardGap) {
                            ForEach(TopUpPackage.packages) { pkg in
                                Button {
                                    selectedPackage = pkg
                                } label: {
                                    HStack(spacing: 10) {
                                        OmniCoinView(size: 36, showShadow: selectedPackage.id == pkg.id)

                                        HStack(spacing: 6) {
                                            Text("\(pkg.points) Điểm Omni")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(isExtra ? Color.white : Color.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.82)
                                                .layoutPriority(1)

                                            if let badge = pkg.bonusBadge {
                                                Text(badge)
                                                    .font(.system(size: 10, weight: .heavy))
                                                    .foregroundStyle(AppSemanticColor.attention)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                                                    .fixedSize()
                                            }
                                        }

                                        Spacer(minLength: 8)

                                        Text(pkg.priceString)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(selectedPackage.id == pkg.id ? (isExtra ? ExtraAuroraPalette.ice : Color.blue) : (isExtra ? Color.white : Color.primary))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                Capsule()
                                                    .stroke(selectedPackage.id == pkg.id ? (isExtra ? ExtraAuroraPalette.ice : Color.blue) : Color.secondary.opacity(0.25), lineWidth: 1.2)
                                            )
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                                    .appSurface(.row, isExtra: isExtra)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
                                            .stroke(selectedPackage.id == pkg.id ? AppTheme(isExtra: isExtra).accent : .clear, lineWidth: 2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("top-up-package-\(pkg.id)")
                                .accessibilityValue(selectedPackage.id == pkg.id ? "Đã chọn" : "Chưa chọn")
                            }
                        }

                        Spacer(minLength: 20)

                        // Purchase Button
                        Button {
                            processTopUp()
                        } label: {
                            HStack(spacing: 8) {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    OmniCoinView(size: 20, showShadow: false)
                                    Text("Nạp \(selectedPackage.points) Điểm - \(selectedPackage.priceString)")
                                        .fontWeight(.bold)
                                }
                            }
                        }
                        .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
                        .disabled(isProcessing)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal)
                    .frame(minHeight: geo.size.height)
                }
            }
            .scrollContentBackground(isExtra ? .hidden : .automatic)
            .background {
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .navigationTitle("Điểm thưởng Omni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(isExtra ? Color.white.opacity(0.6) : .secondary)
                    }
                }
            }
            .alert("Nạp điểm thành công", isPresented: $showSuccessAlert) {
                Button("Tuyệt vời", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func processTopUp() {
        isProcessing = true
        let pointsToAdd = selectedPackage.points
        Task {
            do {
                guard let uid = AuthManager.shared.currentUser?.id.uuidString else {
                    throw NSError(domain: "Omninary", code: 401, userInfo: [NSLocalizedDescriptionKey: "Phiên đăng nhập đã hết hạn."])
                }
                let balance = try await OmniRewardRepository.addOmniPoints(userId: uid, pointsToAdd: pointsToAdd)
                await MainActor.run {
                    omniPoints = balance
                    isProcessing = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    alertMessage = "Đã nạp thành công \(pointsToAdd) Điểm Omni vào tài khoản!"
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    alertMessage = "Không thể nạp điểm: \(error.localizedDescription)"
                    showSuccessAlert = true
                }
            }
            await MainActor.run {
                isProcessing = false
            }
        }
    }
}
