import SwiftUI

struct ShadowingPracticeView: View {
    let lesson: ListeningLesson
    var onFinished: () -> Void = {}

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sampleAudioPlayer = ListeningAudioPlayer()
    @StateObject private var pronunciationManager = PronunciationManager()

    @State private var segments: [ListeningSegment] = []
    @State private var currentIndex = 0
    @State private var passedSegmentIds: Set<String> = []
    @State private var attemptedSegmentIds: Set<String> = []
    @State private var bestLessonScore = 0.0
    @State private var assessment: AzurePronunciationAssessment?
    @State private var playbackRate: Float = 1
    @State private var selectedWordIndex: Int?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var activitySessionID = UUID()
    @State private var didKeepStreak = false
    @State private var streakRecorded = false
    @State private var completedThisSession = false
    @State private var isShowingCompletion = false
    @State private var errorMessage: String?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    private var currentSegment: ListeningSegment? {
        guard segments.indices.contains(currentIndex) else { return nil }
        return segments[currentIndex]
    }

    private var completedSentenceCount: Int {
        passedSegmentIds.count
    }

    private var lessonIsCompleted: Bool {
        !segments.isEmpty && completedSentenceCount >= segments.count
    }

    private var currentHasAttempt: Bool {
        guard let currentSegment else { return false }
        return attemptedSegmentIds.contains(currentSegment.id)
    }

    private var currentIsPassed: Bool {
        guard let currentSegment else { return false }
        return passedSegmentIds.contains(currentSegment.id)
    }

    private var didCurrentAttemptPass: Bool {
        assessment?.shadowingProgress?.attemptPassed
            ?? assessment.map(ShadowingPassingRule.passes)
            ?? false
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
                    ProgressView("Đang tải bài Shadowing...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(isExtra ? .white : .primary)
                } else if segments.isEmpty {
                    ContentUnavailableView(
                        "Bài này chưa có câu luyện",
                        systemImage: "waveform.slash",
                        description: Text("Bạn kiểm tra lại dữ liệu bài nghe trong Supabase.")
                    )
                    .foregroundStyle(isExtra ? .white : .primary)
                } else if isShowingCompletion {
                    completionContent
                } else {
                    practiceContent
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
                Button("Thoát") {
                    exitPracticeRoom()
                }
                .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isLoading, !segments.isEmpty, !isShowingCompletion {
                practiceControlPanel
            }
        }
        .task {
            await loadPractice()
        }
        .onDisappear {
            sampleAudioPlayer.stop()
            if pronunciationManager.isRecording {
                pronunciationManager.stopRecording()
            }
            pronunciationManager.stopPlayback()
        }
        .alert("Thông báo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: wordFeedbackSheetPresented) {
            selectedWordFeedbackSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var practiceContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                progressHeader

                if let currentSegment {
                    referenceCard(for: currentSegment)
                    sampleControls(for: currentSegment)
                    recordingSection

                    if let assessment {
                        assessmentResult(assessment)
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.top, AppSpacing.row)
            .padding(.bottom, 28)
        }
        .background(Color.clear)
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Câu \(currentIndex + 1)/\(segments.count)", systemImage: "waveform.and.mic")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isExtra ? .white : .primary)

                Spacer(minLength: 8)

                Text("\(completedSentenceCount)/\(segments.count) đạt")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppTheme(isExtra: isExtra).accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme(isExtra: isExtra).accent.opacity(0.12))
                    .cornerRadius(7)
            }

            ProgressView(
                value: Double(currentIndex + 1),
                total: Double(max(segments.count, 1))
            )
            .tint(AppTheme(isExtra: isExtra).accent)
        }
    }

    private func referenceCard(for segment: ListeningSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Câu mẫu", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isExtra ? ExtraAuroraPalette.champagne : .purple)

                Spacer()

                if currentIsPassed {
                    Label("Đã đạt", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppSemanticColor.success)
                }
            }

            Text(segment.english_text)
                .font(.title3.weight(.semibold))
                .foregroundColor(isExtra ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if let vietnamese = segment.vietnamese_text, !vietnamese.isEmpty {
                Text(vietnamese)
                    .font(.subheadline)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ipa = segment.ipa, !ipa.isEmpty {
                Text(ipa)
                    .font(.subheadline)
                    .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }

    private func sampleControls(for segment: ListeningSegment) -> some View {
        HStack(spacing: 12) {
            Button {
                playSample(segment)
            } label: {
                Label(
                    sampleAudioPlayer.isPlaying ? "Dừng câu mẫu" : "Nghe câu mẫu",
                    systemImage: sampleAudioPlayer.isPlaying ? "stop.fill" : "play.fill"
                )
                .font(AppTypography.action)
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.row)
                .padding(.vertical, AppSpacing.item)
                .frame(maxWidth: .infinity, minHeight: 52)
                .modifier(AppActionFill(isExtra: isExtra))
            }
            .buttonStyle(.plain)

            speedPicker
        }
    }

    private var recordingSection: some View {
        VStack(spacing: 14) {
            if pronunciationManager.hasRecorded {
                Button {
                    if pronunciationManager.isPlaying {
                        pronunciationManager.stopPlayback()
                    } else {
                        pronunciationManager.playRecordedAudio()
                    }
                } label: {
                    Label(
                        pronunciationManager.isPlaying ? "Dừng nghe" : "Nghe lại giọng của bạn",
                        systemImage: pronunciationManager.isPlaying ? "stop.fill" : "person.wave.2.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .secondary))
            }

            Button {
                toggleRecording()
            } label: {
                Image(systemName: pronunciationManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 68))
                    .foregroundColor(pronunciationManager.isRecording ? AppSemanticColor.attention : AppTheme(isExtra: isExtra).accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordingInstruction)

            Text(recordingInstruction)
                .font(.subheadline)
                .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

            if pronunciationManager.hasRecorded, assessment == nil {
                Button {
                    submitRecording()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(isSubmitting ? "Đang chấm..." : "Chấm phát âm")
                    }
                    .font(AppTypography.action)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.row)
                    .padding(.vertical, AppSpacing.item)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .modifier(AppActionFill(isExtra: isExtra))
                }
                .disabled(isSubmitting)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }

    private func assessmentResult(_ assessment: AzurePronunciationAssessment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Kết quả phát âm")
                    .font(AppTypography.cardTitle)
                    .foregroundColor(isExtra ? Color.white.opacity(0.85) : .secondary)

                Spacer()

                if didCurrentAttemptPass {
                    Label("Đạt", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppSemanticColor.success)
                } else if currentIsPassed {
                    Label("Đã đạt từ trước", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppSemanticColor.success)
                } else {
                    Label("Chưa đạt", systemImage: "exclamationmark.circle.fill")
                        .font(AppTypography.label)
                        .foregroundColor(AppSemanticColor.attention)
                }
            }

            if let transcript = displayTranscript(from: assessment) {
                Text("Bạn đọc: \(transcript)")
                    .font(.subheadline)
                    .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isExtra ? ExtraAuroraPalette.ice.opacity(0.12) : Color.blue.opacity(0.08))
                    )
            }

            if !assessment.words.isEmpty {
                wordFeedbackSection(assessment.words)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ScoreCircle(title: "Tổng", score: assessment.scores.pronunciation, color: .purple)
                ScoreCircle(title: "Chính xác", score: assessment.scores.accuracy, color: .blue)
                ScoreCircle(title: "Trôi chảy", score: assessment.scores.fluency, color: .green)
                ScoreCircle(title: "Đầy đủ", score: assessment.scores.completeness, color: .orange)
            }

            if !didCurrentAttemptPass {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hãy nghe lại câu mẫu và bấm mic để thu lại.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)

                    ForEach(ShadowingPassingRule.failureReasons(for: assessment), id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }

    private var practiceControlPanel: some View {
        HStack(spacing: 14) {
            controlButton(
                icon: "chevron.left",
                label: "Câu trước",
                enabled: currentIndex > 0
            ) {
                selectSegment(at: currentIndex - 1)
            }

            if let currentSegment {
                Button {
                    replaySample(currentSegment)
                } label: {
                    Image(systemName: "gobackward")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppTheme(isExtra: isExtra).accent)
                        .frame(width: 44, height: 44)
                        .background(AppTheme(isExtra: isExtra).accent.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe lại câu mẫu")
            }

            speedPicker

            controlButton(
                icon: currentIndex == segments.count - 1 ? "checkmark" : "chevron.right",
                label: currentIndex == segments.count - 1 ? "Hoàn thành bài" : "Câu tiếp theo",
                enabled: currentHasAttempt && !isSubmitting
            ) {
                moveForward()
            }
        }
        .frame(maxWidth: .infinity)
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
                    sampleAudioPlayer.setPlaybackRate(rate)
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

    private var completionContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundColor(AppSemanticColor.success)

                VStack(spacing: 6) {
                    Text("Đã pass bài Shadowing")
                        .font(AppTypography.metric)
                        .foregroundColor(isExtra ? .white : .primary)
                        .multilineTextAlignment(.center)

                    Text(lesson.title)
                        .font(.subheadline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    Circle()
                        .stroke(AppSemanticColor.success.opacity(0.16), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(max(bestLessonScore / 100, 0), 1))
                        .stroke(AppSemanticColor.success, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(ListeningScoreCalculator.display(bestLessonScore))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(AppTheme(isExtra: isExtra).accent)
                        Text("điểm tốt nhất")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }
                }
                .frame(width: 170, height: 170)

                VStack(spacing: 10) {
                    completionRow(title: "Câu đã đạt", value: "\(completedSentenceCount)/\(segments.count)")
                    completionRow(title: "Điểm bài", value: "\(ListeningScoreCalculator.display(bestLessonScore))/100")
                }
                .padding(AppSpacing.row)
                .appSurface(.row, isExtra: isExtra)

                Button {
                    isShowingCompletion = false
                    activitySessionID = UUID()
                    completedThisSession = false
                    passedSegmentIds = []
                    attemptedSegmentIds = []
                    streakRecorded = false
                    didKeepStreak = false
                    selectSegment(at: 0)
                } label: {
                    Label("Luyện lại", systemImage: "arrow.counterclockwise")
                        .font(AppTypography.action)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .modifier(AppActionFill(isExtra: isExtra))
                }

                Button("Quay lại") {
                    exitPracticeRoom()
                }
                .font(AppTypography.cardTitle)
                .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
            }
            .padding(24)
        }
        .background(Color.clear)
    }

    private func completionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(isExtra ? .white : .primary)
        }
    }

    @MainActor
    private func loadPractice() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedSegments = try await ListeningRepository.fetchSegments(lessonId: lesson.id)
            var savedProgress: [ShadowingProgress] = []
            var entry: UserListeningLesson?

            if let userId = AuthManager.shared.currentUser?.id.uuidString {
                async let progressRequest = ListeningRepository.fetchShadowingProgress(userId: userId)
                async let entryRequest = ListeningRepository.fetchUserLessonEntry(userId: userId, lessonId: lesson.id)
                (savedProgress, entry) = try await (progressRequest, entryRequest)
            }

            let lessonSegmentIds = Set(loadedSegments.map(\.id))
            let lessonProgress = savedProgress.filter { lessonSegmentIds.contains($0.segment_id) }

            segments = loadedSegments
            passedSegmentIds = Set(lessonProgress.filter(\.isPassed).map(\.segment_id))
            attemptedSegmentIds = Set(lessonProgress.map(\.segment_id))
            bestLessonScore = entry?.shadowing_best_score ?? 0
            currentIndex = loadedSegments.firstIndex { !passedSegmentIds.contains($0.id) } ?? 0
            if lessonIsCompleted { isShowingCompletion = true }
        } catch {
            errorMessage = "Không tải được bài Shadowing: \(error.localizedDescription)"
        }
    }

    private func selectSegment(at index: Int) {
        guard segments.indices.contains(index) else { return }

        sampleAudioPlayer.stop()
        if pronunciationManager.isRecording {
            pronunciationManager.stopRecording()
        }
        pronunciationManager.resetRecordingState()
        assessment = nil
        selectedWordIndex = nil
        currentIndex = index
    }

    private func playSample(_ segment: ListeningSegment) {
        do {
            let url = try ListeningRepository.publicAudioURL(for: segment)
            sampleAudioPlayer.toggle(url: url, rate: playbackRate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replaySample(_ segment: ListeningSegment) {
        do {
            let url = try ListeningRepository.publicAudioURL(for: segment)
            sampleAudioPlayer.replay(url: url, rate: playbackRate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleRecording() {
        if pronunciationManager.isRecording {
            pronunciationManager.stopRecording()
            return
        }

        do {
            sampleAudioPlayer.stop()
            assessment = nil
            selectedWordIndex = nil
            try pronunciationManager.startRecording()
        } catch {
            errorMessage = "Không thể bắt đầu thu âm: \(error.localizedDescription)"
        }
    }

    private func submitRecording() {
        guard let currentSegment,
              let audioURL = pronunciationManager.recordedAudioURL else {
            errorMessage = "Không tìm thấy bản ghi âm. Vui lòng thu âm lại."
            return
        }

        if pronunciationManager.isPlaying {
            pronunciationManager.stopPlayback()
        }

        isSubmitting = true
        Task {
            do {
                let result = try await PronunciationAssessmentService.assessListeningSegment(
                    audioURL: audioURL,
                    segmentId: currentSegment.id
                )

                await MainActor.run {
                    assessment = result
                    attemptedSegmentIds.insert(currentSegment.id)

                    if result.shadowingProgress?.attemptPassed ?? ShadowingPassingRule.passes(result) {
                        passedSegmentIds.insert(currentSegment.id)
                    }

                    bestLessonScore = max(
                        bestLessonScore,
                        result.shadowingProgress?.lessonBestScore ?? 0
                    )
                    isSubmitting = false
                    onFinished()
                }
            } catch {
                await MainActor.run {
                    errorMessage = PronunciationAssessmentService.userFacingMessage(for: error)
                    isSubmitting = false
                }
            }
        }
    }

    private func moveForward() {
        guard currentHasAttempt, !isSubmitting else { return }

        if currentIndex < segments.count - 1 {
            selectSegment(at: currentIndex + 1)
            return
        }

        if lessonIsCompleted {
            isSubmitting = true
            Task {
                defer { isSubmitting = false }
                do {
                    if !streakRecorded, let userId = AuthManager.shared.currentUser?.id.uuidString {
                        didKeepStreak = try await UserProgressRepository.recordDailyActivityAndUpdateStreak(userId: userId, sessionId: activitySessionID)
                        streakRecorded = true
                    }
                    completedThisSession = true
                    isShowingCompletion = true
                } catch { errorMessage = "Chưa thể ghi nhận phiên học: \(error.localizedDescription)" }
            }
            return
        }

        if let firstPendingIndex = segments.firstIndex(where: { !passedSegmentIds.contains($0.id) }) {
            selectSegment(at: firstPendingIndex)
            errorMessage = "Bạn cần đạt tất cả các câu trước khi hoàn thành bài."
        }
    }

    private func exitPracticeRoom() {
        sampleAudioPlayer.stop()
        if pronunciationManager.isRecording {
            pronunciationManager.stopRecording()
        }
        pronunciationManager.stopPlayback()
        onFinished()
        dismiss()
        if completedThisSession {
            NotificationCenter.default.post(name: didKeepStreak ? .returnToHomeAfterLearning : .returnToLearningTab, object: nil)
        }
    }

    private func playbackRateLabel(_ rate: Float) -> String {
        rate == 1 ? "1x" : "\(rate.formatted(.number.precision(.fractionLength(0...2))))x"
    }

    private var recordingInstruction: String {
        if pronunciationManager.isRecording {
            return "Đang thu âm... Bấm mic để dừng"
        }

        return pronunciationManager.hasRecorded ? "Bấm mic để thu âm lại" : "Bấm mic để bắt đầu thu âm"
    }

    private func displayTranscript(from assessment: AzurePronunciationAssessment) -> String? {
        let transcript = assessment.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript.isEmpty ? nil : transcript
    }

    private func controlButton(
        icon: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundColor(enabled ? (isExtra ? Color.white : .primary) : (isExtra ? Color.white.opacity(0.3) : .secondary.opacity(0.4)))
                .frame(width: 38, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var wordFeedbackSheetPresented: Binding<Bool> {
        Binding(
            get: { selectedWordIndex != nil },
            set: { isPresented in
                if !isPresented {
                    selectedWordIndex = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedWordFeedbackSheet: some View {
        if let selectedWordIndex,
            let assessment,
            assessment.words.indices.contains(selectedWordIndex) {
            PronunciationWordFeedbackSheet(
                feedback: assessment.words[selectedWordIndex],
                pronunciationManager: pronunciationManager
            )
        } else {
            EmptyView()
        }
    }

    private func wordFeedbackSection(_ words: [AzurePronunciationAssessment.WordFeedback]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kết quả từng từ")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isExtra ? Color.white.opacity(0.85) : .primary)

            FlowLayout(spacing: 8) {
                PronunciationFeedbackLegend(level: .good)
                PronunciationFeedbackLegend(level: .needsImprovement)
                PronunciationFeedbackLegend(level: .retry)
            }

            FlowLayout(spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    let level = PronunciationPassingRule.feedbackLevel(for: word)

                    Button {
                        selectedWordIndex = index
                    } label: {
                        HStack(spacing: 4) {
                            Text(word.word)
                            Text("\(Int(word.accuracy.rounded()))")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundColor(level.foregroundColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(level.backgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(level.foregroundColor.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(word.word), \(level.title), \(Int(word.accuracy.rounded())) điểm")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShadowingPracticeDashboardView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var items: [ListeningLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    private var completedLessonCount: Int {
        items.filter(\.isShadowingCompleted).count
    }

    private var activeItems: [ListeningLibraryItem] {
        items.filter(\.isInShadowing)
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
                    ProgressView("Đang tải tiến độ Shadowing...")
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
        .navigationTitle("Luyện Shadowing")
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
                Text("Tiến độ Shadowing")
                    .font(AppTypography.cardTitle)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

                Text("\(completedLessonCount) / \(items.count) bài")
                    .font(AppTypography.metric)
                    .foregroundColor(isExtra ? .white : .primary)

                Text(items.isEmpty ? "Hãy tải một seri bài nghe từ Trang chủ." : "Số bài đã đạt trên tổng bài đã tải về.")
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
            ShadowingPracticeMenuView(items: activeItems)
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bài đang luyện")
                            .font(AppTypography.cardTitle)
                            .foregroundColor(isExtra ? .white : .primary)

                        Text(activeItems.isEmpty ? "Hãy vào My Listening và đưa bài vào luyện Shadowing." : "Bạn đang có \(activeItems.count) bài sẵn sàng luyện.")
                            .font(.subheadline)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }

                    Spacer()

                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(activeItems.isEmpty ? (isExtra ? Color.white.opacity(0.4) : .secondary) : .purple)
                }

                Label("Luyện Shadowing", systemImage: "play.fill")
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
        .accessibilityIdentifier("shadowing-practice-card")
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
            errorMessage = "Không tải được tiến độ Shadowing: \(error.localizedDescription)"
        }
    }
}

struct ShadowingPracticeMenuView: View {
    @State private var activeItems: [ListeningLibraryItem]
    @State private var selectedItem: ListeningLibraryItem?
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    init(items: [ListeningLibraryItem]) {
        _activeItems = State(initialValue: items)
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }

            Group {
                if activeItems.isEmpty {
                    ContentUnavailableView(
                        "Chưa có bài đang luyện",
                        systemImage: "waveform.and.mic",
                        description: Text("Bạn cần đưa bài từ My Listening vào Luyện Shadowing trước.")
                    )
                    .foregroundStyle(isExtra ? .white : .primary)
                } else {
                    List {
                        Section("Bài đang luyện") {
                            ForEach(activeItems) { item in
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
        .onAppear {
            Task { await refreshItems() }
        }
        .fullScreenCover(item: $selectedItem) { item in
            NavigationStack {
                ShadowingPracticeView(lesson: item.lesson) {
                    Task { await refreshItems() }
                }
            }
        }
    }

    @MainActor
    private func refreshItems() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            activeItems = []
            return
        }

        do {
            activeItems = try await ListeningRepository.fetchLibraryItems(userId: userId)
                .filter(\.isInShadowing)
        } catch {
            // The parent dashboard will surface a fresh error when it reloads.
        }
    }
}
