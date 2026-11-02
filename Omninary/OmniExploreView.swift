import SwiftUI

/// Explore tab of the new interface: open a printed card by its code, browse system word sets
/// as collectible cards, and listening series. Downloading a word puts it into learning at level 0.
struct OmniExploreView: View {
    @Environment(\.omniPalette) private var palette
    @StateObject private var store = OmniExploreStore()
    @State private var showCode = false
    @State private var revealed: Vocabulary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OmniPageTitle("Explore")

                    codeButton
                    NavigationLink {
                        OmniWordSetsView(store: store)
                    } label: {
                        exploreRow(title: "Khám phá bộ từ", subtitle: setsSubtitle, symbol: "rectangle.on.rectangle.angled", tint: 0x2F6FD6, tile: 0xE3EDFF)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("explore-vocabulary")
                    NavigationLink {
                        ListeningExploreView(
                            catalog: store.listeningCatalog,
                            downloadedLessonIds: store.listeningLibraryLessonIds,
                            refreshLibrary: { Task { await store.fetchListeningLibrary() } }
                        )
                    } label: {
                        exploreRow(title: "Khám phá bài luyện nghe", subtitle: "\(store.listeningCatalog.count) seri bài luyện nghe", symbol: "headphones", tint: 0xD9711A, tile: 0xFFEBDD)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("explore-listening")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background { PixelSkyBackground() }
            .omniStatusBarBackdrop()
            .omniTabRoot(.explore)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(isPresented: $showCode) {
                OmniCardCodeSheet { vocab in
                    showCode = false
                    // let the sheet slide away before the stage takes the screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { revealed = vocab }
                }
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $revealed) { vocab in
                OmniCardRevealView(vocab: vocab, store: store)
            }
            .alert("Thông báo", isPresented: $store.showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(store.alertMessage)
            }
        }
    }

    // MARK: Sections

    private var codeButton: some View {
        Button { showCode = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Image("CardBack").resizable()
                            .frame(width: 44, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                            .rotationEffect(.degrees(Double(i - 1) * 11))
                            .offset(x: CGFloat(i - 1) * 18, y: i == 1 ? -3 : 2)
                    }
                }
                .frame(width: 92, height: 74)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhập mã thẻ").font(.omniDisplay(20, weight: 800))
                    Text("Có thẻ giấy Omninary? Nhập mã để mở thẻ từ mới")
                        .font(.omniBody(12, weight: 500))
                        .foregroundStyle(Color(hex: 0xCFD6EE))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x3B2A05))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xE8B93A), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [Color(hex: 0x1B2550), Color(hex: 0x2C4F9C)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .omniCardShadow(radius: 22)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore-card-code")
    }

    private var setsSubtitle: String {
        let words = store.sets.reduce(0) { $0 + $1.words.count }
        return "\(store.sets.count) bộ từ · \(words) thẻ và từ"
    }

    /// A row with a light tinted tile; at night the tile becomes a wash of the tint so it doesn't glare.
    private func exploreRow(title: String, subtitle: String, symbol: String, tint: UInt32, tile: UInt32) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(palette.night ? Color(hex: tile) : Color(hex: tint))
                .frame(width: 60, height: 60)
                .background(palette.night ? Color(hex: tint).opacity(0.35) : Color(hex: tile), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.omniBody(16, weight: 800)).foregroundStyle(palette.text)
                Text(subtitle).font(.omniBody(12, weight: 500)).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(palette.muted)
        }
        .omniCard(padding: 14, radius: 22)
        .contentShape(Rectangle())
    }
}

// MARK: - Data

struct OmniWordSet: Identifiable {
    let id: String
    let name: String
    let words: [Vocabulary]
    var hasCards: Bool { words.contains { $0.card_no != nil } }

    func subtitle(owned: Int) -> String {
        let levels = Set(words.compactMap { $0.CEFR?.uppercased() }).sorted()
        var parts = ["\(words.count) \(hasCards ? "thẻ" : "từ")"]
        if let first = levels.first, let last = levels.last { parts.append(first == last ? first : "\(first)–\(last)") }
        if owned > 0 { parts.append("Đã tải \(owned)") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class OmniExploreStore: ObservableObject {
    @Published private(set) var sets: [OmniWordSet] = []
    /// The learner's own copies, by catalog id.
    @Published private(set) var owned: [String: Vocabulary] = [:]
    @Published private(set) var profiles: [String: WordSkillProfile] = [:]
    @Published private(set) var listeningCatalog: [ListeningSeriesCatalogItem] = []
    @Published private(set) var listeningLibraryLessonIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var downloading: Set<String> = []
    @Published var showAlert = false
    @Published var alertMessage = ""

    private var userId: String? { AuthManager.shared.currentUser?.id.uuidString }

    func load() async {
        isLoading = true
        async let words: () = fetchSets()
        async let mine: () = fetchOwned()
        async let listening: () = fetchListeningCatalog()
        async let library: () = fetchListeningLibrary()
        _ = await (words, mine, listening, library)
        isLoading = false
    }

    private func fetchSets() async {
        guard let fetched = try? await VocabularyRepository.fetchSystemVocabs(adminUserId: AppConfig.adminUserId) else { return }
        var byTopic: [String: (name: String, words: [Vocabulary])] = [:]
        for vocab in fetched {
            for topic in vocab.collectionTopics {
                var contextual = vocab
                contextual.topic_id = topic.id
                contextual.topics = topic.name
                byTopic[topic.id, default: (topic.name, [])].words.append(contextual)
            }
        }
        sets = byTopic.map { id, value in
            OmniWordSet(id: id, name: value.name, words: value.words.sorted(by: Self.cardOrder))
        }
        .sorted { a, b in
            if a.hasCards != b.hasCards { return a.hasCards }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func cardOrder(_ a: Vocabulary, _ b: Vocabulary) -> Bool {
        switch (a.card_no, b.card_no) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return (a.vocab ?? "").localizedStandardCompare(b.vocab ?? "") == .orderedAscending
        }
    }

    func fetchOwned() async {
        guard let userId, let fetched = try? await VocabularyRepository.fetchUserVocabs(userId: userId) else { return }
        var map: [String: Vocabulary] = [:]
        for v in fetched { if let key = v.catalog_id?.lowercased() { map[key] = v } }
        owned = map
        profiles = (try? await LearningProfileRepository.fetchProfiles(userId: userId)) ?? profiles
    }

    func fetchListeningCatalog() async {
        listeningCatalog = (try? await ListeningRepository.fetchSeriesCatalog()) ?? []
    }

    func fetchListeningLibrary() async {
        guard let userId, let entries = try? await ListeningRepository.fetchUserLessonEntries(userId: userId) else { return }
        listeningLibraryLessonIds = Set(entries.map(\.lesson_id))
    }

    func set(_ id: String) -> OmniWordSet? { sets.first { $0.id == id } }
    func ownedCopy(_ v: Vocabulary) -> Vocabulary? { v.catalog_id.flatMap { owned[$0.lowercased()] } }
    func isOwned(_ v: Vocabulary) -> Bool { ownedCopy(v) != nil }
    func ownedCount(_ set: OmniWordSet) -> Int { set.words.filter(isOwned).count }
    func ownedFraction(_ set: OmniWordSet) -> CGFloat { set.words.isEmpty ? 0 : CGFloat(ownedCount(set)) / CGFloat(set.words.count) }
    func mastery(_ v: Vocabulary) -> Int? { ownedCopy(v)?.id.flatMap { profiles[$0]?.lastMastery } }
    func profile(_ v: Vocabulary) -> WordSkillProfile? { ownedCopy(v)?.id.flatMap { profiles[$0] } }

    /// What the card shows: the learner's copy (with its level) when downloaded, else the system word.
    func display(_ v: Vocabulary) -> Vocabulary {
        guard var copy = ownedCopy(v) else { return v }
        copy.card_no = copy.card_no ?? v.card_no
        copy.art_path = copy.art_path ?? v.art_path
        return copy
    }

    /// Downloads words into the learner's library; they start learning at level 0.
    @discardableResult
    func download(_ words: [Vocabulary], topicId: String?) async -> Bool {
        let missing = words.filter { !isOwned($0) }
        let ids = missing.compactMap(\.catalog_id)
        guard userId != nil else {
            alertMessage = "Vui lòng đăng nhập!"
            showAlert = true
            return false
        }
        guard !ids.isEmpty else { return true }
        downloading.formUnion(ids)
        defer { downloading.subtract(ids) }
        do {
            try await VocabularyRepository.saveMeanings(ids, toTopic: topicId ?? missing.first?.topic_id)
            await fetchOwned()
            if OmniSoundSettings.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return true
        } catch {
            alertMessage = "Không thể tải về: \(error.localizedDescription)"
            showAlert = true
            return false
        }
    }
}

extension WordCardStyle {
    /// CEFR colours regardless of the learning level (for set covers and the reveal glow).
    static func cefrPair(_ cefr: String?) -> (Color, Color) {
        let p = colors[cefr?.uppercased() ?? ""] ?? colors["B1"]!
        return (Color(hex: p.0), Color(hex: p.1))
    }
}


// MARK: - Shared page chrome for Explore's inner pages

/// Back button and title over the sky, as on every page of the new interface.
private struct OmniExplorePageHeader: View {
    @Environment(\.omniPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    let back: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.text)
                        .frame(width: 34, height: 34)
                        .background(palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(back).font(.omniBody(13, weight: 700)).foregroundStyle(palette.night ? Color(hex: 0xCFD6EE) : Color(hex: 0x1F2B3C))
                }
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.omniDisplay(30, weight: 800))
                .foregroundStyle(palette.night ? Color.white : Color(hex: 0x17202E))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - All word sets

struct OmniWordSetsView: View {
    @ObservedObject var store: OmniExploreStore
    @Environment(\.omniPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                OmniExplorePageHeader(back: "Explore", title: "Khám phá bộ từ")
                    .padding(.bottom, 4)
                ForEach(store.sets) { set in
                    NavigationLink {
                        OmniWordSetView(setId: set.id, store: store)
                    } label: {
                        row(set)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .background { PixelSkyBackground() }
        .omniStatusBarBackdrop()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ set: OmniWordSet) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: -14) {
                ForEach(Array(set.words.prefix(3).enumerated()), id: \.offset) { i, v in
                    let (c1, c2) = WordCardStyle.cefrPair(v.CEFR)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 46)
                        .overlay(WordPictureView(vocab: v, size: 22))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 2))
                        .rotationEffect(.degrees(Double(i - 1) * 8))
                }
            }
            .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(set.name).font(.omniBody(15, weight: 800)).foregroundStyle(palette.text)
                Text(set.subtitle(owned: store.ownedCount(set))).font(.omniBody(11.5, weight: 500)).foregroundStyle(palette.muted)
                GeometryReader { p in
                    Capsule().fill(palette.line)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.selected).frame(width: p.size.width * store.ownedFraction(set))
                        }
                }
                .frame(height: 5)
                .padding(.top, 3)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(palette.muted)
        }
        .omniCard(padding: 12, radius: 20)
        .contentShape(Rectangle())
    }
}

// MARK: - One word set

struct OmniWordSetView: View {
    let setId: String
    @ObservedObject var store: OmniExploreStore
    @Environment(\.omniPalette) private var palette
    @State private var filter = "all"
    @State private var stage: StageRequest?
    @State private var showsTopButton = false

    struct StageRequest: Identifiable { let id = UUID(); let words: [Vocabulary]; let index: Int }

    private var set: OmniWordSet? { store.set(setId) }

    private var filtered: [Vocabulary] {
        guard let set else { return [] }
        switch filter {
        case "owned": return set.words.filter(store.isOwned)
        case "new": return set.words.filter { !store.isOwned($0) }
        case "all": return set.words
        default: return set.words.filter { $0.CEFR?.uppercased() == filter }
        }
    }

    private var levels: [String] { Set(set?.words.compactMap { $0.CEFR?.uppercased() } ?? []).sorted() }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                OmniExplorePageHeader(back: "Khám phá bộ từ", title: set?.name ?? "")
                    .id("top")
                if let set {
                    OmniSetSummaryCard(words: set.words.map(store.display), owned: store.ownedCount(set))
                    downloadButton(set)
                }
                chips
                LazyVStack(spacing: 10) {
                    ForEach(Array(filtered.enumerated()), id: \.element.vocabularyIdentity) { index, v in
                        Button { stage = StageRequest(words: filtered, index: index) } label: {
                            WordCardView(vocab: store.display(v), mastery: store.mastery(v), mode: .summary)
                                .overlay(alignment: .bottomTrailing) {
                                    if !store.isOwned(v) {
                                        Text("＋ Tải về")
                                            .font(.omniBody(10, weight: 800))
                                            .foregroundStyle(Color(hex: 0x2F6FD6))
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(Color(hex: 0xE7EFFF), in: Capsule())
                                            .padding(12)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        // after scrolling a good way down, a button in the bottom-right corner jumps back to the top
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 700 } action: { _, far in
            withAnimation(.easeInOut(duration: 0.2)) { showsTopButton = far }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsTopButton {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(palette.selected, in: Circle())
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 20)
                .padding(.bottom, 24)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Lên đầu trang")
            }
        }
        }
        .background { PixelSkyBackground() }
        .omniStatusBarBackdrop()
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $stage) { request in
            OmniCardStageView(title: set?.name ?? "", words: request.words, index: request.index, store: store)
        }
    }

    private func downloadButton(_ set: OmniWordSet) -> some View {
        let missing = set.words.count - store.ownedCount(set)
        return Button {
            Task { await store.download(set.words, topicId: set.id) }
        } label: {
            Text(missing == 0 ? "Đã tải cả bộ" : store.downloading.isEmpty ? "Tải về cả bộ (\(missing) từ)" : "Đang tải...")
        }
        .buttonStyle(OmniPrimaryButtonStyle())
        .disabled(missing == 0 || !store.downloading.isEmpty)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("all", "Tất cả")
                chip("owned", "Đã tải")
                chip("new", "Chưa tải")
                ForEach(levels, id: \.self) { chip($0, $0) }
            }
        }
    }

    private func chip(_ key: String, _ title: String) -> some View {
        let on = filter == key
        return Button { withAnimation(.easeInOut(duration: 0.2)) { filter = key } } label: {
            Text(title)
                .font(.omniBody(11.5, weight: 700))
                .foregroundStyle(on ? palette.card : palette.muted)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(on ? palette.text : palette.card, in: Capsule())
                .overlay(Capsule().stroke(on ? .clear : palette.line))
        }
        .buttonStyle(.plain)
    }
}

/// Words of a set by CEFR level or by learning level, as in the old Library overview.
struct OmniSetSummaryCard: View {
    @Environment(\.omniPalette) private var palette
    let words: [Vocabulary]
    let owned: Int
    @State private var byLevel = false

    var body: some View {
        let summary = VocabularyCollectionSummary(vocabularies: words)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                OmniSectionLabel("Tổng quan bộ từ")
                Spacer()
                Text("\(summary.total) từ · Đã tải \(owned)").font(.omniBody(12, weight: 700)).foregroundStyle(palette.muted)
            }
            Picker("Loại biểu đồ", selection: $byLevel) {
                Text("CEFR").tag(false)
                Text("Cấp độ học").tag(true)
            }
            .pickerStyle(.segmented)
            if byLevel { levelBars(summary) } else { cefrChart(summary) }
        }
        .omniCard(padding: 16, radius: 22)
    }

    private func cefrChart(_ summary: VocabularyCollectionSummary) -> some View {
        let maxCount = max(1, summary.cefrCounts.values.max() ?? 0)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(VocabularyCollectionSummary.cefrLevels, id: \.self) { level in
                let count = summary.cefrCounts[level, default: 0]
                VStack(spacing: 4) {
                    Text("\(count)").font(.omniBody(10.5, weight: 700)).foregroundStyle(palette.muted).monospacedDigit()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(hex: 0x5E97EC), Color(hex: 0x2F6FD6)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(2, 110 * CGFloat(count) / CGFloat(maxCount)))
                    Text(level).font(.omniBody(11, weight: 700)).foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(level): \(count) từ")
            }
        }
        .frame(height: 150, alignment: .bottom)
    }

    private func levelBars(_ summary: VocabularyCollectionSummary) -> some View {
        let rows: [(String, Int, Bool)] = [("New", summary.unlearnedCount, true)]
            + VocabularyCollectionSummary.learningBuckets.map { (VocabularyCollectionSummary.learningTitle(for: $0), summary.learningLevelCounts[$0, default: 0], false) }
        let maxCount = max(1, rows.map(\.1).max() ?? 0)
        return VStack(spacing: 7) {
            ForEach(rows, id: \.0) { title, count, isNew in
                HStack(spacing: 8) {
                    Text(title).font(.omniBody(11, weight: 600)).foregroundStyle(palette.muted).frame(width: 52, alignment: .leading)
                    GeometryReader { p in
                        Capsule().fill(palette.panel)
                            .overlay(alignment: .leading) {
                                Capsule().fill(isNew ? Color(hex: 0x9AA2B2) : Color(hex: 0x2F6FD6))
                                    .frame(width: max(count > 0 ? 6 : 0, p.size.width * CGFloat(count) / CGFloat(maxCount)))
                            }
                    }
                    .frame(height: 10)
                    Text("\(count)").font(.omniBody(11, weight: 700)).foregroundStyle(palette.text).monospacedDigit().frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title): \(count) từ")
            }
        }
    }
}
