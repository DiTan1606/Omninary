import SwiftUI

struct VocabularyWorkspaceBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: VocabularyWorkspaceStore
    let topic: UserTopic?
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var search = ""
    @State private var selecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showingCreateFolder = false
    @State private var showingCreateMeaning = false
    @State private var showingExistingMeaning = false
    @State private var locationRequest: VocabularyFolderRequest?
    @State private var deleteIDs: [String] = []
    @State private var showingDelete = false
    @State private var folderToDelete: UserTopic?
    @State private var showingDeleteFolder = false
    @State private var previewEntry: VocabularyFileEntry?
    @State private var previewDirection = 1

    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    private var currentID: String? { topic?.id ?? store.rootID }
    private var currentTopic: UserTopic? { topic ?? store.rootTopic }
    private var entries: [VocabularyFileEntry] {
        guard let currentID else { return [] }
        return VocabularyFileEntry.entries(from: store.meanings, topicID: currentID)
    }
    private var visibleEntries: [VocabularyFileEntry] {
        guard !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        return entries.filter { entry in
            entry.title.localizedCaseInsensitiveContains(search) ||
            entry.subtitle.localizedCaseInsensitiveContains(search)
        }
    }
    private var visibleFolders: [UserTopic] {
        guard topic == nil else { return [] }
        return store.folders.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    private var accent: Color { isExtra ? ExtraAuroraPalette.ice : .blue }

    var body: some View {
        ZStack {
            if isExtra { AuroraBackdrop() } else { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
            ScrollView {
                workspaceList
            }
            .accessibilityHidden(previewEntry != nil)
            .refreshable { await store.load() }
            if store.isBusy && store.meanings.isEmpty {
                ProgressView("Đang mở kho từ vựng…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle(topic?.name ?? "My Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Xong" : "Chọn") {
                    withAnimation(.snappy) {
                        selecting.toggle()
                        selectedIDs.removeAll()
                    }
                }.disabled(store.isBusy || entries.isEmpty)
            }
            if let topic {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink("Thông tin và chia sẻ bộ từ") {
                            TopicDetailView(topic: topic.name, topicInfo: topic,
                                topicSubmission: store.submissions.filter { $0.topicId == topic.id }.last,
                                vocabs: store.meanings.filter { $0.collectionTopics.contains { $0.id == topic.id } },
                                onRefresh: { Task { await store.load() } })
                        }
                        if topic.visibility == "private" {
                            Button("Xoá bộ từ", role: .destructive) { folderToDelete = topic; showingDeleteFolder = true }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let notice = store.notice {
                    HStack {
                        Text(notice).font(.caption).lineLimit(2)
                        Spacer()
                        if store.undoSnapshot != nil {
                            Button("Hoàn tác") { Task { await store.undo() } }.disabled(store.isBusy)
                        }
                        Button { store.notice = nil; store.undoSnapshot = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Đóng thông báo")
                    }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                }
                if selecting { selectionBar }
                LiquidGlassBottomActionBar(searchText: $search, searchPrompt: "Tìm bộ từ hoặc từ",
                    addAccessibilityLabel: "Tạo từ hoặc bộ từ",
                    addAction: {}, addMenuItems: createMenuItems)
                    .disabled(store.isBusy || currentID == nil)
            }
            .accessibilityHidden(previewEntry != nil)
        }
        .sheet(isPresented: $showingCreateFolder) {
            PrivateTopicCreateView { Task { await store.load() } }.vocabularySheetStyle(isExtra: isExtra)
        }
        .sheet(isPresented: $showingCreateMeaning) {
            if let currentTopic {
                AddVocabView(fixedTopic: currentTopic.name, fixedTopicId: currentTopic.id) { Task { await store.load() } }.vocabularySheetStyle(isExtra: isExtra)
            }
        }
        .sheet(isPresented: $showingExistingMeaning) {
            if let currentID { ExistingMeaningPickerView(topicId: currentID) { Task { await store.load() } }.vocabularySheetStyle(isExtra: isExtra) }
        }
        .sheet(item: $locationRequest) { request in
            VocabularyFolderPicker(folders: store.destinations.filter { $0.id != currentID }, action: request.action) { destination in
                applyLocation(request.ids, destination: destination.id, action: request.action)
            }.vocabularySheetStyle(isExtra: isExtra)
        }
        .confirmationDialog("Xoá khỏi kho học?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Xoá \(deleteIDs.count) từ", role: .destructive) {
                let ids = deleteIDs
                Task { await store.delete(ids); selectedIDs.removeAll() }
            }
        } message: {
            Text("Các từ được chọn sẽ biến mất khỏi mọi bộ từ trong kho học của bạn. Tiến độ học của chúng sẽ bị xoá.")
        }
        .confirmationDialog("Xoá bộ từ?", isPresented: $showingDeleteFolder, titleVisibility: .visible) {
            if let folderToDelete {
                Button("Xoá \(folderToDelete.name)", role: .destructive) {
                    Task {
                        await store.deleteFolder(folderToDelete)
                        if topic?.id == folderToDelete.id && !store.folders.contains(where: { $0.id == folderToDelete.id }) { dismiss() }
                    }
                }
            }
        } message: { Text("Giữ nguyên các từ và tiến độ. Từ không còn nằm trong bộ từ nào sẽ được đưa ra trang gốc.") }
        .alert("Thông báo", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Đóng") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .blur(radius: previewEntry == nil ? 0 : 6)
        .overlay { previewOverlay }
        .toolbar(previewEntry == nil ? .visible : .hidden, for: .navigationBar)
        .onChange(of: store.meanings) { _, _ in
            selectedIDs.formIntersection(Set(entries.flatMap(\.catalogIDs)))
        }
        .onChange(of: visibleEntries.map(\.id)) { _, ids in
            if let previewEntry, !ids.contains(previewEntry.id) { self.previewEntry = nil }
        }
    }

    @ViewBuilder
    private var previewOverlay: some View {
        if let entry = previewEntry {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(isExtra ? 0.35 : 0.18)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { previewEntry = nil }
                        .accessibilityLabel("Đóng chi tiết từ vựng")

                    let vocabulary = store.meanings.first { $0.vocabularyIdentity == entry.id } ?? entry.vocabulary
                    WordDetailView(word: vocabulary.vocab ?? "", meanings: [vocabulary],
                        isPrivateTopic: currentTopic?.visibility == "private", collectionTopicId: currentID,
                        allowsMembershipRemoval: topic != nil, isCenteredCard: true,
                        previewContentHeight: max(80, min(geometry.size.height * 0.54,
                            geometry.size.height - max(geometry.safeAreaInsets.top, 16)
                                - max(geometry.safeAreaInsets.bottom, 16) - 270)),
                        previewPosition: visibleEntries.firstIndex { $0.id == entry.id }.map { $0 + 1 },
                        previewCount: visibleEntries.count,
                        onPrevious: { changePreview(-1) },
                        onNext: { changePreview(1) },
                        onClose: { previewEntry = nil },
                        onRefresh: { Task { await store.load() } })
                        .equatable()
                        .frame(width: min(geometry.size.width - 32, 640))
                        .id(entry.id)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: previewDirection > 0 ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: previewDirection > 0 ? .leading : .trailing).combined(with: .opacity)))
                        .accessibilityAction(named: Text("Từ trước")) { changePreview(-1) }
                        .accessibilityAction(named: Text("Từ tiếp theo")) { changePreview(1) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .ignoresSafeArea()
            .accessibilityElement(children: .contain)
            .preferredColorScheme(isExtra ? .dark : nil)
        }
    }

    private func canChangePreview(_ direction: Int) -> Bool {
        guard let previewEntry,
              let index = visibleEntries.firstIndex(where: { $0.id == previewEntry.id }) else { return false }
        return visibleEntries.indices.contains(index + direction)
    }

    private func changePreview(_ direction: Int) {
        guard let previewEntry,
              let index = visibleEntries.firstIndex(where: { $0.id == previewEntry.id }) else { return }
        let destination = index + direction
        guard visibleEntries.indices.contains(destination) else { return }
        previewDirection = direction
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.9)) {
            self.previewEntry = visibleEntries[destination]
        }
    }

    private var workspaceList: some View {
    LazyVStack(alignment: .leading, spacing: AppSpacing.cardGap) {
        if topic != nil {
            VocabularyCollectionSummaryCard(vocabularies: entries.map(\.vocabulary), isExtra: isExtra)
        }
        ForEach(visibleFolders) { folder in
            NavigationLink {
                VocabularyWorkspaceBrowser(store: store, topic: folder)
            } label: {
                VocabularyFolderTile(folder: folder,
                    count: store.meanings.filter { $0.collectionTopics.contains { $0.id == folder.id } }.count,
                    isExtra: isExtra)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vocabulary-folder-\(folder.id)")
            .contextMenu {
                if folder.visibility == "private" {
                    Button("Xoá bộ từ", role: .destructive) { folderToDelete = folder; showingDeleteFolder = true }
                }
            }
        }
        ForEach(visibleEntries) { entry in fileTile(entry) }
        if visibleFolders.isEmpty && visibleEntries.isEmpty {
            ContentUnavailableView(search.isEmpty ? "Chưa có từ nào" : "Không tìm thấy",
                systemImage: "doc.text", description: Text(search.isEmpty ? "Bấm + để tạo từ mới hoặc thêm từ đã có." : "Thử tìm bằng từ tiếng Anh hoặc nghĩa tiếng Việt."))
        }
    }
    .padding(AppSpacing.page)
    }

    private func fileTile(_ entry: VocabularyFileEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if selecting { toggle(entry.catalogIDs) }
                else { previewEntry = entry }
            } label: {
                HStack(alignment: .top, spacing: AppSpacing.item) {
                    if selecting {
                        Image(systemName: Set(entry.catalogIDs).isSubset(of: selectedIDs) ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(accent).frame(width: 28, height: 32)
                    }
                    fileLabel(entry)
                }
                .padding(.trailing, selecting ? 0 : 44 + AppSpacing.inline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.row)
                .appSurface(.row, isExtra: isExtra)
                .overlay {
                    RoundedRectangle(cornerRadius: AppSurfaceKind.row.cornerRadius)
                        .stroke(selecting && Set(entry.catalogIDs).isSubset(of: selectedIDs) ? accent : Color.clear, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vocabularyPreview-\(entry.id)")
            .accessibilityValue(selecting ? (Set(entry.catalogIDs).isSubset(of: selectedIDs) ? "Đã chọn" : "Chưa chọn") : "")
            .simultaneousGesture(LongPressGesture().onEnded { _ in
                if !selecting { previewEntry = entry }
            })

            if !selecting {
                Menu { fileActions(entry.catalogIDs) } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.semibold))
                        .foregroundStyle(accent).frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("Thao tác với \(entry.title)")
                    .padding(.top, AppSpacing.inline)
                    .padding(.trailing, AppSpacing.inline)
            }
        }
    }

    private func fileLabel(_ entry: VocabularyFileEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title).font(AppTypography.cardTitle).foregroundStyle(.primary).lineLimit(2)
                if let form = entry.vocabulary.word_form, !form.isEmpty {
                    Text(form).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(LearningLevelDisplay.title(for: entry.vocabulary.learning_level))
                    .font(.caption.weight(.medium)).foregroundStyle(accent).fixedSize()
            }
            if let ipa = entry.vocabulary.IPA, !ipa.isEmpty {
                Text(ipa).font(.subheadline).foregroundStyle(accent)
            }
            Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    @ViewBuilder
    private func fileActions(_ ids: [String]) -> some View {
        Button("Di chuyển đến bộ từ…", systemImage: "folder") { locationRequest = .init(ids: ids, action: "move") }
        Button("Thêm vào bộ từ khác…", systemImage: "folder.badge.plus") { locationRequest = .init(ids: ids, action: "add") }
        if topic != nil {
            Button("Đưa về trang gốc", systemImage: "tray") { applyLocation(ids, action: "root") }
            Button("Gỡ khỏi bộ từ này", systemImage: "minus.circle") { applyLocation(ids, action: "remove") }
        }
        Divider()
        Button("Xoá khỏi kho học", systemImage: "trash", role: .destructive) { deleteIDs = ids; showingDelete = true }
    }

    private var createMenuItems: [LiquidGlassMenuAction] {
        var items = [
            LiquidGlassMenuAction(title: "Tạo từ mới", systemImage: "doc.badge.plus", action: { showingCreateMeaning = true }),
            LiquidGlassMenuAction(title: "Thêm từ đã có", systemImage: "doc.on.doc", action: { showingExistingMeaning = true })
        ]
        if topic == nil {
            items.append(LiquidGlassMenuAction(title: "Tạo bộ từ", systemImage: "folder.badge.plus", action: { showingCreateFolder = true }))
        }
        return items
    }

    private var selectionBar: some View {
        HStack {
            Text("\(selectedIDs.count) từ").font(.subheadline.weight(.semibold))
            Button("Chọn tất cả") { selectedIDs = Set(visibleEntries.flatMap(\.catalogIDs)) }.font(.subheadline)
            Spacer()
            Menu {
                fileActions(Array(selectedIDs))
            } label: { Label("Thao tác", systemImage: "ellipsis.circle") }
                .disabled(selectedIDs.isEmpty || store.isBusy)
        }
        .font(.subheadline)
        .foregroundStyle(accent)
        .padding(.horizontal, 16)
        .frame(height: 48)
        .liquidGlassCapsule(useSystemGlass: true)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    private func toggle(_ ids: [String]) {
        if Set(ids).isSubset(of: selectedIDs) { selectedIDs.subtract(ids) } else { selectedIDs.formUnion(ids) }
    }
    private func applyLocation(_ ids: [String], destination: String? = nil, action: String) {
        guard let currentID else { return }
        Task { await store.change(ids, from: currentID, to: destination, action: action); selectedIDs.removeAll() }
    }
}

struct VocabularyWorkspacePreview: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @StateObject private var store: VocabularyWorkspaceStore
    init() {
        let store = VocabularyWorkspaceStore()
        let root = UserTopic(id: "preview-root", name: "Bộ từ gốc", visibility: "private", owner_id: "preview")
        let exam = UserTopic(id: "preview-exam", name: "IELTS", visibility: "private", owner_id: "preview")
        store.rootID = root.id
        store.privateTopics = [root, exam]
        let bank = Vocabulary(topicMemberships: [root, exam], catalog_id: "bank-finance", vocab: "bank", CEFR: "A2", IPA: "/bæŋk/",
            word_form: "noun", V_meaning: "Ngân hàng",
            bonus: String(repeating: "Ghi chú cách dùng từ trong ngữ cảnh tài chính.\n", count: 40), learning_level: 4, next_review: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
        let shore = Vocabulary(topicMemberships: [root], catalog_id: "bank-river", vocab: "bank",
            word_form: "noun", V_meaning: "Bờ sông", learning_level: 1)
        store.meanings = [bank, shore,
            Vocabulary(topicMemberships: [root], catalog_id: "bank-third", vocab: "bank",
                word_form: "verb", V_meaning: "Gửi tiền vào ngân hàng", learning_level: nil),
            Vocabulary(topicMemberships: [root], catalog_id: "adapt", vocab: "adapt",
                word_form: "verb", V_meaning: "Thích nghi", learning_level: 2)]
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WordCardContentUITest") {
            store.meanings = [
                Vocabulary(topicMemberships: [root], catalog_id: "layout-lay-off", vocab: "lay off", CEFR: "B2", IPA: "/leɪ ɒf/",
                    word_form: "phrasal verb", E_meaning: "To stop employing someone because there is not enough work.",
                    EV_meaning: "Cho một người nghỉ việc vì không còn đủ việc làm.", V_meaning: "Cho nghỉ việc",
                    E_example: "Governments should provide support for people who are laid off unexpectedly.",
                    V_example: "Chính phủ nên hỗ trợ những người lao động bất ngờ bị cắt giảm.",
                    word_family: "layoff (noun): sự cắt giảm nhân sự; laid-off (adjective): bị cho nghỉ việc",
                    synonymous: "make redundant; dismiss; terminate someone's employment because work is no longer available",
                    antonym: "hire; recruit; take on",
                    collocation: "employers lay off workers; laid off hundreds of employees",
                    formula: "lay sb off; lay off sb", note: "Đại từ đứng giữa động từ và tiểu từ: lay them off.",
                    bonus: "Thường dùng khi doanh nghiệp thiếu việc hoặc cần cắt giảm chi phí.", learning_level: 1),
                Vocabulary(topicMemberships: [root], catalog_id: "layout-apple", vocab: "apple", CEFR: "A1", IPA: "/ˈæp.əl/",
                    word_form: "noun", V_meaning: "Quả táo")
            ]
        }
#endif
        _store = StateObject(wrappedValue: store)
    }
    var body: some View {
        TabView {
            NavigationStack { VocabularyWorkspaceBrowser(store: store, topic: nil) }
                .tabItem { Label("Kho từ vựng", systemImage: "books.vertical") }
        }
        .preferredColorScheme((AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme ? .dark : nil)
    }
}

private struct VocabularyFolderRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    let action: String
}

private struct VocabularyFolderTile: View {
    let folder: UserTopic
    let count: Int
    let isExtra: Bool
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isExtra ? ExtraAuroraPalette.violet.opacity(0.2) : Color.blue.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: "folder.fill").font(.system(size: 22))
                    .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : .blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name).font(AppTypography.cardTitle).foregroundStyle(.primary).lineLimit(2)
                Text("\(count) từ · \(folder.visibility == "system" ? "Hệ thống" : "Riêng tư")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(AppSpacing.row)
            .appSurface(.row, isExtra: isExtra)
    }
}

private struct VocabularyFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    let folders: [UserTopic]
    let action: String
    let onSelect: (UserTopic) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(action == "move" ? "Gỡ khỏi vị trí hiện tại và đưa vào bộ từ bạn chọn." : "Giữ vị trí hiện tại và thêm vào bộ từ bạn chọn. Tiến độ học dùng chung.")
                        .font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                ForEach(folders) { folder in
                    Button { onSelect(folder); dismiss() } label: { Label(folder.name, systemImage: "folder") }
                }.listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                if folders.isEmpty { Text("Tạo thêm bộ từ tại trang gốc để sắp xếp các từ.") }
            }
            .scrollContentBackground(isExtra ? .hidden : .automatic)
            .background { if isExtra { AuroraBackdrop() } }
            .navigationTitle(action == "move" ? "Di chuyển đến" : "Thêm vào")
                .toolbar { Button("Huỷ") { dismiss() } }
        }.vocabularySheetStyle(isExtra: isExtra)
    }
}
