import SwiftUI

struct LearningActionButtonLabel: View {
    let title: String
    let systemImage: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .font(AppTypography.action)
        .frame(maxWidth: .infinity)
    }
}

struct LearningSessionView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @Environment(\.scenePhase) private var scenePhase
    let sessionID: UUID
    @State var tasks: [LearningTask]
    let learningVocabGroups: [[Vocabulary]]
    /// Why Extra added reinforcement for each word (vocabulary ID → text).
    var reasons: [String: String] = [:]
    let onClose: () -> Void
    /// Adventure mode: the session stays mounted under the stage map and shows one question per quest.
    var questMode: LearningQuestMode? = nil

    /// False while an adventure stage keeps this session hidden behind its map.
    private var isOnScreen: Bool { questMode?.isVisible ?? true }

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }
    
    @State private var currentTaskIndex = 0
    @State private var isCompleted = false
    @State private var isFinishingSession = false
    @State private var saveErrorMessage: String?
    @State private var hasStartedCelebration = false
    @State private var shouldRouteToHomeAfterCompletion = false
    #if DEBUG
    @State private var isShowingDeveloperFinishConfirmation = false
    #endif
    
    @State private var inputText = ""
    @State private var currentResult: TaskResult? = nil
    
    // Scramble logic state
    @State private var selectedScrambleWords: [String] = []
    @State private var availableScrambleWords: [String] = []
    @State private var shouldRetryCurrentTask = false
    @State private var correctAnswersCount = 0
    @State private var lastEarnedPoints = 0
    @State private var sessionStartedAt = Date()
    @State private var taskPresentedAt = Date()
    @State private var learningAttempts: [LearningAttemptTelemetry] = []
    @State private var attemptNumbersByExercise: [UUID: Int] = [:]
    @FocusState private var isAnswerFieldFocused: Bool

    // Extra v1 interaction evidence for the attempt on screen.
    @State private var signals = AttemptSignals()
    @State private var awaitingRescue = false
    @State private var listenSpeed: Double = 1
    @State private var backgroundedAt: Date?
    @State private var eliminatedOptions: Set<String> = []
    /// Question index at which the answer card of each word was last shown.
    @State private var lastExposureByWord: [String: Int] = [:]
    @State private var lastAttemptScore = 0
    @State private var wordResults: [WordMasteryResult] = []
    @State private var lastPlayAt: Date?
    /// How each answered question went, by its index, for the quest's progress segments.
    @State private var marks: [Int: QuizMark] = [:]
    /// Right answers in a row.
    @State private var streak = 0
    /// The settled words for the results screen, with their history; nil until loaded.
    @State private var resultItems: [WordResultItem]?
    @State private var accountIsExtra = false

    @Environment(\.omniV2) private var v2
    @Environment(\.omniNight) private var night
    /// White by day, dark by night like the rest of the app; with the old interface, Extra stays dark.
    private var isDark: Bool { v2 ? night : isExtra }
    private var palette: QuizPalette { QuizPalette(dark: isDark) }

    var currentTask: LearningTask? {
        guard currentTaskIndex < tasks.count else { return nil }
        return tasks[currentTaskIndex]
    }
    
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(currentTaskIndex) / Double(tasks.count)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isExtra && !v2 {
                    AuroraBackdrop()
                } else {
                    palette.page.ignoresSafeArea()
                }

                VStack(spacing: 8) {
                    if isCompleted {
                        completionView
                    } else if let saveErrorMessage {
                        savingFailureView(message: saveErrorMessage)
                    } else if isFinishingSession {
                        savingProgressView
                    } else if let task = currentTask {
                        quizHeader
                        #if DEBUG
                        if let answer = uiTestAnswer(for: task) {
                            // Lets the real-session UI test answer like a learner who knows the word.
                            Text(answer)
                                .font(.system(size: 1))
                                .opacity(0.02)
                                .accessibilityIdentifier("learning-debug-answer")
                        }
                        #endif

                        if task.type == .pronunciationExample {
                            inputArea(for: task)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    questionView(for: task)
                                    answerArea(for: task)
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, currentResult == nil ? 12 : 260)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .scrollBounceBehavior(.basedOnSize)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if task.type != .multipleChoice, currentResult == nil {
                                    checkBar(for: task)
                                }
                            }
                        }
                    }
                }
                .accessibilityHidden(currentResult != nil)
                .allowsHitTesting(currentResult == nil)
            }
            .navigationTitle(isCompleted ? "Hoàn thành" : "Đang học")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            // The quiz draws its own top row (close, progress, streak).
            .toolbar(isCompleted && !showsResults ? .visible : .hidden, for: .navigationBar)
            .streakRescueWarning(onLeave: onClose)
            .environment(\.colorScheme, isDark ? .dark : .light)
            .onAppear {
                if let resume = questMode?.resume { restore(resume) }
                initializeTaskState()
                if let first = tasks.first, first.type == .listenAndType {
                    scheduleAutoplay(for: first)
                }
            }
            .onChange(of: currentTaskIndex) { oldValue, newValue in
                initializeTaskState()
            }
            .onChange(of: questMode?.isVisible) { _, visible in
                // A quest opens the next question: start its clock, focus and audio now.
                guard visible == true, !isFinishingSession, !isCompleted else { return }
                initializeTaskState()
                if let task = currentTask, task.type == .listenAndType { scheduleAutoplay(for: task) }
            }
            .onChange(of: scenePhase) { _, phase in
                // Time spent outside the app is not answering time.
                if phase != .active, backgroundedAt == nil {
                    backgroundedAt = Date()
                    signals.pauseCount += 1
                } else if phase == .active, let start = backgroundedAt {
                    signals.pausedMs += Int(Date().timeIntervalSince(start) * 1_000)
                    backgroundedAt = nil
                }
            }
            .onChange(of: inputText) { oldValue, newValue in
                if newValue.count < oldValue.count { signals.deletions += 1 }
                if !newValue.isEmpty { markFirstInteraction() }
            }
            .overlay(alignment: .bottom) {
                if let result = currentResult {
                    feedbackPanel(for: result)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.2), value: currentResult?.id)
            .onDisappear {
                CelebrationFeedbackPlayer.shared.stop()
            }
            #if DEBUG
            .alert("Hoàn tất phiên kiểm thử?", isPresented: $isShowingDeveloperFinishConfirmation) {
                Button("Huỷ", role: .cancel) {}
                Button("Lưu như đã hoàn thành") {
                    completeDeveloperTestSession()
                }
            } message: {
                Text("Thao tác này bỏ qua các câu hỏi nhưng vẫn lưu thật: tăng cấp, đặt lịch ôn, cập nhật chuỗi ngày học, cộng Điểm Omni và trừ một lượt học nếu bạn dùng Ditan.")
            }
            #endif
        }
    }

    private var showsResults: Bool { !(resultItems ?? []).isEmpty }

    @ViewBuilder
    private var completionView: some View {
        if let items = resultItems, !items.isEmpty {
            LearningResultsView(items: items, isExtra: accountIsExtra, dark: isDark,
                                title: questMode == nil ? "Kết quả bài học" : "Kết quả màn",
                                place: questMode?.place,
                                finishTitle: questMode == nil ? "Tiếp tục" : "Nhận thưởng màn",
                                onFinish: finishCompletion)
        } else {
            plainCompletionView
        }
    }

    /// After the results: back to the map's reward card, or to Home / the learning tab.
    private func finishCompletion() {
        CelebrationFeedbackPlayer.shared.stop()
        if questMode != nil {
            // The adventure stage shows its own reward card next.
        } else if shouldRouteToHomeAfterCompletion {
            NotificationCenter.default.post(name: .returnToHomeAfterLearning, object: nil)
        } else {
            NotificationCenter.default.post(name: .returnToLearningTab, object: nil)
        }
        onClose()
    }

    private var plainCompletionView: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 132, height: 132)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 62, weight: .bold))
                        .foregroundColor(AppSemanticColor.attention)
                }

                VStack(spacing: 8) {
                    Text("Hoàn thành bài học!")
                        .font(.title.bold())
                        .foregroundColor(isExtra ? .white : .primary)
                        .multilineTextAlignment(.center)

                    Text("Bạn đã ôn tập \(learningVocabGroups.count) nghĩa từ vựng và cập nhật lịch ôn tiếp theo.")
                        .font(.body)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Label("Tiến độ đã được lưu", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppSemanticColor.success)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppSemanticColor.success.opacity(0.1))
                        .clipShape(Capsule())

                    HStack(spacing: 5) {
                        OmniCoinView(size: 18, showShadow: false)
                        Text("+\(lastEarnedPoints) Điểm Omni")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(AppSemanticColor.attention)
                        if OmniDoublePointsManager.shared.isActive {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.yellow)
                                Text("x2")
                                    .font(.caption2.weight(.black))
                                    .foregroundColor(.yellow)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.2)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }

                if !wordResults.isEmpty {
                    ScrollView {
                        VStack(spacing: AppSpacing.item) {
                            ForEach(wordResults) { item in
                                WordMasteryResultRow(
                                    result: item,
                                    word: wordText(for: item.user_vocabulary_id),
                                    reason: reasons[item.user_vocabulary_id],
                                    isExtra: isExtra
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 340)
                    .accessibilityIdentifier("learning-word-results")
                }

                Button {
                    finishCompletion()
                } label: {
                    LearningActionButtonLabel(
                        title: "Tiếp tục",
                        systemImage: "arrow.right.circle.fill"
                    )
                }
                .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)

            CelebrationConfettiView()
                .ignoresSafeArea()
        }
        .onAppear {
            startCelebrationIfNeeded()
        }
    }

    #if DEBUG
    private func uiTestAnswer(for task: LearningTask) -> String? {
        guard ProcessInfo.processInfo.arguments.contains("-RealSessionUITest") else { return nil }
        let answer = task.type == .sentenceScramble
            ? LearningTextNormalizer.sentenceScrambleWords(task.correctSentence ?? "").joined(separator: "|")
            : task.word
        return "\(task.type.telemetryName)::\(answer)::\(task.word)"
    }
    #endif

    private func wordText(for vocabularyID: String) -> String {
        learningVocabGroups.flatMap { $0 }.first { $0.id == vocabularyID }?.vocab ?? "Từ vựng"
    }

    private var savingProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Đang lưu tiến độ...")
                .font(.headline)

            Text("Omninary đang cập nhật cấp độ và lịch ôn tiếp theo của bạn.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func savingFailureView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 46))
                .foregroundColor(AppSemanticColor.attention)

            Text("Chưa thể xác nhận tiến độ đã lưu")
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                saveErrorMessage = nil
                isFinishingSession = true
                Task { await finishSession() }
            } label: {
                LearningActionButtonLabel(
                    title: "Thử lưu lại",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))

            Button("Để sau") {
                onClose()
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra, emphasis: .secondary))
        }
        .padding(28)
    }

    private func startCelebrationIfNeeded() {
        guard !hasStartedCelebration else { return }
        hasStartedCelebration = true
        CelebrationFeedbackPlayer.shared.play()
    }
    
    /// Close, the quest's question segments (or the session's progress) and the streak.
    private var quizHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if let questMode { questMode.onHide() } else { onClose() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(palette.text)
                        .frame(width: 42, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(palette.card))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(questMode == nil ? "Thoát" : "Về bản đồ")

                if let q = questPosition {
                    QuizSegments(marks: questMarks(q), palette: palette)
                } else {
                    GeometryReader { g in
                        Capsule().fill(palette.empty)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color(hex: 0x34b45a)).frame(width: g.size.width * progress)
                            }
                    }
                    .frame(height: 10)
                    .accessibilityElement()
                    .accessibilityLabel("Câu \(currentTaskIndex + 1) trên \(tasks.count)")
                }

                if streak >= 2 { QuizStreak(count: streak, dark: isDark) }

                #if DEBUG
                Button {
                    isShowingDeveloperFinishConfirmation = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 13)).foregroundStyle(palette.muted)
                }
                .accessibilityLabel("Hoàn tất phiên kiểm thử")
                #endif
            }
            if let q = questPosition {
                Text("Nhiệm vụ \(q.quest) · câu \(q.question)/\(q.size)")
                    .font(.omniBody(12, weight: 700)).foregroundStyle(palette.muted)
            } else {
                Text("Câu \(currentTaskIndex + 1) / \(tasks.count)")
                    .font(.omniBody(12, weight: 700)).foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// The marks of the questions in the current quest, the one on screen in light blue.
    private func questMarks(_ q: (quest: Int, question: Int, size: Int)) -> [QuizMark] {
        let start = currentTaskIndex - (q.question - 1)
        return (0..<q.size).map { k in
            let index = start + k
            if let mark = marks[index] { return mark }
            return index == currentTaskIndex ? .current : .none
        }
    }

    /// The question on screen closes its quest.
    private var isLastInQuest: Bool { questPosition.map { $0.question == $0.size } ?? false }

    /// The button that leaves the answer: "Xem kết quả" after the session's last question (when it
    /// needs no retry), "Xong nhiệm vụ" at the end of a quest, otherwise "Tiếp tục".
    private var continueTitle: String {
        if currentTaskIndex == tasks.count - 1 && !shouldRetryCurrentTask { return "Xem kết quả" }
        return isLastInQuest ? "Xong nhiệm vụ" : "Tiếp tục"
    }

    /// Records how the attempt went for the segments and the streak.
    private func mark(correct: Bool, score: Int) {
        let mark: QuizMark = correct ? .ok : LearningScoring.passes(score) ? .near : .bad
        marks[currentTaskIndex] = mark
        streak = mark == .bad ? 0 : streak + 1
    }

    /// The small line over each question.
    private func questionLabel(_ type: QuestionType) -> String {
        switch type {
        case .multipleChoice: "Chọn từ đúng nghĩa"
        case .listenAndType: "Nghe và viết lại"
        case .meaningAndType: "Viết từ có nghĩa này"
        case .sentenceScramble: "Ghép thành câu"
        case .pronunciationExample: "Đọc to câu"
        }
    }

    @ViewBuilder
    func questionView(for task: LearningTask) -> some View {
        let meaning = task.meanings.first
        VStack(spacing: 12) {
            if let skill = task.reinforcedSkill {
                Label("Tăng cường: \(skill.title)", systemImage: "bolt.heart.fill")
                    .font(.omniBody(12, weight: 700))
                    .foregroundStyle(palette.verdict(.near).text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(palette.verdict(.near).fill))
                    .accessibilityIdentifier("learning-reinforcement-badge")
            }

            Text(questionLabel(task.type).uppercased())
                .font(.omniBody(12, weight: 800))
                .tracking(0.8)
                .foregroundStyle(palette.muted)
                .padding(.top, 8)

            switch task.type {
            case .listenAndType:
                // The speaker and its speeds on one row, kept short so the keyboard bar never covers
                // them; the example sentence is the first hint now, not part of the question.
                HStack(spacing: 14) {
                    Button { replayListening(task) } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x6fa2ff), Color(hex: 0x2f6fd6)], startPoint: .top, endPoint: .bottom)))
                            .overlay(Circle().stroke(palette.outline(0x2f6fd6), lineWidth: 4))
                    }
                    .buttonStyle(QuizPressStyle(shape: Circle(), depth: 5, base: palette.outline(0x2f6fd6)))
                    .accessibilityLabel("Nghe lại")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach([1.0, 0.75, 0.5], id: \.self) { speed in
                                let on = listenSpeed == speed
                                Button {
                                    listenSpeed = speed
                                    replayListening(task)
                                } label: {
                                    Text(speed == 1 ? "1×" : speed == 0.75 ? "0,75×" : "0,5×")
                                        .font(.omniBody(13, weight: 700))
                                        .foregroundStyle(on ? palette.link : palette.muted)
                                        .padding(.horizontal, 12).frame(height: 40)
                                        .background(Capsule().fill(on ? palette.placed.fill : palette.card))
                                        .overlay(Capsule().stroke(on ? palette.placed.edge : palette.line, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Nghe tốc độ \(speed == 1 ? "thường" : speed == 0.75 ? "chậm" : "rất chậm")")
                            }
                        }
                        Text(signals.replayCount > 0 ? "Đã nghe lại \(signals.replayCount) lần" : "Bấm loa để nghe lại")
                            .font(.omniBody(12, weight: 700))
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.top, 4)

            case .meaningAndType, .multipleChoice:
                meaningCard(meaning)

            case .sentenceScramble:
                promptCard(task.vHint ?? meaning?.V_meaning ?? "")

            case .pronunciationExample:
                EmptyView()
            }
        }
    }

    private func promptCard(_ text: String) -> some View {
        Text(text)
            .font(.omniBody(17, weight: 700))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(palette.text)
            .quizCard(palette, padding: 18)
    }

    /// The word form and the Vietnamese meaning, large, with the English meaning under it.
    private func meaningCard(_ meaning: Vocabulary?) -> some View {
        VStack(spacing: 8) {
            if let form = meaning?.word_form, !form.isEmpty {
                Text(form)
                    .font(.omniBody(12, weight: 700))
                    .foregroundStyle(palette.pill.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.pill.fill))
            }
            if let vMeaning = meaning?.V_meaning, !vMeaning.isEmpty {
                Text(vMeaning)
                    .font(.omniBody(24, weight: 800))
                    .foregroundStyle(palette.text)
            }
            if let eMeaning = meaning?.E_meaning, !eMeaning.isEmpty {
                Text(eMeaning)
                    .font(.omniBody(14, weight: 500))
                    .foregroundStyle(palette.muted)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
        .quizCard(palette, padding: 16)
    }

    /// Hints opened so far, under the links so the hint button stays put.
    @ViewBuilder
    private func hintLines(for task: LearningTask) -> some View {
        if signals.hintLevel > 0 {
            let meaning = task.meanings.first
            VStack(spacing: 4) {
                ForEach(1...min(signals.hintLevel, 2), id: \.self) { level in
                    if let text = hintText(level: level, task: task, meaning: meaning) {
                        Text(text)
                            .font(.omniBody(15, weight: 700))
                            .foregroundStyle(palette.hint)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("learning-hint-panel")
        }
    }

    private func hintText(level: Int, task: LearningTask, meaning: Vocabulary?) -> String? {
        switch (task.type, level) {
        case (.listenAndType, 1): return task.blankedExample ?? meaning?.E_meaning
        case (.listenAndType, 2): return task.blankedExample == nil ? meaning?.EV_meaning : meaning?.E_meaning
        case (.meaningAndType, 1), (.multipleChoice, 1): return task.blankedExample ?? meaning?.englishExample
        case (.meaningAndType, 2):
            let letters = task.word.filter(\.isLetter).count
            return "Bắt đầu bằng “\(task.word.prefix(1))”, gồm \(letters) chữ cái"
        case (.multipleChoice, 2): return "Đã loại 2 phương án sai"
        case (.sentenceScramble, 1): return "Đã đặt sẵn từ đầu câu"
        case (.sentenceScramble, 2): return "Đã đặt sẵn nửa đầu câu"
        default: return nil
        }
    }

    /// What the learner answers with, under the question.
    @ViewBuilder
    private func answerArea(for task: LearningTask) -> some View {
        switch task.type {
        case .multipleChoice:
            optionGrid(for: task)
            supportLinks(for: task)
            hintLines(for: task)
        case .listenAndType, .meaningAndType:
            // Typed answers live in the bottom bar, right above the keyboard.
            EmptyView()
        case .sentenceScramble:
            sentenceScrambleInput
            supportLinks(for: task)
            hintLines(for: task)
        case .pronunciationExample:
            EmptyView()
        }
    }

    @ViewBuilder
    func inputArea(for task: LearningTask) -> some View {
        if task.type == .pronunciationExample {
            PronunciationExampleExerciseView(task: task, continueTitle: currentTaskIndex == tasks.count - 1 ? "Xem kết quả" : isLastInQuest ? "Xong nhiệm vụ" : "Tiếp tục") { isCorrect, details in
                completePronunciationTask(task, isCorrect: isCorrect, details: details)
            }
            .id(task.id)
        }
    }

    /// Answer tiles, two by two. Once answered: the right one green, a wrong pick red, the rest faded.
    private func optionGrid(for task: LearningTask) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
            ForEach(task.options, id: \.self) { option in
                let isAnswer = LearningTextNormalizer.normalizedAnswer(option) == LearningTextNormalizer.normalizedAnswer(task.word)
                Button(option) { checkAnswer(for: task, selected: option) }
                    .buttonStyle(QuizTileStyle(state: tileState(option, isAnswer: isAnswer), palette: palette))
                    .disabled(eliminatedOptions.contains(option))
                    .accessibilityIdentifier("learning-option-\(option)")
            }
        }
        .padding(.top, 4)
    }

    private func tileState(_ option: String, isAnswer: Bool) -> QuizTileStyle.State {
        guard let result = currentResult else { return eliminatedOptions.contains(option) ? .dim : .idle }
        return isAnswer ? .ok : option == result.selectedOption ? .bad : .dim
    }

    private func typedAnswerField(for task: LearningTask) -> some View {
        TextField("", text: $inputText, prompt: Text("gõ từ tiếng Anh").foregroundColor(palette.muted.opacity(0.7)))
            .textFieldStyle(.plain)
            .font(.omniBody(22, weight: 700))
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isAnswerFieldFocused ? Color(hex: 0x2f6fd6) : palette.line, lineWidth: 2)
            )
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .focused($isAnswerFieldFocused)
            .onAppear {
                scheduleTypedAnswerFocus(for: task)
            }
            .onSubmit {
                submitTypedAnswer(for: task)
            }
            .accessibilityLabel("Câu trả lời")
            .accessibilityIdentifier("learning-answer-field")
    }

    /// "Không nhớ" (give up), clearing a built sentence, and the hint ladder. Every use is recorded and priced.
    private func supportLinks(for task: LearningTask) -> some View {
        HStack {
            Button("Không nhớ") {
                signals.gaveUp = true
                finalizeAttempt(for: task, answerText: inputText)
            }
            .foregroundStyle(palette.muted)
            .accessibilityIdentifier("learning-give-up")

            Spacer()

            if task.type == .sentenceScramble, !selectedScrambleWords.isEmpty {
                Button("Xoá hết") {
                    signals.undoCount += selectedScrambleWords.count
                    availableScrambleWords.append(contentsOf: selectedScrambleWords)
                    selectedScrambleWords.removeAll()
                }
                .foregroundStyle(palette.muted)
                Spacer()
            }

            // Two hints at most: past them, "Không nhớ" shows the answer.
            Button(signals.hintLevel >= 2 ? "Gợi ý 2/2" : "Gợi ý \(signals.hintLevel + 1)/2") {
                openNextHint(for: task)
            }
            .foregroundStyle(signals.hintLevel >= 2 ? palette.muted.opacity(0.6) : palette.link)
            .disabled(signals.hintLevel >= 2)
            .accessibilityIdentifier("learning-hint")
        }
        .font(.omniBody(13.5, weight: 700))
        .buttonStyle(.plain)
        .frame(minHeight: 44)
    }

    private func rescueBanner(for task: LearningTask) -> some View {
        VStack(spacing: 2) {
            Text("Chưa đúng. Bạn còn 1 lần thử lại (−10 điểm).")
                .font(.omniBody(13.5, weight: 700))
                .foregroundStyle(Color(hex: 0xb3261e))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xffe7e5)))
            HStack {
                Button("Xem đáp án") {
                    awaitingRescue = false
                    finalizeAttempt(for: task, answerText: inputText)
                }
                .foregroundStyle(palette.muted)
                Spacer()
                Button("Nhập lại (−10)") {
                    awaitingRescue = false
                    signals.rescueUsed = true
                    inputText = ""
                    isAnswerFieldFocused = true
                }
                .foregroundStyle(palette.link)
                .accessibilityIdentifier("learning-rescue")
            }
            .font(.omniBody(13.5, weight: 700))
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        }
    }

    /// The built sentence in a dashed tray, the words left under it.
    private var sentenceScrambleInput: some View {
        VStack(spacing: 14) {
            FlowLayout(spacing: 8) {
                ForEach(Array(selectedScrambleWords.enumerated()), id: \.offset) { index, word in
                    Button(word) {
                        let removed = selectedScrambleWords.remove(at: index)
                        availableScrambleWords.append(removed)
                        signals.undoCount += 1
                    }
                    .buttonStyle(QuizTokenStyle(placed: true, palette: palette))
                    .accessibilityHint("Chạm để đưa từ về danh sách gợi ý")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            .padding(10)
            .padding(.bottom, 3)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.tray))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(palette.trayLine, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Câu của bạn, \(selectedScrambleWords.count) trên \(totalScrambleWordCount) từ")

            FlowLayout(spacing: 8) {
                ForEach(Array(availableScrambleWords.enumerated()), id: \.offset) { index, word in
                    Button(word) {
                        selectedScrambleWords.append(word)
                        availableScrambleWords.remove(at: index)
                        signals.tokenMoves += 1
                        markFirstInteraction()
                    }
                    .buttonStyle(QuizTokenStyle(placed: false, palette: palette))
                    .accessibilityHint("Chạm để thêm từ vào câu")
                    .accessibilityIdentifier("scramble-available-\(word)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 3)
        }
        .padding(.top, 2)
    }

    private var totalScrambleWordCount: Int {
        selectedScrambleWords.count + availableScrambleWords.count
    }

    /// The bottom bar: for typed answers the field, its hints and links sit on top of the blue 3D
    /// "Kiểm tra", so the keyboard lifts them all together and nothing hides behind it. Hints open
    /// above the links, so the hint button stays where it was tapped.
    private func checkBar(for task: LearningTask) -> some View {
        let scramble = task.type == .sentenceScramble
        return VStack(spacing: 6) {
            if !scramble {
                typedAnswerField(for: task)
                    .id(task.id)
                hintLines(for: task)
                if awaitingRescue { rescueBanner(for: task) } else { supportLinks(for: task) }
            }
            Button("Kiểm tra") {
                if scramble { checkAnswer(for: task) } else { submitTypedAnswer(for: task) }
            }
            .buttonStyle(Quiz3DButtonStyle(tone: .blue))
            .disabled(scramble ? !availableScrambleWords.isEmpty || selectedScrambleWords.isEmpty : !isTypedAnswerReady)
            .accessibilityIdentifier("learning-check")
        }
        .padding(.horizontal, scramble ? 18 : 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(palette.page.opacity(0.96))
    }

    private var isTypedAnswerReady: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitTypedAnswer(for task: LearningTask) {
        guard isTypedAnswerReady else { return }
        isAnswerFieldFocused = false
        checkAnswer(for: task)
    }

    private func completePronunciationTask(
        _ task: LearningTask,
        isCorrect: Bool,
        details: PronunciationAttemptDetails
    ) {
        guard currentTask?.id == task.id else { return }
        signals.pronunciationScore = details.finalScore
        signals.targetWordAccuracy = details.targetWordAccuracy
        signals.accuracyScore = details.accuracy
        signals.fluencyScore = details.fluency
        signals.completenessScore = details.completeness
        signals.modelPlays = details.modelPlays
        signals.recordings = details.recordings
        signals.firstInteractionMs = details.firstRecordingMs
        signals.pronunciationPassed = isCorrect
        let score = sealAttempt(for: task, answerText: nil)
        if isCorrect {
            correctAnswersCount += 1
        }
        mark(correct: isCorrect, score: score)
        shouldRetryCurrentTask = !LearningScoring.passes(score)
        lastAttemptScore = score
        // The reading's own result sheet was the feedback: go straight on.
        nextTask()
    }

    private func scheduleTypedAnswerFocus(for task: LearningTask) {
        guard isOnScreen, task.type == .listenAndType || task.type == .meaningAndType else { return }

        let taskID = task.id
        DispatchQueue.main.async {
            guard currentTask?.id == taskID,
                  currentResult == nil,
                  !isCompleted,
                  !isFinishingSession else {
                return
            }
            isAnswerFieldFocused = true
        }
    }
    
    /// The answer, at the bottom: right, nearly or wrong, the correction, the scores of a reading and the word to hear again.
    private func feedbackPanel(for result: TaskResult) -> some View {
        let task = result.task
        let passed = LearningScoring.passes(lastAttemptScore)
        let (title, verdict, tone): (String, QuizPalette.Verdict, Quiz3DButtonStyle.Tone) = result.isCorrect
            ? ("Chính xác!", .ok, .green)
            : passed ? ("Gần đúng", .near, .amber)
            : ("Chưa đúng", .bad, .red)
        let colors = palette.verdict(verdict)
        let meaning = task.meanings.first
        let text = palette.text, muted = palette.muted
        let shape = UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.omniDisplay(24))
                    .foregroundStyle(colors.text)
                Spacer()
                // This attempt's score, out of 100: hints, a retype and slowness take from it.
                Text("\(lastAttemptScore)/100")
                    .font(.omniDisplay(16))
                    .foregroundStyle(colors.text)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(Capsule().fill(palette.card.opacity(0.8)))
                    .accessibilityLabel("Điểm lượt này \(lastAttemptScore) trên 100")
            }
            if let line = correctionLine(for: result) {
                Text(line).font(.omniBody(14, weight: 600)).foregroundStyle(text).fixedSize(horizontal: false, vertical: true)
            }
            if !passed {
                Text("Câu này sẽ quay lại sau.").font(.omniBody(12.5, weight: 600)).foregroundStyle(muted)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(task.word).font(.omniBody(18, weight: 800)).foregroundStyle(text)
                        if let ipa = meaning?.IPA, !ipa.isEmpty { Text(ipa).font(.omniBody(13.5)).foregroundStyle(muted) }
                    }
                    if let short = meaning?.V_meaning ?? meaning?.EV_meaning {
                        Text(short).font(.omniBody(13.5)).foregroundStyle(text).lineLimit(2).accessibilityIdentifier("vocabulary-short-meaning")
                    }
                }
                Spacer(minLength: 0)
                Button { speakAnswer(task) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.link)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(palette.placed.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nghe phát âm")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
            .padding(.top, 10).padding(.bottom, 10)
            Button(continueTitle) { nextTask() }
                .buttonStyle(Quiz3DButtonStyle(tone: tone))
                .accessibilityIdentifier("learning-next")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            shape.fill(colors.fill)
                .shadow(color: .black.opacity(0.12), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .onAppear { speakAnswer(task) }
    }

    /// Reads the answer aloud: the word for word questions, the whole sentence for sentence ones.
    private func speakAnswer(_ task: LearningTask) {
        let sentence = task.type == .sentenceScramble ? task.correctSentence
            : task.type == .pronunciationExample ? task.pronunciationExample : nil
        if let sentence, !sentence.isEmpty {
            SpeechManager.shared.speak(example: sentence, targetWord: task.word, ipa: task.meanings.first?.IPA)
        } else {
            playAllAudios(for: task.word, meanings: task.meanings)
        }
    }

    private func correctionLine(for result: TaskResult) -> String? {
        let task = result.task
        guard !result.isCorrect else { return nil }
        switch task.type {
        case .multipleChoice: return "Bạn chọn: \(result.selectedOption ?? "") · đáp án: \(task.word)"
        case .sentenceScramble: return "Câu đúng: \(task.correctSentence ?? "")"
        case .pronunciationExample: return nil
        case .listenAndType, .meaningAndType:
            return result.answerText.isEmpty ? "Đáp án: \(task.word)" : "Bạn viết: \(result.answerText) · đáp án: \(task.word)"
        }
    }

    func playAllAudios(for word: String, meanings: [Vocabulary]) {
        var seenIPAs = Set<String>()
        var count = 0
        for m in meanings {
            let ipa = m.IPA ?? ""
            if !seenIPAs.contains(ipa) {
                seenIPAs.insert(ipa)
                SpeechManager.shared.speak(word: word, ipa: ipa, stopPrevious: count == 0)
                count += 1
            }
        }
    }
    
    func checkAnswer(for task: LearningTask, selected: String? = nil) {
        guard task.type != .pronunciationExample, currentResult == nil else { return }
        markFirstInteraction()

        switch task.type {
        case .multipleChoice:
            guard let selected else { return }
            signals.chosenOptions.append(selected)
            let isRight = LearningTextNormalizer.normalizedAnswer(selected) == LearningTextNormalizer.normalizedAnswer(task.word)
            signals.submissions.append(AnswerSubmission(text: selected, kind: isRight ? .correct : .far, atMs: elapsedMs))
            finalizeAttempt(for: task, answerText: selected, selectedOption: selected)
        case .sentenceScramble:
            let expected = LearningTextNormalizer.sentenceScrambleWords(task.correctSentence ?? "").map { $0.lowercased() }
            let built = selectedScrambleWords.map { $0.lowercased() }
            let isRight = built == expected
            if !isRight {
                let misplaced = zip(built, expected).filter { $0 != $1 }.count + abs(built.count - expected.count)
                signals.misplacedShare = Double(misplaced) / Double(max(expected.count, 1))
                signals.correctPrefix = zip(built, expected).prefix { $0 == $1 }.count
            }
            let text = selectedScrambleWords.joined(separator: " ")
            signals.submissions.append(AnswerSubmission(text: text, kind: isRight ? .correct : .far, atMs: elapsedMs))
            finalizeAttempt(for: task, answerText: text)
        case .listenAndType, .meaningAndType:
            let kind = LearningScoring.classify(answer: inputText, target: task.word)
            signals.submissions.append(AnswerSubmission(text: inputText, kind: kind, atMs: elapsedMs))
            if kind != .correct && canOfferRescue(for: task) {
                awaitingRescue = true
                return
            }
            finalizeAttempt(for: task, answerText: inputText)
        case .pronunciationExample:
            break
        }
    }

    /// One retype for a first wrong submission made without any support.
    private func canOfferRescue(for task: LearningTask) -> Bool {
        task.type.allowsRescue && !signals.rescueUsed && signals.submissions.count == 1
            && signals.hintLevel == 0 && signals.replayCount == 0 && signals.slowestSpeed >= 1
    }

    private func openNextHint(for task: LearningTask) {
        guard currentResult == nil, signals.hintLevel < 2 else { return }
        markFirstInteraction()
        signals.hintLevel += 1
        signals.hintOpenedMs.append(elapsedMs)

        switch (task.type, signals.hintLevel) {
        case (.multipleChoice, 2):
            let wrong = task.options.filter {
                LearningTextNormalizer.normalizedAnswer($0) != LearningTextNormalizer.normalizedAnswer(task.word)
            }
            eliminatedOptions = Set(wrong.shuffled().prefix(2))
        case (.sentenceScramble, 1), (.sentenceScramble, 2):
            let expected = LearningTextNormalizer.sentenceScrambleWords(task.correctSentence ?? "")
            let placed = signals.hintLevel == 1 ? 1 : max(1, expected.count / 2)
            var available = task.scrambledWords
            var selected: [String] = []
            for token in expected.prefix(placed) {
                if let index = available.firstIndex(of: token) {
                    selected.append(available.remove(at: index))
                }
            }
            selectedScrambleWords = selected
            availableScrambleWords = available
        default:
            break
        }

    }

    private var elapsedMs: Int {
        Int(Date().timeIntervalSince(taskPresentedAt) * 1_000)
    }

    private func markFirstInteraction() {
        guard signals.firstInteractionMs == nil else { return }
        signals.firstInteractionMs = elapsedMs
        if let playedAt = lastPlayAt {
            signals.firstKeyAfterAudioMs = Int(Date().timeIntervalSince(playedAt) * 1_000)
        }
    }

    private func scheduleAutoplay(for task: LearningTask) {
        guard isOnScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard currentTask?.id == task.id, currentResult == nil else { return }
            signals.autoplayed = true
            signals.playSpeeds.append(1)
            lastPlayAt = Date()
            SpeechManager.shared.speak(word: task.word, ipa: task.meanings.first?.IPA, rateMultiplier: 1)
        }
    }

    private func replayListening(_ task: LearningTask) {
        signals.replayCount += 1
        signals.playSpeeds.append(listenSpeed)
        lastPlayAt = Date()
        SpeechManager.shared.speak(word: task.word, ipa: task.meanings.first?.IPA, rateMultiplier: listenSpeed)
    }

    /// Closes the attempt, scores it and opens the answer card.
    private func finalizeAttempt(for task: LearningTask, answerText: String, selectedOption: String? = nil) {
        awaitingRescue = false
        isAnswerFieldFocused = false
        let score = sealAttempt(for: task, answerText: answerText)
        let isCorrect = signals.isCorrect
        if isCorrect {
            correctAnswersCount += 1
        }
        mark(correct: isCorrect, score: score)
        shouldRetryCurrentTask = !LearningScoring.passes(score)
        lastAttemptScore = score
        currentResult = TaskResult(
            task: task,
            isCorrect: isCorrect,
            selectedOption: selectedOption,
            answerText: answerText
        )
    }

    /// Fills time and exposure signals, records the attempt and returns its score.
    private func sealAttempt(for task: LearningTask, answerText: String?) -> Int {
        signals.activeMs = max(0, elapsedMs - signals.pausedMs)
        signals.positionInSession = currentTaskIndex
        if let key = task.vocabularyID {
            signals.questionsSinceExposure = lastExposureByWord[key].map { currentTaskIndex - $0 }
            lastExposureByWord[key] = currentTaskIndex
        }
        let score = LearningScoring.attemptScore(type: task.type, word: task.word, signals: signals)
        recordLearningAttempt(for: task, answerText: answerText, score: score)
        return score
    }

    func nextTask() {
        if let current = currentTask {
            tasks = LearningRetryPlanner.tasks(
                afterAnswering: current,
                isCorrect: !shouldRetryCurrentTask,
                scheduledTasks: tasks
            )
        }
        
        shouldRetryCurrentTask = false
        
        inputText = ""
        currentResult = nil
        
        currentTaskIndex += 1
        
        if currentTaskIndex >= tasks.count {
            SpeechManager.shared.stopSpeaking()
            isFinishingSession = true
            Task { await finishSession() }
        } else if let questMode, AdventureQuests.ends(planned: questMode.planned, total: tasks.count).contains(currentTaskIndex) {
            // A quest is done. Once the planned quests are over, the questions left are retries:
            // spread them so one word does not come back twice in a row.
            if currentTaskIndex >= questMode.planned.reduce(0, +) {
                tasks = Array(tasks[..<currentTaskIndex])
                    + SessionComposer.spreadAdjacentRepeats(Array(tasks[currentTaskIndex...]), wordKey: { $0.vocabularyID ?? $0.word })
            }
            // Back to the stage map; the next quest opens the next questions.
            questMode.onStep(questProgress)
        } else {
            if let next = currentTask, next.type == .listenAndType {
                scheduleAutoplay(for: next)
            }
        }
    }
    
    private var questProgress: LearningQuestProgress {
        LearningQuestProgress(tasks: tasks, answered: currentTaskIndex, attempts: learningAttempts,
                              attemptNumbers: attemptNumbersByExercise, correctAnswers: correctAnswersCount,
                              exposures: lastExposureByWord, startedAt: sessionStartedAt)
    }

    private func restore(_ progress: LearningQuestProgress) {
        guard progress.answered < progress.tasks.count else { return }
        tasks = progress.tasks
        currentTaskIndex = progress.answered
        learningAttempts = progress.attempts
        attemptNumbersByExercise = progress.attemptNumbers
        correctAnswersCount = progress.correctAnswers
        lastExposureByWord = progress.exposures
        sessionStartedAt = progress.startedAt
    }

    /// Quest number and this question's place in it, for the adventure header.
    private var questPosition: (quest: Int, question: Int, size: Int)? {
        guard let questMode else { return nil }
        let ends = AdventureQuests.ends(planned: questMode.planned, total: tasks.count)
        let done = AdventureQuests.done(answered: currentTaskIndex, ends: ends)
        let start = done == 0 ? 0 : ends[done - 1]
        let end = done < ends.count ? ends[done] : tasks.count
        return (done + 1, currentTaskIndex - start + 1, max(1, end - start))
    }

    func initializeTaskState() {
        isAnswerFieldFocused = false
        inputText = ""
        taskPresentedAt = Date()
        signals = AttemptSignals()
        awaitingRescue = false
        eliminatedOptions = []
        listenSpeed = 1
        lastPlayAt = nil

        guard let task = currentTask else { return }

        if task.type == .sentenceScramble {
            availableScrambleWords = task.scrambledWords
            selectedScrambleWords = []
            signals.tokenCount = task.scrambledWords.count
        }
        if task.type == .multipleChoice {
            signals.optionCount = task.options.count
        }

        scheduleTypedAnswerFocus(for: task)
    }


    #if DEBUG
    private func completeDeveloperTestSession() {
        guard !isFinishingSession else { return }

        // Treat every originally scheduled question as correct so reward testing
        // follows the same server path as a fully completed real session.
        correctAnswersCount = max(correctAnswersCount, tasks.count)
        SpeechManager.shared.stopSpeaking()
        currentResult = nil
        isFinishingSession = true
        Task { await finishSession() }
    }
    #endif

    private func recordLearningAttempt(for task: LearningTask, answerText: String?, score: Int) {
        let vocabularyIDs = Array(Set(task.meanings
            .filter { ReviewScheduler.isDue($0, now: Date()) }
            .compactMap(\.id)
        )).sorted()

        guard !vocabularyIDs.isEmpty else { return }

        let attemptNumber = (attemptNumbersByExercise[task.exerciseID] ?? 0) + 1
        attemptNumbersByExercise[task.exerciseID] = attemptNumber
        var evidence = signals
        evidence.attemptNumber = attemptNumber
        let costs = LearningScoring.skillCosts(type: task.type, word: task.word, signals: evidence)

        learningAttempts.append(
            LearningAttemptTelemetry(
                id: UUID(),
                exercise_id: task.exerciseID,
                user_vocabulary_ids: vocabularyIDs,
                task_type: task.type.telemetryName,
                attempt_number: attemptNumber,
                is_correct: task.type == .pronunciationExample ? evidence.pronunciationPassed : evidence.isCorrect,
                answer_text: answerText?.trimmingCharacters(in: .whitespacesAndNewlines),
                response_duration_ms: min(max(evidence.activeMs, 0), 600_000),
                pronunciation_score: evidence.pronunciationScore,
                answered_at: Self.telemetryDateFormatter.string(from: Date()),
                attempt_score: score,
                skill_costs: Dictionary(uniqueKeysWithValues: costs.map { ($0.key.rawValue, ($0.value * 10).rounded() / 10) }),
                signals: evidence,
                is_reinforcement: task.reinforcedSkill != nil
            )
        )
    }


    private static let telemetryDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    @MainActor
    func finishSession() async {
        do {
            let vocabularyIDs = Array(Set(learningVocabGroups.flatMap { group in
                // A displayed word may have several meanings, each with its own
                // review date. Only settle the meanings that were actually due;
                // otherwise the server correctly rejects a mixed due/not-due set.
                group
                    .filter { ReviewScheduler.isDue($0, now: Date()) }
                    .compactMap(\.id)
            })).sorted()

            guard !vocabularyIDs.isEmpty else {
                throw NSError(
                    domain: "OmninaryLearning",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Thiếu mã định danh của từ vựng."]
                )
            }

            // One idempotent server transaction owns levels, review dates, streak,
            // rewards, and Ditan heart consumption.
            let result = try await VocabularyRepository.completeLearningSession(
                sessionId: sessionID,
                userVocabularyIds: vocabularyIDs,
                correctAnswers: correctAnswersCount,
                attempts: learningAttempts,
                startedAt: Self.telemetryDateFormatter.string(from: sessionStartedAt)
            )
            lastEarnedPoints = result.earned_points
            wordResults = result.word_results ?? []
            accountIsExtra = result.is_extra
            resultItems = await WordResultLoader.load(results: wordResults, words: learningVocabGroups.flatMap { $0 },
                                                      sessionID: sessionID, isExtra: result.is_extra)
            // Route only the server-confirmed first completed session of the day.
            shouldRouteToHomeAfterCompletion = result.is_first_learning_today == true
            if shouldRouteToHomeAfterCompletion {
                StreakActionPresenter.shared.enqueue(.learning,
                    previousDays: result.previous_streak_count ?? max(0, result.streak_count - 1),
                    newDays: result.streak_count, wasFrozen: result.was_frozen_today == true)
            }
            UserDefaults.standard.set(result.new_points, forKey: "omni_reward_points")
            OmniLearningHeartManager.shared.applySettlement(result)
            OmniStreakFreezeManager.shared.applyRemoteState(.init(
                streak_count: result.streak_count, saved_streak_count: result.saved_streak_count ?? result.streak_count,
                last_learning_date: result.last_learning_date, streak_freeze_date: result.streak_freeze_date,
                streak_restore_expires_at: result.streak_restore_expires_at,
                streak_protected_through: result.streak_protected_through,
                streak_freeze_used_at: result.streak_freeze_used_at,
                streak_freeze_requires_learning: result.streak_freeze_requires_learning,
                streak_restored_on: result.streak_restored_on))

            if result.is_extra {
                NotificationManager.shared.schedulePotentialStreakRestoreAlert(afterLearningOn: Date())
            } else {
                NotificationManager.shared.cancelPotentialStreakRestoreAlert()
            }

            isFinishingSession = false
            isCompleted = true
            questMode?.onSettled(result, questProgress)
        } catch {
            isFinishingSession = false
            saveErrorMessage = learningSaveErrorMessage(for: error)
        }
    }

    private func learningSaveErrorMessage(for error: Error) -> String {
        let technicalDetail = String(describing: error)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var message = "Chưa thể xác nhận kết quả với máy chủ. Bạn có thể thử lại an toàn mà không bị tăng cấp hoặc trừ lượt hai lần."

        #if DEBUG
        if !technicalDetail.isEmpty {
            message += "\n\nChi tiết để kiểm tra: \(technicalDetail)"
        }
        #endif

        return message
    }
    
    struct DetailRow: View {
        let title: String
        let content: String
        var color: Color = .primary
        var isItalic: Bool = false
        var isExtra: Bool = false
        var isMultiple: Bool = false
        var onSpeak: (() -> Void)? = nil
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isMultiple {
                    VocabularySupplementaryCards(value: content, isExtra: isExtra)
                } else if let onSpeak = onSpeak {
                    HStack(alignment: .top) {
                        Text(content)
                            .font(.body)
                            .foregroundColor(color)
                            .italic(isItalic)
                        Spacer()
                        Button(action: onSpeak) {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    Text(content)
                        .font(.body)
                        .foregroundColor(color)
                        .italic(isItalic)
                }
            }
            .padding(.bottom, 2)
        }
    }
}

#if DEBUG
/// Local fixtures exercise the production layouts without changing account progress.
struct LearningLayoutPreview: View {
    static let words: [Vocabulary] = (0..<80).map { index in
        Vocabulary(id: "layout-\(index)", vocab: index == 0 ? "apple" : "word \(index)",
                   CEFR: "A1", IPA: "/ˈæp.əl/", word_form: "noun",
                   E_meaning: "A round fruit with firm, white flesh and a green or red skin.",
                   EV_meaning: "Một loại quả tròn, thịt trắng, vỏ xanh hoặc đỏ.", V_meaning: "Quả táo",
                   E_example: "She eats an apple every morning.", V_example: "Cô ấy ăn một quả táo mỗi sáng.",
                   learning_level: 0)
    }

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-LearningLayoutReview") {
            VocabularyLearningView()
        } else {
            let tasks = [QuestionType.meaningAndType, .listenAndType, .sentenceScramble, .multipleChoice, .meaningAndType].map { type in
                LearningTask(word: "apple", meanings: [Self.words[0]], type: type,
                             options: ["apple", "pear", "orange", "peach"],
                             correctSentence: "She eats an apple every morning",
                             scrambledWords: ["every", "apple", "She", "morning", "an", "eats"],
                             vHint: "Cô ấy ăn một quả táo mỗi sáng.",
                             blankedExample: "She eats an _____ every morning.")
            }
            LearningSessionView(sessionID: UUID(), tasks: tasks, learningVocabGroups: [[Self.words[0]]], onClose: {})
        }
    }
}
#endif

/// How an adventure stage drives a learning session: shown one quest (a few questions) at a time.
struct LearningQuestMode {
    var isVisible: Bool
    /// Questions in each planned quest; retries after them form quests of `AdventureQuests.size`.
    var planned: [Int]
    /// Where a saved adventure left off.
    var resume: LearningQuestProgress? = nil
    /// After each finished quest that is not the last, with everything needed to resume.
    var onStep: (LearningQuestProgress) -> Void
    /// The learner asked to go back to the map without answering.
    var onHide: () -> Void
    /// The server settled the session (levels, review dates, streak, points), with every answer given.
    var onSettled: (VocabularyLearningSettlementResult, LearningQuestProgress) -> Void
    /// The island, shown under the results title.
    var place: String? = nil
}
