import AVFoundation
import SwiftUI

struct ListeningDictationView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    let lesson: ListeningLesson
    var startsNewAttempt = false
    var onFinished: () -> Void = {}

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = ListeningAudioPlayer()

    @State private var segments: [ListeningSegment] = []
    @State private var currentIndex = 0
    @State private var answerText = ""
    @State private var completedSegmentIds: Set<String> = []
    @State private var resultsBySegmentId: [String: ListeningSentenceResult] = [:]
    @State private var hintedWordIndices: Set<Int> = []
    @State private var hintedWordIndicesBySegmentId: [String: Set<Int>] = [:]
    @State private var completedLessonScore: Double?
    @State private var bestLessonScore = 0.0
    @State private var playbackRate: Float = 1
    @State private var isLoading = true
    @State private var isRecordingProgress = false
    @State private var isFinishingLesson = false
    @State private var isRestartingLesson = false
    @State private var activitySessionID = UUID()
    @State private var didKeepStreak = false
    @State private var completedSession = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var currentSegment: ListeningSegment? {
        guard segments.indices.contains(currentIndex) else { return nil }
        return segments[currentIndex]
    }

    private var maskProgress: ListeningMaskProgress {
        guard let currentSegment else {
            return ListeningMaskProgress(fullCorrectWordCount: 0, partialWord: nil, hasMistake: false, isComplete: false)
        }
        return ListeningTextMasker.progress(target: currentSegment.english_text, input: answerText)
    }

    private var currentLessonScore: Double {
        ListeningScoreCalculator.lessonScore(
            results: Array(resultsBySegmentId.values),
            totalSentenceCount: segments.count
        )
    }

    private var lessonHasPassed: Bool {
        ListeningScoreCalculator.hasPassed(score: bestLessonScore)
    }

    private var isReviewingCurrentSegment: Bool {
        guard let currentSegment else { return false }
        return completedSegmentIds.contains(currentSegment.id)
    }

    private var canMoveForward: Bool {
        guard let currentSegment else { return false }
        return completedSegmentIds.contains(currentSegment.id)
            || (maskProgress.isComplete && !isRecordingProgress)
    }

    private var currentTiles: [ListeningWordTile] {
        guard let currentSegment else { return [] }
        return ListeningTextMasker.wordTiles(
            target: currentSegment.english_text,
            input: answerText,
            hintedWordIndices: hintedWordIndices
        )
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
                    ProgressView("Đang tải câu nghe...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(isExtra ? .white : .primary)
                } else if segments.isEmpty {
                    ContentUnavailableView(
                        "Bài này chưa có câu nghe",
                        systemImage: "waveform.slash",
                        description: Text("Bạn kiểm tra lại dữ liệu import lesson trong Supabase nha.")
                    )
                } else if let completedLessonScore {
                    completionContent(score: completedLessonScore)
                } else {
                    lessonContent
                }
            }
        }
        .streakRescueWarning(onLeave: { exitPracticeRoom() })
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    exitPracticeRoom()
                } label: {
                    Text("Thoát")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isLoading, !segments.isEmpty, completedLessonScore == nil {
                practiceControlPanel
            }
        }
        .task {
            await loadSegments()
        }
        .onDisappear {
            audioPlayer.stop()
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

    private var lessonContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                progressHeader

                if let currentSegment {
                    dictationInput(for: currentSegment)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.row)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.clear)
    }

    private func completionContent(score: Double) -> some View {
        let attemptPassed = ListeningScoreCalculator.hasPassed(score: score)
        let resultTint: Color = attemptPassed || lessonHasPassed ? AppSemanticColor.success : AppSemanticColor.attention

        return ScrollView {
            VStack(spacing: 22) {
                Image(systemName: attemptPassed || lessonHasPassed ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 58))
                    .foregroundColor(resultTint)

                VStack(spacing: 6) {
                    Text(resultTitle(score: score))
                        .font(AppTypography.metric)
                        .multilineTextAlignment(.center)

                    Text(resultSubtitle(score: score))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    Circle()
                        .stroke(resultTint.opacity(0.16), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: Double(score) / 100)
                        .stroke(resultTint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(ListeningScoreCalculator.display(score))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(resultTint)
                        Text("/ 100 điểm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 170, height: 170)

                resultSummary(tint: resultTint)

                Button {
                    Task { await restartLesson() }
                } label: {
                    Label(
                        isRestartingLesson
                            ? "Đang chuẩn bị..."
                            : (lessonHasPassed ? "Luyện lại từ đầu" : "Luyện lại để đạt 80 điểm"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .font(AppTypography.action)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.row)
                    .padding(.vertical, AppSpacing.item)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .modifier(AppActionFill(isExtra: isExtra))
                }
                .disabled(isRestartingLesson)

                Button("Quay lại") {
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
            }
            .padding(24)
        }
        .background(Color.clear)
    }

    private func resultTitle(score: Double) -> String {
        if ListeningScoreCalculator.hasPassed(score: score) {
            return "Đã pass bài luyện nghe"
        }
        return lessonHasPassed ? "Hoàn thành lượt luyện" : "Chưa đạt 80 điểm"
    }

    private func resultSubtitle(score: Double) -> String {
        if ListeningScoreCalculator.hasPassed(score: score) {
            return lesson.title
        }
        if lessonHasPassed {
            return "Bài này đã pass trước đó. Lượt luyện này đạt \(ListeningScoreCalculator.display(score))/100 điểm."
        }
        let remainingScore = max(ListeningScoreCalculator.passingScore - score, 0)
        return "Bạn cần thêm \(ListeningScoreCalculator.display(remainingScore)) điểm để pass bài này."
    }

    private func resultSummary(tint: Color) -> some View {
        let totalWordCount = resultsBySegmentId.values.reduce(0) { $0 + $1.wordCount }
        let hintedWordCount = resultsBySegmentId.values.reduce(0) { $0 + $1.hintedWordCount }

        return VStack(spacing: 12) {
            resultSummaryRow(title: "Số câu hoàn thành", value: "\(segments.count)/\(segments.count)")
            resultSummaryRow(title: "Từ tự nghe đúng", value: "\(max(totalWordCount - hintedWordCount, 0))/\(totalWordCount)")
            resultSummaryRow(title: "Từ đã dùng gợi ý", value: "\(hintedWordCount)")
            resultSummaryRow(
                title: "Điểm cao nhất",
                value: "\(ListeningScoreCalculator.display(max(bestLessonScore, completedLessonScore ?? 0)))/100"
            )
        }
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }

    private func resultSummaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(isExtra ? .white : .primary)
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Câu \(currentIndex + 1)/\(segments.count)", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isExtra ? .white : .primary)

                Spacer(minLength: 8)

                if let duration = currentSegment?.duration_seconds {
                    Text(durationText(duration))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                }

                Text("\(ListeningScoreCalculator.display(currentLessonScore))/100")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppSemanticColor.attention)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(7)
            }

            ProgressView(value: Double(currentIndex + 1), total: Double(max(segments.count, 1)))
                .tint(AppTheme(isExtra: isExtra).accent)
        }
    }

    private func dictationInput(for segment: ListeningSegment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Nhập câu bạn nghe được", text: $answerText, axis: .vertical)
                .focused($isInputFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.next)
                .padding(16)
                .background(
                    isExtra
                        ? AnyShapeStyle(Color.white.opacity(0.12))
                        : AnyShapeStyle(Color(UIColor.systemBackground))
                )
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(inputBorderColor, lineWidth: 2)
                )
                .foregroundStyle(isExtra ? .white : .primary)
                .disabled(isReviewingCurrentSegment)
                .onSubmit {
                    if canMoveForward {
                        moveToNextSegment()
                    }
                }
                .onChange(of: answerText) { _, _ in
                    handleAnswerChanged(segment)
                }

            if isReviewingCurrentSegment {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Câu đã hoàn thành", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppSemanticColor.success)

                    if let vietnameseText = segment.vietnamese_text, !vietnameseText.isEmpty {
                        Text(vietnameseText)
                            .font(.subheadline)
                            .foregroundColor(isExtra ? Color.white.opacity(0.85) : .primary)
                    }

                    if let ipa = segment.ipa, !ipa.isEmpty {
                        Text(ipa)
                            .font(.subheadline)
                            .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    }
                }
            } else if maskProgress.hasMistake {
                Label("Từ đang sai hiển thị màu đỏ, hãy sửa rồi tiếp tục.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if maskProgress.isComplete {
                HStack(spacing: 6) {
                    Label("Chính xác", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppSemanticColor.success)

                    if let result = resultsBySegmentId[segment.id] {
                        Text(sentencePointText(result))
                            .font(.caption.bold())
                            .foregroundColor(AppSemanticColor.attention)
                    } else if isRecordingProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var inputBorderColor: Color {
        if isReviewingCurrentSegment || maskProgress.isComplete { return AppSemanticColor.success }
        if maskProgress.hasMistake { return AppSemanticColor.error }
        return isInputFocused ? .blue : Color.secondary.opacity(0.25)
    }

    private var practiceControlPanel: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chạm vào từng từ để xem gợi ý")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(currentTiles) { tile in
                                ListeningWordHintChip(tile: tile) {
                                    revealHint(at: tile.index)
                                }
                                .id(tile.id)
                                .disabled(isReviewingCurrentSegment || tile.state == .correct || tile.state == .hinted)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onAppear {
                        scrollToActiveWord(using: proxy)
                    }
                    .onChange(of: activeWordIndex) { _, _ in
                        scrollToActiveWord(using: proxy)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                iconControlButton(
                    icon: "chevron.left",
                    label: "Câu trước",
                    isEnabled: currentIndex > 0
                ) {
                    moveToPreviousSegment()
                }

                if let currentSegment {
                    iconControlButton(
                        icon: "gobackward",
                        label: "Nghe lại từ đầu",
                        isEnabled: true
                    ) {
                        replayCurrentSegment(currentSegment)
                    }

                    Button {
                        togglePlayback(for: currentSegment)
                    } label: {
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(AppTheme(isExtra: isExtra).primaryGradient)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audioPlayer.isPlaying ? "Tạm dừng audio" : "Phát audio")
                }

                speedPicker

                iconControlButton(
                    icon: currentIndex == segments.count - 1 ? "checkmark" : "chevron.right",
                    label: currentIndex == segments.count - 1 ? "Hoàn thành bài" : "Câu tiếp theo",
                    isEnabled: canMoveForward && !isFinishingLesson
                ) {
                    moveToNextSegment()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .appActionBar()
    }

    private var speedPicker: some View {
        Menu {
            ForEach([Float(0.5), 0.75, 1, 1.25, 1.5], id: \.self) { rate in
                Button {
                    playbackRate = rate
                    audioPlayer.setPlaybackRate(rate)
                } label: {
                    Label(
                        playbackRateLabel(rate),
                        systemImage: playbackRate == rate ? "checkmark" : "speedometer"
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "speedometer")
                Text(playbackRateLabel(playbackRate))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.bold))
            .foregroundColor(isExtra ? .white : .primary)
            .frame(minWidth: 72, minHeight: 44)
            .background(isExtra ? Color.white.opacity(0.12) : Color.secondary.opacity(0.12))
            .cornerRadius(10)
        }
        .accessibilityLabel("Tốc độ phát \(playbackRateLabel(playbackRate))")
    }

    private func iconControlButton(
        icon: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundColor(isEnabled ? (isExtra ? Color.white : .primary) : (isExtra ? Color.white.opacity(0.3) : .secondary.opacity(0.4)))
                .frame(width: 38, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private var activeWordIndex: Int {
        guard !currentTiles.isEmpty else { return 0 }
        return min(maskProgress.fullCorrectWordCount, currentTiles.count - 1)
    }

    private func scrollToActiveWord(using proxy: ScrollViewProxy) {
        guard !currentTiles.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(activeWordIndex, anchor: .center)
        }
    }

    private func playbackRateLabel(_ rate: Float) -> String {
        rate == 1 ? "1x" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))x"
    }

    private func durationText(_ duration: Double) -> String {
        "\(max(Int(duration.rounded()), 1)) giây"
    }

    private func sentencePointText(_ result: ListeningSentenceResult) -> String {
        guard !segments.isEmpty, result.wordCount > 0 else { return "+0 điểm" }
        let maximumPoints = 100.0 / Double(segments.count)
        let earnedFraction = Double(result.wordCount - result.hintedWordCount) / Double(result.wordCount)
        let earnedPoints = maximumPoints * earnedFraction
        return "+\(ListeningScoreCalculator.display(earnedPoints))/\(ListeningScoreCalculator.display(maximumPoints)) điểm"
    }

    @MainActor
    private func loadSegments() async {
        isLoading = true
        do {
            let loadedSegments = try await ListeningRepository.fetchSegments(lessonId: lesson.id)
            var savedProgress: [ListeningProgress] = []
            var lessonEntry: UserListeningLesson?

            if let userId = AuthManager.shared.currentUser?.id.uuidString {
                async let progressRequest = ListeningRepository.fetchListeningProgress(userId: userId)
                async let lessonEntryRequest = ListeningRepository.fetchUserLessonEntry(
                    userId: userId,
                    lessonId: lesson.id
                )
                (savedProgress, lessonEntry) = try await (progressRequest, lessonEntryRequest)
            }

            let lessonSegmentIds = Set(loadedSegments.map(\.id))
            let segmentById = Dictionary(uniqueKeysWithValues: loadedSegments.map { ($0.id, $0) })
            let lessonProgress = savedProgress.filter { lessonSegmentIds.contains($0.segment_id) }
            let completedProgress = lessonProgress.filter { $0.status == "completed" }

            segments = loadedSegments
            completedSegmentIds = Set(completedProgress.map(\.segment_id))
            let completedResults = completedProgress.compactMap { progress -> (String, ListeningSentenceResult)? in
                guard let segment = segmentById[progress.segment_id] else { return nil }
                let fallbackWordCount = ListeningTextMasker.normalizedWords(segment.english_text).count
                let wordCount = max(progress.word_count ?? segment.word_count ?? fallbackWordCount, 1)
                let hintedWordCount = min(max(progress.hinted_word_count ?? 0, 0), wordCount)
                let savedHintIndexes = (progress.hinted_word_indexes ?? Array(0..<hintedWordCount))
                    .filter { (0..<wordCount).contains($0) }
                let hintedWordIndices = Set(savedHintIndexes)
                return (
                    progress.segment_id,
                    ListeningSentenceResult(
                        wordCount: wordCount,
                        hintedWordCount: hintedWordCount,
                        hintedWordIndices: hintedWordIndices
                    )
                )
            }
            resultsBySegmentId = Dictionary(uniqueKeysWithValues: completedResults)
            hintedWordIndicesBySegmentId = Dictionary(
                uniqueKeysWithValues: completedResults.map { ($0.0, $0.1.hintedWordIndices) }
            )
            bestLessonScore = lessonEntry?.best_score ?? 0
            currentIndex = loadedSegments.firstIndex { !completedSegmentIds.contains($0.id) } ?? 0

            if !loadedSegments.isEmpty, completedSegmentIds.count == loadedSegments.count {
                if startsNewAttempt, AuthManager.shared.currentUser != nil {
                    try await ListeningRepository.restartLesson(lessonId: lesson.id)
                    activitySessionID = UUID()
                    completedSession = false
                    didKeepStreak = false
                    completedSegmentIds = []
                    resultsBySegmentId = [:]
                    hintedWordIndicesBySegmentId = [:]
                    currentIndex = 0
                    onFinished()
                } else {
                    completedLessonScore = lessonEntry?.latest_score ?? currentLessonScore
                    bestLessonScore = max(bestLessonScore, completedLessonScore ?? 0)
                }
            }
        } catch {
            errorMessage = "Không tải được nội dung bài nghe: \(error.localizedDescription)"
        }
        isLoading = false
        if completedLessonScore == nil {
            selectSegment(at: currentIndex, focusInput: true)
        }
    }

    private func togglePlayback(for segment: ListeningSegment) {
        do {
            let url = try ListeningRepository.publicAudioURL(for: segment)
            audioPlayer.toggle(url: url, rate: playbackRate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replayCurrentSegment(_ segment: ListeningSegment) {
        do {
            let url = try ListeningRepository.publicAudioURL(for: segment)
            audioPlayer.replay(url: url, rate: playbackRate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revealHint(at wordIndex: Int) {
        guard let currentSegment, !isReviewingCurrentSegment else { return }
        guard currentTiles.indices.contains(wordIndex) else { return }
        hintedWordIndices.insert(wordIndex)
        hintedWordIndicesBySegmentId[currentSegment.id] = hintedWordIndices
    }

    private func handleAnswerChanged(_ segment: ListeningSegment) {
        guard ListeningTextMasker.progress(target: segment.english_text, input: answerText).isComplete else { return }
        guard !completedSegmentIds.contains(segment.id), !isRecordingProgress else { return }

        let wordCount = max(ListeningTextMasker.normalizedWords(segment.english_text).count, 1)
        let result = ListeningSentenceResult(
            wordCount: wordCount,
            hintedWordCount: min(hintedWordIndices.count, wordCount),
            hintedWordIndices: hintedWordIndices
        )
        isInputFocused = false
        isRecordingProgress = true
        Task {
            do {
                if AuthManager.shared.currentUser != nil {
                    try await ListeningRepository.recordSegmentCompleted(
                        segmentId: segment.id,
                        result: result
                    )
                }

                await MainActor.run {
                    resultsBySegmentId[segment.id] = result
                    hintedWordIndicesBySegmentId[segment.id] = hintedWordIndices
                    completedSegmentIds.insert(segment.id)
                    isRecordingProgress = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Đã đúng câu, nhưng chưa lưu được tiến độ: \(error.localizedDescription)"
                    isRecordingProgress = false
                }
            }
        }
    }

    private func moveToNextSegment() {
        guard canMoveForward else { return }

        if currentIndex < segments.count - 1 {
            selectSegment(at: currentIndex + 1, focusInput: true)
        } else {
            isInputFocused = false
            Task { await finishLesson() }
        }
    }

    private func moveToPreviousSegment() {
        guard currentIndex > 0 else { return }
        selectSegment(at: currentIndex - 1, focusInput: false)
    }

    private func exitPracticeRoom() {
        audioPlayer.stop()
        onFinished()
        dismiss()
        if completedSession {
            NotificationCenter.default.post(name: didKeepStreak ? .returnToHomeAfterLearning : .returnToLearningTab, object: nil)
        }
    }

    private func selectSegment(at index: Int, focusInput: Bool) {
        guard segments.indices.contains(index) else { return }

        audioPlayer.stop()
        currentIndex = index
        let segment = segments[index]

        if completedSegmentIds.contains(segment.id) {
            answerText = segment.english_text
            hintedWordIndices = hintedWordIndicesBySegmentId[segment.id] ?? []
            isInputFocused = false
        } else {
            answerText = ""
            hintedWordIndices = hintedWordIndicesBySegmentId[segment.id] ?? []
            if focusInput {
                DispatchQueue.main.async {
                    isInputFocused = true
                }
            }
        }
    }

    @MainActor
    private func finishLesson() async {
        isInputFocused = false
        isFinishingLesson = true
        defer { isFinishingLesson = false }

        do {
            let score: Double
            if AuthManager.shared.currentUser != nil {
                score = try await ListeningRepository.markLessonCompleted(lessonId: lesson.id)
                if let userId = AuthManager.shared.currentUser?.id.uuidString {
                    didKeepStreak = try await UserProgressRepository.recordDailyActivityAndUpdateStreak(userId: userId, sessionId: activitySessionID)
                }
            } else {
                score = currentLessonScore
            }
            completedSession = true
            completedLessonScore = score
            bestLessonScore = max(bestLessonScore, score)
            onFinished()
        } catch {
            errorMessage = "Bạn đã hoàn thành bài, nhưng chưa lưu được trạng thái bài nghe: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func restartLesson() async {
        isRestartingLesson = true
        defer { isRestartingLesson = false }

        do {
            if AuthManager.shared.currentUser != nil {
                try await ListeningRepository.restartLesson(lessonId: lesson.id)
            }

            audioPlayer.stop()
            activitySessionID = UUID()
            completedSession = false
            didKeepStreak = false
            completedSegmentIds = []
            resultsBySegmentId = [:]
            hintedWordIndices = []
            hintedWordIndicesBySegmentId = [:]
            answerText = ""
            currentIndex = 0
            completedLessonScore = nil
            selectSegment(at: 0, focusInput: true)
            onFinished()
        } catch {
            errorMessage = "Không thể bắt đầu lượt luyện mới: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class ListeningAudioPlayer: ObservableObject {
    @Published var isPlaying = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var playbackRate: Float = 1

    func play(url: URL, rate: Float = 1) {
        stop()

        let player = AVPlayer(url: url)
        self.player = player
        playbackRate = rate

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player?.seek(to: .zero)
                self?.isPlaying = false
            }
        }

        player.playImmediately(atRate: rate)
        isPlaying = true
    }

    func toggle(url: URL, rate: Float) {
        playbackRate = rate

        guard let player else {
            play(url: url, rate: rate)
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    func replay(url: URL, rate: Float) {
        play(url: url, rate: rate)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
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

private struct ListeningWordHintChip: View {
    let tile: ListeningWordTile
    let onTap: () -> Void

    private var tint: Color {
        switch tile.state {
        case .hidden:
            return .secondary
        case .partial:
            return .blue
        case .correct:
            return AppSemanticColor.success
        case .wrong:
            return AppSemanticColor.error
        case .hinted:
            return AppSemanticColor.attention
        }
    }

    private var background: Color {
        tint.opacity(tile.state == .hidden ? 0.12 : 0.16)
    }

    var body: some View {
        Button(action: onTap) {
            Text(tile.displayText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 42, minHeight: 42)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                )
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Từ \(tile.index + 1): \(tile.displayText)")
    }
}
