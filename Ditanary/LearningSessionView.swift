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
        .font(.headline)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
}

struct LearningBottomActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}

struct LearningSessionView: View {
    @State var tasks: [LearningTask]
    let learningVocabGroups: [[Vocabulary]]
    let onClose: () -> Void
    
    @State private var currentTaskIndex = 0
    @State private var isCompleted = false
    @State private var isFinishingSession = false
    @State private var hasStartedCelebration = false
    
    @State private var inputText = ""
    @State private var currentResult: TaskResult? = nil
    
    // Scramble logic state
    @State private var selectedScrambleWords: [String] = []
    @State private var availableScrambleWords: [String] = []
    @State private var shouldRetryCurrentTask = false
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
            VStack {
                if isCompleted {
                    completionView
                } else if isFinishingSession {
                    savingProgressView
                } else if let task = currentTask {
                    ProgressView(value: progress)
                        .padding()
                        .tint(.blue)
                    
                    Text("Câu \(currentTaskIndex + 1) / \(tasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
            .navigationTitle(isCompleted ? "Hoàn thành" : "Đang học")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isCompleted && !isFinishingSession {
                        Button("Thoát") {
                            onClose()
                        }
                    }
                }
            }
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
        }
    }

    private var completionView: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 132, height: 132)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 62, weight: .bold))
                        .foregroundColor(.orange)
                }

                VStack(spacing: 8) {
                    Text("Hoàn thành bài học!")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text("Bạn đã ôn tập \(learningVocabGroups.count) từ vựng và cập nhật lịch ôn tiếp theo.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Tiến độ đã được lưu", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())

                Button {
                    CelebrationFeedbackPlayer.shared.stop()
                    onClose()
                } label: {
                    LearningActionButtonLabel(
                        title: "Tiếp tục",
                        systemImage: "arrow.right.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
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
                    Text("Viết từ vựng có các nghĩa sau:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
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
                                        .foregroundColor(.primary)
                                }
                                
                                if let vMeaning = meaning.V_meaning, !vMeaning.isEmpty {
                                    Text(vMeaning)
                                        .font(.body)
                                        .bold()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.gray.opacity(0.1)))
                
            case .multipleChoice:
                VStack(spacing: 15) {
                    Text("Chọn nghĩa Tiếng Việt đúng cho từ:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(task.word)
                        .font(.largeTitle)
                        .bold()
                }
                
            case .sentenceScramble:
                VStack(spacing: 15) {
                    Text("Ghép các từ để hoàn thiện câu:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let hint = task.vHint, !hint.isEmpty {
                        Text(hint)
                            .font(.headline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 15).fill(Color.orange.opacity(0.1)))
                    } else {
                        let meanings = task.meanings.compactMap { $0.V_meaning }.joined(separator: ", ")
                        Text(meanings)
                            .font(.headline)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 15).fill(Color.orange.opacity(0.1)))
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
                PronunciationExampleExerciseView(task: task) { isCorrect in
                    completePronunciationTask(task, isCorrect: isCorrect)
                }
                .id(task.id)
            } else if task.type == .multipleChoice {
                ForEach(task.options, id: \.self) { option in
                    Button(action: {
                        checkAnswer(for: task, selected: option)
                    }) {
                        Text(option)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.blue, lineWidth: 1))
                            .foregroundColor(.primary)
                    }
                }
            } else if task.type == .sentenceScramble {
                sentenceScrambleInput
            } else {
                TextField("Nhập từ tiếng Anh...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
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
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.22), lineWidth: 1)
        )
    }

    private var availableScrambleWordsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Từ gợi ý", systemImage: "square.grid.2x2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("Còn \(availableScrambleWords.count) từ")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            ScrollView {
                if availableScrambleWords.isEmpty {
                    Label("Đã dùng hết từ gợi ý", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.green)
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
                                    .foregroundColor(.primary)
                                    .background(Color(UIColor.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
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
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        )
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
            .buttonStyle(.borderedProminent)
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
            .buttonStyle(.borderedProminent)
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

    private func completePronunciationTask(_ task: LearningTask, isCorrect: Bool) {
        guard currentTask?.id == task.id else { return }
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
            HStack {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : .red)
                Text(isCorrect ? "Chính xác!" : "Chưa đúng rồi!")
                    .font(.headline)
                    .foregroundColor(isCorrect ? .green : .red)
            }
            
            if !isCorrect {
                if task.type == .multipleChoice {
                    let correctMeaning = task.meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty }.joined(separator: " / ")
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
                            Text("NGHĨA \(index + 1)")
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
                                    DetailRow(title: "Từ cùng họ (Word family)", content: family)
                                }
                                if let synonymous = meaning.synonymous, !synonymous.isEmpty {
                                    DetailRow(title: "Từ đồng nghĩa", content: synonymous)
                                }
                                if let antonym = meaning.antonym, !antonym.isEmpty {
                                    DetailRow(title: "Từ trái nghĩa", content: antonym)
                                }
                                if let bonus = meaning.bonus, !bonus.isEmpty {
                                    DetailRow(title: "Thông tin mở rộng", content: bonus)
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(10)
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
            .buttonStyle(.borderedProminent)
            .tint(isCorrect ? .green : .red)
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
            let correctMeaning = task.meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty }.joined(separator: " / ")
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

        guard let task = currentTask else { return }

        if task.type == .sentenceScramble {
            availableScrambleWords = task.scrambledWords
            selectedScrambleWords = []
        }

        scheduleTypedAnswerFocus(for: task)
    }
    
    @MainActor
    func finishSession() async {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for group in learningVocabGroups {
            for vocab in group {
                guard let id = vocab.id else { continue }
                
                let newLvl = ReviewScheduler.nextLearningLevel(from: vocab.learning_level ?? 0)
                let nextStr = ReviewScheduler.reviewString(for: newLvl, from: now, formatter: formatter)
                
                do {
                    try await VocabularyRepository.updateLearningData(id: id, learningLevel: newLvl, nextReview: nextStr)
                } catch {
                    print("Lỗi cập nhật level cho \(vocab.vocab ?? ""): \(error)")
                }
            }
        }
        
        // Record activity and update streak
        await recordActivity()

        isFinishingSession = false
        isCompleted = true
    }
    
    func recordActivity() async {
        guard let myUserId = AuthManager.shared.currentUser?.id.uuidString else { return }
        
        do {
            try await UserProgressRepository.recordDailyActivityAndUpdateStreak(userId: myUserId)
        } catch {
            print("Lỗi đồng bộ hoạt động với Supabase: \(error)")
        }
    }
    
    struct DetailRow: View {
        let title: String
        let content: String
        var color: Color = .primary
        var isItalic: Bool = false
        var onSpeak: (() -> Void)? = nil
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let onSpeak = onSpeak {
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
