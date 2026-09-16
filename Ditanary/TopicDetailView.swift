import SwiftUI

struct TopicDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let topic: String
    var topicInfo: UserTopic? = nil
    var topicSubmission: TopicContribution? = nil
    var vocabs: [Vocabulary]
    var saveAsSystem: Bool = false
    var onRefresh: () -> Void
    
    @State private var selectedVocabForEdit: Vocabulary? = nil
    @State private var showingAddVocab = false
    @State private var isSubmittingTopic = false
    @State private var isDeletingTopic = false
    @State private var topicReviewMessage = ""
    @State private var showingTopicReviewAlert = false
    @State private var showingDeleteTopicConfirm = false
    @State private var shouldDismissAfterTopicAlert = false
    @State private var removedVocabularyIDs: Set<String> = []
    @State private var deletingWordKeys: Set<String> = []
    @State private var shouldDismissAfterLastVocabularyRemoval = false

    private var displayedVocabs: [Vocabulary] {
        vocabs.filter { vocabulary in
            guard let id = vocabulary.id else { return true }
            return !removedVocabularyIDs.contains(id)
        }
    }
    
    var groupedByWord: [String: [Vocabulary]] {
        Dictionary(grouping: displayedVocabs, by: { $0.vocab?.trimmingCharacters(in: .whitespaces) ?? "Unknown" })
    }
    
    var uniqueWords: [String] {
        groupedByWord.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var body: some View {
        List {
            if let topicInfo, topicInfo.visibility == "private" {
                Section {
                    privateTopicReviewCard(topicInfo)
                }
                .listRowBackground(Color.clear)
            }

            if displayedVocabs.isEmpty {
                Text("Không có từ vựng nào trong chủ đề này.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(uniqueWords, id: \.self) { word in
                    let meanings = groupedByWord[word] ?? []
                    let firstMeaning = meanings.first
                    
                    NavigationLink(destination: WordDetailView(
                        word: word,
                        meanings: meanings,
                        saveAsSystem: saveAsSystem,
                        isPrivateTopic: isPrivateTopic,
                        onRefresh: onRefresh,
                        onVocabularyDeleted: markVocabularyRemoved
                    )) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(word)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if meanings.contains(where: { $0.visibility == "private" }) {
                                    learningTag("Riêng tư", foreground: .white, background: .purple)
                                }
                                
                                let learningItem = meanings.first(where: { ($0.learning_level ?? 0) > 0 })
                                let level = learningItem?.learning_level ?? 0
                                if level >= 6 {
                                    learningTag("Master", foreground: .white, background: .purple)

                                    if let score = pronunciationAverage(for: meanings) {
                                        HStack(spacing: 2) {
                                            Image(systemName: "mic.fill")
                                                .font(.system(size: 8))
                                            Text("\(score)/100")
                                        }
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(score >= 70 ? .green : .orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((score >= 70 ? Color.green : Color.orange).opacity(0.2))
                                        .cornerRadius(4)
                                    }
                                } else {
                                    learningTag(
                                        "\(level)/6",
                                        foreground: level == 0 ? .red : .orange,
                                        background: (level == 0 ? Color.red : Color.yellow).opacity(0.2)
                                    )
                                }
                                
                                Spacer()
                            }
                            
                            if let ipa = firstMeaning?.IPA, !ipa.isEmpty {
                                Text(ipa)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            
                            // Nối các nghĩa Tiếng Việt lại
                            let vMeanings = Array(Set(meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty })).joined(separator: "; ")
                            if !vMeanings.isEmpty {
                                Text(vMeanings)
                                    .font(.body)
                                    .lineLimit(1) // Thu gọn ở màn hình ngoài
                            }

                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await deleteWord(meanings, wordKey: word) }
                        } label: {
                            Label(
                                deletingWordKeys.contains(word) ? "Đang xóa" : "Xóa từ",
                                systemImage: "trash"
                            )
                        }
                        .disabled(!deletingWordKeys.isEmpty)
                        
                        if canEdit(firstMeaning) {
                            Button {
                                selectedVocabForEdit = firstMeaning
                            } label: {
                                Label("Sửa", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .navigationTitle(topic)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dismissAfterLastVocabularyRemovalIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddVocab = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedVocabForEdit) { vocab in
            AddVocabView(existing: vocab, saveAsSystem: saveAsSystem, onComplete: {
                onRefresh()
                selectedVocabForEdit = nil
            })
        }
        .sheet(isPresented: $showingAddVocab) {
            AddVocabView(saveAsSystem: saveAsSystem, fixedTopic: topic, fixedTopicId: fixedTopicId, onComplete: {
                onRefresh()
            })
        }
        .alert("Thông báo", isPresented: $showingTopicReviewAlert) {
            Button("OK") {
                onRefresh()
                if shouldDismissAfterTopicAlert {
                    shouldDismissAfterTopicAlert = false
                    dismiss()
                }
            }
        } message: {
            Text(topicReviewMessage)
        }
        .confirmationDialog("Xoá topic riêng?", isPresented: $showingDeleteTopicConfirm, titleVisibility: .visible) {
            if let topicInfo {
                Button("Xoá topic", role: .destructive) {
                    Task { await deletePrivateTopic(topicInfo) }
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Topic này chưa có từ vựng nào nên có thể xoá khỏi My Vocabulary.")
        }
    }

    private var fixedTopicId: String? {
        topicInfo?.id ?? displayedVocabs.first?.topic_id
    }

    private var isPrivateTopic: Bool {
        topicInfo?.visibility == "private"
    }

    private var canDeletePrivateTopic: Bool {
        topicInfo?.visibility == "private" && displayedVocabs.isEmpty && topicSubmission?.status != "pending"
    }

    private func deleteWord(_ meanings: [Vocabulary], wordKey: String) async {
        let ids = meanings.compactMap(\.id)
        guard !ids.isEmpty, deletingWordKeys.insert(wordKey).inserted else { return }
        defer { deletingWordKeys.remove(wordKey) }

        var firstError: Error?
        for id in ids {
            do {
                try await VocabularyRepository.delete(id: id)
                removedVocabularyIDs.insert(id)
            } catch {
                firstError = error
                break
            }
        }

        onRefresh()

        if let firstError {
            topicReviewMessage = "Xoá từ thất bại: \(firstError.localizedDescription)"
            showingTopicReviewAlert = true
        } else if displayedVocabs.isEmpty {
            dismiss()
        }
    }

    private func markVocabularyRemoved(_ id: String) {
        removedVocabularyIDs.insert(id)
        onRefresh()

        if displayedVocabs.isEmpty {
            shouldDismissAfterLastVocabularyRemoval = true
        }
    }

    private func dismissAfterLastVocabularyRemovalIfNeeded() {
        guard shouldDismissAfterLastVocabularyRemoval, displayedVocabs.isEmpty else { return }
        shouldDismissAfterLastVocabularyRemoval = false
        dismiss()
    }

    private func canEdit(_ item: Vocabulary?) -> Bool {
        guard let item else { return false }
        return AuthManager.shared.isAdmin || item.visibility == "private"
    }

    @ViewBuilder
    private func privateTopicReviewCard(_ topicInfo: UserTopic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Topic riêng", systemImage: "lock.fill")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                if let status = topicSubmission?.status {
                    privateTopicStatusBadge(status)
                }
            }

            Text("Bạn có thể học topic này ngay. Khi thấy bộ từ đủ hay, hãy gửi admin duyệt để chia sẻ lên hệ thống chung.")
                .font(.caption)
                .foregroundColor(.secondary)

            if topicSubmission?.status == "pending" {
                Label("Đang chờ admin duyệt", systemImage: "clock.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
            } else if canSubmitTopic {
                Button {
                    Task { await submitTopicForReview(topicInfo) }
                } label: {
                    HStack {
                        if isSubmittingTopic {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(topicSubmission?.status == "rejected" ? "Gửi duyệt lại" : "Gửi chia sẻ lên hệ thống")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(canSubmitTopic ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(!canSubmitTopic || isSubmittingTopic)
            } else {
                Text("Hãy thêm ít nhất một từ trước khi gửi duyệt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if canDeletePrivateTopic {
                Button(role: .destructive) {
                    showingDeleteTopicConfirm = true
                } label: {
                    HStack {
                        if isDeletingTopic {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                        Text("Xoá topic riêng")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.red)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                }
                .disabled(isDeletingTopic)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func privateTopicStatusBadge(_ status: String) -> some View {
        if status == "pending" {
            Text("Chờ duyệt")
                .font(.caption.bold())
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
        } else if status == "rejected" {
            Text("Không duyệt")
                .font(.caption.bold())
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
        }
    }

    private var canSubmitTopic: Bool {
        !displayedVocabs.isEmpty
    }

    private func submitTopicForReview(_ topicInfo: UserTopic) async {
        isSubmittingTopic = true
        defer { isSubmittingTopic = false }
        shouldDismissAfterTopicAlert = false

        do {
            try await ContributionRepository.submitPrivateTopicForReview(topic: topicInfo, vocabs: displayedVocabs)
            topicReviewMessage = "Đã gửi topic cho admin duyệt."
            showingTopicReviewAlert = true
        } catch {
            topicReviewMessage = "Gửi duyệt thất bại: \(error.localizedDescription)"
            showingTopicReviewAlert = true
        }
    }

    private func deletePrivateTopic(_ topicInfo: UserTopic) async {
        isDeletingTopic = true
        defer { isDeletingTopic = false }

        do {
            try await VocabularyRepository.deletePrivateTopic(topicInfo)
            shouldDismissAfterTopicAlert = true
            topicReviewMessage = "Đã xoá topic riêng."
            showingTopicReviewAlert = true
        } catch {
            shouldDismissAfterTopicAlert = false
            topicReviewMessage = "Xoá topic thất bại: \(error.localizedDescription)"
            showingTopicReviewAlert = true
        }
    }

    private func learningTag(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .cornerRadius(4)
    }

    private func pronunciationAverage(for meanings: [Vocabulary]) -> Int? {
        let scores = meanings.compactMap(\.pronunciation_score)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }
}

struct WordDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let word: String
    var meanings: [Vocabulary]
    var saveAsSystem: Bool = false
    var isPrivateTopic: Bool = false
    var onRefresh: () -> Void
    var onVocabularyDeleted: (String) -> Void = { _ in }
    
    @State private var selectedVocab: Vocabulary? = nil
    @State private var isSubmittingContribution = false
    @State private var contributionMessage = ""
    @State private var showingContributionAlert = false
    @State private var submissionStatuses: [String: VocabSubmissionStatus] = [:]
    @State private var removedMeaningIDs: Set<String> = []

    private var displayedMeanings: [Vocabulary] {
        meanings.filter { meaning in
            guard let id = meaning.id else { return true }
            return !removedMeaningIDs.contains(id)
        }
    }
    
    var body: some View {
        List {
            ForEach(Array(displayedMeanings.enumerated()), id: \.element.id) { index, item in
                Section(header: HStack {
                    Text("Nghĩa \(index + 1)")
                    if item.visibility == "private" {
                        privateTag()
                    }
                }) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let form = item.word_form, !form.isEmpty {
                            HStack {
                                DetailRow(title: "Từ loại (Word form)", content: form, color: .purple)
                                Spacer()
                                Button(action: {
                                    SpeechManager.shared.speak(word: item.vocab ?? "", ipa: item.IPA)
                                }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                        }
                        if let ipa = item.IPA, !ipa.isEmpty {
                            DetailRow(title: "Phát âm (IPA)", content: ipa, color: .blue)
                        }
                        if let cefr = item.CEFR, !cefr.isEmpty {
                            DetailRow(title: "Cấp độ (CEFR)", content: cefr, color: .orange)
                        }
                        if let eMeaning = item.E_meaning, !eMeaning.isEmpty {
                            DetailRow(title: "Nghĩa Tiếng Anh", content: eMeaning, onSpeak: {
                                SpeechManager.shared.speak(word: eMeaning, ipa: nil)
                            })
                        }
                        if let evMeaning = item.EV_meaning, !evMeaning.isEmpty {
                            DetailRow(title: "Nghĩa Anh - Việt", content: evMeaning)
                        }
                        if let vMeaning = item.V_meaning, !vMeaning.isEmpty {
                            DetailRow(title: "Nghĩa Tiếng Việt", content: vMeaning)
                        }
                                if let eExample = item.englishExample {
                            DetailRow(title: "Ví dụ Tiếng Anh", content: eExample, isItalic: true, onSpeak: {
                                SpeechManager.shared.speak(
                                    example: eExample,
                                    targetWord: item.vocab ?? word,
                                    ipa: item.IPA
                                )
                            })
                        }
                                if let vExample = item.vietnameseExample {
                            DetailRow(title: "Ví dụ Tiếng Việt", content: vExample)
                        }
                        if let family = item.word_family, !family.isEmpty {
                            DetailRow(title: "Từ cùng họ (Word family)", content: family)
                        }
                        if let synonymous = item.synonymous, !synonymous.isEmpty {
                            DetailRow(title: "Từ đồng nghĩa", content: synonymous)
                        }
                        if let antonym = item.antonym, !antonym.isEmpty {
                            DetailRow(title: "Từ trái nghĩa", content: antonym)
                        }
                        if let bonus = item.bonus, !bonus.isEmpty {
                            DetailRow(title: "Thông tin mở rộng", content: bonus)
                        }
                        
                    }
                    .padding(.vertical, 4)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await deleteSingleMeaning(item) }
                    } label: {
                        Label("Xóa", systemImage: "trash")
                    }
                    
                    if canEdit(item) {
                        Button {
                            selectedVocab = item
                        } label: {
                            Label("Sửa", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            
            Section {
                let learningItem = displayedMeanings.first(where: { ($0.learning_level ?? 0) > 0 })
                if learningItem == nil {
                    Button(action: {
                        Task { await addToLearning(displayedMeanings) }
                    }) {
                        HStack {
                            Image(systemName: "graduationcap.fill")
                            Text("Đưa từ này vào học")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                    }
                    .listRowBackground(Color.clear)
                } else if let learningItem = learningItem {
                    let level = learningItem.learning_level ?? 1
                    let isDue = ReviewScheduler.isDue(learningItem, now: Date())

                    if isDue {
                        Button {
                            openLearningTab()
                        } label: {
                            if level >= 6 {
                                reviewInfoCard(
                                    title: "Đang học (Cấp độ \(level))",
                                    reviewText: reviewTimeText(for: learningItem.next_review),
                                    tint: .purple,
                                    isAction: true
                                )
                            } else {
                                learningProgressCard(
                                    level: level,
                                    reviewText: reviewTimeText(for: learningItem.next_review),
                                    isAction: true
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    } else if level >= 6 {
                        reviewInfoCard(
                            title: "Đang học (Cấp độ \(level))",
                            reviewText: reviewTimeText(for: learningItem.next_review),
                            tint: .purple,
                            isAction: false
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        learningProgressCard(
                            level: level,
                            reviewText: reviewTimeText(for: learningItem.next_review),
                            isAction: false
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }

            if canSubmitToSystem {
                Section {
                    if hasPendingSubmission {
                        Label("Đang chờ admin duyệt", systemImage: "clock.fill")
                            .foregroundColor(.orange)
                    } else if hasRejectedSubmission {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Từ này chưa được duyệt", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)

                            Button {
                                Task { await submitPrivateMeanings() }
                            } label: {
                                HStack {
                                    if isSubmittingContribution {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                    }
                                    Text(isSubmittingContribution ? "Đang gửi duyệt..." : "Gửi duyệt lại")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSubmittingContribution)
                        }
                    } else {
                        Button {
                            Task { await submitPrivateMeanings() }
                        } label: {
                            if isSubmittingContribution {
                                HStack {
                                    ProgressView()
                                    Text("Đang gửi duyệt...")
                                }
                            } else {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Gửi duyệt lên hệ thống")
                                }
                            }
                        }
                        .disabled(isSubmittingContribution)
                    }
                } footer: {
                    Text("Admin duyệt xong thì từ riêng này sẽ được bổ sung vào bộ từ chung.")
                }
            }
        }
        .navigationTitle(word)
        .sheet(item: $selectedVocab) { vocab in
            AddVocabView(existing: vocab, saveAsSystem: saveAsSystem, onComplete: {
                onRefresh()
                selectedVocab = nil
            })
        }
        .alert("Thông báo", isPresented: $showingContributionAlert) {
            Button("OK") {}
        } message: {
            Text(contributionMessage)
        }
        .task {
            await fetchSubmissionStatuses()
        }
    }
    
    func reviewTimeText(for dateStr: String?) -> String {
        ReviewTimeFormatter.text(for: dateStr)
    }

    private func openLearningTab() {
        NotificationCenter.default.post(name: .openLearningTab, object: nil)
    }

    func deleteSingleMeaning(_ item: Vocabulary) async {
        guard let id = item.id else { return }
        do {
            try await VocabularyRepository.delete(id: id)
            removedMeaningIDs.insert(id)
            onVocabularyDeleted(id)
            onRefresh()

            if displayedMeanings.isEmpty {
                dismiss()
            }
        } catch {
            contributionMessage = "Xoá nghĩa thất bại: \(error.localizedDescription)"
            showingContributionAlert = true
        }
    }
    
    func addToLearning(_ items: [Vocabulary]) async {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = formatter.string(from: now)
        
        do {
            for item in items {
                guard let id = item.id else { continue }
                try await VocabularyRepository.updateLearningData(id: id, learningLevel: 1, nextReview: dateString)
            }
                
            DispatchQueue.main.async {
                onRefresh()
            }
        } catch {
            print("Học: \(error)")
        }
    }

    private func canEdit(_ item: Vocabulary) -> Bool {
        AuthManager.shared.isAdmin || item.visibility == "private"
    }

    private func learningProgressCard(level: Int, reviewText: String, isAction: Bool) -> some View {
        VStack(spacing: 5) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                Text("Đang học (Cấp độ \(level)/6)")
            }
            .font(.headline)
            .foregroundColor(isAction ? .white : .orange)

            Text("=> Ôn lại: \(reviewText)")
                .font(.subheadline)
                .foregroundColor(isAction ? .white.opacity(0.9) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(isAction ? Color.orange : Color.green.opacity(0.1))
        .cornerRadius(10)
    }

    private func reviewInfoCard(title: String, reviewText: String, tint: Color, isAction: Bool) -> some View {
        VStack(spacing: 5) {
            HStack {
                Image(systemName: "clock.badge.checkmark.fill")
                Text(title)
            }
            .font(.headline)
            .foregroundColor(isAction ? .white : tint)

            Text("=> Ôn lại: \(reviewText)")
                .font(.subheadline)
                .foregroundColor(isAction ? .white.opacity(0.9) : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(isAction ? tint : tint.opacity(0.08))
        .cornerRadius(10)
    }

    private var canSubmitToSystem: Bool {
        !AuthManager.shared.isAdmin && !isPrivateTopic && displayedMeanings.contains { $0.visibility == "private" }
    }

    private func privateTag() -> some View {
        Text("Riêng tư")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple)
            .cornerRadius(4)
    }

    private var hasPendingSubmission: Bool {
        privateSubmissionStatuses.contains { $0.status == "pending" }
    }

    private var hasRejectedSubmission: Bool {
        privateSubmissionStatuses.contains { $0.status == "rejected" }
    }

    private var privateSubmissionStatuses: [VocabSubmissionStatus] {
        displayedMeanings.compactMap { item in
            guard item.visibility == "private",
                  let catalogId = item.catalog_id ?? item.id else { return nil }
            return submissionStatuses[catalogId]
        }
    }

    private func submitPrivateMeanings() async {
        let privateMeanings = displayedMeanings.filter { item in
            guard item.visibility == "private",
                  let catalogId = item.catalog_id ?? item.id else { return false }
            return submissionStatuses[catalogId]?.status != "pending"
        }
        guard !privateMeanings.isEmpty else { return }

        isSubmittingContribution = true
        defer { isSubmittingContribution = false }

        do {
            for item in privateMeanings {
                try await ContributionRepository.submitVocabulary(item)
            }
            await fetchSubmissionStatuses()
            contributionMessage = "Đã gửi từ này cho admin duyệt."
            showingContributionAlert = true
        } catch {
            contributionMessage = "Gửi duyệt thất bại: \(error.localizedDescription)"
            showingContributionAlert = true
        }
    }

    private func fetchSubmissionStatuses() async {
        do {
            let statuses = try await ContributionRepository.fetchUserVocabularySubmissionStatuses()
            let latestByCatalog = statuses.reduce(into: [String: VocabSubmissionStatus]()) { partialResult, status in
                if partialResult[status.catalogId] == nil {
                    partialResult[status.catalogId] = status
                }
            }

            DispatchQueue.main.async {
                submissionStatuses = latestByCatalog
            }
        } catch {
            print("Lỗi tải trạng thái gửi duyệt: \(error)")
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
