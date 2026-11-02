import SwiftUI

// The results after a level: word by word, the card turns over as it was, then its scores come in
// (each exercise type, the five skills against the last two times, mastery M), what the next review
// will reinforce and when it is; last, the card takes its new level and stars. Ditan sees the level,
// the stars and the review day; the scores stay behind an Extraordinary upgrade.

/// One word's outcome, with what the results screen compares it to.
struct WordResultItem: Identifiable {
    /// The word as it was before this level.
    let vocab: Vocabulary
    let result: WordMasteryResult
    /// Skill scores of earlier sessions, newest first (two at most).
    var history: [[String: Double]] = []
    /// What the next review adds for this word.
    var boost: [Reinforcement] = []

    var id: String { result.user_vocabulary_id }
    var levelBefore: Int { result.level_before ?? vocab.learning_level ?? 0 }
    var levelAfter: Int { result.stored_level ?? result.reached_level ?? levelBefore }
    var nextReview: Date? { result.next_review.flatMap(ReviewDates.parse) }
    var reviewDays: Int? {
        nextReview.map { date in
            let cal = Calendar.current
            return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0)
        }
    }
    func vocab(level: Int) -> Vocabulary { var v = vocab; v.learning_level = level; return v }
    func skills(_ scores: [String: Double]) -> [Double] { LearningSkill.allCases.map { scores[$0.rawValue] ?? 0 } }
}

enum WordResultLoader {
    /// Pairs each settled word with its card and, for Extra, its last two skill profiles and the
    /// reinforcement its next review will get.
    static func load(results: [WordMasteryResult], words: [Vocabulary], sessionID: UUID, isExtra: Bool) async -> [WordResultItem] {
        var items: [WordResultItem] = results.compactMap { r in
            guard let vocab = words.first(where: { $0.id == r.user_vocabulary_id }) else { return nil }
            return WordResultItem(vocab: vocab, result: r)
        }
        // AuthManager lives on the main actor.
        guard isExtra, let userId = await AuthManager.shared.currentUser?.id.uuidString else { return items }
        let ids = items.map(\.id)
        let histories = await withTaskGroup(of: (String, [[String: Double]]).self) { group in
            for id in ids {
                group.addTask {
                    let rows = (try? await WordHistoryRepository.fetch(userId: userId, userVocabularyId: id)) ?? []
                    let past = rows.filter { $0.session_id != sessionID }.compactMap(\.skill_scores).filter { !$0.isEmpty }
                    return (id, Array(past.suffix(2).reversed()))
                }
            }
            var all: [String: [[String: Double]]] = [:]
            for await (id, past) in group { all[id] = past }
            return all
        }
        let profiles = (try? await LearningProfileRepository.fetchProfiles(userId: userId)) ?? [:]
        for k in items.indices {
            items[k].history = histories[items[k].id] ?? []
            if let profile = profiles[items[k].id] { items[k].boost = ReinforcementPlanner.plan(for: profile) }
        }
        return items
    }
}

struct LearningResultsView: View {
    let items: [WordResultItem]
    /// The learner's plan: Extra sees every score.
    let isExtra: Bool
    let dark: Bool
    let title: String
    var place: String? = nil
    let finishTitle: String
    let onFinish: () -> Void

    @State private var index = 0

    private var palette: QuizPalette { QuizPalette(dark: dark) }

    var body: some View {
        ZStack {
            palette.page.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if index < items.count {
                    // the last word's button leaves the results (no summary page)
                    WordResultPage(item: items[index], isExtra: isExtra, palette: palette,
                                   nextTitle: index == items.count - 1 ? finishTitle : "Từ tiếp theo") {
                        if index < items.count - 1 { index += 1 } else { onFinish() }
                    }
                    .id(items[index].id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.omniDisplay(24)).foregroundStyle(palette.text)
            Text([place, "từ \(index + 1)/\(items.count)"].compactMap { $0 }.joined(separator: " · "))
                .font(.omniBody(12, weight: 700)).foregroundStyle(palette.muted)
            HStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { k in
                    Capsule().fill(k < index ? Color(hex: 0x34b45a) : k == index ? Color(hex: 0xffcc33) : palette.empty)
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - One word

private struct WordResultPage: View {
    let item: WordResultItem
    let isExtra: Bool
    let palette: QuizPalette
    let nextTitle: String
    let onNext: () -> Void

    @State private var flipped = false
    @State private var step = 0
    @State private var typesOn = false
    @State private var radarT: Double = 0
    @State private var m: Int
    @State private var upgraded = false
    @State private var celebrate = false
    @State private var finished = false
    @State private var fast = false
    @State private var showUpgrade = false
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    init(item: WordResultItem, isExtra: Bool, palette: QuizPalette, nextTitle: String, onNext: @escaping () -> Void) {
        self.item = item; self.isExtra = isExtra; self.palette = palette; self.nextTitle = nextTitle; self.onNext = onNext
        _m = State(initialValue: item.result.previous_mastery ?? 0)
    }

    /// The blocks under the card, in the order they come in.
    private var blocks: [String] { isExtra ? ["types", "radar", "m", "boost", "next"] : ["lock", "level", "next"] }
    private func shown(_ id: String) -> Bool { (blocks.firstIndex(of: id).map { $0 < step }) ?? false }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    card.id("card")
                    ForEach(blocks, id: \.self) { id in
                        if shown(id) {
                            block(id).id(id)
                                .transition(.opacity.combined(with: .offset(y: 12)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, finished ? 100 : 24)
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .topTrailing) {
                if !finished {
                    Button("Bỏ qua") { fast = true }
                        .font(.omniBody(12, weight: 700)).foregroundStyle(palette.text)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .background(Capsule().fill(palette.card.opacity(0.9)))
                        .buttonStyle(.plain)
                        .padding(.trailing, 16).padding(.top, 4)
                }
            }
            .overlay {
                if celebrate { CelebrationConfettiView().allowsHitTesting(false).ignoresSafeArea() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if finished {
                    // Only once everything is shown, so it never covers a block coming in.
                    Button(nextTitle, action: onNext)
                        .buttonStyle(Quiz3DButtonStyle(tone: .blue))
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
                        .background(palette.page.opacity(0.97))
                        .transition(.move(edge: .bottom))
                }
            }
            .task { await run(proxy) }
        }
        .sheet(isPresented: $showUpgrade) { ExtraordinaryUpgradeSheet(interfaceModeRaw: $interfaceModeRaw) }
    }

    // MARK: the sequence

    private func pause(_ seconds: Double) async {
        guard !fast else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func run(_ proxy: ScrollViewProxy) async {
        await pause(0.35)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { flipped = true }
        await pause(1.0)
        for (k, id) in blocks.enumerated() {
            withAnimation(.easeOut(duration: 0.35)) { step = k + 1 }
            await pause(0.08)
            withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(id, anchor: .bottom) }
            switch id {
            case "types":
                await pause(0.2)
                withAnimation(.easeOut(duration: 0.9)) { typesOn = true }
                await pause(1.2)
            case "radar":
                await pause(0.4)
                withAnimation(.easeOut(duration: 1.1)) { radarT = 1 }
                await pause(1.4)
            case "m":
                await pause(0.3)
                withAnimation(.easeOut(duration: 1.1)) { m = item.result.mastery ?? m }
                await pause(1.4)
            default:
                await pause(0.9)
            }
        }
        // Last, back up to the card: it takes its new level, stars and M.
        withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo("card", anchor: .top) }
        await pause(0.7)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { upgraded = true }
        if item.levelAfter > item.levelBefore && !fast { celebrate = true }
        SpeechManager.shared.speak(word: item.vocab.vocab ?? "", ipa: item.vocab.IPA)
        await pause(1.3)
        withAnimation(.easeOut(duration: 0.3)) { finished = true }
    }

    // MARK: the card

    private var card: some View {
        let level = upgraded ? item.levelAfter : item.levelBefore
        let mastery = isExtra ? (upgraded ? item.result.mastery : item.result.previous_mastery) : nil
        let scale: CGFloat = 0.78, size = WordCardView.fullSize
        return VStack(spacing: 10) {
            ZStack {
                CardBack()
                    .opacity(flipped ? 0 : 1)
                WordCardView(vocab: item.vocab(level: level), mastery: mastery, mode: .full, speaksOnTap: true)
                    .overlay { if upgraded { CardShine() } }
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(scale * (upgraded ? 1 : 0.97))
            .frame(width: size.width * scale, height: size.height * scale)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.vocab.vocab ?? ""), cấp \(level)")

            if upgraded {
                HStack(spacing: 8) {
                    decisionTag(item.result.decisionKind)
                    Text(item.levelAfter == item.levelBefore ? "Giữ cấp \(item.levelAfter)" : "Cấp \(item.levelBefore) → Cấp \(item.levelAfter)")
                        .font(.omniBody(14, weight: 800)).foregroundStyle(palette.text)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func decisionTag(_ kind: LevelDecisionKind) -> some View {
        let (fill, text): (UInt32, UInt32) = switch kind {
        case .jump: palette.dark ? (0x233e43, 0x8ee6a4) : (0xe2f6e6, 0x1f7a37)
        case .advance: palette.dark ? (0x252c52, 0xeef1fb) : (0xe3edff, 0x2f6fd6)
        case .hold: palette.dark ? (0x403621, 0xe8b93a) : (0xfff1d1, 0x8a5a00)
        }
        return Text(kind == .hold ? "Giữ cấp" : kind == .jump ? "Lên \(max(2, item.levelAfter - item.levelBefore)) cấp" : "Lên cấp")
            .font(.omniBody(11.5, weight: 800)).foregroundStyle(Color(hex: text))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(Color(hex: fill)))
    }

    // MARK: blocks

    @ViewBuilder
    private func block(_ id: String) -> some View {
        switch id {
        case "types": section("Điểm từng dạng bài") { typeRows }
        case "radar": section("Hồ sơ 5 kỹ năng") { radar }
        case "m": section("Điểm thông thạo M") { masteryBlock }
        case "boost": section("Lần tới tăng cường") { boostBlock }
        case "next": section(isExtra ? "Lịch ôn tiếp theo" : "Lịch ôn") { nextBlock }
        case "lock": lockBlock
        case "level": levelBlock
        default: EmptyView()
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.omniBody(12, weight: 800)).tracking(0.8).foregroundStyle(palette.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1))
    }

    private var typeRows: some View {
        let scores = QuestionType.allCases.compactMap { type in item.result.exercise_scores[type.telemetryName].map { (type, $0) } }
        return VStack(spacing: 7) {
            ForEach(scores, id: \.0) { type, score in
                QuizScoreBar(name: type.questTitle, value: typesOn ? Int(score.rounded()) : 0, palette: palette, nameWidth: 74)
            }
        }
    }

    private var radar: some View {
        let now = item.skills(item.result.skill_scores)
        let prev = item.history.first.map(item.skills)
        let prev2 = item.history.count > 1 ? item.skills(item.history[1]) : nil
        return VStack(spacing: 6) {
            SkillRadar(now: now, previous: prev, older: prev2, t: radarT, palette: palette)
                .frame(height: 250)
            HStack(spacing: 12) {
                if prev2 != nil { legend(Color(hex: 0x9aa3b5), "2 lần trước") }
                if prev != nil { legend(Color(hex: 0x9cc0ff), "Lần trước") }
                legend(Color(hex: 0xffcc33), "Lần này")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.omniBody(11.5, weight: 700)).foregroundStyle(palette.muted)
        }
    }

    private var masteryBlock: some View {
        let before = item.result.previous_mastery, after = item.result.mastery
        let reached = after != nil && m == after
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(after == nil ? "--" : "\(m)")
                    .font(.omniDisplay(52)).foregroundStyle(palette.text)
                    .contentTransition(.numericText(value: Double(m)))
                if let before { Text("từ \(before)").font(.omniDisplay(15)).foregroundStyle(palette.muted) }
                Spacer()
                if reached, let after {
                    let delta = after - (before ?? 0)
                    let v: QuizPalette.Verdict = delta > 0 ? .ok : delta < 0 ? .bad : .near
                    Text(before == nil ? "Mới" : delta >= 0 ? "+\(delta)" : "−\(-delta)")
                        .font(.omniDisplay(16)).foregroundStyle(palette.verdict(v).text)
                        .padding(.horizontal, 12).padding(.vertical, 3)
                        .background(Capsule().fill(palette.verdict(v).fill))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.empty)
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0x6fa2ff), Color(hex: 0x9b7bff)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(m) / 100)
                    if let before {
                        Rectangle().fill(palette.text.opacity(0.55)).frame(width: 2).offset(x: g.size.width * CGFloat(before) / 100)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            HStack {
                Text("0"); Spacer(); Text("Cấp \(item.levelBefore) → \(item.levelAfter)"); Spacer(); Text("100")
            }
            .font(.omniBody(10.5, weight: 700)).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    private var boostBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.boost.isEmpty {
                Text("Không cần tăng cường: kỹ năng nào cũng từ 80 điểm.")
                    .font(.omniBody(13, weight: 600)).foregroundStyle(palette.muted)
            } else {
                let near = palette.verdict(.near)
                FlowLayout(spacing: 8) {
                    ForEach(item.boost, id: \.skill) { b in
                        HStack(spacing: 6) {
                            Text(b.type.questTitle).font(.omniBody(13.5, weight: 800))
                            Text("+\(b.count)").font(.omniDisplay(13))
                        }
                        .foregroundStyle(near.text)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(near.fill))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(near.edge, lineWidth: 2))
                        .accessibilityLabel("\(b.type.questTitle), thêm \(b.count) câu")
                    }
                }
                Text(item.boost.map { "\($0.skill.title) \(Int($0.skillScore.rounded()))" }.joined(separator: " · ") + " · làm trước ở lượt ôn tới")
                    .font(.omniBody(12.5, weight: 600)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nextBlock: some View {
        let date = item.nextReview, days = item.reviewDays
        let weekday = date.map { ["Chủ nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"][Calendar.current.component(.weekday, from: $0) - 1] }
        let dayMonth = date.map { "\(Calendar.current.component(.day, from: $0))/\(Calendar.current.component(.month, from: $0))" }
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(date.map { "TH\(Calendar.current.component(.month, from: $0))" } ?? "--")
                    .font(.omniBody(10, weight: 800)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 2).background(Color(hex: 0xe8463f))
                Text(date.map { "\(Calendar.current.component(.day, from: $0))" } ?? "?")
                    .font(.omniDisplay(24)).foregroundStyle(Color(hex: 0x2a2440))
            }
            .frame(width: 54).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x2a2440), lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                if let days, let weekday, let dayMonth {
                    Text(isExtra ? "\(weekday), \(dayMonth)" : "Ôn lại sau \(days) ngày")
                        .font(.omniBody(16, weight: 800)).foregroundStyle(palette.text)
                    Text(isExtra ? (days == 0 ? "hôm nay" : "sau \(days) ngày · đúng lúc bạn sắp quên") : "\(weekday), \(dayMonth)")
                        .font(.omniBody(12.5, weight: 600)).foregroundStyle(palette.muted)
                } else {
                    Text("Chưa có lịch ôn").font(.omniBody(16, weight: 800)).foregroundStyle(palette.text)
                }
            }
        }
    }

    private var lockBlock: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(["Chọn nghĩa", "Nghe viết", "Viết từ", "Ghép câu", "Đọc to"].enumerated()), id: \.offset) { k, name in
                    QuizScoreBar(name: name, value: 50 + k * 9, palette: palette, nameWidth: 74)
                }
                Text("M --").font(.omniDisplay(40)).foregroundStyle(palette.text)
            }
            .padding(14)
            .blur(radius: 6).opacity(0.5)
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x2a2440))
                    .frame(width: 38, height: 38).background(.white, in: Circle()).overlay(Circle().stroke(Color(hex: 0x2a2440), lineWidth: 3))
                Text("Omni vẫn đang học dữ liệu học tập của bạn, hãy nâng cấp Extraordinary để những dữ liệu này tối ưu trải nghiệm học của bạn")
                    .font(.omniBody(13.5, weight: 700)).foregroundStyle(palette.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Nâng cấp") { showUpgrade = true }
                    .buttonStyle(Quiz3DButtonStyle(tone: .amber, height: 42))
                    .frame(maxWidth: 180)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var levelBlock: some View {
        HStack(spacing: 10) {
            decisionTag(item.result.decisionKind)
            Text("Cấp \(item.levelBefore) → Cấp \(item.levelAfter)").font(.omniBody(15, weight: 800)).foregroundStyle(palette.text)
            Spacer(minLength: 0)
            CardStars(count: item.levelAfter, size: 12)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1))
    }
}

/// The card's back before it turns over: the printed card back, as when a card is opened.
private struct CardBack: View {
    var body: some View {
        Image("CardBack").resizable()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
            .accessibilityHidden(true)
    }
}

/// One bright sweep across the card as it takes its new values.
private struct CardShine: View {
    @State private var x: CGFloat = -1.2
    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: g.size.width * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: g.size.width * x)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { x = 1.4 } }
    }
}

// MARK: - Radar

/// Five skills on five axes: the two earlier sessions as outlines, this one growing out of the last.
private struct SkillRadar: View {
    let now: [Double]
    let previous: [Double]?
    let older: [Double]?
    let t: Double
    let palette: QuizPalette

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2 + 4), r = min(g.size.width / 2 - 56, g.size.height / 2 - 26)
            ZStack {
                ForEach([20.0, 40, 60, 80, 100], id: \.self) { ring in
                    RadarShape(from: Array(repeating: ring, count: 5), to: Array(repeating: ring, count: 5), t: 1, center: c, radius: r)
                        .stroke(palette.line, lineWidth: 1)
                }
                Path { p in
                    for i in 0..<5 { p.move(to: c); p.addLine(to: RadarShape.point(i, 100, c, r)) }
                }
                .stroke(palette.line, lineWidth: 1)
                if let older {
                    RadarShape(from: older, to: older, t: 1, center: c, radius: r)
                        .stroke(Color(hex: 0x9aa3b5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if let previous {
                    RadarShape(from: previous, to: previous, t: 1, center: c, radius: r).fill(Color(hex: 0x9cc0ff).opacity(0.18))
                    RadarShape(from: previous, to: previous, t: 1, center: c, radius: r).stroke(Color(hex: 0x9cc0ff), lineWidth: 2)
                }
                let start = previous ?? Array(repeating: 0, count: 5)
                RadarShape(from: start, to: now, t: t, center: c, radius: r).fill(Color(hex: 0xffcc33).opacity(0.3))
                RadarShape(from: start, to: now, t: t, center: c, radius: r).stroke(Color(hex: 0xffcc33), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                ForEach(0..<5, id: \.self) { i in
                    let a = LearningSkill.allCases[i]
                    Text(a.title)
                        .font(.omniBody(11, weight: 700)).foregroundStyle(palette.text)
                        .fixedSize()
                        .position(label(i, c, r))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(LearningSkill.allCases.enumerated().map { "\($1.title) \(Int(now[$0].rounded()))" }.joined(separator: ", "))
    }

    private func label(_ i: Int, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let p = RadarShape.point(i, 100, c, r), a = RadarShape.angle(i)
        let dx = cos(a) * 14 + (abs(cos(a)) > 0.3 ? (cos(a) > 0 ? 30 : -30) : 0), dy = sin(a) * 14
        return CGPoint(x: p.x + dx, y: p.y + dy)
    }
}

private struct RadarShape: Shape {
    var from: [Double]
    var to: [Double]
    var t: Double
    let center: CGPoint
    let radius: CGFloat

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    static func angle(_ i: Int) -> Double { -Double.pi / 2 + Double(i) * 2 * Double.pi / 5 }
    static func point(_ i: Int, _ value: Double, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let a = angle(i), k = CGFloat(max(0, min(100, value)) / 100) * r
        return CGPoint(x: c.x + CGFloat(cos(a)) * k, y: c.y + CGFloat(sin(a)) * k)
    }

    func path(in rect: CGRect) -> Path {
        Path { p in
            for i in 0..<5 {
                let v = from[i] + (to[i] - from[i]) * t
                let q = Self.point(i, v, center, radius)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
        }
    }
}
