import SwiftUI

struct HomeView: View {
    let adminUserId = AppConfig.adminUserId 
    
    @State private var storeVocabs: [Vocabulary] = []
    @State private var myDownloadKeysByTopic: [String: Set<String>] = [:]
    @State private var storeListeningSeries: [ListeningSeriesCatalogItem] = []
    @State private var listeningLibraryLessonIds: Set<String> = []
    
    @State private var isLoading = false
    @State private var isDownloading = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    // Streak and Activity states
    @ObservedObject private var streakState = OmniStreakFreezeManager.shared
    @State private var streakCount: Int = 0
    @State private var activityLogs: [String: Bool] = [:] // "YYYY-MM-DD" -> completed
    @State private var hasUnreadNotifications = false
    
    // Calendar state
    @State private var selectedMonth = Date()
    
    var groupedStoreVocabs: [String: [Vocabulary]] {
        Vocabulary.groupedByTopic(storeVocabs)
    }
    
    var sortedTopics: [String] {
        groupedStoreVocabs.keys.sorted()
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.cardGap) {
                    // Header
                    headerView
                    
                    // Streak Section
                    streakCard
                    
                    // Activity Calendar Section
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("Lịch học tập")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                                }
                            }) {
                                Image(systemName: "chevron.left")
                            }
                            Text(monthYearString(selectedMonth))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .frame(width: 120)
                            Button(action: {
                                withAnimation {
                                    selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                                }
                            }) {
                                Image(systemName: "chevron.right")
                            }
                        }
                        
                        CustomMonthCalendar(month: selectedMonth, activityLogs: activityLogs,
                                            frozenDates: streakState.frozenDates, rescuedDates: streakState.rescuedDates) { _ in }
                    }
                    .padding()
                    .appSurface(.card, isExtra: false)
                    .padding(.horizontal)
                    
                    // Explore Vocabulary Section (Wrapped in card)
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Khám Phá Từ Vựng")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                        
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if storeVocabs.isEmpty {
                            VStack {
                                Image(systemName: "books.vertical")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray)
                                    .padding()
                                Text("Hiện chưa có bộ từ vựng hệ thống nào.")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVStack(spacing: AppSpacing.cardGap) {
                                ForEach(sortedTopics, id: \.self) { topic in
                                    topicRow(topic: topic)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .appSurface(.card, isExtra: false)
                    .padding(.horizontal)

                    // Explore Listening Section
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Khám Phá Bài Luyện Nghe")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Image(systemName: "headphones")
                                .foregroundColor(.secondary)
                        }

                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else if storeListeningSeries.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.slash")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray)
                                Text("Hiện chưa có seri bài luyện nghe hệ thống nào.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        } else {
                            LazyVStack(spacing: AppSpacing.cardGap) {
                                ForEach(storeListeningSeries) { catalogItem in
                                    NavigationLink {
                                        ListeningSeriesPreviewView(
                                            catalogItem: catalogItem,
                                            downloadedLessonIds: listeningLibraryLessonIds,
                                            onLibraryChanged: {
                                                Task { await fetchListeningLibrary() }
                                            }
                                        )
                                    } label: {
                                        ListeningSystemSeriesRow(
                                            catalogItem: catalogItem,
                                            downloadedLessonIds: listeningLibraryLessonIds
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .appSurface(.card, isExtra: false)
                    .padding(.horizontal)
                }
                .padding(.bottom, 30)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Components
    
    var headerView: some View {
        HStack {
            // Tạm thời tắt chức năng bấm vào logo mở thông báo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 45)
                .accessibilityLabel("Ditandnary thuộc Omninary")
            /*
            NavigationLink(destination: NotificationView()) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 45)
                    .accessibilityLabel("Ditandnary thuộc Omninary")
            }
            .buttonStyle(.plain)
            */

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    var streakCard: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(streakCount > 0 ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(streakCount > 0 ? .orange : .gray)
                    .shadow(color: streakCount > 0 ? .orange.opacity(0.5) : .clear, radius: 10)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Chuỗi học tập")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(streakCount)")
                        .font(.system(size: 40, weight: .bold))
                    Text("ngày")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                if streakCount > 0 {
                    Text("Tuyệt vời! Hãy tiếp tục nhé.")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Text("Bắt đầu học để tạo chuỗi nhé!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .appSurface(.card, isExtra: false)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    func topicRow(topic: String) -> some View {
        let topicVocabs = groupedStoreVocabs[topic] ?? []
        let myDownloadKeysInTopic = myDownloadKeysByTopic[topicVocabs.first?.topic_id ?? ""] ?? []
        let missingVocabs = topicVocabs.filter { adminVocab in
            guard let downloadKey = adminVocab.downloadIdentityKey else { return false }
            return !myDownloadKeysInTopic.contains(downloadKey)
        }
        
        let hasDownloadedSome = !myDownloadKeysInTopic.isEmpty
        let isFullyDownloaded = hasDownloadedSome && missingVocabs.isEmpty
        let needsUpdate = hasDownloadedSome && !missingVocabs.isEmpty
        
        let uniqueTopicVocabsCount = Vocabulary.sortedItems(topicVocabs).count
        let uniqueMissingVocabsCount = Vocabulary.sortedItems(missingVocabs).count
        
        NavigationLink(destination: TopicPreviewView(
            topicName: topic, 
            vocabs: topicVocabs, 
            missingVocabs: missingVocabs,
            isFullyDownloaded: isFullyDownloaded,
            needsUpdate: needsUpdate,
            onDownload: {
                Task { await downloadTopic(missingVocabs, topicName: topic) }
            },
            isDownloading: $isDownloading
        )) {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("\(uniqueTopicVocabsCount) từ vựng")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                statusBadge(isFullyDownloaded: isFullyDownloaded, needsUpdate: needsUpdate, missingCount: uniqueMissingVocabsCount)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 5)
        }
    }
    
    @ViewBuilder
    func statusBadge(isFullyDownloaded: Bool, needsUpdate: Bool, missingCount: Int) -> some View {
        if isFullyDownloaded {
            Text("Đã tải")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.green.opacity(0.1)))
        } else if needsUpdate {
            Text("+\(missingCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.orange.opacity(0.1)))
        } else {
            Text("Mới")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.blue.opacity(0.1)))
        }
    }
    
    // MARK: - Logic
    
    func loadData() async {
        isLoading = true
        async let fetchStore: () = fetchStoreVocabs()
        async let fetchMy: () = fetchMyTopics()
        async let fetchListeningLessonsData: () = fetchStoreListeningSeries()
        async let fetchListeningLibraryData: () = fetchListeningLibrary()
        async let fetchStats: () = fetchUserStats()
        async let fetchNotif: () = fetchNotifications()
        
        _ = await (fetchStore, fetchMy, fetchListeningLessonsData, fetchListeningLibraryData, fetchStats, fetchNotif)
        isLoading = false
    }
    
    func fetchStoreVocabs() async {
        do {
            let fetched = try await VocabularyRepository.fetchSystemVocabs(adminUserId: adminUserId)
            
            DispatchQueue.main.async { self.storeVocabs = fetched }
        } catch {
            print("Lỗi lấy dữ liệu cửa hàng: \(error)")
        }
    }
    
    func fetchMyTopics() async {
        guard let myUserId = AuthManager.shared.currentUser?.id.uuidString else { return }
        do {
            let fetched = try await VocabularyRepository.fetchUserVocabs(userId: myUserId)
            
            var dict: [String: Set<String>] = [:]
            for v in fetched {
                guard let key = v.downloadIdentityKey else { continue }
                for topic in v.collectionTopics { dict[topic.id, default: []].insert(key) }
            }

            DispatchQueue.main.async {
                self.myDownloadKeysByTopic = dict
            }
        } catch {
            print("Lỗi lấy my topics: \(error)")
        }
    }

    func fetchStoreListeningSeries() async {
        do {
            let fetched = try await ListeningRepository.fetchSeriesCatalog()
            DispatchQueue.main.async {
                self.storeListeningSeries = fetched
            }
        } catch {
            print("Lỗi lấy seri bài luyện nghe hệ thống: \(error)")
        }
    }

    func fetchListeningLibrary() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }

        do {
            let entries = try await ListeningRepository.fetchUserLessonEntries(userId: userId)
            DispatchQueue.main.async {
                self.listeningLibraryLessonIds = Set(entries.map(\.lesson_id))
            }
        } catch {
            print("Lỗi lấy thư viện bài nghe: \(error)")
        }
    }
    
    func fetchUserStats() async {
        guard let myUserId = AuthManager.shared.currentUser?.id.uuidString else { return }
        do {
            // The server atomically decides both a broken streak and whether a
            // 24-hour rescue window is still valid.
            let currentStats = try await UserProgressRepository.refreshStreakState()
            await MainActor.run {
                self.streakCount = currentStats.streak_count
                OmniStreakFreezeManager.shared.applyRemoteState(currentStats)
            }
            
            // Fetch Activity Logs from Supabase
            let logs = try await UserProgressRepository.fetchCompletedActivityLogs(userId: myUserId)
            
            var dict: [String: Bool] = [:]
            for log in logs { dict[log.date] = log.completed }
            DispatchQueue.main.async { self.activityLogs = dict }
            
        } catch {
            print("Lỗi lấy stats từ Supabase: \(error)")
        }
    }
    
    func fetchNotifications() async {
        guard let myUserId = AuthManager.shared.currentUser?.id.uuidString else { return }
        do {
            let unreadCount = try await NotificationRepository.fetchUnreadCount(userId: myUserId)
            
            DispatchQueue.main.async { self.hasUnreadNotifications = unreadCount > 0 }
        } catch {
            print("Lỗi check thông báo: \(error)")
        }
    }
    
    func downloadTopic(_ vocabsToDownload: [Vocabulary], topicName: String) async {
        guard let myUserId = AuthManager.shared.currentUser?.id.uuidString else {
            alertMessage = "Vui lòng đăng nhập!"
            showAlert = true
            return
        }
        
        DispatchQueue.main.async { isDownloading = true }
        
        let myNewVocabs = vocabsToDownload.map { v -> Vocabulary in
            var newVocab = v
            newVocab.user_id = myUserId
            newVocab.created_at = nil
            return newVocab
        }
        
        do {
            try await VocabularyRepository.insert(myNewVocabs)
            
            DispatchQueue.main.async {
                isDownloading = false
                let newDownloadKeys = myNewVocabs.compactMap(\.downloadIdentityKey)
                if let topicId = myNewVocabs.first?.topic_id {
                    myDownloadKeysByTopic[topicId, default: []].formUnion(newDownloadKeys)
                }
                let uniqueWordCount = Vocabulary.sortedItems(myNewVocabs).count
                alertMessage = "Tải thành công \(uniqueWordCount) từ!"
                showAlert = true
            }
        } catch {
            DispatchQueue.main.async {
                isDownloading = false
                alertMessage = "Lỗi: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    // MARK: - Helpers
    
    func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
