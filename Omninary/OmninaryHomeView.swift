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
    @ObservedObject private var streakSimulator = StreakPresentationSimulator.shared
    @State private var showNotifications = false
    @State private var showExtraUpgradeSheet = false
    @State private var isFlameTransforming = false
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

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    private var isExtra: Bool {
        interfaceMode == .extraordinary
    }

    private var streakForDisplay: Int {
        streakSimulator.isActive ? streakSimulator.displayedDays : freezeManager.currentStreak
    }

    private var isVisualFlameLit: Bool {
        if streakSimulator.isActive { return streakSimulator.isFlameLit }
        return isCelebrationRunning ? isFlameLitInCelebration : isLearnedToday
    }

    private var isLearnedToday: Bool {
        if streakSimulator.isActive { return streakSimulator.isFlameLit }
        return freezeManager.isLearnedToday
    }

    private var isFrozenToday: Bool {
        if let frozenOverride { return frozenOverride }
        if streakSimulator.isActive {
            return streakSimulator.winterShieldIsReady && !streakSimulator.isFlameLit
        }
        return freezeManager.isFrozenToday && !isVisualFlameLit
    }

    private var calendarActivityLogs: [String: Bool] {
        var logs = streakSimulator.activityLogs(merging: activityLogs)
        if !streakSimulator.isActive && freezeManager.isLearnedToday { logs[StreakClock.dayKey()] = true }
        if let actionDayKey, let calendarLearnedOverride { logs[actionDayKey] = calendarLearnedOverride }
        return logs
    }

    private var frozenDatesForCalendar: Set<String> {
        var dates = streakSimulator.frozenDates(merging: freezeManager.frozenDates)
        if let actionDayKey, let calendarFrozenOverride {
            if calendarFrozenOverride { dates.insert(actionDayKey) } else { dates.remove(actionDayKey) }
        }
        return dates
    }

    private var rescuedDatesForCalendar: Set<String> {
        var dates = streakSimulator.rescuedDates(merging: freezeManager.rescuedDates)
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
                .background {
                    if isExtra {
                        AuroraBackdrop()
                    } else {
                        Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .refreshable { await loadData() }
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
        .onChange(of: streakForDisplay) { oldValue, newValue in
            guard !streakSimulator.isActive else { return }
            OmniIconCatalog.shared.checkAndUnlockStreakIcons(userId: AuthManager.shared.currentUser?.id.uuidString)
        }
        .onChange(of: streakSimulator.isActive) { _, active in
            if !active { Task { await fetchProgress() } }
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
        if streakSimulator.isActive { selectedMonth = streakSimulator.simulatedNow }
        guard let request = StreakActionPresenter.shared.consume(isSimulation: streakSimulator.isActive) else { return }
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

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                // Cụm chữ bên trái: Số ở trên, "ngày streak!" ở dưới, màu theo ngọn lửa
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(displayedStreakNumber))
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(streakTextColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("ngày streak!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(streakTextColor)
                }

                Spacer(minLength: 8)

                // Bên phải: Ngọn lửa to hơn, nảy khi bấm, rung & to lên khi nhấn giữ
                streakFlameEmblem
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

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
                    .font(.caption.weight(.medium))
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
        let podDiameter: CGFloat = 36

        return ZStack(alignment: .leading) {
            // 1. Rãnh thanh năng lượng liền từ mốc trái tới mốc phải, chiều cao bằng đường kính 2 mốc
            Capsule()
                .fill(
                    isExtra
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isFrozenToday
                                ? Color.cyan.opacity(0.45)
                                : (isExtra ? Color.white.opacity(0.10) : Color.black.opacity(0.06)),
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
                            isExtra
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(cardBackground)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-energy-card")
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.row) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Text("Lịch học tập")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(isExtra ? Color.white : Color.black)
                        .frame(width: proxy.size.width * 0.5, alignment: .leading)

                    HStack(spacing: isExtra ? 6 : 10) {
                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.left")
                                .foregroundStyle(isExtra ? Color.white.opacity(0.8) : Color.black)
                        }

                        Text(monthYearString(selectedMonth))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isExtra ? Color.white : Color.black)
                            .lineLimit(1)
                            .minimumScaleFactor(isExtra ? 0.62 : 0.8)
                            .frame(maxWidth: .infinity)

                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(isExtra ? Color.white.opacity(0.8) : Color.black)
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
                Text("Khám phá")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(isExtra ? Color.white : Color.black)


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
                    tint: isExtra ? ExtraAuroraPalette.ice : Color(red: 0.0, green: 0.48, blue: 1.0)
                )
            }
            .accessibilityIdentifier("home-explore-vocabulary")

            Divider()
                .overlay(isExtra ? Color.white.opacity(0.12) : Color.clear)

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

    private var cardBackground: some View {
        AppSurfaceBackground(kind: .card, isExtra: isExtra)
    }

    private func folderRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isExtra ? Color.white : Color.black)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isExtra ? Color.white.opacity(0.72) : Color.black.opacity(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(isExtra ? Color.white.opacity(0.5) : Color.black.opacity(0.35))
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

    private func triggerBurstWobbleSequence() {
        let wobbleSteps: [(delay: Double, angle: Double, offset: CGFloat)] = [
            (0.00,  8.0,  6.0),
            (0.11, -8.0, -6.0),
            (0.22,  7.0,  5.0),
            (0.33, -7.0, -5.0),
            (0.44,  5.5,  4.0),
            (0.55, -5.5, -4.0),
            (0.66,  4.0,  2.5),
            (0.77, -3.5, -2.5),
            (0.88,  2.0,  1.5),
            (0.99, -1.5, -1.0),
            (1.10,  0.0,  0.0)
        ]

        for step in wobbleSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    burstWobbleAngle = step.angle
                    burstWobbleOffset = step.offset
                }
            }
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
            return isExtra ? Color.white.opacity(0.42) : Color.gray
        }

        if isExtra {
            // Giao diện Extraordinary
            if streak < 100 {
                // 1 - 100 Extra dùng dãi màu vàng gold sang trọng
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
    private var flamePedestal: some View {
        ZStack {
            // Vệt hào quang toả dưới chân (nhỏ gọn vừa vặn)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: isVisualFlameLit
                            ? [
                                flameTone.opacity(isExtra ? 0.60 : 0.45),
                                flameTone.opacity(0)
                            ]
                            : [Color.black.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: flameBaseSize * 0.30
                    )
                )
                .frame(width: flameBaseSize * 0.60, height: flameBaseSize * 0.20)

            // Đĩa bệ đỡ dưới chân
            Ellipse()
                .fill(
                    isVisualFlameLit
                        ? (isExtra
                            ? LinearGradient(colors: [flameTone.opacity(0.40), flameTone.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [flameTone.opacity(0.35), flameTone.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                        : LinearGradient(colors: [Color.gray.opacity(0.20), Color.gray.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                )
                .frame(width: flameBaseSize * 0.46, height: flameBaseSize * 0.12)
                .overlay {
                    Ellipse()
                        .stroke(
                            isVisualFlameLit
                                ? flameTone.opacity(0.40)
                                : Color.gray.opacity(0.15),
                            lineWidth: 1
                        )
                }
        }
        .offset(y: flameBaseSize * 0.42)
    }

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
        guard !streakSimulator.isActive else { return }
        guard let userID = AuthManager.shared.currentUser?.id.uuidString else { return }
        if let stats = try? await UserProgressRepository.refreshStreakState() {
            freezeManager.applyRemoteState(stats)
            // The simulator is presentation-only: it must not trigger any
            // server-side icon unlock while a visual scenario is active.
            if !streakSimulator.isActive {
                OmniIconCatalog.shared.checkAndUnlockStreakIcons(userId: userID)
            }
        }
        if let logs = try? await UserProgressRepository.fetchCompletedActivityLogs(userId: userID) {
            activityLogs = Dictionary(uniqueKeysWithValues: logs.map { ($0.date, $0.completed) })
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.cardGap) {
                    // Header icon & title
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [ExtraAuroraPalette.electricBlue, ExtraAuroraPalette.violet],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: ExtraAuroraPalette.electricBlue.opacity(0.6), radius: 18)

                            Image(systemName: "sparkles")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(spacing: 8) {
                            Text("Omninary Extraordinary")
                                .font(.title.weight(.heavy))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.white, ExtraAuroraPalette.ice],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .multilineTextAlignment(.center)

                            Text("Mở khoá sức mạnh phi thường của Omninary: Học không giới hạn thích ứng cao cấp theo dữ liệu người học, Ưu đãi thưởng điểm Omni, Quyền năng Omnicons tối thượng")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 24)

                    // 2 Bảng so sánh tóm tắt hai phiên bản
                    VStack(spacing: AppSpacing.cardGap) {
                        HStack {
                            Text("SO SÁNH ĐẶC QUYỀN HAI PHIÊN BẢN")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ExtraAuroraPalette.ice)
                                .tracking(1.0)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        // Bảng 1: Ditandnary (Bản tiêu chuẩn - Miễn phí)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "book.closed.fill")
                                        .foregroundStyle(Color.blue)
                                    Text("Ditandnary")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Color.white)
                                }

                                Spacer()

                                Text("Bản tiêu chuẩn • 0đ")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                            }

                            Divider()
                                .overlay(Color.white.opacity(0.12))

                            VStack(alignment: .leading, spacing: 10) {
                                comparisonRow(icon: "clock.fill", text: "Giới hạn 10 lượt học mỗi ngày (dùng Tim)", isExtra: false)
                                comparisonRow(icon: "calendar", text: "Lịch ôn tập cố định theo cấp độ tiêu chuẩn", isExtra: false)
                                comparisonRow(icon: "gift", text: "Tích lũy 1 Điểm Omni cho mỗi câu trả lời đúng", isExtra: false)
                                comparisonRow(icon: "app.badge", text: "Chỉ mở khóa biểu tượng Classic và mốc Streak", isExtra: false)
                                comparisonRow(icon: "xmark.circle", text: "Không có tính năng khôi phục chuỗi Streak", isExtra: false)
                            }
                        }
                        .padding(16)
                        .appSurface(.card, isExtra: true)

                        // Bảng 2: Extraordinary (Bản phi thường - Trả phí)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(ExtraAuroraPalette.champagne)
                                    Text("Extraordinary")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Color.white)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                    Text("VƯỢT TRỘI")
                                }
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(ExtraAuroraPalette.ice)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(ExtraAuroraPalette.violet.opacity(0.35))
                                        .overlay(Capsule().stroke(ExtraAuroraPalette.ice.opacity(0.5), lineWidth: 1))
                                )
                            }

                            Divider()
                                .overlay(
                                    LinearGradient(
                                        colors: [ExtraAuroraPalette.electricBlue.opacity(0.4), ExtraAuroraPalette.violet.opacity(0.4)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            VStack(alignment: .leading, spacing: 10) {
                                comparisonRow(icon: "infinity", text: "Vô hạn lượt học mỗi ngày (Không cần Tim, học mọi lúc)", isExtra: true)
                                comparisonRow(icon: "brain.head.profile", text: "Học thích ứng 5 năng lực theo dữ liệu trí nhớ người học", isExtra: true)
                                comparisonRow(icon: "bolt.fill", text: "Ưu đãi thưởng thêm +20% Điểm Omni sau mỗi bài học", isExtra: true)
                                comparisonRow(icon: "app.badge.fill", text: "Quyền năng mở khóa toàn bộ Omnicon độc quyền", isExtra: true)
                                comparisonRow(icon: "waveform.badge.mic", text: "Chấm phát âm chuyên sâu Azure AI chuẩn quốc tế", isExtra: true)
                                comparisonRow(icon: "flame.fill", text: "Đặc quyền khôi phục chuỗi Streak đã mất (Người giữ lửa)", isExtra: true)
                            }
                        }
                        .padding(16)
                        .appSurface(.card, isExtra: true)
                    }
                    .padding(.horizontal)

                    // Pricing Plans Selection
                    VStack(spacing: AppSpacing.cardGap) {
                        HStack {
                            Text("CHỌN GÓI NÂNG CẤP")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(ExtraAuroraPalette.ice)
                                .tracking(1.0)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        // Gói 1 Năm
                        Button {
                            selectedPlan = .annual
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: selectedPlan == .annual ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedPlan == .annual ? ExtraAuroraPalette.ice : Color.white.opacity(0.4))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text("Gói 1 Năm")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(Color.white)

                                        Text("Tiết kiệm ~48%")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.green.opacity(0.2)))
                                    }

                                    Text("499.000đ / năm (~41.500đ / tháng)")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }

                                Spacer()
                            }
                            .padding(14)
                            .appSurface(.row, isExtra: true)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
                                    .stroke(selectedPlan == .annual ? ExtraAuroraPalette.ice : .clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("upgrade-plan-annual")
                        .accessibilityValue(selectedPlan == .annual ? "Đã chọn" : "Chưa chọn")

                        // Gói 1 Tháng
                        Button {
                            selectedPlan = .monthly
                        } label: {
                            HStack(alignment: .center, spacing: 14) {
                                Image(systemName: selectedPlan == .monthly ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedPlan == .monthly ? ExtraAuroraPalette.ice : Color.white.opacity(0.4))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Gói 1 Tháng")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(Color.white)

                                    Text("79.000đ / tháng")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }

                                Spacer()
                            }
                            .padding(14)
                            .appSurface(.row, isExtra: true)
                            .overlay {
                                RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius, style: .continuous)
                                    .stroke(selectedPlan == .monthly ? ExtraAuroraPalette.ice : .clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("upgrade-plan-monthly")
                        .accessibilityValue(selectedPlan == .monthly ? "Đã chọn" : "Chưa chọn")
                    }
                    .padding(.horizontal)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            guard !isActivating else { return }
                            isActivating = true
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
                        } label: {
                            HStack(spacing: 8) {
                                if isActivating { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
                                Text(selectedPlan == .annual ? "Nâng cấp Extraordinary theo năm (499.000đ)" : "Nâng cấp Extraordinary theo tháng (79.000đ)")
                                    .fontWeight(.bold)
                            }
                        }
                        .buttonStyle(AppActionButtonStyle(isExtra: true))
                        .disabled(isActivating)

                        if !activationError.isEmpty {
                            Text(activationError)
                                .font(.caption)
                                .foregroundStyle(Color.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }

                        Button("Để sau", role: .cancel) {
                            dismiss()
                        }
                        .buttonStyle(AppActionButtonStyle(isExtra: true, emphasis: .secondary))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                AuroraBackdrop()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func comparisonRow(icon: String, text: String, isExtra: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : Color.white.opacity(0.45))
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(isExtra ? Color.white : Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
