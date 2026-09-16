import SwiftUI
import Foundation

struct PronunciationExampleExerciseView: View {
    let task: LearningTask
    let onContinue: (Bool) -> Void

    @StateObject private var pronunciationManager = PronunciationManager()
    @State private var assessment: AzurePronunciationAssessment?
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedWordIndex: Int?
    @State private var playbackSpeed: SpeechPlaybackSpeed = .normal
    @State private var isResultPresented = false
    @State private var pendingContinuationResult: Bool?

    private var meaning: Vocabulary? {
        task.pronunciationMeaning
    }

    private var example: String {
        task.pronunciationExample ?? ""
    }

    private var score: PronunciationScore? {
        assessment.map(PronunciationScore.init)
    }

    private var canContinue: Bool {
        guard let assessment else { return false }
        return VocabularyPronunciationProgressRule.canContinue(assessment)
    }

    private var hasSolidTargetPronunciation: Bool {
        guard let assessment else { return false }
        return VocabularyPronunciationProgressRule.hasSolidTargetPronunciation(
            assessment,
            targetWord: task.word
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                sampleSentencePanel

                if assessment == nil {
                    recordingPracticePanel
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pronunciationCheckActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Lỗi", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $isResultPresented, onDismiss: finishPendingContinuation) {
            pronunciationResultSheet
                .presentationDetents([.fraction(1.0), .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .onDisappear {
            if pronunciationManager.isRecording {
                pronunciationManager.stopRecording()
            }
            pronunciationManager.stopPlayback()
        }
    }

    private var sampleSentencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Luyện phát âm câu ví dụ", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundColor(.purple)

                HStack(spacing: 8) {
                    Text(task.word)
                        .font(.subheadline.weight(.semibold))

                    if let ipa = meaning?.IPA, !ipa.isEmpty {
                        Text(ipa)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Text(tappableExample)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .tint(.blue)
                .environment(\.openURL, OpenURLAction { url in
                    playTappedExampleWord(from: url)
                    return .handled
                })

            if let vietnameseExample = meaning?.vietnameseExample {
                Text(vietnameseExample)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button(action: playSampleSentence) {
                Label("Nghe câu mẫu", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Picker("Tốc độ đọc", selection: $playbackSpeed) {
                ForEach(SpeechPlaybackSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tốc độ đọc câu mẫu")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.purple.opacity(0.08)))
    }

    private var recordedAudioControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bản thu của bạn")
                .font(.headline)

            Button {
                if pronunciationManager.isPlaying {
                    pronunciationManager.stopPlayback()
                } else {
                    pronunciationManager.playRecordedAudio()
                }
            } label: {
                Label(
                    pronunciationManager.isPlaying ? "Dừng nghe" : "Nghe lại giọng của bạn",
                    systemImage: pronunciationManager.isPlaying ? "stop.circle.fill" : "play.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .tint(pronunciationManager.isPlaying ? .red : .orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    private var pronunciationResultSheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: canContinue ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(canContinue ? .green : .red)

                        Text(canContinue ? "Chính xác!" : "Chưa đúng rồi!")
                            .font(.headline)
                            .foregroundColor(canContinue ? .green : .red)
                    }

                    if pronunciationManager.hasRecorded {
                        recordedAudioControls
                    }

                    if let score {
                        scoreResult(score)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            pronunciationResultActionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .sheet(isPresented: wordFeedbackSheetPresented) {
            selectedWordFeedbackSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var pronunciationResultActionBar: some View {
        LearningBottomActionBar {
            Button {
                pendingContinuationResult = canContinue
                pronunciationManager.stopPlayback()
                isResultPresented = false
            } label: {
                LearningActionButtonLabel(
                    title: "Tiếp tục",
                    systemImage: "arrow.right.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(canContinue ? .green : .red)
        }
    }

    private var recordingPracticePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Bản thu của bạn", systemImage: "waveform.and.mic")
                .font(.headline)

            VStack(spacing: 8) {
                Button {
                    toggleRecording()
                } label: {
                    Image(systemName: pronunciationManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 58))
                        .foregroundColor(pronunciationManager.isRecording ? .red : .purple)
                }
                .accessibilityLabel(pronunciationManager.isRecording ? "Dừng thu âm" : "Bắt đầu thu âm")

                Text(recordingInstruction)
                    .font(.subheadline.weight(.medium))

                Text(
                    pronunciationManager.hasRecorded
                        ? "Bạn có thể nghe lại hoặc kiểm tra ngay."
                        : "Đọc đầy đủ câu mẫu phía trên."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            if pronunciationManager.hasRecorded, assessment == nil {
                Button {
                    if pronunciationManager.isPlaying {
                        pronunciationManager.stopPlayback()
                    } else {
                        pronunciationManager.playRecordedAudio()
                    }
                } label: {
                    Label(
                        pronunciationManager.isPlaying ? "Dừng nghe" : "Nghe lại giọng của bạn",
                        systemImage: pronunciationManager.isPlaying ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(pronunciationManager.isPlaying ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    private var pronunciationCheckActionBar: some View {
        LearningBottomActionBar {
            Button {
                submitRecording()
            } label: {
                LearningActionButtonLabel(
                    title: isSubmitting ? "Đang kiểm tra" : "Kiểm tra",
                    systemImage: "checkmark.circle.fill",
                    isLoading: isSubmitting
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(
                assessment != nil
                    || !pronunciationManager.hasRecorded
                    || pronunciationManager.isRecording
                    || isSubmitting
            )
        }
    }

    @ViewBuilder
    private func scoreResult(_ score: PronunciationScore) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Kết quả phát âm", systemImage: "waveform.path.ecg")
                    .font(.headline)

                Spacer()

                Text(resultStatusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundColor(resultStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(resultStatusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let azureTranscript {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bạn đọc")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(azureTranscript)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .italic()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.blue.opacity(0.08)))
            }

            if let assessment, !assessment.words.isEmpty {
                wordFeedbackSection(assessment.words)
            }

            scoreMetricsSection(score)

            if canContinue {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        hasSolidTargetPronunciation
                            ? "Từ chủ điểm đã đạt yêu cầu"
                            : "Đủ tốt để tiếp tục học",
                        systemImage: hasSolidTargetPronunciation
                            ? "checkmark.seal.fill"
                            : "arrow.forward.circle.fill"
                    )
                        .font(.headline)
                        .foregroundColor(resultStatusColor)

                    if !hasSolidTargetPronunciation {
                        Text("Bạn không cần đọc lại cả câu. Những từ màu đỏ hoặc cam sẽ giúp bạn biết chỗ cần cải thiện và câu này sẽ xuất hiện lại ở lần ôn sau.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(resultStatusColor.opacity(0.08)))
            } else if let assessment {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Chưa đạt, câu này sẽ được đưa về cuối bài để bạn thử lại.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)

                    ForEach(
                        VocabularyPronunciationProgressRule.continueFailureReasons(for: assessment),
                        id: \.self
                    ) { reason in
                        Label(reason, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.07)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleRecording() {
        if pronunciationManager.isRecording {
            pronunciationManager.stopRecording()
            return
        }

        do {
            assessment = nil
            try pronunciationManager.startRecording()
        } catch {
            errorMessage = "Không thể bắt đầu thu âm: \(error.localizedDescription)"
            showError = true
        }
    }

    private func submitRecording() {
        if pronunciationManager.isPlaying {
            pronunciationManager.stopPlayback()
        }

        guard let userVocabularyId = meaning?.user_vocabulary_id ?? meaning?.id,
              let audioURL = pronunciationManager.recordedAudioURL else {
            errorMessage = "Không tìm thấy bản ghi âm. Vui lòng thu âm lại."
            showError = true
            return
        }

        isSubmitting = true
        Task {
            do {
                let result = try await PronunciationAssessmentService.assess(
                    audioURL: audioURL,
                    userVocabularyId: userVocabularyId
                )
                let resultScore = PronunciationScore(assessment: result)

                if VocabularyPronunciationProgressRule.canContinue(result) {
                    let currentBestScore = meaning?.pronunciation_score ?? 0
                    let newScore = Int(resultScore.finalScore.rounded())
                    if newScore > currentBestScore {
                        try? await VocabularyRepository.updatePronunciationScore(
                            id: userVocabularyId,
                            score: newScore
                        )
                    }
                }

                await MainActor.run {
                    assessment = result
                    isSubmitting = false
                    isResultPresented = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = PronunciationAssessmentService.userFacingMessage(for: error)
                    showError = true
                    isSubmitting = false
                }
            }
        }
    }

    private func finishPendingContinuation() {
        guard let result = pendingContinuationResult else { return }
        pendingContinuationResult = nil

        if !result {
            assessment = nil
            selectedWordIndex = nil
            isSubmitting = false
            pronunciationManager.resetRecordingState()
        }

        onContinue(result)
    }

    private var recordingInstruction: String {
        if pronunciationManager.isRecording {
            return "Đang thu âm... Bấm để dừng"
        }

        return pronunciationManager.hasRecorded ? "Bấm mic để thu âm lại" : "Bấm để thu âm"
    }

    private var azureTranscript: String? {
        let transcript = assessment?.transcript.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return transcript.isEmpty ? nil : transcript
    }

    private var resultStatusTitle: String {
        if hasSolidTargetPronunciation {
            return "Đạt tốt"
        }
        return canContinue ? "Đạt để tiếp tục" : "Cần thu lại"
    }

    private var resultStatusColor: Color {
        if hasSolidTargetPronunciation {
            return .green
        }
        return canContinue ? .orange : .red
    }

    private var tappableExample: AttributedString {
        var sentence = AttributedString()
        let tokens = example.split(whereSeparator: \.isWhitespace)

        for (index, token) in tokens.enumerated() {
            if index > 0 {
                sentence.append(AttributedString(" "))
            }

            let displayedToken = String(token)
            var attributedToken = AttributedString(displayedToken)
            if let spokenWord = speakableWord(from: displayedToken),
               let url = wordPlaybackURL(for: spokenWord) {
                attributedToken.link = url
            }
            sentence.append(attributedToken)
        }

        return sentence
    }

    private func playSampleSentence() {
        SpeechManager.shared.speak(
            example: example,
            targetWord: task.word,
            ipa: meaning?.IPA,
            rateMultiplier: playbackSpeed.rawValue
        )
    }

    private func playTappedExampleWord(from url: URL) {
        guard url.scheme == "ditanary-word",
              url.host == "speak",
              let word = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "word" })?
                .value,
              !word.isEmpty else {
            return
        }

        let ipa = normalizedWord(word) == normalizedWord(task.word) ? meaning?.IPA : nil
        SpeechManager.shared.speak(
            word: word,
            ipa: ipa,
            rateMultiplier: playbackSpeed.rawValue
        )
    }

    private func wordPlaybackURL(for word: String) -> URL? {
        var components = URLComponents()
        components.scheme = "ditanary-word"
        components.host = "speak"
        components.queryItems = [URLQueryItem(name: "word", value: word)]
        return components.url
    }

    private func speakableWord(from token: String) -> String? {
        let word = token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        return word.isEmpty ? nil : word
    }

    private func normalizedWord(_ value: String) -> String {
        (speakableWord(from: value) ?? value)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                .font(.headline)

            HStack(spacing: 10) {
                PronunciationFeedbackLegend(level: .good)
                PronunciationFeedbackLegend(level: .needsImprovement)
                PronunciationFeedbackLegend(level: .retry)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    let level = PronunciationPassingRule.feedbackLevel(for: word)
                    Button {
                        selectedWordIndex = index
                    } label: {
                        HStack(spacing: 4) {
                            Text(word.word)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("\(Int(word.accuracy.rounded()))")
                                .font(.caption2.weight(.bold))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(level.foregroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemGroupedBackground)))
    }

    private func scoreMetricsSection(_ score: PronunciationScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Điểm đánh giá")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                PronunciationMetricCard(title: "Tổng", score: score.finalScore, color: .purple)
                PronunciationMetricCard(title: "Chính xác", score: score.accuracyScore, color: .blue)
                PronunciationMetricCard(title: "Trôi chảy", score: score.fluencyScore, color: .green)
                PronunciationMetricCard(title: "Đầy đủ", score: score.completenessScore, color: .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PronunciationMetricCard: View {
    let title: String
    let score: Double
    let color: Color

    private var boundedScore: Double {
        min(max(score, 0), 100)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(boundedScore / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(boundedScore.rounded()))")
                    .font(.title3.weight(.bold))
            }
            .frame(width: 58, height: 58)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 106)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(color.opacity(0.08)))
    }
}
