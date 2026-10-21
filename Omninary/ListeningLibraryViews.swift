import AVFoundation
import SwiftUI

struct LibraryView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.cardGap) {
                        NavigationLink {
                            MyVocabularyView()
                        } label: {
                            LibraryDestinationCard(
                                eyebrow: "TỪ VỰNG",
                                title: "My Vocabulary",
                                icon: "books.vertical.fill",
                                tint: isExtra ? ExtraAuroraPalette.ice : .blue,
                                isExtra: isExtra
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library-vocabulary-card")

                        NavigationLink {
                            MyListeningView()
                        } label: {
                            LibraryDestinationCard(
                                eyebrow: "BÀI NGHE",
                                title: "My Listening",
                                icon: "headphones",
                                tint: LearningDashboardWidget.listening.iconTint(isExtra: isExtra),
                                isExtra: isExtra
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library-listening-card")
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

private struct LibraryDestinationCard: View {
    let eyebrow: String
    let title: String
    let icon: String
    let tint: Color
    let isExtra: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(tint.opacity(isExtra ? 0.19 : 0.14))
                        .frame(width: 58, height: 58)
                        .overlay {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .stroke(tint.opacity(isExtra ? 0.45 : 0.15), lineWidth: 1)
                        }

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(tint)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isExtra ? Color.white.opacity(0.48) : .secondary)
                    .padding(10)
                    .background(isExtra ? Color.white.opacity(0.08) : Color.black.opacity(0.045), in: Circle())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(tint)

                Text(title)
                    .font(AppTypography.destinationTitle)
                    .foregroundStyle(isExtra ? .white : .primary)

            }
        }
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.card, isExtra: isExtra)
        .contentShape(RoundedRectangle(cornerRadius: AppSurfaceKind.card.cornerRadius, style: .continuous))
    }
}

struct MyListeningView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var seriesItems: [ListeningSeriesLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            Group {
                if isLoading && seriesItems.isEmpty {
                    ProgressView("Đang tải thư viện nghe...")
                } else if seriesItems.isEmpty {
                    VStack {
                        Text("Chưa có seri bài nghe nào.")
                            .foregroundColor(isExtra ? Color.white.opacity(0.85) : .secondary)
                        Text("Hãy tải seri bài nghe ở Trang chủ để xem và luyện nghe.")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
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
                                    ListeningLibrarySeriesRow(seriesItem: seriesItem, isExtra: isExtra)
                                }
                                .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                                .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                            }
                        }
                    }
                    .scrollContentBackground(isExtra ? .hidden : .automatic)
                }
            }
        }
        .navigationTitle("My Listening")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var items: [ListeningLibraryItem]
    @State private var summariesByLessonId: [String: ListeningLessonSummary] = [:]
    @State private var deletingLessonId: String?
    @State private var errorMessage: String?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    init(seriesItem: ListeningSeriesLibraryItem, onLibraryChanged: @escaping () -> Void) {
        self.series = seriesItem.series
        self.onLibraryChanged = onLibraryChanged
        _items = State(initialValue: seriesItem.lessons)
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            List {
                if items.isEmpty {
                    Text("Không có bài luyện nghe nào trong seri này.")
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
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
                                summary: summariesByLessonId[item.lesson.id],
                                isExtra: isExtra
                            )
                        }
                        .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                        .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
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
            .scrollContentBackground(isExtra ? .hidden : .automatic)
        }
        .navigationTitle(series.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Đang tải danh sách bài nghe...")
                    .foregroundStyle(isExtra ? .white : .primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                            let isNew = !downloadedLessonIds.contains(summary.lesson.id)
                            let isBottom = (index == summaries.count - 1)
                            ListeningSeriesLessonRow(summary: summary, isNew: isNew, isExtra: isExtra)
                                .padding(.vertical, 4)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(isBottom ? .hidden : .visible, edges: .bottom)
                                .listRowSeparator(.hidden, edges: .top)
                                .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                        }
                    } header: {
                        Text("Danh sách bài luyện nghe (\(summaries.count) bài)")
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(isExtra ? Color.white.opacity(0.8) : .secondary)
                    }
                    .listSectionSeparator(.hidden, edges: .all)
                }
                .scrollContentBackground(isExtra ? .hidden : .automatic)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    seriesAction
                }
            }
        }
        .background {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(catalogItem.series.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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

    private var seriesAction: some View {
        AppFloatingDownloadBar(
            title: isFullyDownloaded ? "Seri bài nghe này đã có trong máy của bạn" : (isSaving ? "Đang tải..." : (needsUpdate ? "Cập nhật \(missingLessons.count) bài mới" : "Tải seri bài nghe này về máy")),
            isWorking: isSaving, isComplete: isFullyDownloaded, isExtra: isExtra
        ) { Task { await downloadMissingLessons() } }
    }

    @MainActor
    private func loadSummaries() async {
        isLoading = true
        defer { isLoading = false }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting") && ProcessInfo.processInfo.arguments.contains("-InterfacePolishUITest") {
            summaries = catalogItem.lessons.map { ListeningLessonSummary(lesson: $0, segmentCount: 3, durationSeconds: 45) }
            return
        }
#endif

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

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
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

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

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
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            Group {
                if isLoading {
                    ProgressView("Đang tải nội dung bài nghe...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            lessonHeader
                        }
                        .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                        .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))

                        ForEach(segments) { segment in
                            Section(header: Text("Câu \(segment.order_index)").foregroundColor(isExtra ? Color.white.opacity(0.9) : .secondary)) {
                                ListeningSegmentDetailRow(
                                    segment: segment,
                                    isPlaying: sentenceAudioPlayer.isPlaying,
                                    isExtra: isExtra,
                                    onPlay: { playSentence(segment) }
                                )
                            }
                            .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                            .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
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
                    .scrollContentBackground(isExtra ? .hidden : .automatic)
                }
            }
        }
        .navigationTitle(item.lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
                        .foregroundColor(isExtra ? .white : .primary)

                    if let viTitle = item.lesson.vi_title, !viTitle.isEmpty {
                        Text(viTitle)
                            .font(.subheadline)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    toggleWholeLessonPlayback()
                } label: {
                    Image(systemName: lessonAudioPlayer.isPlaying ? "stop.fill" : "play.fill")
                        .font(AppTypography.cardTitle)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(AppTheme(isExtra: isExtra).primaryGradient)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lessonAudioPlayer.isPlaying ? "Dừng nghe cả bài" : "Nghe cả bài")
            }

            FlowLayout(spacing: 8) {
                if let cefr = item.lesson.cefr, !cefr.isEmpty {
                    ListeningPill(text: cefr, tint: isExtra ? ExtraAuroraPalette.iceCyan : .blue)
                }
                ListeningPill(text: "\(segments.count) câu", tint: .orange)
                if isPassed {
                    ListeningPill(text: "Đã pass", tint: .green)
                    ListeningPill(text: "\(ListeningScoreCalculator.display(bestScore))/100", tint: .orange)
                } else if isInLearning {
                    ListeningPill(text: "Đang luyện", tint: AppTheme(isExtra: isExtra).accent)
                    if bestScore > 0 {
                        ListeningPill(text: "Cao nhất \(ListeningScoreCalculator.display(bestScore))/100", tint: .orange)
                    }
                } else {
                    ListeningPill(text: "Đã tải", tint: .green)
                }

                if isShadowingPassed {
                    ListeningPill(text: "Shadowing đã pass", tint: AppSemanticColor.success)
                    if shadowingBestScore > 0 {
                        ListeningPill(
                            text: "\(ListeningScoreCalculator.display(shadowingBestScore))/100",
                            tint: .purple
                        )
                    }
                } else if isInShadowing {
                    ListeningPill(text: "Đang Shadowing", tint: AppTheme(isExtra: isExtra).accent)
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
                    icon: "arrow.counterclockwise"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        } else if isInLearning {
            Button {
                showingDictation = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện nghe chép chính tả ngay",
                    icon: "play.fill"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        } else {
            Button {
                Task { await startPractice() }
            } label: {
                ListeningActionLabel(
                    title: isSaving
                        ? "Đang đưa vào luyện nghe chép chính tả..."
                        : "Đưa bài nghe này vào luyện nghe chép chính tả ngay",
                    icon: "graduationcap.fill"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
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
                    icon: "arrow.counterclockwise"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        } else if isInShadowing {
            Button {
                showingShadowing = true
            } label: {
                ListeningActionLabel(
                    title: "Luyện Shadowing ngay",
                    icon: "waveform.and.mic"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        } else {
            Button {
                Task { await startShadowing() }
            } label: {
                ListeningActionLabel(
                    title: isStartingShadowing
                        ? "Đang đưa vào luyện Shadowing..."
                        : "Đưa bài nghe này vào luyện Shadowing ngay",
                    icon: "waveform.and.mic"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
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
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var items: [ListeningLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    private var completedLessonCount: Int {
        items.filter(\.isCompleted).count
    }

    private var activeItems: [ListeningLibraryItem] {
        items.filter(\.isInLearning)
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }

            Group {
                if isLoading {
                    ProgressView("Đang tải tiến độ luyện nghe...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(isExtra ? .white : .primary)
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.section) {
                            progressCard
                            practiceCard
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Luyện nghe chép chính tả")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
                tint: AppSemanticColor.success
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Tiến độ bài nghe")
                    .font(AppTypography.cardTitle)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

                Text("\(completedLessonCount) / \(items.count) bài")
                    .font(.title2.bold())
                    .foregroundColor(isExtra ? .white : .primary)

                Text(items.isEmpty ? "Hãy tải một seri bài nghe từ Trang chủ." : "Số bài đã hoàn thành trên tổng bài đã tải về.")
                    .font(.subheadline)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.card)
        .appSurface(.card, isExtra: isExtra)
    }

    private var practiceCard: some View {
        NavigationLink {
            ListeningPracticeMenuView(items: activeItems)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bài đang luyện")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(isExtra ? .white : .primary)

                        Text(activeItems.isEmpty ? "Hãy vào My Listening và bấm Đưa bài này vào luyện nghe." : "Bạn đang có \(activeItems.count) bài sẵn sàng luyện.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }

                    Spacer()

                    Image(systemName: "headphones")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(activeItems.isEmpty ? (isExtra ? Color.white.opacity(0.4) : .secondary) : AppTheme(isExtra: isExtra).accent)
                }

                Label("Luyện nghe", systemImage: "play.fill")
                    .font(AppTypography.action)
                    .foregroundStyle(activeItems.isEmpty ? AppTheme(isExtra: isExtra).secondaryText : Color.white)
                    .padding(.horizontal, AppSpacing.row)
                    .padding(.vertical, AppSpacing.item)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .modifier(AppActionFill(isExtra: isExtra, enabled: !activeItems.isEmpty))
            }
            .padding(AppSpacing.card)
            .appSurface(.card, isExtra: isExtra)
        }
        .buttonStyle(.plain)
        .disabled(activeItems.isEmpty)
        .accessibilityIdentifier("listening-practice-card")
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
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var selectedItem: ListeningLibraryItem?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }

            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Chưa có bài đang luyện",
                        systemImage: "headphones",
                        description: Text("Bạn cần đưa bài từ My Listening vào Luyện nghe trước.")
                    )
                    .foregroundStyle(isExtra ? .white : .primary)
                } else {
                    List {
                        Section("Bài đang luyện") {
                            ForEach(items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    ListeningLibraryLessonRow(item: item, isExtra: isExtra)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollContentBackground(isExtra ? .hidden : .automatic)
                }
            }
        }
        .navigationTitle("Chọn bài luyện")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
    var showChevron: Bool = true

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

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
                    .fill(isExtra ? ExtraAuroraPalette.violet.opacity(0.2) : Color.blue.opacity(0.12))
                    .frame(width: 50, height: 50)

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22))
                    .foregroundColor(isExtra ? ExtraAuroraPalette.violet : .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogItem.series.title)
                    .font(AppTypography.cardTitle)
                    .foregroundColor(isExtra ? Color.white : .primary)
                    .lineLimit(1)

                Text("\(catalogItem.lessons.count) bài nghe")
                    .font(.caption)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            }

            Spacer(minLength: 6)

            if downloadedCount > 0, missingCount == 0 {
                catalogStatusBadge(text: "Đã tải", tint: AppSemanticColor.success)
            } else if downloadedCount > 0 {
                catalogStatusBadge(text: "+\(missingCount)", tint: AppSemanticColor.attention)
            } else {
                catalogStatusBadge(text: "Mới", tint: isExtra ? ExtraAuroraPalette.electricBlue : .blue)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(isExtra ? Color.white.opacity(0.4) : .secondary)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func catalogStatusBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

private struct ListeningLibrarySeriesRow: View {
    let seriesItem: ListeningSeriesLibraryItem
    var isExtra: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(seriesItem.series.title)
                        .font(AppTypography.cardTitle)
                        .foregroundColor(isExtra ? .white : .primary)

                    if seriesItem.learningLessonCount > 0 {
                        ListeningPill(text: "\(seriesItem.learningLessonCount) đang luyện", tint: .orange)
                    }

                    if seriesItem.shadowingLessonCount > 0 {
                        ListeningPill(text: "\(seriesItem.shadowingLessonCount) Shadowing", tint: .purple)
                    }
                }

                Text("\(seriesItem.lessons.count) bài nghe")
                    .font(.subheadline)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ListeningLibraryLessonRow: View {
    let item: ListeningLibraryItem
    var summary: ListeningLessonSummary? = nil
    var isExtra: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.lesson.title)
                .font(AppTypography.cardTitle)
                .foregroundColor(isExtra ? .white : .primary)
                .lineLimit(2)

            FlowLayout(spacing: 6) {
                if let cefr = item.lesson.cefr, !cefr.isEmpty {
                    ListeningPill(text: cefr, tint: isExtra ? ExtraAuroraPalette.ice : .blue)
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
                    ListeningPill(text: "Đã tải", tint: isExtra ? ExtraAuroraPalette.ice : .blue)
                }

                if item.isShadowingCompleted {
                    ListeningPill(text: "Shadowing đã pass", tint: AppSemanticColor.success)
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
                    .foregroundColor(isExtra ? Color.white.opacity(0.85) : .primary)
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
            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct ListeningSeriesLessonRow: View {
    let summary: ListeningLessonSummary
    let isNew: Bool
    var isExtra: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(summary.lesson.title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)

                if isNew {
                    Text("Mới")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppSemanticColor.attention)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppSemanticColor.attention.opacity(0.12)))
                }

                Spacer()
            }

            if let viTitle = summary.lesson.vi_title, !viTitle.isEmpty {
                Text(viTitle)
                    .font(.body)
                    .foregroundStyle(isExtra ? Color.white.opacity(0.85) : .primary)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                if let cefr = summary.lesson.cefr, !cefr.isEmpty {
                    Text(cefr)
                        .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    Text("•")
                        .foregroundColor(isExtra ? Color.white.opacity(0.5) : .secondary)
                }
                Text("\(summary.segmentCount) câu")
                if summary.durationSeconds > 0 {
                    Text("•")
                        .foregroundColor(isExtra ? Color.white.opacity(0.5) : .secondary)
                    Text(ListeningDurationFormatter.text(summary.durationSeconds))
                }
            }
            .font(.subheadline)
            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
        }
    }
}

private struct ListeningSegmentDetailRow: View {
    let segment: ListeningSegment
    let isPlaying: Bool
    var isExtra: Bool = false
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(segment.english_text)
                    .font(.body.weight(.semibold))
                    .foregroundColor(isExtra ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(isExtra ? ExtraAuroraPalette.iceCyan : .blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe câu \(segment.order_index)")
            }

            if let vietnamese = segment.vietnamese_text, !vietnamese.isEmpty {
                listeningDetailRow(title: "Nghĩa Tiếng Việt", content: vietnamese, isExtra: isExtra)
            }

            if let ipa = segment.ipa, !ipa.isEmpty {
                listeningDetailRow(title: "Phát âm (IPA)", content: ipa, color: isExtra ? ExtraAuroraPalette.iceCyan : .blue, isExtra: isExtra)
            }
        }
        .padding(.vertical, 4)
    }

    private func listeningDetailRow(title: String, content: String, color: Color = .primary, isExtra: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            Text(content)
                .foregroundColor(color == .primary && isExtra ? Color.white.opacity(0.85) : color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct ListeningActionLabel: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon).fixedSize(horizontal: false, vertical: true)
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
                .font(AppTypography.cardTitle)
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
