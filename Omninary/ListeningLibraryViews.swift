import AVFoundation
import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NavigationLink {
                        MyVocabularyView()
                    } label: {
                        LibraryDestinationCard(
                            title: "My Vocabulary",
                            subtitle: "Bộ từ đã tải, topic riêng và tiến độ học từ vựng.",
                            icon: "books.vertical.fill",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        MyListeningView()
                    } label: {
                        LibraryDestinationCard(
                            title: "My Listening",
                            subtitle: "Seri bài nghe đã tải để đọc trước, nghe trước và đưa từng bài vào luyện.",
                            icon: "headphones",
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Thư viện")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct LibraryDestinationCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(tint.opacity(0.14))
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
        )
    }
}

struct MyListeningView: View {
    @State private var seriesItems: [ListeningSeriesLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && seriesItems.isEmpty {
                ProgressView("Đang tải thư viện nghe...")
            } else if seriesItems.isEmpty {
                VStack {
                    Text("Chưa có seri bài nghe nào.")
                        .foregroundColor(.secondary)
                    Text("Hãy tải seri bài nghe ở Trang chủ để xem và luyện nghe.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            } else {
                List {
                    Section("Seri bài luyện nghe của tôi") {
                        ForEach(seriesItems) { seriesItem in
                            NavigationLink {
                                MyListeningSeriesView(
                                    seriesItem: seriesItem,
                                    onLibraryChanged: {
                                        Task { await loadItems() }
                                    }
                                )
                            } label: {
                                ListeningLibrarySeriesRow(seriesItem: seriesItem)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My Listening")
        .task {
            await loadItems()
        }
        .refreshable {
            await loadItems()
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func loadItems() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            seriesItems = try await ListeningRepository.fetchLibrarySeriesItems(userId: userId)
        } catch {
            errorMessage = "Không tải được thư viện nghe: \(error.localizedDescription)"
        }
    }
}

struct MyListeningSeriesView: View {
    let series: ListeningSeries
    let onLibraryChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ListeningLibraryItem]
    @State private var summariesByLessonId: [String: ListeningLessonSummary] = [:]
    @State private var deletingLessonId: String?
    @State private var errorMessage: String?

    init(seriesItem: ListeningSeriesLibraryItem, onLibraryChanged: @escaping () -> Void) {
        self.series = seriesItem.series
        self.onLibraryChanged = onLibraryChanged
        _items = State(initialValue: seriesItem.lessons)
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("Không có bài luyện nghe nào trong seri này.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    NavigationLink {
                        ListeningLessonDetailView(
                            item: item,
                            onLibraryChanged: onLibraryChanged
                        )
                    } label: {
                        ListeningLibraryLessonRow(
                            item: item,
                            summary: summariesByLessonId[item.lesson.id]
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await delete(item) }
                        } label: {
                            Label(
                                deletingLessonId == item.lesson.id ? "Đang xóa" : "Xóa bài",
                                systemImage: "trash"
                            )
                        }
                        .disabled(deletingLessonId != nil)
                    }
                }
            }
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSummaries()
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @MainActor
    private func loadSummaries() async {
        do {
            let summaries = try await ListeningRepository.fetchLessonSummaries(for: items.map(\.lesson))
            summariesByLessonId = Dictionary(uniqueKeysWithValues: summaries.map { ($0.lesson.id, $0) })
        } catch {
            errorMessage = "Không tải được thông tin bài nghe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func delete(_ item: ListeningLibraryItem) async {
        deletingLessonId = item.lesson.id
        defer {
            deletingLessonId = nil
        }

        do {
            try await ListeningRepository.removeLessonFromLibrary(lessonId: item.lesson.id)
            items.removeAll { $0.id == item.id }
            summariesByLessonId[item.lesson.id] = nil
            onLibraryChanged()

            if items.isEmpty {
                dismiss()
            }
        } catch {
            errorMessage = "Không thể xóa bài nghe: \(error.localizedDescription)"
        }
    }
}

struct ListeningSeriesPreviewView: View {
    let catalogItem: ListeningSeriesCatalogItem
    let onLibraryChanged: () -> Void

    @State private var downloadedLessonIds: Set<String>
    @State private var summaries: [ListeningLessonSummary] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(
        catalogItem: ListeningSeriesCatalogItem,
        downloadedLessonIds: Set<String>,
        onLibraryChanged: @escaping () -> Void
    ) {
        self.catalogItem = catalogItem
        self.onLibraryChanged = onLibraryChanged
        _downloadedLessonIds = State(initialValue: downloadedLessonIds)
    }

    private var seriesLessonIds: Set<String> {
        Set(catalogItem.lessons.map(\.id))
    }

    private var downloadedLessonIdsInSeries: Set<String> {
        downloadedLessonIds.intersection(seriesLessonIds)
    }

    private var missingLessons: [ListeningLesson] {
        catalogItem.lessons.filter { !downloadedLessonIds.contains($0.id) }
    }

    private var hasDownloadedSome: Bool {
        !downloadedLessonIdsInSeries.isEmpty
    }

    private var isFullyDownloaded: Bool {
        hasDownloadedSome && missingLessons.isEmpty
    }

    private var needsUpdate: Bool {
        hasDownloadedSome && !missingLessons.isEmpty
    }

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Đang tải danh sách bài nghe...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("Danh sách bài luyện nghe (\(summaries.count) bài)")) {
                        ForEach(summaries) { summary in
                            let isNew = !downloadedLessonIds.contains(summary.lesson.id)
                            ListeningSeriesLessonRow(summary: summary, isNew: isNew)
                                .padding(.vertical, 4)
                                .listRowBackground(isNew ? Color.orange.opacity(0.08) : Color.clear)
                        }
                    }
                }

                seriesAction
            }
        }
        .navigationTitle(catalogItem.series.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSummaries()
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Đã xong", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
    }

    @ViewBuilder
    private var seriesAction: some View {
        if isFullyDownloaded {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Seri bài nghe này đã có trong máy của bạn")
            }
                .font(.headline)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding()
        } else {
            Button {
                Task { await downloadMissingLessons() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Đang tải...")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(needsUpdate ? "Cập nhật \(missingLessons.count) bài mới" : "Tải seri bài nghe này về máy")
                    }
                }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSaving ? Color.gray : (needsUpdate ? Color.orange : Color.blue))
                    .cornerRadius(12)
                    .padding()
            }
            .disabled(isSaving)
        }
    }

    @MainActor
    private func loadSummaries() async {
        isLoading = true
        defer { isLoading = false }

        do {
            summaries = try await ListeningRepository.fetchLessonSummaries(for: catalogItem.lessons)
        } catch {
            errorMessage = "Không tải được danh sách bài nghe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func downloadMissingLessons() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            errorMessage = "Vui lòng đăng nhập để tải seri bài nghe."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let insertedCount = try await ListeningRepository.addLessonsToLibrary(
                userId: userId,
                lessonIds: missingLessons.map(\.id)
            )
            downloadedLessonIds.formUnion(missingLessons.map(\.id))
            onLibraryChanged()

            successMessage = insertedCount > 0
                ? "Đã tải \(insertedCount) bài trong seri vào My Listening."
                : "Tất cả bài trong seri này đã có trong My Listening."
        } catch {
            errorMessage = "Tải seri bài nghe thất bại: \(error.localizedDescription)"
        }
    }
}

struct ListeningLessonDetailView: View {
    let item: ListeningLibraryItem
    let onLibraryChanged: () -> Void

    @StateObject private var sentenceAudioPlayer = ListeningAudioPlayer()
    @StateObject private var lessonAudioPlayer = ListeningSequenceAudioPlayer()
    @State private var segments: [ListeningSegment] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isInLearning: Bool
    @State private var isPassed: Bool
    @State private var bestScore: Double
    @State private var isInShadowing: Bool
    @State private var isShadowingPassed: Bool
    @State private var shadowingBestScore: Double
    @State private var showingDictation = false
    @State private var showingShadowing = false
    @State private var isStartingShadowing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(item: ListeningLibraryItem, onLibraryChanged: @escaping () -> Void) {
        self.item = item
        self.onLibraryChanged = onLibraryChanged
        _isInLearning = State(initialValue: item.isInLearning)
        _isPassed = State(initialValue: item.isCompleted)
        _bestScore = State(initialValue: item.entry.best_score ?? 0)
        _isInShadowing = State(initialValue: item.isInShadowing)
        _isShadowingPassed = State(initialValue: item.isShadowingCompleted)
        _shadowingBestScore = State(initialValue: item.entry.shadowing_best_score ?? 0)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Đang tải nội dung bài nghe...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            } else {
                List {
                    Section {
                        lessonHeader
                    }

                    ForEach(segments) { segment in
                        Section(header: Text("Câu \(segment.order_index)")) {
                            ListeningSegmentDetailRow(
                                segment: segment,
                                isPlaying: sentenceAudioPlayer.isPlaying,
                                onPlay: { playSentence(segment) }
                            )
                        }
                    }

                    Section("Luyện nghe chép chính tả") {
                        dictationLearningAction
                    }
                    .listRowBackground(Color.clear)

                    Section("Luyện Shadowing") {
                        shadowingLearningAction
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(item.lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingDictation) {
            NavigationStack {
                ListeningDictationView(
                    lesson: item.lesson,
                    startsNewAttempt: isPassed,
                    onFinished: {
                        onLibraryChanged()
                        Task { await refreshLearningStatus() }
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showingShadowing) {
            NavigationStack {
                ShadowingPracticeView(
                    lesson: item.lesson,
                    onFinished: {
                        onLibraryChanged()
                        Task { await refreshLearningStatus() }
                    }
                )
            }
        }
        .task {
            await loadContent()
        }
        .onAppear {
            Task { await refreshLearningStatus() }
        }
        .onDisappear {
            sentenceAudioPlayer.stop()
            lessonAudioPlayer.stop()
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Đã xong", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
    }

    private var lessonHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.lesson.title)
                        .font(.title3.bold())

                    if let viTitle = item.lesson.vi_title, !viTitle.isEmpty {
                        Text(viTitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    toggleWholeLessonPlayback()
                } label: {
                    Image(systemName: lessonAudioPlayer.isPlaying ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lessonAudioPlayer.isPlaying ? "Dừng nghe cả bài" : "Nghe cả bài")
            }

            FlowLayout(spacing: 8) {
                if let cefr = item.lesson.cefr, !cefr.isEmpty {
                    ListeningPill(text: cefr, tint: .blue)
                }
                ListeningPill(text: "\(segments.count) câu", tint: .orange)
                if isPassed {
                    ListeningPill(text: "Đã pass", tint: .green)
                    ListeningPill(text: "\(ListeningScoreCalculator.display(bestScore))/100", tint: .orange)
                } else if isInLearning {
                    ListeningPill(text: "Đang luyện", tint: .green)
                    if bestScore > 0 {
                        ListeningPill(text: "Cao nhất \(ListeningScoreCalculator.display(bestScore))/100", tint: .orange)
                    }
                } else {
                    ListeningPill(text: "Đã tải", tint: .green)
                }

                if isShadowingPassed {
                    ListeningPill(text: "Shadowing đã pass", tint: .purple)
                    if shadowingBestScore > 0 {
                        ListeningPill(
                            text: "\(ListeningScoreCalculator.display(shadowingBestScore))/100",
                            tint: .purple
                        )
                    }
                } else if isInShadowing {
                    ListeningPill(text: "Đang Shadowing", tint: .purple)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var dictationLearningAction: some View {
        if isPassed {
            Button {
                showingDictation = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện nghe chép chính tả lại",
                    icon: "arrow.counterclockwise",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)
        } else if isInLearning {
            Button {
                showingDictation = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện nghe chép chính tả ngay",
                    icon: "play.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await startPractice() }
            } label: {
                ListeningActionLabel(
                    title: isSaving
                        ? "Đang đưa vào luyện nghe chép chính tả..."
                        : "Đưa bài nghe này vào luyện nghe chép chính tả ngay",
                    icon: "graduationcap.fill",
                    tint: .green
                )
            }
            .disabled(isSaving)
        }
    }

    @ViewBuilder
    private var shadowingLearningAction: some View {
        if isShadowingPassed {
            Button {
                showingShadowing = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện Shadowing lại",
                    icon: "arrow.counterclockwise",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
        } else if isInShadowing {
            Button {
                showingShadowing = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện Shadowing ngay",
                    icon: "waveform.and.mic",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await startShadowing() }
            } label: {
                ListeningActionLabel(
                    title: isStartingShadowing
                        ? "Đang đưa vào luyện Shadowing..."
                        : "Đưa bài nghe này vào luyện Shadowing ngay",
                    icon: "waveform.and.mic",
                    tint: .green
                )
            }
            .disabled(isStartingShadowing)
        }
    }

    @MainActor
    private func loadContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            segments = try await ListeningRepository.fetchSegments(lessonId: item.lesson.id)
        } catch {
            errorMessage = "Không tải được nội dung bài nghe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshLearningStatus() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }

        do {
            guard let entry = try await ListeningRepository.fetchUserLessonEntry(
                userId: userId,
                lessonId: item.lesson.id
            ) else { return }

            isInLearning = entry.isInLearning
            isPassed = entry.completed_at != nil
            bestScore = entry.best_score ?? 0
            isInShadowing = entry.isInShadowing
            shadowingBestScore = entry.shadowing_best_score ?? 0

            let segments = try await ListeningRepository.fetchSegments(lessonId: item.lesson.id)
            let passedSegmentIds = try await ListeningRepository.fetchPassedShadowingSegmentIds(userId: userId)
            isShadowingPassed = !segments.isEmpty && segments.allSatisfy { passedSegmentIds.contains($0.id) }
        } catch {
            errorMessage = "Không tải được trạng thái bài nghe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startPractice() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            errorMessage = "Vui lòng đăng nhập để luyện nghe."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await ListeningRepository.startListeningPractice(userId: userId, lessonId: item.lesson.id)
            isInLearning = true
            onLibraryChanged()
            successMessage = "Bài đã được đưa vào Luyện nghe chép chính tả."
        } catch {
            errorMessage = "Không thể đưa bài vào luyện nghe chép chính tả: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func startShadowing() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            errorMessage = "Vui lòng đăng nhập để luyện Shadowing."
            return
        }

        isStartingShadowing = true
        defer { isStartingShadowing = false }

        do {
            try await ListeningRepository.startShadowingPractice(userId: userId, lessonId: item.lesson.id)
            isInShadowing = true
            onLibraryChanged()
            successMessage = "Bài đã được đưa vào Luyện Shadowing."
        } catch {
            errorMessage = "Không thể đưa bài vào luyện Shadowing: \(error.localizedDescription)"
        }
    }

    private func playSentence(_ segment: ListeningSegment) {
        do {
            lessonAudioPlayer.stop()
            let url = try ListeningRepository.publicAudioURL(for: segment)
            sentenceAudioPlayer.play(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleWholeLessonPlayback() {
        if lessonAudioPlayer.isPlaying {
            lessonAudioPlayer.stop()
            return
        }

        do {
            sentenceAudioPlayer.stop()
            try lessonAudioPlayer.play(segments: segments)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ListeningPracticeDashboardView: View {
    @State private var items: [ListeningLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var completedLessonCount: Int {
        items.filter(\.isCompleted).count
    }

    private var activeItems: [ListeningLibraryItem] {
        items.filter(\.isInLearning)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Đang tải tiến độ luyện nghe...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        screenTitle
                        progressCard
                        practiceCard
                    }
                    .padding()
                }
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Luyện nghe")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadItems() }
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var progressCard: some View {
        HStack(spacing: 22) {
            ListeningCompletionRing(
                completed: completedLessonCount,
                total: items.count,
                tint: .orange
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Tiến độ bài nghe")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("\(completedLessonCount) / \(items.count) bài")
                    .font(.title2.bold())

                Text(items.isEmpty ? "Hãy tải một seri bài nghe từ Trang chủ." : "Số bài đã hoàn thành trên tổng bài đã tải về.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    private var screenTitle: some View {
        Text("Luyện nghe\nchép chính tả")
            .font(.system(size: 32, weight: .bold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bài đang luyện")
                        .font(.headline)

                    Text(activeItems.isEmpty ? "Hãy vào My Listening và bấm Đưa bài này vào luyện nghe." : "Bạn đang có \(activeItems.count) bài sẵn sàng luyện.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "headphones")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(activeItems.isEmpty ? .secondary : .orange)
            }

            NavigationLink {
                ListeningPracticeMenuView(items: activeItems)
            } label: {
                Label("Luyện nghe", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(activeItems.isEmpty ? Color.gray.opacity(0.45) : Color.orange)
                    .cornerRadius(18)
            }
            .disabled(activeItems.isEmpty)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    @MainActor
    private func loadItems() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            items = try await ListeningRepository.fetchLibraryItems(userId: userId)
        } catch {
            errorMessage = "Không tải được tiến độ luyện nghe: \(error.localizedDescription)"
        }
    }
}

struct ListeningPracticeMenuView: View {
    let items: [ListeningLibraryItem]
    @State private var selectedItem: ListeningLibraryItem?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Chưa có bài đang luyện",
                    systemImage: "headphones",
                    description: Text("Bạn cần đưa bài từ My Listening vào Luyện nghe trước.")
                )
            } else {
                List {
                    Section("Bài đang luyện") {
                        ForEach(items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                ListeningLibraryLessonRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Chọn bài luyện")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedItem) { item in
            NavigationStack {
                ListeningDictationView(lesson: item.lesson)
            }
        }
    }
}

struct ListeningSystemSeriesRow: View {
    let catalogItem: ListeningSeriesCatalogItem
    let downloadedLessonIds: Set<String>

    private var missingCount: Int {
        catalogItem.lessons.filter { !downloadedLessonIds.contains($0.id) }.count
    }

    private var downloadedCount: Int {
        catalogItem.lessons.filter { downloadedLessonIds.contains($0.id) }.count
    }

    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: "rectangle.stack.fill")
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogItem.series.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(catalogItem.lessons.count) bài nghe")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 6)

            if downloadedCount > 0, missingCount == 0 {
                catalogStatusBadge(text: "Đã tải", tint: .green)
            } else if downloadedCount > 0 {
                catalogStatusBadge(text: "+\(missingCount)", tint: .orange)
            } else {
                catalogStatusBadge(text: "Mới", tint: .blue)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
    }

    private func catalogStatusBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.1)))
    }
}

private struct ListeningLibrarySeriesRow: View {
    let seriesItem: ListeningSeriesLibraryItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(seriesItem.series.title)
                        .font(.headline)

                    if seriesItem.learningLessonCount > 0 {
                        ListeningPill(text: "\(seriesItem.learningLessonCount) đang luyện", tint: .orange)
                    }

                    if seriesItem.shadowingLessonCount > 0 {
                        ListeningPill(text: "\(seriesItem.shadowingLessonCount) Shadowing", tint: .purple)
                    }
                }

                Text("\(seriesItem.lessons.count) bài nghe")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct ListeningLibraryLessonRow: View {
    let item: ListeningLibraryItem
    var summary: ListeningLessonSummary? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.lesson.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            FlowLayout(spacing: 6) {
                if let cefr = item.lesson.cefr, !cefr.isEmpty {
                    ListeningPill(text: cefr, tint: .blue)
                }

                if item.isCompleted {
                    ListeningPill(text: "Đã pass", tint: .green)
                    if let score = item.entry.best_score {
                        ListeningPill(text: "\(ListeningScoreCalculator.display(score))/100", tint: .orange)
                    }
                } else if item.isInLearning {
                    ListeningPill(text: "Đang luyện", tint: .orange)
                    if let score = item.entry.best_score, score > 0 {
                        ListeningPill(text: "\(ListeningScoreCalculator.display(score))/100", tint: .orange)
                    }
                } else {
                    ListeningPill(text: "Đã tải", tint: .blue)
                }

                if item.isShadowingCompleted {
                    ListeningPill(text: "Shadowing đã pass", tint: .purple)
                    if let score = item.entry.shadowing_best_score, score > 0 {
                        ListeningPill(text: "\(ListeningScoreCalculator.display(score))/100", tint: .purple)
                    }
                } else if item.isInShadowing {
                    ListeningPill(
                        text: "Shadowing \(item.shadowingPassedSegmentCount)/\(item.segmentCount)",
                        tint: .purple
                    )
                }
            }

            if let viTitle = item.lesson.vi_title, !viTitle.isEmpty {
                Text(viTitle)
                    .font(.body)
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                Text("\(item.completedSegmentCount)/\(item.segmentCount) câu hoàn thành")

                if let summary, summary.durationSeconds > 0 {
                    Text("•")
                    Text(ListeningDurationFormatter.text(summary.durationSeconds))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ListeningSeriesLessonRow: View {
    let summary: ListeningLessonSummary
    let isNew: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.lesson.title)
                    .font(.headline)

                if isNew {
                    Text("Mới")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }

                Spacer()
            }

            if let viTitle = summary.lesson.vi_title, !viTitle.isEmpty {
                Text(viTitle)
                    .font(.body)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                if let cefr = summary.lesson.cefr, !cefr.isEmpty {
                    Text(cefr)
                        .foregroundColor(.blue)
                    Text("•")
                }
                Text("\(summary.segmentCount) câu")
                if summary.durationSeconds > 0 {
                    Text("•")
                    Text(ListeningDurationFormatter.text(summary.durationSeconds))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}

private struct ListeningSegmentDetailRow: View {
    let segment: ListeningSegment
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(segment.english_text)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe câu \(segment.order_index)")
            }

            if let vietnamese = segment.vietnamese_text, !vietnamese.isEmpty {
                listeningDetailRow(title: "Nghĩa Tiếng Việt", content: vietnamese)
            }

            if let ipa = segment.ipa, !ipa.isEmpty {
                listeningDetailRow(title: "Phát âm (IPA)", content: ipa, color: .blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func listeningDetailRow(title: String, content: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(content)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct ListeningActionLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .background(tint)
            .cornerRadius(10)
    }
}

private struct ListeningPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12))
            .cornerRadius(4)
    }
}

struct ListeningCompletionRing: View {
    let completed: Int
    let total: Int
    let tint: Color

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 12)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int((fraction * 100).rounded()))%")
                .font(.headline)
                .foregroundColor(tint)
        }
        .frame(width: 100, height: 100)
    }
}

private enum ListeningDurationFormatter {
    static func text(_ seconds: Double) -> String {
        let roundedSeconds = max(Int(seconds.rounded()), 0)
        let minutes = roundedSeconds / 60
        let remainingSeconds = roundedSeconds % 60

        if minutes == 0 {
            return "\(remainingSeconds) giây"
        }

        return remainingSeconds == 0
            ? "\(minutes) phút"
            : "\(minutes) phút \(remainingSeconds) giây"
    }
}

@MainActor
private final class ListeningSequenceAudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVQueuePlayer?
    private var endObserver: NSObjectProtocol?

    func play(segments: [ListeningSegment]) throws {
        let urls = try segments.map { try ListeningRepository.publicAudioURL(for: $0) }
        guard !urls.isEmpty else { return }

        stop()

        let player = AVQueuePlayer(items: urls.map(AVPlayerItem.init(url:)))
        self.player = player

        if let lastItem = player.items().last {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: lastItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isPlaying = false
                }
            }
        }

        player.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        player = nil
        isPlaying = false

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
