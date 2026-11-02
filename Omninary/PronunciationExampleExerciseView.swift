import SwiftUI
import Foundation

/// What the read-aloud attempt observed, for Extra v1 skill evidence.
struct PronunciationAttemptDetails {
    var finalScore: Int?
    var targetWordAccuracy: Int?
    var accuracy: Int?
    var fluency: Int?
    var completeness: Int?
    var modelPlays = 0
    var recordings = 0
    var firstRecordingMs: Int?
}

struct PronunciationExampleExerciseView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    let task: LearningTask
    /// The result sheet's button: "Tiếp tục", or "Xong nhiệm vụ" on a quest's last question.
    var continueTitle = "Tiếp tục"
    let onContinue: (Bool, PronunciationAttemptDetails) -> Void
    @State private var modelPlays = 0
    @State private var recordings = 0
    @State private var presentedAt = Date()
    @State private var firstRecordingMs: Int?

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    @StateObject private var pronunciationManager = PronunciationManager()
    @State private var assessment: AzurePronunciationAssessment?
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var selectedWordIndex: Int?
    @State private var playbackSpeed: SpeechPlaybackSpeed = .normal
    @State private var isResultPresented = false
    @State private var pendingContinuationResult: Bool?
    /// Height of the result sheet's content, so the sheet opens exactly as tall as it needs.
    @State private var resultHeight: CGFloat = 0

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
            VStack(spacing: 12) {
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
        .sheet(isPresented: $isResultPresented) {
            pronunciationResultSheet
        }
        .onDisappear {
            if pronunciationManager.isRecording {
                pronunciationManager.stopRecording()
            }
            pronunciationManager.stopPlayback()
        }
    }

    @Environment(\.omniV2) private var v2
    @Environment(\.omniNight) private var night
    private var palette: QuizPalette { QuizPalette(dark: v2 ? night : isExtra) }

    /// The sentence to read, its translation, and the model reading at three speeds.
    private var sampleSentencePanel: some View {
        VStack(spacing: 8) {
            Text("ĐỌC TO CÂU")
                .font(.omniBody(12, weight: 800))
                .tracking(0.8)
                .foregroundStyle(palette.muted)
                .padding(.top, 8)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(task.word).font(.omniBody(13.5, weight: 800)).foregroundStyle(palette.pill.text)
                    if let ipa = meaning?.IPA, !ipa.isEmpty {
                        Text(ipa).font(.omniBody(12.5)).foregroundStyle(palette.muted)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.pill.fill))

                Text(tappableExample)
                    .font(.omniBody(22, weight: 800))
                    .foregroundStyle(palette.text)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .tint(palette.text)
                    .environment(\.openURL, OpenURLAction { url in
                        playTappedExampleWord(from: url)
                        return .handled
                    })
                    .padding(.top, 4)

                if let vietnameseExample = meaning?.vietnameseExample {
                    Text(vietnameseExample)
                        .font(.omniBody(13.5))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    ForEach(SpeechPlaybackSpeed.allCases) { speed in
                        let on = playbackSpeed == speed
                        Button {
                            playbackSpeed = speed
                            playSampleSentence()
                        } label: {
                            Text(speed == .normal ? "Nghe mẫu" : speed.title)
                                .font(.omniBody(13, weight: 700))
                                .foregroundStyle(on ? palette.link : palette.muted)
                                .padding(.horizontal, 14).frame(height: 44)
                                .background(Capsule().fill(on ? palette.placed.fill : palette.card))
                                .overlay(Capsule().stroke(on ? Color(hex: 0x9cc0ff) : palette.line, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nghe câu mẫu tốc độ \(speed.title)")
                    }
                }
                .padding(.top, 6)
            }
            .quizCard(palette, padding: 18)
        }
    }

    /// The result of a reading, in the quiz's result style: verdict and total, the three part
    /// scores, what was heard, every word coloured by how it was said (tap one for details), your
    /// own recording and the model sentence again. Opens half-height and slides up to full screen.
    private var pronunciationResultSheet: some View {
        let solid = canContinue && hasSolidTargetPronunciation
        let (title, verdict, tone): (String, QuizPalette.Verdict, Quiz3DButtonStyle.Tone) = solid
            ? ("Chính xác!", .ok, .green)
            : canContinue ? ("Đạt", .near, .amber)
            : ("Chưa đạt", .bad, .red)
        let colors = palette.verdict(verdict), light = palette, text = palette.text, muted = palette.muted
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.omniDisplay(24)).foregroundStyle(colors.text)
                    Spacer()
                    if let score {
                        Text("\(Int(score.finalScore.rounded()))/100")
                            .font(.omniDisplay(16)).foregroundStyle(colors.text)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(palette.card.opacity(0.8)))
                            .accessibilityLabel("Điểm tổng \(Int(score.finalScore.rounded()))")
                    }
                }

                if let score {
                    VStack(spacing: 5) {
                        QuizScoreBar(name: "Chính xác", value: Int(score.accuracyScore.rounded()), palette: light)
                        QuizScoreBar(name: "Trôi chảy", value: Int(score.fluencyScore.rounded()), palette: light)
                        QuizScoreBar(name: "Đầy đủ", value: Int(score.completenessScore.rounded()), palette: light)
                    }
                }

                if let assessment {
                    if canContinue {
                        if !hasSolidTargetPronunciation {
                            Text("Không cần đọc lại cả câu. Từ màu đỏ hoặc cam là chỗ cần luyện thêm; câu này sẽ quay lại ở lần ôn sau.")
                                .font(.omniBody(13, weight: 600)).foregroundStyle(text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Câu này sẽ quay lại cuối bài để bạn thử lại.")
                                .font(.omniBody(13.5, weight: 700)).foregroundStyle(Color(hex: 0xb3261e))
                            ForEach(VocabularyPronunciationProgressRule.continueFailureReasons(for: assessment), id: \.self) { reason in
                                Text("• " + reason).font(.omniBody(12.5, weight: 600)).foregroundStyle(muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let azureTranscript {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BẠN ĐỌC").font(.omniBody(11, weight: 800)).tracking(0.6).foregroundStyle(muted)
                            Text(azureTranscript).font(.omniBody(15, weight: 600)).italic().foregroundStyle(text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let assessment, !assessment.words.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                PronunciationFeedbackLegend(level: .good)
                                PronunciationFeedbackLegend(level: .needsImprovement)
                                PronunciationFeedbackLegend(level: .retry)
                            }
                            FlowLayout(spacing: 6) {
                                ForEach(Array(assessment.words.enumerated()), id: \.offset) { index, word in
                                    let level = PronunciationPassingRule.feedbackLevel(for: word)
                                    Button { selectedWordIndex = index } label: {
                                        HStack(spacing: 4) {
                                            Text(word.word).font(.omniBody(14, weight: 700))
                                            Text("\(Int(word.accuracy.rounded()))").font(.omniBody(11, weight: 800))
                                        }
                                        .foregroundStyle(level.foregroundColor)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(level.backgroundColor))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(level.foregroundColor.opacity(0.3), lineWidth: 1.5))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(word.word), \(level.title), \(Int(word.accuracy.rounded())) điểm")
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(task.word).font(.omniBody(18, weight: 800)).foregroundStyle(text)
                                if let ipa = meaning?.IPA, !ipa.isEmpty { Text(ipa).font(.omniBody(13.5)).foregroundStyle(muted) }
                            }
                            if let short = meaning?.V_meaning ?? meaning?.EV_meaning {
                                Text(short).font(.omniBody(13.5)).foregroundStyle(text).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if pronunciationManager.hasRecorded {
                            Button {
                                if pronunciationManager.isPlaying { pronunciationManager.stopPlayback() } else { pronunciationManager.playRecordedAudio() }
                            } label: {
                                Image(systemName: pronunciationManager.isPlaying ? "stop.fill" : "person.wave.2.fill")
                                    .font(.system(size: 17, weight: .bold)).foregroundStyle(palette.verdict(.ok).text)
                                    .frame(width: 44, height: 44)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(palette.verdict(.ok).fill))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(pronunciationManager.isPlaying ? "Dừng nghe" : "Nghe lại giọng của bạn")
                        }
                        Button { playSampleSentence() } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(palette.link)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(palette.placed.fill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nghe câu mẫu")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(continueTitle) {
                pendingContinuationResult = canContinue
                pronunciationManager.stopPlayback()
                isResultPresented = false
                finishPendingContinuation()
            }
            .buttonStyle(Quiz3DButtonStyle(tone: tone))
            .accessibilityIdentifier("learning-next")
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
            .background(colors.fill)
        }
        // the content plus the button bar under it (button, its shadow and padding, the home indicator)
        .presentationDetents(resultHeight > 0 ? [.height(resultHeight + 112)] : [.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(colors.fill)
        .presentationBackgroundInteraction(.disabled)
        .interactiveDismissDisabled()
        .environment(\.colorScheme, palette.dark ? .dark : .light)
        .onAppear { playSampleSentence(counted: false) }
        .sheet(isPresented: wordFeedbackSheetPresented) {
            // the sheet sizes itself to its content
            selectedWordFeedbackSheet
                .presentationDragIndicator(.visible)
        }
    }

    /// The big green microphone; it pulses while recording.
    private var recordingPracticePanel: some View {
        VStack(spacing: 12) {
            Button {
                toggleRecording()
            } label: {
                Image(systemName: pronunciationManager.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x6fdc60), Color(hex: 0x2f9e3a)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Circle().stroke(palette.outline(0x2f9e3a), lineWidth: 4))
                    .background {
                        if pronunciationManager.isRecording {
                            MicPulse()
                        }
                    }
            }
            .buttonStyle(QuizPressStyle(shape: Circle(), depth: 6, base: palette.outline(0x2f9e3a)))
            .padding(.top, 18)
            .accessibilityLabel(pronunciationManager.isRecording ? "Dừng thu âm" : "Bắt đầu thu âm")

            Text(recordingInstruction)
                .font(.omniBody(14, weight: 700))
                .foregroundStyle(palette.muted)
                .padding(.top, 8)

            if pronunciationManager.hasRecorded, assessment == nil, !pronunciationManager.isRecording {
                Button(pronunciationManager.isPlaying ? "Dừng nghe" : "Nghe lại giọng của bạn") {
                    if pronunciationManager.isPlaying {
                        pronunciationManager.stopPlayback()
                    } else {
                        pronunciationManager.playRecordedAudio()
                    }
                }
                .font(.omniBody(13.5, weight: 700))
                .foregroundStyle(palette.link)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pronunciationCheckActionBar: some View {
        Button(isSubmitting ? "Đang kiểm tra…" : "Kiểm tra") {
            submitRecording()
        }
        .buttonStyle(Quiz3DButtonStyle(tone: .blue))
        .disabled(
            assessment != nil
                || !pronunciationManager.hasRecorded
                || pronunciationManager.isRecording
                || isSubmitting
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(palette.page.opacity(0.96))
    }

    private func toggleRecording() {
        if pronunciationManager.isRecording {
            pronunciationManager.stopRecording()
            return
        }

        do {
            assessment = nil
            try pronunciationManager.startRecording()
            recordings += 1
            if firstRecordingMs == nil {
                firstRecordingMs = Int(Date().timeIntervalSince(presentedAt) * 1_000)
            }
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

        var details = PronunciationAttemptDetails(modelPlays: modelPlays, recordings: recordings,
                                                  firstRecordingMs: firstRecordingMs)
        if let assessment {
            details.finalScore = Int(PronunciationScore(assessment: assessment).finalScore.rounded())
            details.accuracy = Int(assessment.scores.accuracy.rounded())
            details.fluency = Int(assessment.scores.fluency.rounded())
            details.completeness = Int(assessment.scores.completeness.rounded())
            let target = VocabularyPronunciationProgressRule.targetFeedback(in: assessment, targetWord: task.word)
            if !target.isEmpty {
                details.targetWordAccuracy = Int((target.map(\.accuracy).reduce(0, +) / Double(target.count)).rounded())
            }
        }
        onContinue(result, details)
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

    private func playSampleSentence(counted: Bool = true) {
        if counted { modelPlays += 1 }
        SpeechManager.shared.speak(
            example: example,
            targetWord: task.word,
            ipa: meaning?.IPA,
            rateMultiplier: playbackSpeed.rawValue
        )
    }

    private func playTappedExampleWord(from url: URL) {
        guard url.scheme == "omninary-word",
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
        components.scheme = "omninary-word"
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
                pronunciationManager: pronunciationManager,
                fitsContent: true
            )
        } else {
            EmptyView()
        }
    }
}
