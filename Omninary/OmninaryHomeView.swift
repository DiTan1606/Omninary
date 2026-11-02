import SwiftUI

struct OmninaryHomeView: View {
    private let adminUserId = AppConfig.adminUserId

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var storeVocabs: [Vocabulary] = []
    @State private var downloadedKeysByTopic: [String: Set<String>] = [:]
    @State private var listeningCatalog: [ListeningSeriesCatalogItem] = []
    @State private var listeningLibraryLessonIds: Set<String> = []
    @State private var activityLogs: [String: Bool] = [:]
    @State private var hasUnreadNotifications = false
    @State private var selectedMonth = Date()
    @State private var selectedActivityDate = Date()
    @State private var showDailyStats = false
    @State private var isDownloading = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var flameTapEnergy: CGFloat = 0
    @State private var isFlameHeld = false
    @State private var flameFlickerPhase = false
    @State private var flameFlickerTask: Task<Void, Never>?
    @State private var flameDecayWorkItem: DispatchWorkItem?
    @State private var sparklePulse = false
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var freezeManager = OmniStreakFreezeManager.shared
    @ObservedObject private var hearts = OmniLearningHeartManager.shared
    @AppStorage("omni_reward_points") private var omniPoints = 1250
    @Environment(\.omniV2) private var v2
    @Environment(\.omniPalette) private var palette
    @State private var showNotifications = false
    @State private var showExtraUpgradeSheet = false
    @State private var animatedStreakNumber: Int?
    @State private var animatedFlameDays: Int?
    @State private var animatedFootnoteText: String?
    @State private var animatedFootnoteIcon: String?
    @State private var animatedFootnoteColor: Color?
    @State private var animatedEnergyProgress: CGFloat?
    @State private var animatedMilestoneStage: FlameMilestoneStage?
    @State private var celebrationFlameAsset: String?
    @State private var isTargetUnlocked = false
    @State private var isFlameBursting = false
    @State private var burstFlameAsset: String?
    @State private var burstWobbleAngle: Double = 0.0
    @State private var burstWobbleOffset: CGFloat = 0.0
    @State private var isCelebrationRunning = false
    @State private var isFlameLitInCelebration = false
    @State private var celebrationTask: Task<Void, Never>?
    @State private var frozenOverride: Bool?
    @State private var calendarLearnedOverride: Bool?
    @State private var calendarFrozenOverride: Bool?
    @State private var rescuedDayOverrideKey: String?
    @State private var calendarRescuedOverride: Bool?
    @State private var actionDayKey: String?
    @State private var dailyWordCounts: [String: Int] = [:]
    @ObservedObject private var weather = OmniWeather.shared

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    private var isExtra: Bool {
        interfaceMode == .extraordinary
    }

    private var streakForDisplay: Int {
        freezeManager.currentStreak
    }

    private var isVisualFlameLit: Bool {
        isCelebrationRunning ? isFlameLitInCelebration : isLearnedToday
    }

    private var isLearnedToday: Bool {
        freezeManager.isLearnedToday
    }

    private var isFrozenToday: Bool {
        if let frozenOverride { return frozenOverride }
        return freezeManager.isFrozenToday && !isVisualFlameLit
    }

    private var calendarActivityLogs: [String: Bool] {
        var logs = activityLogs
        if freezeManager.isLearnedToday { logs[StreakClock.dayKey()] = true }
        if let actionDayKey, let calendarLearnedOverride { logs[actionDayKey] = calendarLearnedOverride }
        return logs
    }

    private var frozenDatesForCalendar: Set<String> {
        var dates = freezeManager.frozenDates
        if let actionDayKey, let calendarFrozenOverride {
            if calendarFrozenOverride { dates.insert(actionDayKey) } else { dates.remove(actionDayKey) }
        }
        return dates
    }

    private var rescuedDatesForCalendar: Set<String> {
        var dates = freezeManager.rescuedDates
        if let rescuedDayOverrideKey, let calendarRescuedOverride {
            if calendarRescuedOverride { dates.insert(rescuedDayOverrideKey) }
            else { dates.remove(rescuedDayOverrideKey) }
        }
        return dates
    }

    private var groupedVocabs: [String: [Vocabulary]] {
        Vocabulary.groupedByTopic(storeVocabs)
    }

    private var sortedTopics: [String] {
        groupedVocabs.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if v2 {
                        v2Page
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                header
                                VStack(spacing: AppSpacing.cardGap) {
                                    streakCard
                                    streakEnergyCard
                                    calendarCard
                                    discoveryCard
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 32)
                        }
                        .refreshable { await loadData() }
                    }
                }
                .background {
                    if v2 {
                        PixelSkyBackground()
                    } else if isExtra {
                        AuroraBackdrop()
                    } else {
                        Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                    }
                }
                .omniStatusBarBackdrop()
                .omniTabRoot(.streak)
                .toolbar(.hidden, for: .navigationBar)
                .task { await loadData() }
                .alert("Thông báo", isPresented: $showAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(alertMessage)
                }
                .sheet(isPresented: $showExtraUpgradeSheet) {
                    ExtraordinaryUpgradeSheet(interfaceModeRaw: $interfaceModeRaw)
                }
                .navigationDestination(isPresented: $showDailyStats) {
                    DailyLearningStatsPlaceholderView(date: selectedActivityDate)
                }
            }

            if showNotifications {
                NavigationStack {
                    NotificationView(onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            showNotifications = false
                        }
                    })
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .leading),
                    removal: .move(edge: .leading)
                ))
                .zIndex(200)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.width < -60 && abs(value.translation.height) < 80 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    showNotifications = false
                                }
                            }
                        }
                )
            }
        }
        .onChange(of: showNotifications) { _, isShowing in
            if !isShowing {
                Task { await fetchNotifications() }
            }
        }
        .onChange(of: streakForDisplay) { _, _ in
            OmniIconCatalog.shared.checkAndUnlockStreakIcons(userId: AuthManager.shared.currentUser?.id.uuidString)
        }
        .onAppear { playPendingStreakAction() }
        .onDisappear { cancelStreakAnimation() }
        .onReceive(NotificationCenter.default.publisher(for: .returnToHomeAfterLearning)) { _ in
            playPendingStreakAction()
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToHomeTab)) { _ in
            playPendingStreakAction()
        }
    }

    private func playPendingStreakAction() {
        // in the new interface the day's first lesson is lit on its own full screen, not here
        guard let request = StreakActionPresenter.shared.consume(leaving: v2 ? [.learning] : []) else { return }
        cancelStreakAnimation()
        if let date = StreakClock.parseDay(request.rescuedDayKey ?? request.dayKey) { selectedMonth = date }
        playStreakAction(request)
    }

    private func cancelStreakAnimation() {
        celebrationTask?.cancel()
        celebrationTask = nil
        isCelebrationRunning = false
        animatedStreakNumber = nil
        animatedFlameDays = nil
        animatedEnergyProgress = nil
        animatedMilestoneStage = nil
        celebrationFlameAsset = nil
        burstFlameAsset = nil
        isFlameBursting = false
        isTargetUnlocked = false
        frozenOverride = nil
        calendarLearnedOverride = nil
        calendarFrozenOverride = nil
        rescuedDayOverrideKey = nil
        calendarRescuedOverride = nil
        actionDayKey = nil
    }

    private var header: some View {
        HStack {
            // Tạm thời tắt chức năng bấm vô icon chữ Ditandnary / Extraordinary mở thông báo
            HStack(alignment: .top, spacing: 6) {
                Image(interfaceMode.wordmarkAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(height: isExtra ? 30 : 43, alignment: .leading)
                    .accessibilityLabel(interfaceMode.title)

                if hasUnreadNotifications {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(y: 2)
                }
            }
            /*
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    showNotifications = true
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(interfaceMode.wordmarkAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(height: isExtra ? 30 : 43, alignment: .leading)
                        .accessibilityLabel(interfaceMode.title)

                    if hasUnreadNotifications {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .offset(y: 2)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mở trang thông báo")
            */

            Spacer(minLength: 12)
        }
        .padding(.horizontal)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Streak tab (v2): fixed page with the streak card and the calendar heatmap

    /// The whole page fits the screen: title, streak card, calendar, no scrolling.
    /// Like Learning, My Omni and Setting it sits on the still header sky; only Home shows the live one.
    private var v2Page: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmniPageTitle("Streak")
                .padding(.horizontal)
            v2StreakCard
            v2CalendarCard
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var v2Flame: PixelFlame { PixelFlame(days: visualFlameDays) }

    private var v2Ink: Color {
        if isFrozenToday && !isVisualFlameLit { return Color(hex: 0x1AA7C4) }
        guard isVisualFlameLit && (displayedStreakNumber > 0 || isCelebrationRunning) else { return PixelFlame.unlit.ink(night: palette.night) }
        return PixelFlame(days: max(1, displayedStreakNumber)).ink(night: palette.night)
    }

    private var v2StatusText: String {
        if isFrozenToday { return streakFootnote.text }
        let days = displayedStreakNumber
        guard isVisualFlameLit, days > 0 else { return calculateFootnote(for: days, isLearned: false).text }
        if let next = [10, 30, 100, 200, 300].first(where: { $0 > days }) {
            return "Giữ chuỗi thành công! Còn \(next - days) ngày tới lửa \(next) ngày"
        }
        return "Giữ chuỗi thành công! Huyền thoại \(days) ngày rực sáng"
    }

    private var v2StreakCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            OmniSectionLabel("Chuỗi học tập")
            HStack(alignment: .center, spacing: 8) {
                // Grow the digits down toward the caption, keeping both beside the larger flame.
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(displayedStreakNumber))
                        .font(.omniDisplay(128, weight: 800))
                        .foregroundStyle(v2Ink)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 104, alignment: .center)
                        .offset(y: v2NumberOffset)
                    Text("ngày streak!")
                        .font(.omniDisplay(22, weight: 800))
                        .foregroundStyle(v2Ink)
                        .frame(height: 20)
                        .offset(y: v2CaptionOffset)
                }
                .frame(height: 124)
                Spacer(minLength: 8)
                v2FlameEmblem
            }
            .frame(height: 144)
            // a hairline between the streak and its note
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
            Text(v2StatusText)
                .font(.omniBody(12.5, weight: 600))
                .foregroundStyle(v2Ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: 0x1AA7C4).opacity(0.8), lineWidth: isFrozenToday ? 1.8 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 50, pressing: { pressing in
            if pressing { handleFlameTouchDown() } else { handleFlameTouchUp() }
        }, perform: { handleFlameLongPressTriggered() })
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-streak-card")
    }

    // Baloo's line box is taller than its digits; bring the visible digits and caption together.
    private var v2NumberOffset: CGFloat { -14 }
    private var v2CaptionOffset: CGFloat { -3 }

    private var v2FlameEmblem: some View {
        let lit = isVisualFlameLit && visualFlameDays > 0
        // the grey outline until today's lesson lights it; the flame plays its own lighting effect
        return PixelFlameImage(flame: lit ? v2Flame : .unlit, height: 144)
            .opacity(lit ? 1 : (isFrozenToday ? 0.75 : 0.65))
            .overlay(alignment: .topTrailing) {
                if isFrozenToday && !lit {
                    PixelIcon("snow", size: 22).offset(x: 8, y: -4)
                }
            }
            .scaleEffect((1.0 + min(flameTapEnergy * 0.06, 0.3) + (isFlameHeld ? 0.14 : 0)) * (isFlameBursting ? 1.3 : 1.0), anchor: .bottom)
            .offset(x: isFlameHeld ? (flameFlickerPhase ? 3.0 : -3.0) : 0)
            .rotationEffect(.degrees(isFlameHeld ? (flameFlickerPhase ? 4 : -4) : 0), anchor: .bottom)
            .animation(isFlameHeld ? .easeInOut(duration: 0.075) : .spring(response: 0.30, dampingFraction: 0.70), value: flameFlickerPhase)
            .animation(.spring(response: 0.26, dampingFraction: 0.60), value: flameTapEnergy)
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: isFlameHeld)
            .animation(.spring(response: 0.35, dampingFraction: 0.52), value: isFlameBursting)
            .padding(.trailing, 6)
    }

    private var v2CalendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                OmniSectionLabel("Lịch học tập")
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    Button { shiftMonth(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy)).padding(.horizontal, 4)
                    }
                    .accessibilityLabel("Tháng trước")
                    Text(v2MonthTitle(selectedMonth))
                        .font(.omniBody(14, weight: 700))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Button { shiftMonth(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).padding(.horizontal, 4)
                    }
                    .accessibilityLabel("Tháng sau")
                }
                .foregroundStyle(palette.muted)
            }
            OmniHeatmapCalendar(
                month: selectedMonth,
                wordCounts: dailyWordCounts,
                learnedDays: calendarActivityLogs,
                frozenDays: frozenDatesForCalendar,
                rescuedDays: rescuedDatesForCalendar,
                today: Date()
            ) { date in
                selectedActivityDate = date
                showDailyStats = true
            }
            .padding(.top, 6)
            OmniHeatmapLegend()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(cardBackground)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-calendar-card")
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) ?? selectedMonth }
    }

    private func v2MonthTitle(_ date: Date) -> String {
        let c = StreakClock.calendar.dateComponents([.month, .year], from: date)
        return "Tháng \(c.month ?? 1), \(c.year ?? 2026)"
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: "Chào buổi sáng"
        case 11..<13: "Chào buổi trưa"
        case 13..<18: "Chào buổi chiều"
        default: "Chào buổi tối"
        }
    }

    /// Main text colour for both interfaces.
    private var ink: Color { v2 ? palette.text : (isExtra ? .white : .black) }
    private var subInk: Color { v2 ? palette.muted : (isExtra ? Color.white.opacity(0.72) : Color.black.opacity(0.55)) }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if v2 {
                OmniSectionLabel("Chuỗi học tập")
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
            HStack(alignment: .center, spacing: 14) {
                // Cụm chữ bên trái: Số ở trên, "ngày streak!" ở dưới, màu theo ngọn lửa
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(displayedStreakNumber))
                        .font(v2 ? .omniDisplay(58, weight: 800) : .system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(streakTextColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("ngày streak!")
                        .font(v2 ? .omniDisplay(20, weight: 800) : .title3.weight(.bold))
                        .foregroundStyle(streakTextColor)
                }

                Spacer(minLength: 8)

                // Bên phải: Ngọn lửa to hơn, nảy khi bấm, rung & to lên khi nhấn giữ
                streakFlameEmblem
            }
            .padding(.horizontal, 20)
            .padding(.top, v2 ? 4 : 16)
            .padding(.bottom, 12)

            if v2 {
                energyBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }

            // Đường kẻ ngang ở dưới
            Divider()
                .background(isExtra ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .padding(.horizontal, 20)

            // Chú thích dưới dấu gạch: ngắn gọn, 1 dòng không bị xuống dòng, cùng màu với "<Số> ngày streak!"
            HStack(spacing: 7) {
                Image(systemName: displayedFootnote.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(displayedFootnote.color)

                Text(displayedFootnote.text)
                    .font(v2 ? .omniBody(12.5, weight: 600) : .caption.weight(.medium))
                    .foregroundStyle(displayedFootnote.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.85), Color.white.opacity(0.9), Color.cyan.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFrozenToday ? 1.8 : 0
                )
        )
        .shadow(
            color: isFrozenToday ? Color.cyan.opacity(0.35) : Color.clear,
            radius: 10,
            y: 2
        )
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onLongPressGesture(
            minimumDuration: 0.25,
            maximumDistance: 50,
            pressing: { isPressing in
                if isPressing {
                    handleFlameTouchDown()
                } else {
                    handleFlameTouchUp()
                }
            },
            perform: {
                handleFlameLongPressTriggered()
            }
        )
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-streak-card")
    }

    private var streakEnergyCard: some View {
        energyBar
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(cardBackground)
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-energy-card")
    }

    private var energyBar: some View {
        let podDiameter: CGFloat = v2 ? 32 : 36
        let dark = v2 ? palette.night : isExtra

        return ZStack(alignment: .leading) {
            // 1. Rãnh thanh năng lượng liền từ mốc trái tới mốc phải, chiều cao bằng đường kính 2 mốc
            Capsule()
                .fill(
                    dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isFrozenToday
                                ? Color.cyan.opacity(0.45)
                                : (dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)),
                            lineWidth: isFrozenToday ? 1.5 : 1
                        )
                )
                .frame(height: podDiameter)

            // 2. Thanh năng lượng liền (fill liền không chia vạch, màu tương tự streak)
            GeometryReader { proxy in
                let totalWidth = proxy.size.width
                let fillWidth = max(podDiameter, totalWidth * displayedEnergyProgress)

                Capsule()
                    .fill(energyFillGradient)
                    .frame(width: fillWidth, height: podDiameter)
                    .shadow(
                        color: energyGlowColor,
                        radius: 6,
                        x: 0,
                        y: 0
                    )
            }
            .frame(height: podDiameter)
            .clipShape(Capsule())

            // 3. Hai hình tròn cột mốc đặt ở 2 đầu thanh năng lượng (bỏ số ở 2 mốc)
            HStack {
                // Mốc bắt đầu (bên trái)
                ZStack {
                    Circle()
                        .fill(leftPodBackground)
                        .frame(width: podDiameter, height: podDiameter)
                        .overlay(
                            Circle()
                                .stroke(leftPodBorder, lineWidth: 1.5)
                        )

                    Image(activeMilestoneStage.startFlameAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .grayscale(isVisualFlameLit ? 0.0 : 0.92)
                        .opacity(isVisualFlameLit ? 1.0 : 0.45)

                    if isFrozenToday {
                        Image(systemName: "snowflake")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.cyan)
                            .offset(x: 8, y: -8)
                    }
                }

                Spacer()

                // Mốc kết thúc (bên phải - ngọn lửa 2 tia mờ, không ổ khoá)
                ZStack {
                    Circle()
                        .fill(
                            dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.04)
                        )
                        .frame(width: podDiameter, height: podDiameter)
                        .overlay(
                            Circle()
                                .stroke(rightPodBorder, lineWidth: 1.5)
                        )

                    Image(activeMilestoneStage.targetFlameAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .blur(radius: isTargetUnlocked ? 0 : 3.0)
                        .opacity(isTargetUnlocked ? 1.0 : 0.38)
                        .animation(.easeInOut(duration: 0.40), value: isTargetUnlocked)
                }
            }
        }
        .frame(height: podDiameter)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Group {
                        if v2 {
                            OmniSectionLabel("Lịch học tập")
                        } else {
                            Text("Lịch học tập")
                                .font(AppTypography.cardTitle)
                                .foregroundStyle(ink)
                        }
                    }
                    .frame(width: proxy.size.width * 0.5, alignment: .leading)

                    HStack(spacing: isExtra ? 6 : 10) {
                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(v2 ? palette.muted : (isExtra ? Color.white.opacity(0.8) : Color.black))
                        }

                        Text(monthYearString(selectedMonth))
                            .font(v2 ? .omniBody(14, weight: 700) : .subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(isExtra ? 0.62 : 0.8)
                            .frame(maxWidth: .infinity)

                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(v2 ? palette.muted : (isExtra ? Color.white.opacity(0.8) : Color.black))
                        }
                    }
                    .frame(width: proxy.size.width * 0.5)
                }
            }
            .frame(height: 32)
            CustomMonthCalendar(
                month: selectedMonth,
                activityLogs: calendarActivityLogs,
                frozenDates: frozenDatesForCalendar,
                rescuedDates: rescuedDatesForCalendar,
                isExtra: isExtra
            ) { date in
                selectedActivityDate = date
                showDailyStats = true
            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-calendar-card")
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if v2 {
                    OmniSectionLabel("Khám phá")
                } else {
                    Text("Khám phá")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(ink)
                }


                Spacer()

            }

            NavigationLink {
                VocabularyExploreView(
                    topics: sortedTopics,
                    groupedVocabs: groupedVocabs,
                    downloadedKeysByTopic: downloadedKeysByTopic,
                    isDownloading: $isDownloading,
                    downloadTopic: { vocabs, topic in
                        Task { await downloadTopic(vocabs, topicName: topic) }
                    }
                )
            } label: {
                folderRow(
                    title: "Khám phá Từ vựng",
                    subtitle: "Các chủ đề và bộ từ",
                    icon: "books.vertical.fill",
                    pixelIcon: "book",
                    tint: isExtra ? ExtraAuroraPalette.ice : Color(red: 0.0, green: 0.48, blue: 1.0)
                )
            }
            .accessibilityIdentifier("home-explore-vocabulary")

            Divider()
                .overlay(v2 ? palette.line : (isExtra ? Color.white.opacity(0.12) : Color.clear))

            NavigationLink {
                ListeningExploreView(
                    catalog: listeningCatalog,
                    downloadedLessonIds: listeningLibraryLessonIds,
                    refreshLibrary: { Task { await fetchListeningLibrary() } }
                )
            } label: {
                folderRow(
                    title: "Khám phá Bài luyện nghe",
                    subtitle: "Các seri bài luyện nghe",
                    icon: "headphones",
                    pixelIcon: "head",
                    tint: AppTheme(isExtra: isExtra).accent
                )
            }
            .accessibilityIdentifier("home-explore-listening")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-discovery-card")
    }

    @ViewBuilder
    private var cardBackground: some View {
        if v2 {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.card)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.line, lineWidth: 1))
                .omniCardShadow(radius: 24)
        } else {
            AppSurfaceBackground(kind: .card, isExtra: isExtra)
        }
    }

    private func folderRow(title: String, subtitle: String, icon: String, pixelIcon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            if v2 {
                PixelIcon(pixelIcon, size: 26)
                    .frame(width: 44, height: 44)
                    .background(palette.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            } else {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isExtra ? Color.white : Color(red: 0.0, green: 0.48, blue: 1.0))
                .frame(width: 44, height: 44)
                .background {
                    if isExtra {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(
                                LinearGradient(
                                    colors: [ExtraAuroraPalette.electricBlue.opacity(0.76), ExtraAuroraPalette.violet.opacity(0.64)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.12))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(v2 ? .omniBody(16, weight: 700) : .headline)
                    .foregroundStyle(ink)
                Text(subtitle)
                    .font(v2 ? .omniBody(12.5, weight: 500) : .caption)
                    .foregroundStyle(subInk)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(v2 ? palette.muted : (isExtra ? Color.white.opacity(0.5) : Color.black.opacity(0.35)))
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Flame Milestone Progress & Continuous Energy
    private struct FlameMilestoneStage: Equatable {
        let startDays: Int
        let targetDays: Int
        let totalSegments: Int
        let startFlameAsset: String
        let targetFlameAsset: String
    }

    private var activeMilestoneStage: FlameMilestoneStage {
        animatedMilestoneStage ?? activeMilestoneStage(for: streakForDisplay)
    }

    private func activeMilestoneStage(for streak: Int) -> FlameMilestoneStage {
        if streak < 10 {
            return FlameMilestoneStage(
                startDays: 1, targetDays: 10, totalSegments: 10,
                startFlameAsset: "StreakFlame1", targetFlameAsset: "StreakFlame2"
            )
        } else if streak < 30 {
            return FlameMilestoneStage(
                startDays: 10, targetDays: 30, totalSegments: 21,
                startFlameAsset: "StreakFlame2", targetFlameAsset: "StreakFlame30"
            )
        } else if streak < 100 {
            return FlameMilestoneStage(
                startDays: 30, targetDays: 100, totalSegments: 71,
                startFlameAsset: "StreakFlame30",
                targetFlameAsset: isExtra ? "StreakFlame32" : "StreakFlame31"
            )
        } else if streak < 200 {
            return FlameMilestoneStage(
                startDays: 100, targetDays: 200, totalSegments: 101,
                startFlameAsset: isExtra ? "StreakFlame32" : "StreakFlame31",
                targetFlameAsset: isExtra ? "StreakFlame42" : "StreakFlame41"
            )
        } else if streak < 300 {
            return FlameMilestoneStage(
                startDays: 200, targetDays: 300, totalSegments: 101,
                startFlameAsset: isExtra ? "StreakFlame42" : "StreakFlame41",
                targetFlameAsset: isExtra ? "StreakFlame42" : "StreakFlame41"
            )
        } else {
            return FlameMilestoneStage(
                startDays: 300, targetDays: 365, totalSegments: 66,
                startFlameAsset: isExtra ? "StreakFlame42" : "StreakFlame41",
                targetFlameAsset: isExtra ? "StreakFlame42" : "StreakFlame41"
            )
        }
    }

    private var energyFillGradient: LinearGradient {
        let isLearned = isVisualFlameLit
        let streak = displayedStreakNumber

        guard isLearned && (streak > 0 || isCelebrationRunning) else {
            return LinearGradient(
                colors: isExtra
                    ? [Color.white.opacity(0.18), Color.white.opacity(0.08)]
                    : [Color.gray.opacity(0.32), Color.gray.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        if isExtra {
            if streak < 100 {
                // 1 - 100 Extra dùng dãi màu vàng gold sang trọng
                return LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.92, blue: 0.52),
                        Color(red: 0.98, green: 0.78, blue: 0.22),
                        Color(red: 0.88, green: 0.58, blue: 0.12)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                // 100+ Extra dùng màu xanh tím Aurora
                return LinearGradient(
                    colors: [
                        ExtraAuroraPalette.electricBlue,
                        ExtraAuroraPalette.violet,
                        ExtraAuroraPalette.ice
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        } else {
            if streak < 100 {
                // 1 - 100 Ditandnary dùng tông cam/cam đỏ
                return LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.68, blue: 0.16),
                        Color(red: 1.00, green: 0.42, blue: 0.10),
                        Color(red: 0.95, green: 0.22, blue: 0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                // 100+ Ditandnay dãi màu xanh băng/xanh dương
                return LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.88, blue: 1.00),
                        Color(red: 0.00, green: 0.65, blue: 1.00),
                        Color(red: 0.05, green: 0.45, blue: 0.98)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private var energyGlowColor: Color {
        let isLearned = isVisualFlameLit
        let streak = displayedStreakNumber

        guard isLearned && (streak > 0 || isCelebrationRunning) else {
            return isFrozenToday ? Color.cyan.opacity(0.20) : Color.clear
        }

        if isExtra {
            if streak < 100 {
                return Color(red: 1.0, green: 0.80, blue: 0.20).opacity(0.50)
            } else {
                return ExtraAuroraPalette.electricBlue.opacity(0.45)
            }
        } else {
            if streak < 100 {
                return Color(red: 1.0, green: 0.40, blue: 0.10).opacity(0.45)
            } else {
                return Color(red: 0.0, green: 0.60, blue: 1.0).opacity(0.40)
            }
        }
    }

    private var leftPodBackground: Color {
        let isLearned = isVisualFlameLit
        let streak = displayedStreakNumber

        guard isLearned && (streak > 0 || isCelebrationRunning) else {
            return isFrozenToday
                ? Color.cyan.opacity(isExtra ? 0.16 : 0.08)
                : (isExtra ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        }

        if isExtra {
            if streak < 100 {
                return Color(red: 0.38, green: 0.30, blue: 0.10).opacity(0.85)
            } else {
                return Color(red: 0.20, green: 0.16, blue: 0.50).opacity(0.85)
            }
        } else {
            if streak < 100 {
                return Color(red: 1.00, green: 0.45, blue: 0.10).opacity(0.18)
            } else {
                return Color(red: 0.05, green: 0.45, blue: 0.95).opacity(0.18)
            }
        }
    }

    private var leftPodBorder: Color {
        let isLearned = isVisualFlameLit
        let streak = displayedStreakNumber

        guard isLearned && (streak > 0 || isCelebrationRunning) else {
            return isFrozenToday
                ? Color.cyan.opacity(0.70)
                : (isExtra ? Color.white.opacity(0.15) : Color.black.opacity(0.10))
        }

        if isExtra {
            if streak < 100 {
                return Color(red: 1.0, green: 0.82, blue: 0.28).opacity(0.65)
            } else {
                return ExtraAuroraPalette.ice.opacity(0.60)
            }
        } else {
            if streak < 100 {
                return Color.orange.opacity(0.55)
            } else {
                return Color(red: 0.05, green: 0.45, blue: 0.95).opacity(0.45)
            }
        }
    }

    private var rightPodBorder: Color {
        if isTargetUnlocked {
            let streak = displayedStreakNumber
            if isExtra {
                return streak < 100 ? Color(red: 1.0, green: 0.82, blue: 0.28) : ExtraAuroraPalette.ice
            } else {
                return streak < 100 ? Color.orange : Color.blue
            }
        } else {
            return isExtra ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
        }
    }

    private var displayedEnergyProgress: CGFloat {
        if let animated = animatedEnergyProgress {
            return animated
        }
        return progressForStreak(streakForDisplay)
    }

    private func progressForStreak(_ streak: Int) -> CGFloat {
        if streak <= 0 { return 0 }
        let stage = activeMilestoneStage(for: streak)
        if streak < 10 {
            return min(1.0, CGFloat(streak) / 10.0)
        }
        let total = CGFloat(stage.totalSegments)
        let filled = CGFloat(streak - stage.startDays + 1)
        return min(1.0, max(0.0, filled / total))
    }

    private var displayedStreakNumber: Int {
        animatedStreakNumber ?? streakForDisplay
    }

    private var displayedFootnote: StreakFootnote {
        if let customText = animatedFootnoteText,
           let customIcon = animatedFootnoteIcon,
           let customColor = animatedFootnoteColor {
            return StreakFootnote(icon: customIcon, text: customText, color: customColor)
        }
        return streakFootnote
    }

    private func flameAsset(for streak: Int) -> String? {
        guard streak > 0 else { return nil }
        switch streak {
        case 1...9:
            return "StreakFlame1"
        case 10...29:
            return "StreakFlame2"
        case 30...99:
            return "StreakFlame30"
        case 100...199:
            return isExtra ? "StreakFlame32" : "StreakFlame31"
        default:
            return isExtra ? "StreakFlame42" : "StreakFlame41"
        }
    }

    private func playStreakAction(_ request: StreakActionPresenter.Request) {
        isCelebrationRunning = true
        isFlameLitInCelebration = false
        animatedStreakNumber = request.previousDays
        animatedFlameDays = request.previousDays
        animatedEnergyProgress = progressForStreak(request.previousDays)
        animatedMilestoneStage = activeMilestoneStage(for: request.previousDays)
        celebrationFlameAsset = flameAsset(for: request.previousDays)
        actionDayKey = request.dayKey
        rescuedDayOverrideKey = request.rescuedDayKey
        calendarRescuedOverride = request.rescuedDayKey == nil ? nil : false
        calendarLearnedOverride = false
        calendarFrozenOverride = request.wasFrozen
        frozenOverride = request.wasFrozen
        celebrationTask = Task { @MainActor in
            do {
                switch request.kind {
                case .freeze:
                    try await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeInOut(duration: 0.65)) { frozenOverride = true }
                    try await Task.sleep(for: .milliseconds(850))
                    withAnimation { calendarFrozenOverride = true }
                case .restore:
                    try await Task.sleep(for: .milliseconds(250))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        animatedStreakNumber = request.newDays
                        animatedFlameDays = request.newDays
                        animatedEnergyProgress = progressForStreak(request.newDays)
                        animatedMilestoneStage = activeMilestoneStage(for: request.newDays)
                        celebrationFlameAsset = flameAsset(for: request.newDays)
                    }
                    try await Task.sleep(for: .milliseconds(550))
                    withAnimation(.easeInOut(duration: 0.45)) { calendarRescuedOverride = true }
                case .learning:
                    if request.wasFrozen {
                        withAnimation(.easeInOut(duration: 0.45)) { frozenOverride = false }
                        try await Task.sleep(for: .milliseconds(450))
                    }
                    withAnimation(.easeInOut(duration: 0.35)) { isFlameLitInCelebration = true }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    try await Task.sleep(for: .milliseconds(400))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { animatedStreakNumber = request.newDays }
                    let evolves = [10, 30, 100, 200, 300].contains(request.newDays)
                    try await Task.sleep(for: .milliseconds(500))
                    if evolves {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.52)) {
                            isFlameBursting = true
                            animatedFlameDays = request.newDays
                            burstFlameAsset = flameAsset(for: request.newDays)
                            celebrationFlameAsset = flameAsset(for: request.newDays)
                        }
                        try await Task.sleep(for: .milliseconds(800))
                        withAnimation { isFlameBursting = false; burstFlameAsset = nil }
                    }
                    withAnimation(.easeOut(duration: 0.6)) {
                        animatedEnergyProgress = evolves ? 1 : progressForStreak(request.newDays)
                        isTargetUnlocked = evolves
                    }
                    try await Task.sleep(for: .milliseconds(750))
                    if evolves {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            animatedMilestoneStage = activeMilestoneStage(for: request.newDays)
                            animatedEnergyProgress = progressForStreak(request.newDays)
                            isTargetUnlocked = false
                        }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    withAnimation { calendarLearnedOverride = true; calendarFrozenOverride = false }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                try await Task.sleep(for: .milliseconds(600))
                cancelStreakAnimation()
            } catch { }
        }
    }

    private struct StreakFootnote {
        let icon: String
        let text: String
        let color: Color
    }

    private func calculateFootnote(for streak: Int, isLearned: Bool) -> StreakFootnote {
        let noteColor = streakTextColor

        if !isLearned {
            if streak < 5 {
                return StreakFootnote(
                    icon: "flame",
                    text: "Hãy học ít nhất một bài để thắp lửa lên",
                    color: noteColor
                )
            } else if streak < 30 {
                return StreakFootnote(
                    icon: "flame",
                    text: "Chuỗi \(streak) ngày đang chờ bạn! Hãy học ngay để thắp lửa lên",
                    color: noteColor
                )
            } else if streak < 100 {
                return StreakFootnote(
                    icon: "flame.circle",
                    text: "Ngọn lửa \(streak) ngày đang ngủ say... Thắp lửa ngay kẻo tắt nhé!",
                    color: noteColor
                )
            } else {
                return StreakFootnote(
                    icon: "bolt.heart.fill",
                    text: "Giữ vững chuỗi \(streak) ngày! Hãy học một bài để ngọn lửa bùng cháy",
                    color: noteColor
                )
            }
        } else {
            if streak < 7 {
                return StreakFootnote(
                    icon: "checkmark.circle.fill",
                    text: "Giữ chuỗi thành công! Bạn đã thắp sáng ngọn lửa hôm nay",
                    color: noteColor
                )
            } else if streak < 30 {
                return StreakFootnote(
                    icon: "checkmark.seal.fill",
                    text: "Giữ chuỗi thành công! Tiếp tục phát huy nhé",
                    color: noteColor
                )
            } else if streak < 100 {
                return StreakFootnote(
                    icon: "bolt.fill",
                    text: "Giữ chuỗi thành công! \(streak) ngày kiên trì phi thường",
                    color: noteColor
                )
            } else if streak < 300 {
                return StreakFootnote(
                    icon: "crown.fill",
                    text: "Giữ chuỗi thành công! Chuỗi \(streak) ngày rực sáng đẳng cấp",
                    color: noteColor
                )
            } else {
                return StreakFootnote(
                    icon: "sparkles",
                    text: "Giữ chuỗi thành công! Huyền thoại \(streak) ngày với ngọn lửa lấp lánh",
                    color: noteColor
                )
            }
        }
    }

    private var streakFootnote: StreakFootnote {
        if isFrozenToday {
            return StreakFootnote(
                icon: "snowflake",
                text: "Đã đóng băng bảo vệ chuỗi hôm nay",
                color: isExtra ? ExtraAuroraPalette.ice : Color(red: 0.0, green: 0.70, blue: 0.90)
            )
        }
        return calculateFootnote(for: streakForDisplay, isLearned: isVisualFlameLit)
    }

    private var streakTextColor: Color {
        let isLearned = isVisualFlameLit
        let streak = displayedStreakNumber

        guard isLearned && (streak > 0 || isCelebrationRunning) else {
            // Lửa tàn (chưa học hôm nay) -> màu xám cho cả Ditan và Extra (kể cả khi đóng băng)
            if v2 { return palette.muted }
            return isExtra ? Color.white.opacity(0.42) : Color.gray
        }

        if isExtra {
            // Giao diện Extraordinary
            if streak < 100 {
                // 1 - 100 Extra dùng dãi màu vàng gold sang trọng (đậm hơn trên nền sáng của giao diện mới)
                if v2 && !palette.night { return Color(hex: 0xC98A0E) }
                return Color(red: 1.0, green: 0.82, blue: 0.28)
            } else {
                // 100+ Extra dùng màu xanh tím Aurora
                return Color(red: 0.64, green: 0.52, blue: 1.0)
            }
        } else {
            // Giao diện Ditandnary
            if streak < 100 {
                // 1 - 100 Ditandnary dùng tông cam/cam đỏ
                return Color(red: 1.0, green: 0.44, blue: 0.10)
            } else {
                // 100+ Ditandnay dãi màu xanh băng/xanh dương
                return Color(red: 0.0, green: 0.58, blue: 1.0)
            }
        }
    }

    private var visualFlameDays: Int { animatedFlameDays ?? streakForDisplay }

    private var flameAssetName: String? {
        guard visualFlameDays > 0 else { return nil }

        switch visualFlameDays {
        case 1...9:
            return "StreakFlame1"
        case 10...29:
            return "StreakFlame2"
        case 30...99:
            return "StreakFlame30"
        case 100...199:
            return isExtra ? "StreakFlame32" : "StreakFlame31"
        default:
            return isExtra ? "StreakFlame42" : "StreakFlame41"
        }
    }

    private var flameBaseSize: CGFloat {
        switch visualFlameDays {
        case 1...9:
            return 114
        case 10...29:
            return 125
        case 30...99:
            return 135
        case 100...199:
            return 146
        case 200...299:
            return 153
        case 300...:
            return 161
        default:
            return 110
        }
    }

    private var flameTone: Color {
        if isExtra {
            if visualFlameDays < 100 {
                return Color(red: 1.0, green: 0.82, blue: 0.28) // Vàng gold
            } else {
                return Color(red: 0.64, green: 0.52, blue: 1.0) // Xanh tím
            }
        } else {
            switch visualFlameDays {
            case 1...9:
                return Color(red: 1.0, green: 0.60, blue: 0.10) // Cam vàng
            case 10...29:
                return Color(red: 1.0, green: 0.44, blue: 0.10) // Cam
            case 30...99:
                return Color(red: 1.0, green: 0.28, blue: 0.10) // Cam đỏ
            case 100...:
                return Color(red: 0.0, green: 0.55, blue: 1.0) // Xanh băng
            default:
                return Color.gray
            }
        }
    }

    private var flameCenteringOffset: CGFloat {
        switch visualFlameDays {
        case 1...9:
            return -2
        case 10...29:
            return 1
        default:
            return 0
        }
    }

    // Bệ đỡ / vệt bóng hình elip dưới chân ngọn lửa (nhỏ gọn vừa vặn với chân ngọn lửa)

    private var streakFlameEmblem: some View {
        ZStack(alignment: .center) {
            // Ngọn lửa với tương tác mượt mà và dao động lắc lư liên tục nhiều lần khi giữ hoặc biến đổi mốc
            Group {
                if let displayFlame = burstFlameAsset ?? celebrationFlameAsset ?? flameAssetName {
                    Image(displayFlame)
                        .resizable()
                        .scaledToFit()
                        .grayscale(isVisualFlameLit ? 0.0 : 0.92)
                        .opacity(isVisualFlameLit ? 1.0 : (isFrozenToday ? 0.60 : 0.45))
                        .shadow(
                            color: isFrozenToday
                                ? Color.cyan.opacity(0.65)
                                : (isVisualFlameLit
                                    ? (isFlameBursting ? Color.orange : flameTone).opacity(isExtra ? 0.70 : 0.50)
                                    : Color.clear),
                            radius: (isFlameBursting ? 26 : 14) + (isFlameHeld ? 8 : 0),
                            y: 2
                        )
                        .overlay {
                            if (visualFlameDays >= 300 || isFlameBursting) && isVisualFlameLit {
                                goldenSparkles
                            } else if isFrozenToday {
                                Image(systemName: "snowflake")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color.cyan)
                                    .shadow(color: Color.white, radius: 4)
                                    .offset(x: 24, y: -24)
                            }
                        }
                } else {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(isVisualFlameLit ? (isExtra ? Color(red: 1.0, green: 0.82, blue: 0.28) : flameTone) : Color.gray.opacity(0.35))
                }
            }
            .frame(width: flameBaseSize, height: flameBaseSize)
            .scaleEffect((1.0 + min(flameTapEnergy * 0.08, 0.45) + (isFlameHeld ? 0.22 : 0)) * (isFlameBursting ? 1.45 : 1.0))
            .offset(y: flameCenteringOffset - min(flameTapEnergy * 3.5, 18.0) + (isFlameHeld ? -5.0 : 0) + (isFlameBursting ? -14.0 : 0))
            .offset(x: isFlameHeld ? (flameFlickerPhase ? 4.0 : -4.0) : burstWobbleOffset)
            .rotationEffect(.degrees(isFlameHeld ? (flameFlickerPhase ? 5.5 : -5.5) : (isFlameBursting ? burstWobbleAngle : 0)))
            .animation(
                isFlameHeld
                    ? .easeInOut(duration: 0.075)
                    : .spring(response: 0.30, dampingFraction: 0.70),
                value: flameFlickerPhase
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.60), value: flameTapEnergy)
            .animation(.spring(response: 0.32, dampingFraction: 0.65), value: isFlameHeld)
            .animation(.spring(response: 0.35, dampingFraction: 0.52), value: isFlameBursting)
        }
        .frame(width: 130, height: 130)
    }

    private var goldenSparkles: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.79, blue: 0.28))
                .offset(x: -flameBaseSize * 0.36, y: -flameBaseSize * 0.32)

            Image(systemName: "sparkle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.48))
                .offset(x: flameBaseSize * 0.36, y: -flameBaseSize * 0.14)

            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.92))
                .offset(x: flameBaseSize * 0.26, y: flameBaseSize * 0.30)
        }
        .frame(width: flameBaseSize, height: flameBaseSize)
        .opacity(sparklePulse ? 1 : 0.42)
        .scaleEffect(sparklePulse ? 1.16 : 0.74)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                sparklePulse.toggle()
            }
        }
    }

    private func handleFlameTouchDown() {
        flameDecayWorkItem?.cancel()
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.60)) {
            flameTapEnergy = min(flameTapEnergy + 1.0, 5.0)
        }
    }

    private func handleFlameTouchUp() {
        flameFlickerTask?.cancel()
        flameFlickerTask = nil

        withAnimation(.spring(response: 0.30, dampingFraction: 0.70)) {
            isFlameHeld = false
            flameFlickerPhase = false
        }

        flameDecayWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.72)) {
                flameTapEnergy = 0
            }
        }
        flameDecayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func handleFlameLongPressTriggered() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.60)) {
            isFlameHeld = true
        }
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.impactOccurred()

        // Bắt đầu chu trình lắc lư qua lại liên tục nhiều lần trong khi giữ
        flameFlickerTask?.cancel()
        flameFlickerTask = Task {
            var cycle = 0
            while !Task.isCancelled && isFlameHeld {
                try? await Task.sleep(nanoseconds: 75_000_000)
                guard !Task.isCancelled && isFlameHeld else { break }
                await MainActor.run {
                    flameFlickerPhase.toggle()
                    cycle += 1
                    if cycle % 4 == 0 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }

    private func loadData() async {
        async let vocabs: () = fetchStoreVocabs()
        async let downloads: () = fetchDownloadedTopics()
        async let listening: () = fetchListeningCatalog()
        async let listeningLibrary: () = fetchListeningLibrary()
        async let progress: () = fetchProgress()
        async let notifications: () = fetchNotifications()
        _ = await (vocabs, downloads, listening, listeningLibrary, progress, notifications)
    }

    private func fetchStoreVocabs() async {
        guard let fetched = try? await VocabularyRepository.fetchSystemVocabs(adminUserId: adminUserId) else { return }
        storeVocabs = fetched
    }

    private func fetchDownloadedTopics() async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString,
              let fetched = try? await VocabularyRepository.fetchUserVocabs(userId: userID) else { return }
        var result: [String: Set<String>] = [:]
        for vocab in fetched {
            guard let key = vocab.downloadIdentityKey else { continue }
            for topic in vocab.collectionTopics { result[topic.id, default: []].insert(key) }
        }
        downloadedKeysByTopic = result
    }

    private func fetchListeningCatalog() async {
        listeningCatalog = (try? await ListeningRepository.fetchSeriesCatalog()) ?? []
    }

    private func fetchListeningLibrary() async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString,
              let entries = try? await ListeningRepository.fetchUserLessonEntries(userId: userID) else { return }
        listeningLibraryLessonIds = Set(entries.map(\.lesson_id))
    }

    private func fetchProgress() async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString else { return }
        if let stats = try? await UserProgressRepository.refreshStreakState() {
            freezeManager.applyRemoteState(stats)
            OmniIconCatalog.shared.checkAndUnlockStreakIcons(userId: userID)
        }
        if let logs = try? await UserProgressRepository.fetchCompletedActivityLogs(userId: userID) {
            activityLogs = Dictionary(uniqueKeysWithValues: logs.map { ($0.date, $0.completed) })
        }
        if v2 {
            let from = StreakClock.calendar.date(byAdding: .day, value: -400, to: Date()) ?? Date()
            if let counts = try? await UserProgressRepository.fetchDailyWordCounts(from: StreakClock.dayKey(from), to: StreakClock.dayKey()) {
                dailyWordCounts = counts
            }
        }
    }

    private func fetchNotifications() async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString,
              let count = try? await NotificationRepository.fetchUnreadCount(userId: userID) else { return }
        hasUnreadNotifications = count > 0
    }

    private func downloadTopic(_ vocabs: [Vocabulary], topicName: String) async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString else {
            alertMessage = "Vui lòng đăng nhập!"
            showAlert = true
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        let copies = vocabs.map { vocab -> Vocabulary in
            var copy = vocab
            copy.user_id = userID
            copy.created_at = nil
            return copy
        }
        do {
            try await VocabularyRepository.insert(copies)
            if let topicId = copies.first?.topic_id {
                downloadedKeysByTopic[topicId, default: []].formUnion(copies.compactMap(\.downloadIdentityKey))
            }
            alertMessage = "Tải thành công \(Vocabulary.sortedItems(copies).count) từ!"
            showAlert = true
        } catch {
            alertMessage = "Không thể tải bộ từ: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

