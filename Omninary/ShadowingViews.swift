import SwiftUI

struct ShadowingPracticeView: View {
    let lesson: ListeningLesson
    var onFinished: () -> Void = {}

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
    @State private var isShowingCompletion = false
    @State private var errorMessage: String?

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
        Group {
            if isLoading {
                ProgressView("Đang tải bài Shadowing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            } else if segments.isEmpty {
                ContentUnavailableView(
                    "Bài này chưa có câu luyện",
                    systemImage: "waveform.slash",
                    description: Text("Bạn kiểm tra lại dữ liệu bài nghe trong Supabase.")
                )
            } else if isShowingCompletion {
                completionContent
            } else {
                practiceContent
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Thoát") {
                    exitPracticeRoom()
                }
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
            VStack(alignment: .leading, spacing: 20) {
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
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    private var progressHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label("Câu \(currentIndex + 1)/\(segments.count)", systemImage: "waveform.and.mic")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                Text("\(completedSentenceCount)/\(segments.count) đạt")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(7)
            }

            ProgressView(
                value: Double(currentIndex + 1),
                total: Double(max(segments.count, 1))
            )
            .tint(.purple)
        }
    }

    private func referenceCard(for segment: ListeningSegment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Câu mẫu", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.purple)

                Spacer()

                if currentIsPassed {
                    Label("Đã đạt", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
            }

            Text(segment.english_text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let vietnamese = segment.vietnamese_text, !vietnamese.isEmpty {
                Text(vietnamese)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ipa = segment.ipa, !ipa.isEmpty {
                Text(ipa)
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.purple.opacity(0.08))
        )
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
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
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
                .buttonStyle(.bordered)
                .tint(pronunciationManager.isPlaying ? .red : .orange)
            }

            Button {
                toggleRecording()
            } label: {
                Image(systemName: pronunciationManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 68))
                    .foregroundColor(pronunciationManager.isRecording ? .red : .purple)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordingInstruction)

            Text(recordingInstruction)
                .font(.subheadline)
                .foregroundColor(.secondary)

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
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private func assessmentResult(_ assessment: AzurePronunciationAssessment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Kết quả phát âm")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                if didCurrentAttemptPass {
                    Label("Đạt", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                } else if currentIsPassed {
                    Label("Đã đạt từ trước", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                } else {
                    Label("Chưa đạt", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                }
            }

            if let transcript = displayTranscript(from: assessment) {
                Text("Bạn đọc: \(transcript)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.08))
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
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
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
                        .foregroundColor(.purple)
                        .frame(width: 44, height: 44)
                        .background(Color.purple.opacity(0.12))
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
        .background(Color(UIColor.systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(0.16))
                .frame(height: 1)
        }
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
            .foregroundColor(.primary)
            .frame(minWidth: 72, minHeight: 44)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(10)
        }
        .accessibilityLabel("Tốc độ phát \(playbackRateLabel(playbackRate))")
    }

    private var completionContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 58))
                    .foregroundColor(.green)

                VStack(spacing: 6) {
                    Text("Đã pass bài Shadowing")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(lesson.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.16), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(max(bestLessonScore / 100, 0), 1))
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text(ListeningScoreCalculator.display(bestLessonScore))
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.purple)
                        Text("điểm tốt nhất")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 170, height: 170)

                VStack(spacing: 10) {
                    completionRow(title: "Câu đã đạt", value: "\(completedSentenceCount)/\(segments.count)")
                    completionRow(title: "Điểm bài", value: "\(ListeningScoreCalculator.display(bestLessonScore))/100")
                }
                .padding(18)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)

                Button {
                    isShowingCompletion = false
                    selectSegment(at: 0)
                } label: {
                    Label("Luyện lại", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }

                Button("Quay lại") {
                    exitPracticeRoom()
                }
                .font(.headline)
                .foregroundColor(.blue)
            }
            .padding(24)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }

    private func completionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
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
                await recordShadowingActivity()

                await MainActor.run {
                    assessment = result
                    attemptedSegmentIds.insert(currentSegment.id)

                    if result.shadowingProgress?.status == "passed" {
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
        guard currentHasAttempt else { return }

        if currentIndex < segments.count - 1 {
            selectSegment(at: currentIndex + 1)
            return
        }

        if lessonIsCompleted {
            isShowingCompletion = true
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
    }

    private func recordShadowingActivity() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }

        do {
            try await UserProgressRepository.recordDailyActivityAndUpdateStreak(userId: userId)
        } catch {
            print("Không thể ghi nhận hoạt động Shadowing: \(error)")
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
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.4))
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
    @State private var items: [ListeningLibraryItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var completedLessonCount: Int {
        items.filter(\.isShadowingCompleted).count
    }

    private var activeItems: [ListeningLibraryItem] {
        items.filter(\.isInShadowing)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Đang tải tiến độ Shadowing...")
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
        .navigationTitle("Luyện Shadowing")
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

    private var screenTitle: some View {
        Text("Luyện\nShadowing")
            .font(.system(size: 32, weight: .bold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressCard: some View {
        HStack(spacing: 22) {
            ListeningCompletionRing(
                completed: completedLessonCount,
                total: items.count,
                tint: .purple
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Tiến độ Shadowing")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("\(completedLessonCount) / \(items.count) bài")
                    .font(.title2.bold())

                Text(items.isEmpty ? "Hãy tải một seri bài nghe từ Trang chủ." : "Số bài đã đạt trên tổng bài đã tải về.")
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

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bài đang luyện")
                        .font(.headline)

                    Text(activeItems.isEmpty ? "Hãy vào My Listening và đưa bài vào luyện Shadowing." : "Bạn đang có \(activeItems.count) bài sẵn sàng luyện.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(activeItems.isEmpty ? .secondary : .purple)
            }

            NavigationLink {
                ShadowingPracticeMenuView(items: activeItems)
            } label: {
                Label("Luyện Shadowing", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(activeItems.isEmpty ? Color.gray.opacity(0.45) : Color.purple)
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
            errorMessage = "Không tải được tiến độ Shadowing: \(error.localizedDescription)"
        }
    }
}

struct ShadowingPracticeMenuView: View {
    @State private var activeItems: [ListeningLibraryItem]
    @State private var selectedItem: ListeningLibraryItem?

    init(items: [ListeningLibraryItem]) {
        _activeItems = State(initialValue: items)
    }

    var body: some View {
        Group {
            if activeItems.isEmpty {
                ContentUnavailableView(
                    "Chưa có bài đang luyện",
                    systemImage: "waveform.and.mic",
                    description: Text("Bạn cần đưa bài từ My Listening vào Luyện Shadowing trước.")
                )
            } else {
                List {
                    Section("Bài đang luyện") {
                        ForEach(activeItems) { item in
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
