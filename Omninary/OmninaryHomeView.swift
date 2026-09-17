import SwiftUI

struct OmninaryHomeView: View {
    private let adminUserId = AppConfig.adminUserId

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var storeVocabs: [Vocabulary] = []
    @State private var downloadedKeysByTopic: [String: Set<String>] = [:]
    @State private var listeningCatalog: [ListeningSeriesCatalogItem] = []
    @State private var listeningLibraryLessonIds: Set<String> = []
    @State private var streakCount = 0
    @State private var activityLogs: [String: Bool] = [:]
    @State private var hasUnreadNotifications = false
    @State private var selectedMonth = Date()
    @State private var selectedActivityDate = Date()
    @State private var showDailyStats = false
    @State private var isDownloading = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var interfaceMode: AppInterfaceMode {
        AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary
    }

    private var isExtra: Bool {
        interfaceMode == .extraordinary
    }

    private var groupedVocabs: [String: [Vocabulary]] {
        Dictionary(grouping: storeVocabs) { vocab in
            let topic = vocab.topics?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return topic.isEmpty ? "Chủ đề chung" : topic
        }
    }

    private var sortedTopics: [String] {
        groupedVocabs.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    streakCard
                    calendarCard
                    discoveryCard
                }
                .padding(.bottom, 32)
            }
            .background {
                if isExtra {
                    LinearGradient(
                        colors: [Color(red: 0.015, green: 0.025, blue: 0.05), Color(red: 0.02, green: 0.09, blue: 0.15), Color(red: 0.01, green: 0.035, blue: 0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
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
            .navigationDestination(isPresented: $showDailyStats) {
                DailyLearningStatsPlaceholderView(date: selectedActivityDate)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(interfaceMode.wordmarkAsset)
                .resizable()
                .scaledToFit()
                .frame(width: isExtra ? 232 : 205, height: isExtra ? 74 : 64, alignment: .leading)
                .accessibilityLabel(interfaceMode.title)

            Spacer(minLength: 12)

            NavigationLink(destination: NotificationView()) {
                ZStack {
                    Image(systemName: "bell.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                    if hasUnreadNotifications {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .offset(x: 8, y: -8)
                    }
                }
                .padding(12)
                .background {
                    if isExtra {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    } else {
                        Circle().fill(Color(UIColor.secondarySystemGroupedBackground))
                    }
                }
                .shadow(color: isExtra ? Color.cyan.opacity(0.18) : Color.black.opacity(0.05), radius: 8)
            }
            .accessibilityLabel("Thông báo")
        }
        .padding(.horizontal)
        .padding(.top, 18)
    }

    private var streakCard: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(streakCount > 0 ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(streakCount > 0 ? .orange : .gray)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Chuỗi học tập")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streakCount)")
                        .font(.system(size: 40, weight: .bold))
                    Text("ngày")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(streakCount > 0 ? "Tuyệt vời! Hãy tiếp tục nhé." : "Bắt đầu học để tạo chuỗi nhé!")
                    .font(.caption)
                    .foregroundStyle(streakCount > 0 ? .orange : .secondary)
            }
            Spacer()
        }
        .padding(20)
        .background(cardBackground)
        .padding(.horizontal)
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Text("Lịch học tập")
                        .font(.title2.bold())
                        .frame(width: proxy.size.width * 0.5, alignment: .leading)

                    HStack(spacing: 10) {
                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.left")
                        }

                        Text(monthYearString(selectedMonth))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)

                        Button {
                            withAnimation { selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .frame(width: proxy.size.width * 0.5)
                }
            }
            .frame(height: 32)
            CustomMonthCalendar(month: selectedMonth, activityLogs: activityLogs) { date in
                selectedActivityDate = date
                showDailyStats = true
            }
        }
        .padding()
        .background(cardBackground)
        .padding(.horizontal)
    }

    private var discoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Khám phá")
                    .font(.title2.bold())
                Spacer()
                Image(systemName: "safari.fill")
                    .foregroundStyle(.secondary)
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
                folderRow(title: "Khám phá Từ vựng", subtitle: "Các chủ đề và bộ từ", icon: "books.vertical.fill", tint: isExtra ? .cyan : .blue)
            }

            Divider()

            NavigationLink {
                ListeningExploreView(
                    catalog: listeningCatalog,
                    downloadedLessonIds: listeningLibraryLessonIds,
                    refreshLibrary: { Task { await fetchListeningLibrary() } }
                )
            } label: {
                folderRow(title: "Khám phá Bài luyện nghe", subtitle: "Các seri bài luyện nghe", icon: "headphones", tint: isExtra ? .blue : .orange)
            }
        }
        .padding(20)
        .background(cardBackground)
        .padding(.horizontal)
    }

    private var cardBackground: some View {
        Group {
            if isExtra {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.42), Color.white.opacity(0.14), Color.blue.opacity(0.26)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: Color.cyan.opacity(0.12), radius: 18, x: 0, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
            }
        }
    }

    private func folderRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
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
            guard let topic = vocab.topics?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty,
                  let key = vocab.downloadIdentityKey else { continue }
            result[topic, default: []].insert(key)
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
        if var stats = try? await UserProgressRepository.fetchStats(userId: userID).first {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let lastString = stats.last_learning_date, let lastDate = formatter.date(from: lastString) {
                let difference = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastDate), to: Calendar.current.startOfDay(for: Date())).day ?? 0
                if difference > 1 {
                    stats.streak_count = 0
                    try? await UserProgressRepository.resetStreak(userId: userID)
                }
            }
            streakCount = stats.streak_count
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
            downloadedKeysByTopic[topicName, default: []].formUnion(copies.compactMap(\.downloadIdentityKey))
            alertMessage = "Tải thành công \(Set(copies.compactMap(\.normalizedWord)).count) từ!"
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
