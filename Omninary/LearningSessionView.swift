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
    let sessionID: UUID
    @State var tasks: [LearningTask]
    let learningVocabGroups: [[Vocabulary]]
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

                VStack {
                    if isCompleted {
                        completionView
                    } else if let saveErrorMessage {
                        savingFailureView(message: saveErrorMessage)
                    } else if isFinishingSession {
                        savingProgressView
                    } else if let task = currentTask {
                        ProgressView(value: progress)
                            .padding()
                            .tint(isExtra ? ExtraAuroraPalette.ice : .blue)

                        Text("Câu \(currentTaskIndex + 1) / \(tasks.count)")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

                        if task.type == .pronunciationExample {
                            inputArea(for: task)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(spacing: 20) {
                                    questionView(for: task)
                                        .padding(.top)
                                    inputArea(for: task)
                                }
                                .padding(.bottom, 30)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                learningActionBar(for: task)
                            }
                        }
                    }
                }
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        SpeechManager.shared.speak(word: first.word, ipa: first.meanings.first?.IPA)
                    }
                }
            }
            .onChange(of: currentTaskIndex) { oldValue, newValue in
                initializeTaskState()
            }
            .sheet(item: $currentResult, onDismiss: {
                nextTask()
            }) { result in
                resultView(for: result)
                    .presentationDetents([.fraction(1.0), .large])
                    .presentationDragIndicator(.visible)
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
        VStack(spacing: 20) {
            switch task.type {
            case .listenAndType:
                Button(action: {
                    SpeechManager.shared.speak(word: task.word, ipa: task.meanings.first?.IPA)
                }) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding()
                        .background(Circle().fill(Color.blue.opacity(0.1)))
                }
                Text("Nghe và viết lại từ đúng")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
            case .meaningAndType:
                VStack(spacing: 15) {
                    Text(task.meanings.count > 1 ? "Viết từ vựng có các nghĩa sau:" : "Viết từ vựng có nghĩa sau:")
                        .font(.subheadline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    
                    ForEach(Array(task.meanings.enumerated()), id: \.element.id) { index, meaning in
                        HStack(alignment: .top, spacing: 10) {
                            let form = meaning.word_form ?? ""
                            let eMeaning = meaning.E_meaning ?? ""
                            
                            if !form.isEmpty {
                                Text(form)
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if !eMeaning.isEmpty {
                                    Text(eMeaning)
                                        .font(.body)
                                        .foregroundColor(isExtra ? .white : .primary)
                                }
                                
                                if let vMeaning = meaning.V_meaning, !vMeaning.isEmpty {
                                    Text(vMeaning)
                                        .font(.body)
                                        .bold()
                                        .foregroundColor(isExtra ? .white : .primary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding(AppSpacing.row)
                .appSurface(.row, isExtra: isExtra)
                
            case .multipleChoice:
                VStack(spacing: 15) {
                    Text("Chọn nghĩa Tiếng Việt đúng cho từ:")
                        .font(.subheadline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    
                    Text(task.word)
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(isExtra ? .white : .primary)
                }
                
            case .sentenceScramble:
                VStack(spacing: 15) {
                    Text("Ghép các từ để hoàn thiện câu:")
                        .font(.subheadline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    
                    if let hint = task.vHint, !hint.isEmpty {
                        Text(hint)
                            .font(.headline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(isExtra ? .white : .primary)
                            .padding(AppSpacing.row)
                            .frame(maxWidth: .infinity)
                            .appSurface(.row, isExtra: isExtra)
                    } else {
                        let meanings = task.meanings.compactMap { $0.V_meaning }.joined(separator: ", ")
                        Text(meanings)
                            .font(.headline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundColor(isExtra ? .white : .primary)
                            .padding(AppSpacing.row)
                            .frame(maxWidth: .infinity)
                            .appSurface(.row, isExtra: isExtra)
                    }
                }

            case .pronunciationExample:
                EmptyView()
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    func inputArea(for task: LearningTask) -> some View {
        VStack {
            if task.type == .pronunciationExample {
                PronunciationExampleExerciseView(task: task) { isCorrect, pronunciationScore in
                    completePronunciationTask(
                        task,
                        isCorrect: isCorrect,
                        pronunciationScore: pronunciationScore
                    )
                }
                .id(task.id)
            } else if task.type == .multipleChoice {
                ForEach(task.options, id: \.self) { option in
                    Button(action: {
                        checkAnswer(for: task, selected: option)
                    }) {
                        Text(option)
                            .font(.body)
                            .padding(AppSpacing.row)
                            .frame(maxWidth: .infinity)
                            .appSurface(.row, isExtra: isExtra)
                            .foregroundColor(isExtra ? .white : .primary)
                    }
                }
            } else if task.type == .sentenceScramble {
                sentenceScrambleInput
            } else {
                TextField("Nhập từ tiếng Anh...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .padding(14)
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
            }
        }
        .padding(task.type == .pronunciationExample ? 0 : 16)
    }

    private var sentenceScrambleInput: some View {
        VStack(spacing: 16) {
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
                    .foregroundColor(.blue)

                Spacer()

                Text("\(selectedScrambleWords.count)/\(totalScrambleWordCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                if !selectedScrambleWords.isEmpty {
                    Button {
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
                        .frame(maxWidth: .infinity, minHeight: 126)
                } else {
                    FlowLayout(spacing: 9) {
                        ForEach(Array(selectedScrambleWords.enumerated()), id: \.offset) { index, word in
                            Button {
                                let removed = selectedScrambleWords.remove(at: index)
                                availableScrambleWords.append(removed)
                            } label: {
                                Text(word)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .foregroundColor(.white)
                                    .background(Color.blue)
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
            .frame(height: 150)
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
                        .frame(maxWidth: .infinity, minHeight: 126)
                } else {
                    FlowLayout(spacing: 9) {
                        ForEach(Array(availableScrambleWords.enumerated()), id: \.offset) { index, word in
                            Button {
                                selectedScrambleWords.append(word)
                                availableScrambleWords.remove(at: index)
                            } label: {
                                Text(word)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
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
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollIndicators(.visible)
            .frame(height: 150)
        }
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
        .clipShape(RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius))
    }

    private var totalScrambleWordCount: Int {
        selectedScrambleWords.count + availableScrambleWords.count
    }

    @ViewBuilder
    private func learningActionBar(for task: LearningTask) -> some View {
        switch task.type {
        case .sentenceScramble:
            sentenceScrambleCheckBar(for: task)
        case .listenAndType, .meaningAndType:
            typedAnswerCheckBar(for: task)
        case .multipleChoice, .pronunciationExample:
            EmptyView()
        }
    }

    private func sentenceScrambleCheckBar(for task: LearningTask) -> some View {
        LearningBottomActionBar {
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
        }
    }

    private func typedAnswerCheckBar(for task: LearningTask) -> some View {
        LearningBottomActionBar {
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
        }
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
        pronunciationScore: Int?
    ) {
        guard currentTask?.id == task.id else { return }
        recordLearningAttempt(
            for: task,
            isCorrect: isCorrect,
            answerText: nil,
            pronunciationScore: pronunciationScore
        )
        if isCorrect {
            correctAnswersCount += 1
        }
        shouldRetryCurrentTask = !isCorrect
        nextTask()
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
        let task = result.task
        let isCorrect = result.isCorrect
        
        VStack(spacing: 15) {
            HStack(spacing: 8) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : .red)
                Text(isCorrect ? "Chính xác!" : "Chưa đúng rồi!")
                    .font(.headline)
                    .foregroundColor(isCorrect ? .green : .red)

                if isCorrect {
                    HStack(spacing: 3) {
                        OmniCoinView(size: 14, showShadow: false)
                        Text("+1")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppSemanticColor.attention)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            
            if !isCorrect {
                if task.type == .multipleChoice {
                    let correctMeaning = task.meanings.first?.V_meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let expected = correctMeaning.isEmpty ? "Không có nghĩa" : correctMeaning
                    Text("Bạn chọn: \(result.selectedOption ?? ""). Đáp án đúng: \(expected)")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if task.type == .sentenceScramble {
                    Text("Câu đúng: \(task.correctSentence ?? "")")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Bạn nhập: \(result.answerText). Đáp án đúng: \(task.word)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text(task.word).font(.title).bold()
                        Spacer()
                        Button(action: {
                            playAllAudios(for: task.word, meanings: task.meanings)
                        }) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title)
                        }
                    }
                    .padding(.horizontal)
                    
                    ForEach(Array(task.meanings.enumerated()), id: \.element.id) { index, meaning in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(task.meanings.count > 1 ? "NGHĨA \(index + 1)" : "CHI TIẾT NGHĨA")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 10)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                if let form = meaning.word_form, !form.isEmpty {
                                    HStack {
                                        DetailRow(title: "Từ loại (Word form)", content: form, color: .purple)
                                        Spacer()
                                        Button(action: {
                                            SpeechManager.shared.speak(word: task.word, ipa: meaning.IPA)
                                        }) {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .foregroundColor(.blue)
                                                .font(.title3)
                                        }
                                    }
                                }
                                if let ipa = meaning.IPA, !ipa.isEmpty {
                                    DetailRow(title: "Phát âm (IPA)", content: ipa, color: .blue)
                                }
                                if let cefr = meaning.CEFR, !cefr.isEmpty {
                                    DetailRow(title: "Cấp độ (CEFR)", content: cefr, color: .orange)
                                }
                                if let eMeaning = meaning.E_meaning, !eMeaning.isEmpty {
                                    DetailRow(title: "Nghĩa Tiếng Anh", content: eMeaning, onSpeak: {
                                        SpeechManager.shared.speak(word: eMeaning, ipa: nil)
                                    })
                                }
                                if let evMeaning = meaning.EV_meaning, !evMeaning.isEmpty {
                                    DetailRow(title: "Nghĩa Anh - Việt", content: evMeaning)
                                }
                                if let vMeaning = meaning.V_meaning, !vMeaning.isEmpty {
                                    DetailRow(title: "Nghĩa Tiếng Việt", content: vMeaning)
                                }
                                if let eExample = meaning.englishExample {
                                    DetailRow(title: "Ví dụ Tiếng Anh", content: eExample, isItalic: true, onSpeak: {
                                        SpeechManager.shared.speak(
                                            example: eExample,
                                            targetWord: task.word,
                                            ipa: meaning.IPA
                                        )
                                    })
                                }
                                if let vExample = meaning.vietnameseExample {
                                    DetailRow(title: "Ví dụ Tiếng Việt", content: vExample)
                                }
                                if let family = meaning.word_family, !family.isEmpty {
                                    DetailRow(title: "Từ cùng họ (Word family)", content: family, isExtra: isExtra, isMultiple: true)
                                }
                                if let synonymous = meaning.synonymous, !synonymous.isEmpty {
                                    DetailRow(title: "Từ đồng nghĩa", content: synonymous, isExtra: isExtra, isMultiple: true)
                                }
                                if let antonym = meaning.antonym, !antonym.isEmpty {
                                    DetailRow(title: "Từ trái nghĩa", content: antonym, isExtra: isExtra, isMultiple: true)
                                }
                                if let collocation = meaning.collocation, !collocation.isEmpty {
                                    DetailRow(title: "Cụm từ thường đi cùng", content: collocation, isExtra: isExtra, isMultiple: true)
                                }

                                if let formula = meaning.formula, !formula.isEmpty {
                                    DetailRow(title: "Mẫu cấu trúc", content: formula, isExtra: isExtra, isMultiple: true)
                                }
                                if let note = meaning.note, !note.isEmpty {
                                    DetailRow(title: "Ghi chú cách dùng", content: note, isExtra: isExtra, isMultiple: true)
                                }
                                if let bonus = meaning.bonus, !bonus.isEmpty {
                                    DetailRow(title: "Thông tin mở rộng", content: bonus, isExtra: isExtra, isMultiple: true)
                                }
                            }
                            .padding(AppSpacing.row)
                            .appSurface(.row, isExtra: isExtra)
                        }
                    }
                }
                .padding(.vertical)
            }
            
            Button {
                currentResult = nil
            } label: {
                LearningActionButtonLabel(
                    title: "Tiếp tục",
                    systemImage: "arrow.right.circle.fill"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
        }
        .padding()
        .onAppear {
            playAllAudios(for: task.word, meanings: task.meanings)
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
        guard task.type != .pronunciationExample else { return }

        let actualWord = task.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var isCorrect = false
        var answer = ""
        
        if task.type == .multipleChoice {
            let correctMeaning = task.meanings.first?.V_meaning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let expected = correctMeaning.isEmpty ? "Không có nghĩa" : correctMeaning
            isCorrect = (selected == expected)
        } else if task.type == .sentenceScramble {
            let built = selectedScrambleWords.joined(separator: " ").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let correct = task.correctSentence?.replacingOccurrences(of: "[.,!?;:]", with: "", options: .regularExpression).lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            isCorrect = (built == correct)
            answer = built
        } else {
            answer = inputText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            isCorrect = (answer == actualWord)
        }
        
        // Mark for retry if incorrect
        shouldRetryCurrentTask = !isCorrect
        if isCorrect {
            correctAnswersCount += 1
        }
        recordLearningAttempt(
            for: task,
            isCorrect: isCorrect,
            answerText: selected ?? answer
        )
        
        currentResult = TaskResult(
            task: task,
            isCorrect: isCorrect,
            selectedOption: selected,
            answerText: answer
        )
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
        } else {
            if let next = currentTask, next.type == .listenAndType {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    SpeechManager.shared.speak(word: next.word, ipa: next.meanings.first?.IPA)
                }
            }
        }
    }
    
    func initializeTaskState() {
        isAnswerFieldFocused = false
        inputText = ""
        taskPresentedAt = Date()

        guard let task = currentTask else { return }

        if task.type == .sentenceScramble {
            availableScrambleWords = task.scrambledWords
            selectedScrambleWords = []
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

    private func recordLearningAttempt(
        for task: LearningTask,
        isCorrect: Bool,
        answerText: String?,
        pronunciationScore: Int? = nil
    ) {
        let vocabularyIDs = Array(Set(task.meanings
            .filter { ReviewScheduler.isDue($0, now: Date()) }
            .compactMap(\.id)
        )).sorted()

        guard !vocabularyIDs.isEmpty else { return }

        let attemptNumber = (attemptNumbersByExercise[task.exerciseID] ?? 0) + 1
        attemptNumbersByExercise[task.exerciseID] = attemptNumber
        let duration = Int(Date().timeIntervalSince(taskPresentedAt) * 1_000)

        learningAttempts.append(
            LearningAttemptTelemetry(
                id: UUID(),
                exercise_id: task.exerciseID,
                user_vocabulary_ids: vocabularyIDs,
                task_type: task.type.telemetryName,
                attempt_number: attemptNumber,
                is_correct: isCorrect,
                answer_text: answerText?.trimmingCharacters(in: .whitespacesAndNewlines),
                response_duration_ms: min(max(duration, 0), 600_000),
                pronunciation_score: pronunciationScore,
                answered_at: Self.telemetryDateFormatter.string(from: Date())
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
