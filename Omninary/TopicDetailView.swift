import SwiftUI

struct TopicDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    let topic: String
    var topicInfo: UserTopic? = nil
    var topicSubmission: TopicContribution? = nil
    var vocabs: [Vocabulary]
    var saveAsSystem: Bool = false
    var onRefresh: () -> Void

    @State private var selectedVocabForEdit: Vocabulary? = nil
    @State private var showingAddVocab = false
    @State private var showingExistingMeaningPicker = false
    @State private var isSubmittingTopic = false
    @State private var isDeletingTopic = false
    @State private var topicReviewMessage = ""
    @State private var showingTopicReviewAlert = false
    @State private var showingDeleteTopicConfirm = false
    @State private var shouldDismissAfterTopicAlert = false
    @State private var removedVocabularyIDs: Set<String> = []
    @State private var deletingWordKeys: Set<String> = []
    @State private var shouldDismissAfterLastVocabularyRemoval = false
    @State private var searchText = ""

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    private var displayedVocabs: [Vocabulary] {
        vocabs.filter { vocabulary in
            guard let id = vocabulary.id else { return true }
            return !removedVocabularyIDs.contains(id)
        }
    }

    private var visibleVocabularies: [Vocabulary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Vocabulary.sortedItems(displayedVocabs).filter {
            query.isEmpty || ($0.vocab ?? "").localizedCaseInsensitiveContains(query)
                || ($0.V_meaning ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            List {
                if let fixedTopicId, isPrivateTopic || AuthManager.shared.isAdmin {
                    Section {
                        Button("Thêm từ vựng đã có") { showingExistingMeaningPicker = true }
                            .accessibilityIdentifier("addExistingMeaning")
                    }
                    .sheet(isPresented: $showingExistingMeaningPicker) {
                        ExistingMeaningPickerView(topicId: fixedTopicId, onComplete: onRefresh)
                    }
                }
                if let topicInfo, topicInfo.visibility == "private" {
                    Section {
                        privateTopicReviewCard(topicInfo)
                    }
                    .listRowBackground(isExtra ? Color.white.opacity(0.08) : Color.clear)
                }

                if displayedVocabs.isEmpty {
                    Text("Không có từ vựng nào trong chủ đề này.")
                        .foregroundColor(isExtra ? Color.white.opacity(0.7) : .secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(visibleVocabularies, id: \.vocabularyIdentity) { vocabulary in
                        let word = vocabulary.vocab ?? ""
                        let meanings = [vocabulary]
                        let firstMeaning: Vocabulary? = vocabulary

                        NavigationLink(destination: WordDetailView(
                            word: word,
                            meanings: meanings,
                            saveAsSystem: saveAsSystem,
                            isPrivateTopic: isPrivateTopic,
                            collectionTopicId: fixedTopicId,
                            onRefresh: onRefresh,
                            onVocabularyDeleted: markVocabularyRemoved
                        )) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(word)
                                        .font(.headline)
                                        .foregroundColor(isExtra ? .white : .primary)

                                    if meanings.contains(where: { $0.visibility == "private" }) {
                                        learningTag("Riêng tư", foreground: .white, background: .purple)
                                    }

                                    learningTag(LearningLevelDisplay.title(for: vocabulary.learning_level), foreground: AppTheme(isExtra: isExtra).accent, background: AppTheme(isExtra: isExtra).accent.opacity(0.12))

                                    Spacer()
                                }

                                if let ipa = firstMeaning?.IPA, !ipa.isEmpty {
                                    Text(ipa)
                                        .font(.subheadline)
                                        .foregroundColor(isExtra ? ExtraAuroraPalette.iceCyan : .blue)
                                }

                                // Nối các nghĩa Tiếng Việt lại
                                let vMeanings = Array(Set(meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty })).joined(separator: "; ")
                                if !vMeanings.isEmpty {
                                    Text(vMeanings)
                                        .font(.body)
                                        .foregroundColor(isExtra ? Color.white.opacity(0.85) : .primary)
                                        .lineLimit(1) // Thu gọn ở màn hình ngoài
                                }

                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                        .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await deleteWord(meanings, wordKey: vocabulary.vocabularyIdentity) }
                            } label: {
                                Label(
                                    deletingWordKeys.contains(vocabulary.vocabularyIdentity) ? "Đang gỡ" : (fixedTopicId == nil ? "Xoá khỏi kho học" : "Gỡ khỏi chủ đề"),
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
                                .tint(AppTheme(isExtra: isExtra).accent)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(isExtra ? .hidden : .automatic)
        }
        .navigationTitle(topic)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            dismissAfterLastVocabularyRemovalIfNeeded()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiquidGlassBottomActionBar(
                searchText: $searchText,
                searchPrompt: "Tìm từ vựng",
                addAccessibilityLabel: "Thêm từ mới",
                addAction: { showingAddVocab = true }
            )
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
            Text("Chỉ xoá chủ đề và các liên kết trong chủ đề. Nghĩa, cấp độ và lịch sử học vẫn được giữ.")
        }
    }

    private var fixedTopicId: String? {
        topicInfo?.id ?? displayedVocabs.first?.collectionTopics.first(where: { $0.name == topic })?.id
    }

    private var isPrivateTopic: Bool {
        topicInfo?.visibility == "private"
    }

    private var canDeletePrivateTopic: Bool {
        topicInfo?.visibility == "private" && topicSubmission?.status != "pending"
    }

    private func deleteWord(_ meanings: [Vocabulary], wordKey: String) async {
        let ids = meanings.compactMap(\.id)
        guard !ids.isEmpty, deletingWordKeys.insert(wordKey).inserted else { return }
        defer { deletingWordKeys.remove(wordKey) }

        var firstError: Error?
        do {
            if let topicId = fixedTopicId {
                try await VocabularyRepository.removeMeanings(meanings.compactMap(\.catalog_id), fromTopic: topicId)
            } else {
                for id in ids { try await VocabularyRepository.delete(id: id) }
            }
            removedVocabularyIDs.formUnion(ids)
        } catch { firstError = error }

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
                .foregroundColor(isExtra ? Color.white.opacity(0.7) : .secondary)

            if topicSubmission?.status == "pending" {
                Label("Đang chờ admin duyệt", systemImage: "clock.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(AppSemanticColor.attention)
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
                    .foregroundColor(isExtra ? Color.white.opacity(0.7) : .secondary)
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
                .foregroundColor(AppSemanticColor.attention)
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

/// Reuses a catalog meaning ID; saving it to another topic never copies progress.
struct ExistingMeaningPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    let topicId: String
    let onComplete: () -> Void
    @State private var search = ""
    @State private var meanings: [Vocabulary] = []
    @State private var message = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nhập từ cần tìm", text: $search).onSubmit { Task { await load() } }
                    Button("Tìm từ có sẵn") { Task { await load() } }.disabled(isBusy)
                }.listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                ForEach(meanings) { meaning in
                    Button {
                        Task { await add(meaning) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meaning.vocab ?? "").font(.headline)
                            Text([meaning.word_form, meaning.V_meaning ?? meaning.E_meaning].compactMap { $0 }.joined(separator: " · "))
                            Text("Dùng lại từ này và giữ tiến độ đã có").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(isBusy)
                }.listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
            }
            .scrollContentBackground(isExtra ? .hidden : .automatic)
            .background { if isExtra { AuroraBackdrop() } }
            .navigationTitle("Thêm từ đã có")
            .toolbar { Button("Đóng") { dismiss() } }
            .task { await load() }
        }.vocabularySheetStyle(isExtra: isExtra)
    }

    @MainActor private func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
                meanings = try await VocabularyRepository.fetchUserVocabs(userId: userId, ordered: true)
            } else {
                meanings = try await VocabularyRepository.searchAvailableMeanings(word: search)
            }
            message = meanings.isEmpty ? "Không có từ phù hợp. Bạn có thể tạo từ mới." : ""
        } catch { message = error.localizedDescription }
    }

    @MainActor private func add(_ meaning: Vocabulary) async {
        guard let id = meaning.catalog_id ?? meaning.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await VocabularyRepository.saveMeanings([id], toTopic: topicId)
            onComplete()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct WordDetailView: View, Equatable {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    let word: String
    var meanings: [Vocabulary]
    var saveAsSystem: Bool = false
    var isPrivateTopic: Bool = false
    var collectionTopicId: String? = nil
    var allowsMembershipRemoval: Bool = true
    var isCenteredCard: Bool = false
    var previewContentHeight: CGFloat? = nil
    var previewPosition: Int? = nil
    var previewCount: Int = 0
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    var onClose: () -> Void = {}
    var onRefresh: () -> Void
    var onVocabularyDeleted: (String) -> Void = { _ in }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word && lhs.meanings == rhs.meanings &&
        lhs.saveAsSystem == rhs.saveAsSystem && lhs.isPrivateTopic == rhs.isPrivateTopic &&
        lhs.collectionTopicId == rhs.collectionTopicId &&
        lhs.allowsMembershipRemoval == rhs.allowsMembershipRemoval &&
        lhs.isCenteredCard == rhs.isCenteredCard &&
        lhs.previewContentHeight == rhs.previewContentHeight &&
        lhs.previewPosition == rhs.previewPosition && lhs.previewCount == rhs.previewCount
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var previewDrag: CGFloat = 0
    @State private var isStartingLearning = false
    @State private var shouldDismiss = false
    @State private var selectedVocab: Vocabulary? = nil
    @State private var reviewClockNow = Date()
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

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        Group {
            if isCenteredCard {
                centeredDetailCard
                    .accessibilityAction(.escape, onClose)
            } else {
                detailContent
                    .navigationTitle(word)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .tabBar)
                    .overlay(alignment: .bottom) { wordLearningActionBar }
                    .background {
                        if shouldDismiss { VocabularyDetailDismissAction() }
                    }
            }
        }
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

    private var centeredDetailCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(word)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("vocabularyPreviewTitle")
                        .allowsHitTesting(false)
                    Text(LearningLevelDisplay.title(for: displayedMeanings.first?.learning_level))
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.18), in: Capsule())
                        .fixedSize()
                        .accessibilityIdentifier("vocabulary-card-status")
                        .allowsHitTesting(false)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng thẻ từ")
                }
                if let item = displayedMeanings.first {
                    VocabularyCardMetadata(item: item, onSpeak: { speakVocabulary(item) })
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Nền nhận vùng trống và chữ ở hàng trên; nút đóng nằm ở lớp riêng phía trên.
                AppTheme(isExtra: isExtra).primaryGradient
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let item = displayedMeanings.first { speakVocabulary(item) }
                    }
                    .accessibilityHidden(true)
            }
            .accessibilityAction(named: Text("Nghe phát âm từ \(word)")) {
                if let item = displayedMeanings.first { speakVocabulary(item) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(displayedMeanings, id: \.vocabularyIdentity) { item in
                        vocabularyDetails(item)
                    }
                    if canSubmitToSystem {
                        contributionActions
                        Text("Admin duyệt xong thì từ riêng này sẽ được bổ sung vào bộ từ chung.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(height: previewContentHeight)
            .accessibilityIdentifier("vocabularyPreviewContent")
            .simultaneousGesture(previewSwipeGesture)
            .contextMenu {
                if let item = displayedMeanings.first, canEdit(item) {
                    Button("Sửa từ vựng", systemImage: "pencil") { selectedVocab = item }
                }
            }
            .accessibilityAction(named: Text("Sửa từ vựng")) {
                if let item = displayedMeanings.first, canEdit(item) { selectedVocab = item }
            }

            Divider().overlay(isExtra ? Color.white.opacity(0.12) : Color.clear)
            VStack(spacing: 8) {
                wordLearningActionBar
                if let previewPosition { previewNavigation(position: previewPosition) }
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppSurfaceKind.detail.cornerRadius, style: .continuous))
        .appSurface(.detail, isExtra: isExtra)
        .offset(x: reduceMotion ? 0 : previewDrag)
        .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.86), value: previewDrag)
    }

    private func previewNavigation(position: Int) -> some View {
        Text("Vuốt trái hoặc phải để chuyển từ - \(position)/\(previewCount) từ")
            .font(.caption2)
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
            .accessibilityLabel("Vuốt trái hoặc phải để chuyển từ - Từ \(position) trên \(previewCount)")
            .accessibilityIdentifier("vocabularyPreviewPosition")
    }

    private var previewSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .updating($previewDrag) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let canMove = value.translation.width < 0
                    ? (previewPosition ?? previewCount) < previewCount : (previewPosition ?? 1) > 1
                state = value.translation.width * (canMove ? 0.7 : 0.15)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                guard abs(horizontal) >= 35, abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
                guard abs(horizontal) >= 65 || abs(value.predictedEndTranslation.width) >= 110 else { return }
                if horizontal < 0 { onNext() } else { onPrevious() }
            }
    }

    private func speakVocabulary(_ item: Vocabulary) {
        SpeechManager.shared.speak(word: item.vocab ?? "", ipa: item.IPA)
    }

    private func vocabularyDetails(_ item: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !isCenteredCard {
                VocabularyCardMetadata(item: item, onSpeak: { speakVocabulary(item) }, onHeader: false, isExtra: isExtra)
            }
            VocabularyCardContent(item: item, isExtra: isExtra)
                .id(item.vocabularyIdentity)
        }
    }

    @ViewBuilder
    private var contributionActions: some View {
        if hasPendingSubmission {
            Label("Đang chờ admin duyệt", systemImage: "clock.fill")
                .foregroundColor(AppSemanticColor.attention)
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
                .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
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
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
            .disabled(isSubmittingContribution)
        }
    }

    private var detailContent: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }

            List {
                ForEach(displayedMeanings, id: \.vocabularyIdentity) { item in
                    Section(header: HStack {
                        Text("Từ vựng")
                            .foregroundColor(isExtra ? .white.opacity(0.9) : .secondary)
                        if item.visibility == "private" {
                            privateTag()
                        }
                        Spacer()
                        if let level = item.learning_level, level >= 0 {
                            Text(LearningLevelDisplay.title(for: level))
                                .font(.caption2.weight(.bold))
                                .foregroundColor(AppSemanticColor.attention)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        } else {
                            Text("New")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(isExtra ? Color.white.opacity(0.65) : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isExtra ? Color.white.opacity(0.1) : Color.gray.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }) {
                        vocabularyDetails(item)
                    }
                    .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                    .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if allowsMembershipRemoval {
                            Button(role: .destructive) {
                                Task { await deleteSingleMeaning(item) }
                            } label: {
                                Label(
                                    collectionTopicId == nil ? "Xoá khỏi kho học" : "Gỡ khỏi chủ đề", systemImage: "trash"
                                )
                            }
                        }

                        if canEdit(item) {
                            Button {
                                selectedVocab = item
                            } label: {
                                Label("Sửa", systemImage: "pencil")
                            }
                            .tint(AppTheme(isExtra: isExtra).accent)
                        }
                    }
                }

                if canSubmitToSystem {
                    Section {
                        contributionActions
                    } footer: {
                        Text("Admin duyệt xong thì từ riêng này sẽ được bổ sung vào bộ từ chung.")
                            .foregroundColor(isExtra ? Color.white.opacity(0.65) : .secondary)
                    }
                    .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                    .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                }
            }
            .scrollContentBackground(isExtra || isCenteredCard ? .hidden : .automatic)
            .contentMargins(.bottom, isCenteredCard ? 12 : 80, for: .scrollContent)
        }
    }

    func reviewTimeText(for dateStr: String?) -> String {
        ReviewTimeFormatter.text(for: dateStr)
    }

    @ViewBuilder
    private var wordLearningActionBar: some View {
        let unlearnedMeanings = displayedMeanings.filter { $0.learning_level == nil }
        let activeMeanings = displayedMeanings.filter { level in
            guard let value = level.learning_level else { return false }
            return (0..<10).contains(value)
        }

        if !unlearnedMeanings.isEmpty {
            Button {
                Task { await addToLearning(unlearnedMeanings) }
            } label: {
                Label(
                    isCenteredCard ? "Học từ này" : "Đưa từ này vào học",
                    systemImage: "graduationcap.fill"
                )
                .font(.headline.weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .modifier(AppActionFill(isExtra: isExtra))
            }
            .buttonStyle(.plain)
            .disabled(isStartingLearning)
            .accessibilityLabel("Đưa từ này vào học")
            .accessibilityIdentifier("vocabulary-learning-action")
            .padding(.horizontal, isCenteredCard ? 0 : 16)
            .padding(.top, isCenteredCard ? 0 : 10)
            .padding(.bottom, isCenteredCard ? 0 : 8)
        } else if let earliestDueItem = activeMeanings.min(by: {
            ($0.next_review ?? "") < ($1.next_review ?? "")
        }) {
            Group {
                let isDue = activeMeanings.contains { ReviewScheduler.isDue($0, now: reviewClockNow) }

                Button {
                    guard isDue else { return }
                    openLearningTab()
                } label: {
                    Group {
                        if isCenteredCard && !isDue {
                            VStack(spacing: 2) {
                                Label("Ôn lại sau", systemImage: "clock.fill").font(.caption.weight(.semibold))
                                Text(reviewCountdown(for: earliestDueItem.next_review, now: reviewClockNow))
                                    .font(.subheadline.weight(.bold))
                            }
                        } else {
                            Label(isDue ? "Ôn tập ngay" : "Ôn lại sau: \(reviewCountdown(for: earliestDueItem.next_review, now: reviewClockNow))",
                                  systemImage: isDue ? "arrow.right.circle.fill" : "clock.fill")
                        }
                    }
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isDue ? Color.white : AppTheme(isExtra: isExtra).secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .modifier(AppActionFill(isExtra: isExtra, enabled: isDue))
                }
                .buttonStyle(.plain)
                .disabled(!isDue)
                .accessibilityLabel(isDue ? "Ôn tập ngay" : "Ôn lại sau: \(reviewCountdown(for: earliestDueItem.next_review, now: reviewClockNow))")
                .accessibilityIdentifier("vocabulary-learning-action")
            }
            .task {
                reviewClockNow = Date()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                    reviewClockNow = Date()
                }
            }
            .padding(.horizontal, isCenteredCard ? 0 : 16)
            .padding(.top, isCenteredCard ? 0 : 10)
            .padding(.bottom, isCenteredCard ? 0 : 8)
        } else if displayedMeanings.contains(where: { ($0.learning_level ?? -1) >= 10 }) {
            Label(isCenteredCard ? "Đã hoàn thành" : "Super · Đã hoàn thành lịch ôn", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppSemanticColor.success)
                .accessibilityIdentifier("vocabulary-learning-action")
                .frame(maxWidth: .infinity)
                .padding(.horizontal, isCenteredCard ? 0 : 16)
                .padding(.vertical, 12)
        }
    }

    private func reviewCountdown(for dateString: String?, now: Date) -> String {
        guard let dateString else { return "00:00:00" }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        guard let reviewDate = fractionalFormatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString) else {
            return "00:00:00"
        }

        let seconds = max(0, Int(ceil(reviewDate.timeIntervalSince(now))))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private func openLearningTab() {
        if isCenteredCard { onClose() }
        NotificationCenter.default.post(name: .openLearningTab, object: nil)
    }

    func deleteSingleMeaning(_ item: Vocabulary) async {
        guard let id = item.id else { return }
        do {
            if let topicId = collectionTopicId, let catalogId = item.catalog_id {
                try await VocabularyRepository.removeMeanings([catalogId], fromTopic: topicId)
            } else {
                try await VocabularyRepository.delete(id: id)
            }
            removedMeaningIDs.insert(id)
            onVocabularyDeleted(id)
            onRefresh()

            if displayedMeanings.isEmpty {
                if isCenteredCard { onClose() } else { shouldDismiss = true }
            }
        } catch {
            contributionMessage = "Xoá từ vựng thất bại: \(error.localizedDescription)"
            showingContributionAlert = true
        }
    }

    @MainActor
    func addToLearning(_ items: [Vocabulary]) async {
        guard !isStartingLearning else { return }
        isStartingLearning = true
        defer { isStartingLearning = false }
        do {
            let ids = Array(Set(items.compactMap(\.id))).sorted()
            guard !ids.isEmpty else { return }
            _ = try await VocabularyRepository.startLearning(userVocabularyIds: ids)

            await MainActor.run {
                onRefresh()
            }
        } catch {
            await MainActor.run {
                contributionMessage = "Không thể đưa từ vào học: \(error.localizedDescription)"
                showingContributionAlert = true
            }
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
            .foregroundColor(isAction ? .white : AppSemanticColor.attention)

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
        var isExtra: Bool = false
        var isMultiple: Bool = false
        var onSpeak: (() -> Void)? = nil

        private var resolvedContentColor: Color {
            if isExtra {
                if color == .primary {
                    return .white
                } else if color == .blue {
                    return ExtraAuroraPalette.iceCyan
                }
            }
            return color
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(isExtra ? Color.white.opacity(0.65) : .secondary)

                if isMultiple {
                    VocabularySupplementaryCards(value: content, isExtra: isExtra)
                } else if let onSpeak = onSpeak {
                    HStack(alignment: .top) {
                        Text(content)
                            .font(.body)
                            .foregroundColor(resolvedContentColor)
                            .italic(isItalic)
                        Spacer()
                        Button(action: onSpeak) {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(isExtra ? ExtraAuroraPalette.iceCyan : .blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    Text(content)
                        .font(.body)
                        .foregroundColor(resolvedContentColor)
                        .italic(isItalic)
                }
            }
            .padding(.bottom, 2)
        }
    }
}

// Mỗi giá trị bổ sung phân tách bằng dấu ; hiển thị trên một thẻ riêng.
struct VocabularySupplementaryCards: View {
    let value: String
    var isExtra: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Vocabulary.supplementaryValues(value).enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.body)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isExtra ? Color.white.opacity(0.09) : Color(UIColor.secondarySystemGroupedBackground))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isExtra ? Color.white.opacity(0.14) : Color.primary.opacity(0.08), lineWidth: 0.7)
                    }
            }
        }
    }
}

// Chỉ đọc thao tác đóng trang khi thực sự cần đóng, tránh phụ thuộc điều hướng
// thay đổi liên tục trong nội dung của trang chi tiết.
private struct VocabularyDetailDismissAction: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { dismiss() }
    }
}
