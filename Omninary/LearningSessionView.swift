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

struct LearningBottomActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, AppSpacing.page)
            .padding(.vertical, AppSpacing.item)
            .appActionBar()
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
    @State private var isReviewingWord = false
    
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
    @State private var lastFeeLines: [String] = []
    @State private var wordResults: [WordMasteryResult] = []
    @State private var lastPlayAt: Date?
    
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
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }

                VStack(spacing: 8) {
                    if isCompleted {
                        completionView
                    } else if let saveErrorMessage {
                        savingFailureView(message: saveErrorMessage)
                    } else if isFinishingSession {
                        savingProgressView
                    } else if let task = currentTask {
                        ProgressView(value: progress)
                            .padding(.horizontal)
                            .tint(isExtra ? ExtraAuroraPalette.ice : .blue)

                        Text("Câu \(currentTaskIndex + 1) / \(tasks.count)")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
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
                                VStack(spacing: 10) {
                                    questionView(for: task)
                                        .padding(.top, 4)
                                    if task.type == .multipleChoice || task.type == .sentenceScramble {
                                        inputArea(for: task)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .scrollBounceBehavior(.basedOnSize)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                learningActionBar(for: task)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isCompleted && !isFinishingSession {
                        Button("Thoát") {
                            onClose()
                        }
                    }
                }
                #if DEBUG
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isCompleted && !isFinishingSession {
                        Button {
                            isShowingDeveloperFinishConfirmation = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver.fill")
                        }
                        .accessibilityLabel("Hoàn tất phiên kiểm thử")
                    }
                }
                #endif
            }
            .streakRescueWarning(onLeave: onClose)
            .onAppear {
                initializeTaskState()
                if let first = tasks.first, first.type == .listenAndType {
                    scheduleAutoplay(for: first)
                }
            }
            .onChange(of: currentTaskIndex) { oldValue, newValue in
                initializeTaskState()
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
            .overlay {
                if let result = currentResult {
                    LearningCenteredPopup(isExtra: isExtra, fitsContent: !isReviewingWord) {
                        if isReviewingWord {
                            wordReview(for: result.task)
                        } else {
                            resultView(for: result)
                        }
                    }
                    .id(isReviewingWord)
                }
            }
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

    private var completionView: some View {
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
                    CelebrationFeedbackPlayer.shared.stop()
                    if shouldRouteToHomeAfterCompletion {
                        NotificationCenter.default.post(name: .returnToHomeAfterLearning, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .returnToLearningTab, object: nil)
                    }
                    onClose()
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
    
    @ViewBuilder
    func questionView(for task: LearningTask) -> some View {
        let meaning = task.meanings.first
        let theme = AppTheme(isExtra: isExtra)
        return VStack(spacing: 10) {
            if let skill = task.reinforcedSkill {
                Label("Tăng cường: \(skill.title)", systemImage: "bolt.heart.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppSemanticColor.attention)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(AppSemanticColor.attention.opacity(0.12)))
                    .accessibilityIdentifier("learning-reinforcement-badge")
            }

            switch task.type {
            case .listenAndType:
                Button(action: { replayListening(task) }) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme(isExtra: isExtra).accent)
                        .padding(12)
                        .background(Circle().fill(AppTheme(isExtra: isExtra).accent.opacity(0.1)))
                }
                .accessibilityLabel("Nghe lại")
                Text("Nghe và viết lại từ hoặc cụm từ")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryText)
                Picker("Tốc độ", selection: $listenSpeed) {
                    Text("1×").tag(1.0)
                    Text("0,75×").tag(0.75)
                    Text("0,5×").tag(0.5)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                if let context = task.blankedExample {
                    promptCard(context, font: .body)
                }

            case .meaningAndType:
                Text("Viết từ có nghĩa sau:")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryText)
                meaningCard(meaning)

            case .multipleChoice:
                Text("Chọn từ có nghĩa sau:")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryText)
                meaningCard(meaning)

            case .sentenceScramble:
                Text("Ghép các từ để hoàn thiện câu:")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryText)
                promptCard(task.vHint ?? meaning?.V_meaning ?? "", font: .subheadline)

            case .pronunciationExample:
                EmptyView()
            }

        }
        .padding(.horizontal)
    }

    private func promptCard(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundColor(isExtra ? .white : .primary)
            .padding(AppSpacing.row)
            .frame(maxWidth: .infinity)
            .appSurface(.row, isExtra: isExtra)
    }

    /// English meaning, its Vietnamese translation and the short Vietnamese meaning.
    private func meaningCard(_ meaning: Vocabulary?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let form = meaning?.word_form, !form.isEmpty {
                Text(form)
                    .font(.caption)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.15))
                    .cornerRadius(6)
            }
            if let vMeaning = meaning?.V_meaning, !vMeaning.isEmpty {
                Text(vMeaning)
                    .font(.headline)
                    .foregroundColor(isExtra ? .white : .primary)
            }
            if let eMeaning = meaning?.E_meaning, !eMeaning.isEmpty {
                Text(eMeaning)
                    .font(.subheadline)
                    .foregroundColor(isExtra ? .white : .primary)
            }
            if let evMeaning = meaning?.EV_meaning, !evMeaning.isEmpty {
                Text(evMeaning)
                    .font(.caption)
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }

    @ViewBuilder
    private func hintPanel(for task: LearningTask) -> some View {
        let meaning = task.meanings.first
        VStack(alignment: .leading, spacing: 4) {
            ForEach(1...min(signals.hintLevel, 2), id: \.self) { level in
                if let text = hintText(level: level, task: task, meaning: meaning) {
                    Label(text, systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(isExtra ? Color.white : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppSemanticColor.attention.opacity(0.1)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("learning-hint-panel")
    }

    private func hintText(level: Int, task: LearningTask, meaning: Vocabulary?) -> String? {
        switch (task.type, level) {
        case (.listenAndType, 1): return meaning?.E_meaning
        case (.listenAndType, 2): return meaning?.EV_meaning
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
    @ViewBuilder
    func inputArea(for task: LearningTask) -> some View {
        VStack(spacing: 10) {
            if task.type == .pronunciationExample {
                PronunciationExampleExerciseView(task: task) { isCorrect, details in
                    completePronunciationTask(task, isCorrect: isCorrect, details: details)
                }
                .id(task.id)
            } else if task.type == .multipleChoice {
                ForEach(task.options.filter { !eliminatedOptions.contains($0) }, id: \.self) { option in
                    Button(action: {
                        checkAnswer(for: task, selected: option)
                    }) {
                        Text(option)
                            .font(.title3.weight(.semibold))
                            .padding(AppSpacing.row)
                            .frame(maxWidth: .infinity)
                            .appSurface(.row, isExtra: isExtra)
                            .foregroundColor(isExtra ? .white : .primary)
                    }
                    .accessibilityIdentifier("learning-option-\(option)")
                }
            } else if task.type == .sentenceScramble {
                sentenceScrambleInput
            }

        }
        .padding(.horizontal, task.type == .pronunciationExample ? 0 : 16)
    }

    private func typedAnswerField(for task: LearningTask) -> some View {
        TextField("Nhập từ tiếng Anh...", text: $inputText)
            .textFieldStyle(.plain)
            .font(.headline)
            .padding(12)
            .background(
                isExtra
                    ? AnyShapeStyle(Color.white.opacity(0.12))
                    : AnyShapeStyle(Color(UIColor.systemBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isExtra ? ExtraAuroraPalette.ice.opacity(0.4) : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(isExtra ? .white : .primary)
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
            .accessibilityIdentifier("learning-answer-field")
    }

    /// Give up and the hint ladder. Every use is recorded and priced.
    private func supportBar(for task: LearningTask) -> some View {
        HStack(spacing: 10) {
            Button(role: .destructive) {
                signals.gaveUp = true
                finalizeAttempt(for: task, answerText: inputText)
            } label: {
                Label("Chịu thua", systemImage: "flag.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppSemanticColor.destructive)
            .accessibilityIdentifier("learning-give-up")

            Spacer()

            Button {
                openNextHint(for: task)
            } label: {
                Label(signals.hintLevel >= 2 ? "Xem đáp án" : "Gợi ý \(signals.hintLevel + 1)/3",
                      systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppSemanticColor.attention)
            .accessibilityIdentifier("learning-hint")
        }
        .padding(.top, 6)
    }

    private func rescueBanner(for task: LearningTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chưa đúng. Bạn có 1 mạng để nhập lại (−10 điểm).", systemImage: "heart.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppSemanticColor.attention)
            HStack {
                Button("Xem đáp án") {
                    awaitingRescue = false
                    finalizeAttempt(for: task, answerText: inputText)
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Nhập lại (−10)") {
                    awaitingRescue = false
                    signals.rescueUsed = true
                    inputText = ""
                    isAnswerFieldFocused = true
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("learning-rescue")
            }
        }
        .padding(AppSpacing.row)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppSemanticColor.attention.opacity(0.1)))
        .padding(.top, 6)
    }

    private var sentenceScrambleInput: some View {
        VStack(spacing: 10) {
            selectedScrambleWordsPanel
            availableScrambleWordsPanel
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedScrambleWordsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Câu của bạn", systemImage: "text.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme(isExtra: isExtra).accent)

                Spacer()

                Text("\(selectedScrambleWords.count)/\(totalScrambleWordCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                if !selectedScrambleWords.isEmpty {
                    Button {
                        signals.undoCount += selectedScrambleWords.count
                        availableScrambleWords.append(contentsOf: selectedScrambleWords)
                        selectedScrambleWords.removeAll()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .accessibilityLabel("Đặt lại câu")
                }
            }

            ScrollView {
                if selectedScrambleWords.isEmpty {
                    Text("Chạm các từ gợi ý để tạo câu")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(selectedScrambleWords.enumerated()), id: \.offset) { index, word in
                            Button {
                                let removed = selectedScrambleWords.remove(at: index)
                                availableScrambleWords.append(removed)
                                signals.undoCount += 1
                            } label: {
                                Text(word)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .foregroundColor(.white)
                                    .background(AppTheme(isExtra: isExtra).accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Chạm để đưa từ về danh sách gợi ý")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.visible)
            .frame(height: 96)
        }
        .padding(14)
        .background(
            isExtra
                ? AnyShapeStyle(Color.white.opacity(0.08))
                : AnyShapeStyle(Color.blue.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isExtra ? ExtraAuroraPalette.ice.opacity(0.35) : Color.blue.opacity(0.22), lineWidth: 1)
        )
    }

    private var availableScrambleWordsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Từ gợi ý", systemImage: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

                Spacer()

                Text("Còn \(availableScrambleWords.count) từ")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
            }

            ScrollView {
                if availableScrambleWords.isEmpty {
                    Label("Đã dùng hết từ gợi ý", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppSemanticColor.success)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(availableScrambleWords.enumerated()), id: \.offset) { index, word in
                            Button {
                                selectedScrambleWords.append(word)
                                availableScrambleWords.remove(at: index)
                                signals.tokenMoves += 1
                                markFirstInteraction()
                            } label: {
                                Text(word)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .foregroundColor(isExtra ? .white : .primary)
                                    .background(
                                        isExtra
                                            ? AnyShapeStyle(Color.white.opacity(0.12))
                                            : AnyShapeStyle(Color(UIColor.systemBackground))
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isExtra ? Color.white.opacity(0.18) : Color.gray.opacity(0.25), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Chạm để thêm từ vào câu")
                            .accessibilityIdentifier("scramble-available-\(word)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.visible)
            .frame(height: 96)
        }
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
        .clipShape(RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius))
    }

    private var totalScrambleWordCount: Int {
        selectedScrambleWords.count + availableScrambleWords.count
    }

    private func learningActionBar(for task: LearningTask) -> some View {
        VStack(spacing: 6) {
            if task.type == .listenAndType || task.type == .meaningAndType {
                typedAnswerField(for: task)
                    .id(task.id)
            }
            ScrollView {
                if signals.hintLevel > 0 { hintPanel(for: task) }
            }
            .frame(height: 48)
            .scrollBounceBehavior(.basedOnSize)
            if awaitingRescue {
                rescueBanner(for: task)
            } else {
                supportBar(for: task)
            }
            if task.type == .sentenceScramble {
                sentenceScrambleCheckBar(for: task)
            } else if task.type == .listenAndType || task.type == .meaningAndType {
                typedAnswerCheckBar(for: task)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .appActionBar()
    }

    private func sentenceScrambleCheckBar(for task: LearningTask) -> some View {
        Button {
            checkAnswer(for: task)
        } label: {
            LearningActionButtonLabel(
                title: "Kiểm tra",
                systemImage: "checkmark.circle.fill"
            )
        }
        .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        .disabled(!availableScrambleWords.isEmpty || selectedScrambleWords.isEmpty)
        .accessibilityIdentifier("learning-check")
    }

    private func typedAnswerCheckBar(for task: LearningTask) -> some View {
        Button {
            submitTypedAnswer(for: task)
        } label: {
            LearningActionButtonLabel(
                title: "Kiểm tra",
                systemImage: "checkmark.circle.fill"
            )
        }
        .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        .disabled(!isTypedAnswerReady)
        .accessibilityIdentifier("learning-check")
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
        shouldRetryCurrentTask = !LearningScoring.passes(score)
        lastAttemptScore = score
        lastFeeLines = []
        isReviewingWord = true
        currentResult = TaskResult(task: task, isCorrect: isCorrect, selectedOption: nil, answerText: "")
    }

    private func scheduleTypedAnswerFocus(for task: LearningTask) {
        guard task.type == .listenAndType || task.type == .meaningAndType else { return }

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
    
    @ViewBuilder
    func resultView(for result: TaskResult) -> some View {
        VStack(spacing: 15) {
            ViewThatFits(in: .vertical) {
                resultDetails(for: result)
                ScrollView { resultDetails(for: result) }
                    .scrollBounceBehavior(.basedOnSize)
            }

            Button("OK") { isReviewingWord = true }
                .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
                .accessibilityIdentifier("learning-result-ok")
        }
        .padding(20)
        .accessibilityElement(children: .contain)
    }

    private func resultDetails(for result: TaskResult) -> some View {
        let task = result.task
        let isCorrect = result.isCorrect
        return VStack(spacing: 15) {
                    HStack(spacing: 8) {
                        Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isCorrect ? .green : .red)
                        Text(isCorrect ? "Chính xác!" : "Chưa đúng rồi!")
                            .font(.headline)
                            .foregroundColor(isCorrect ? .green : .red)

                        Text("\(lastAttemptScore)/100")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(LearningScoring.passes(lastAttemptScore) ? AppSemanticColor.success : AppSemanticColor.attention)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            .accessibilityIdentifier("learning-attempt-score")
                    }

                    VStack(spacing: 3) {
                        ForEach(lastFeeLines, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                        }
                        if !LearningScoring.passes(lastAttemptScore) {
                            Text("Từ 50 điểm trở xuống: câu này sẽ quay lại cuối phiên để luyện tiếp.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppSemanticColor.attention)
                                .multilineTextAlignment(.center)
                        }
                    }

                    if !isCorrect {
                        if task.type == .multipleChoice {
                            Text("Bạn chọn: \(result.selectedOption ?? ""). Đáp án đúng: \(task.word)")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else if task.type == .sentenceScramble {
                            Text("Câu đúng: \(task.correctSentence ?? "")")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text(result.answerText.isEmpty ? "Đáp án đúng: \(task.word)" : "Bạn nhập: \(result.answerText). Đáp án đúng: \(task.word)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                }
                .frame(maxWidth: .infinity)
    }

    private func wordReview(for task: LearningTask) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(task.word)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(LearningLevelDisplay.title(for: task.meanings.first?.learning_level))
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.18), in: Capsule())
                    Button { playAllAudios(for: task.word, meanings: task.meanings) } label: {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Nghe phát âm")
                }
                if let meaning = task.meanings.first {
                    VocabularyCardMetadata(item: meaning, onSpeak: {
                        SpeechManager.shared.speak(word: task.word, ipa: meaning.IPA)
                    })
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(AppTheme(isExtra: isExtra).primaryGradient)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(task.meanings, id: \.vocabularyIdentity) { meaning in
                        VocabularyCardContent(item: meaning, isExtra: isExtra)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)

            Button { nextTask() } label: {
                LearningActionButtonLabel(title: "Tiếp tục", systemImage: "arrow.right.circle.fill")
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .onAppear { playAllAudios(for: task.word, meanings: task.meanings) }
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
        guard currentResult == nil else { return }
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

        // The third hint reveals the answer: the attempt ends with 0 points.
        if signals.hintLevel >= 3 {
            finalizeAttempt(for: task, answerText: inputText)
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
        shouldRetryCurrentTask = !LearningScoring.passes(score)
        lastAttemptScore = score
        lastFeeLines = feeLines(for: task)
        isReviewingWord = false
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

    private func feeLines(for task: LearningTask) -> [String] {
        guard signals.isCorrect else {
            if signals.gaveUp { return ["Chịu thua: 0 điểm"] }
            if signals.hintLevel >= 3 { return ["Đã xem đáp án: 0 điểm"] }
            return ["Trả lời sai: 0 điểm"]
        }
        var lines: [String] = []
        if task.type == .listenAndType {
            if signals.replayCount > 0 { lines.append("Nghe lại \(signals.replayCount) lần: −\(signals.replayCount)") }
            let speed = LearningScoring.speedFee(slowestSpeed: signals.slowestSpeed)
            if speed > 0 { lines.append("Nghe chậm: −\(speed)") }
        }
        if signals.hintLevel > 0 {
            lines.append("Gợi ý \(signals.hintLevel): −\(LearningScoring.hintFee(type: task.type, level: signals.hintLevel))")
        }
        if signals.rescueUsed { lines.append("Dùng 1 mạng: −10") }
        let slow = Int(LearningScoring.slownessFee(type: task.type, word: task.word, signals: signals).rounded())
        if slow > 0 { lines.append("Chậm hơn thời gian tham chiếu: −\(slow)") }
        return lines
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
        isReviewingWord = false
        
        currentTaskIndex += 1
        
        if currentTaskIndex >= tasks.count {
            SpeechManager.shared.stopSpeaking()
            isFinishingSession = true
            Task { await finishSession() }
        } else {
            if let next = currentTask, next.type == .listenAndType {
                scheduleAutoplay(for: next)
            }
        }
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

/// Shared, bounded presentation for exercise feedback and vocabulary review.
struct LearningCenteredPopup<Content: View>: View {
    let isExtra: Bool
    /// Size the card to its content (short feedback) instead of filling the screen.
    var fitsContent = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.42).ignoresSafeArea()
                content()
                    .frame(maxWidth: 560)
                    .frame(maxHeight: fitsContent ? nil : max(0, geometry.size.height - 40))
                    .fixedSize(horizontal: false, vertical: fitsContent)
                    .appSurface(.detail, isExtra: isExtra)
                    .clipShape(RoundedRectangle(cornerRadius: AppSurfaceKind.detail.cornerRadius))
                    .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isModal)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
