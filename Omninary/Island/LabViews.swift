import SwiftUI

// Nhà nghiên cứu: progress, how Extra schedules reviews, and the deck of word cards.

private struct LabColors {
    let night: Bool
    var bg: Color { night ? Color(hex: 0x10142a) : Color(hex: 0xeef3fb) }
    var card: Color { night ? Color(hex: 0x1b2140) : .white }
    var line: Color { night ? Color(hex: 0x2b3457) : Color(hex: 0xe3e9f2) }
    var text: Color { night ? Color(hex: 0xeef1fb) : Color(hex: 0x17202e) }
    var muted: Color { night ? Color(hex: 0xa6afc8) : Color(hex: 0x5b6779) }
    var violet: Color { Color(hex: 0x8f6bff) }
    var ghost: Color { night ? Color(hex: 0x3a4472) : Color(hex: 0xd6dde8) }
}

private extension View {
    func labCard(_ c: LabColors, radius: CGFloat = 18) -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(c.card, in: RoundedRectangle(cornerRadius: radius)).overlay(RoundedRectangle(cornerRadius: radius).stroke(c.line))
            .shadow(color: Color(red: 20 / 255, green: 40 / 255, blue: 80 / 255).opacity(c.night ? 0.3 : 0.12), radius: 9, y: 6)
    }
}

struct LabScreen: View {
    @ObservedObject var game: IslandGame
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lab_tab") private var tab = "prog"
    @State private var history: [WordMasteryHistory] = []
    @State private var path: [String] = []
    @State private var listSheet: (title: String, note: String, words: [Vocabulary])?
    @State private var showAdd = false

    private var c: LabColors { LabColors(night: game.night) }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(c.text).frame(width: 42, height: 42).background(c.card, in: RoundedRectangle(cornerRadius: 14)) }
                        .accessibilityLabel("Rời Nhà nghiên cứu")
                    Text("Nhà nghiên cứu").font(.omniBody(24, weight: 800)).foregroundStyle(c.text)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Picker("Mục", selection: $tab) {
                    Text("Tiến độ").tag("prog"); Text("Extra tối ưu").tag("opt"); Text("Bộ từ").tag("deck")
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case "opt": LabOptimiseTab(game: game, history: history, c: c) { path.append($0) }
                        case "deck": LabDeckTab(game: game, c: c, open: { path.append($0) }, add: { showAdd = true })
                        default: LabProgressTab(game: game, c: c) { listSheet = $0 }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 30)
                }
            }
            .background(c.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                if let v = game.vocabs.first(where: { $0.id == id }) { WordLabDetail(game: game, vocab: v, history: history.filter { $0.user_vocabulary_id == id }, c: c) }
            }
            .navigationDestination(for: LabRoute.self) { r in
                switch r {
                case .folders: MyVocabularyView()
                case .oldReview: VocabularyLearningView()
                }
            }
        }
        .sheet(isPresented: Binding(get: { listSheet != nil }, set: { if !$0 { listSheet = nil } })) {
            if let s = listSheet {
                WordListSheet(title: s.title, note: s.note, words: s.words) { id in listSheet = nil; tab = "deck"; path.append(id) }
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showAdd) { AddVocabView { Task { await game.load() } } }
        .task {
            if let id = game.labWord { tab = "deck"; path = [id] }
            if let uid = AuthManager.shared.currentUser?.id.uuidString { history = (try? await WordHistoryRepository.fetch(userId: uid)) ?? [] }
        }
        .environment(\.colorScheme, game.night ? .dark : .light)
    }
}

enum LabRoute: Hashable { case folders, oldReview }

// MARK: - Tiến độ

private struct LabProgressTab: View {
    @ObservedObject var game: IslandGame
    let c: LabColors
    let list: ((title: String, note: String, words: [Vocabulary])) -> Void

    var body: some View {
        let learned = game.learnedVocabs, now = Date(), cal = Calendar.current, today = cal.startOfDay(for: now)
        let solid = learned.filter { ($0.id.flatMap { game.profiles[$0]?.lastMastery } ?? 0) >= 85 }
        let nextOf: (Vocabulary) -> Date? = { $0.next_review.flatMap(ReviewDates.parse) }
        let overdue = learned.filter { (nextOf($0) ?? .distantFuture) < today }
        let due = learned.filter { ReviewScheduler.isDue($0, now: now) && !overdue.contains($0) }
        let byLevel = (0...7).map { b in Vocabulary.sortedItems(game.vocabs).filter { LearningLevelDisplay.bucket(for: $0.learning_level ?? 0) == b } }
        let maxL = max(1, byLevel.map(\.count).max() ?? 1)
        let cefr: [(String, [Vocabulary])] = ["A1", "A2", "B1", "B2", "C1", "C2"].map { (k: String) in (k, learned.filter { $0.CEFR?.uppercased() == k }) }
        let next7 = (0..<7).map { k -> (Date, Int) in
            let d = cal.date(byAdding: .day, value: k, to: today)!, e = cal.date(byAdding: .day, value: 1, to: d)!
            return (d, learned.filter { guard let n = nextOf($0) else { return false }; return (k == 0 && n < d) || (n >= d && n < e) }.count)
        }
        let max7 = max(1, next7.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            Text("Mỗi từ đã học là một cư dân trên đảo. Đây là tình hình \(game.vocabs.count) nghĩa từ bạn đã lưu.").font(.omniBody(13.5, weight: 500)).foregroundStyle(c.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("\(learned.count)", "từ đã học", "trên \(game.vocabs.count) nghĩa đã lưu", c.text) { list(("Từ đã học", "", learned)) }
                tile("\(solid.count)", "từ đã vững", "điểm M gần nhất từ 85", Color(hex: 0x2f9e4f)) { list(("Từ đã vững", "Điểm M gần nhất từ 85 trở lên. Extra dời các từ này ra xa để đỡ ôn thừa.", solid)) }
                tile("\(due.count)", "tới hạn hôm nay", "ôn trong hôm nay để giữ nhịp", Color(hex: 0xe0603a)) { list(("Tới hạn hôm nay", "", due)) }
                tile("\(overdue.count)", "từ quá hạn", "đã lỡ lịch, nên ôn trước", Color(hex: 0x8a1f12)) { list(("Từ quá hạn", "Các từ này lỡ lịch ôn vài ngày trước. Ôn sớm để không quên.", overdue)) }
            }
            heading("Số từ ở mỗi cấp")
            VStack(spacing: 6) {
                ForEach(0...7, id: \.self) { b in
                    Button { list((b == 0 ? "Từ mới" : LearningLevelDisplay.title(for: b == 7 ? 10 : b), "", byLevel[b])) } label: {
                        HStack(spacing: 8) {
                            Text(b == 0 ? "Mới" : LearningLevelDisplay.title(for: b == 7 ? 10 : b)).font(.omniBody(12.5, weight: 700)).foregroundStyle(c.muted).frame(width: 56, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(c.ghost).overlay(alignment: .leading) {
                                    Capsule().fill(b == 0 ? Color(hex: 0xa8a2b8) : b >= 7 ? Color(hex: 0xf0b429) : b >= 6 ? c.violet : Color(hex: 0x3f6fca))
                                        .frame(width: g.size.width * CGFloat(byLevel[b].count) / CGFloat(maxL))
                                }
                            }.frame(height: 10)
                            Text("\(byLevel[b].count)").font(.omniDisplay(14)).foregroundStyle(c.text).frame(width: 34, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain).disabled(byLevel[b].isEmpty)
                }
            }
            .labCard(c)
            heading("Theo trình độ CEFR")
            HStack(spacing: 6) {
                ForEach(cefr, id: \.0) { item in
                    let k: String = item.0, ws: [Vocabulary] = item.1, dot: UInt32 = CEFRColors[k] ?? 0x9aa2b2
                    Button { list(("Trình độ \(k)", "", ws)) } label: {
                        VStack(spacing: 2) {
                            Circle().fill(Color(hex: dot)).frame(width: 10, height: 10)
                            Text("\(ws.count)").font(.omniDisplay(17)).foregroundStyle(c.text)
                            Text(k).font(.omniBody(11, weight: 700)).foregroundStyle(c.muted)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(c.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line))
                    }.buttonStyle(.plain)
                }
            }
            heading("Lịch ôn 7 ngày tới")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { k in
                    VStack(spacing: 4) {
                        Text("\(next7[k].1)").font(.omniDisplay(14)).foregroundStyle(c.text)
                        RoundedRectangle(cornerRadius: 4).fill(k == 0 ? Color(hex: 0xe0603a) : Color(hex: 0x3f6fca))
                            .frame(height: max(3, 90 * CGFloat(next7[k].1) / CGFloat(max7)))
                        Text(k == 0 ? "Hôm nay" : next7[k].0.formatted(.dateTime.day().month(.defaultDigits))).font(.omniBody(10, weight: 600)).foregroundStyle(c.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140, alignment: .bottom).labCard(c)
            Text("Hôm nay gồm cả các từ quá hạn.").font(.omniBody(12, weight: 500)).foregroundStyle(c.muted)
            NavigationLink(value: LabRoute.oldReview) {
                HStack { Image(systemName: "list.bullet.rectangle"); Text("Mở trang ôn tập dạng danh sách"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.omniBody(14, weight: 700)).foregroundStyle(c.text).labCard(c)
            }.buttonStyle(.plain)
        }
    }

    private func heading(_ t: String) -> some View { Text(t).font(.omniBody(16, weight: 800)).foregroundStyle(c.text) }
    private func tile(_ value: String, _ label: String, _ hint: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.omniDisplay(28)).foregroundStyle(color)
                Text(label).font(.omniBody(13.5, weight: 800)).foregroundStyle(c.text)
                Text(hint).font(.omniBody(11, weight: 500)).foregroundStyle(c.muted).lineLimit(2)
            }.labCard(c)
        }.buttonStyle(.plain)
    }
}

// MARK: - Extra tối ưu

/// The demo's comparison: a fixed 1-3-7-15-30-60 ladder against Extra's rules on a simulated mastery score.
struct LabSimulation {
    struct Review { let t: Int; let M: Int; let type: String; let gap: Int; let why: String }
    struct Word { let vocab: Vocabulary; let d0: Int; let fixed: [Int]; let extra: [Review]; let done: [Review]; let avgM: Double? }
    let today: Int, horizon: Int, words: [Word]
    let holds: Int, trimmed: Int, fixedDone: Int, extraDone: Int, nextF: Int, nextE: Int
    let groups: [(name: String, n: Int, fixed: Double, extra: Double)]
    let weeks: [(a: Int, f: Int, e: Int, future: Bool)]

    static let ladder = [1, 3, 7, 15, 30, 60, 120, 240, 365]
    static let base: [String: Double] = ["A1": 0.92, "A2": 0.86, "B1": 0.78, "B2": 0.7, "C1": 0.62, "C2": 0.55]

    init(_ learned: [Vocabulary]) {
        // As in the demo: the learner's words are spread over 24 days of study, today is day 25.
        let perDay = max(1, Int((Double(learned.count) / 24).rounded(.up)))
        let todayV = 25
        today = todayV
        horizon = 70
        var ws: [Word] = []
        for (i, v) in learned.enumerated() {
            var R = Rng32(i * 7919 + 13)
            func gauss() -> Double { (R() + R() + R() - 1.5) * 1.15 }
            let d0 = 1 + i / perDay
            let p = (Self.base[v.CEFR?.uppercased() ?? ""] ?? 0.75) + (R() - 0.5) * 0.42
            var fixed: [Int] = []; var t = d0
            for gap in Self.ladder { t += gap; if t > horizon { break }; fixed.append(t) }
            var extra: [Review] = []; var tt = d0 + 1, k = 0, prev: Int?, reps = 0
            while tt <= horizon && extra.count < 14 {
                let M = Int(max(18, min(99, (22 + p * 66 + Double(reps) * 4 + gauss() * 11).rounded())))
                let drop = prev.map { $0 - M } ?? 0, F = M < 52 ? 2 : M < 66 ? 1 : 0
                let type: String, gap: Int, why: String
                if M < 60 || drop >= 20 || F >= 2 { type = "hold"; gap = 1; why = M < 60 ? "M = \(M), dưới 60" : drop >= 20 ? "M tụt \(drop) điểm so với lần trước" : "sai lần đầu ở \(F) dạng bài" }
                else if M >= 85 && drop <= 5 { k = min(Self.ladder.count - 1, k + 2); type = "jump"; gap = Self.ladder[k]; why = "M = \(M), không tụt điểm, nhảy 2 bậc" }
                else { k = min(Self.ladder.count - 1, k + 1); type = "ok"; gap = Self.ladder[k]; why = "M = \(M), lên 1 bậc" }
                extra.append(Review(t: tt, M: M, type: type, gap: gap, why: why)); prev = M; reps += 1; tt += gap
            }
            let done = extra.filter { $0.t < todayV }
            ws.append(Word(vocab: v, d0: d0, fixed: fixed, extra: extra, done: done, avgM: done.isEmpty ? nil : Double(done.reduce(0) { $0 + $1.M }) / Double(done.count)))
        }
        words = ws
        let td = today
        func before(_ l: [Int], _ d: Int) -> Int { l.filter { $0 < d }.count }
        fixedDone = ws.reduce(0) { $0 + before($1.fixed, td) }
        extraDone = ws.reduce(0) { $0 + $1.done.count }
        holds = ws.reduce(0) { $0 + $1.done.filter { $0.type == "hold" }.count }
        trimmed = ws.reduce(0) { $0 + max(0, before($1.fixed, td) - $1.done.filter { $0.type != "hold" }.count) }
        nextF = ws.reduce(0) { $0 + $1.fixed.filter { $0 >= td && $0 < td + 30 }.count }
        nextE = ws.reduce(0) { $0 + $1.extra.filter { $0.t >= td && $0.t < td + 30 }.count }
        let rules: [(String, (Double) -> Bool)] = [("Từ yếu", { $0 < 65 }), ("Từ khá", { $0 >= 65 && $0 < 82 }), ("Từ vững", { $0 >= 82 })]
        groups = rules.map { name, f in
            let g = ws.filter { $0.avgM.map(f) ?? false }
            func avg(_ v: (Word) -> Int) -> Double { g.isEmpty ? 0 : Double(g.reduce(0) { $0 + v($1) }) / Double(g.count) }
            return (name, g.count, avg { before($0.fixed, td) }, avg { $0.done.count })
        }
        let startWeek = max(1, td - 28)
        weeks = (0..<6).map { k in
            let a = startWeek + k * 7, b = a + 6
            return (a, ws.reduce(0) { $0 + $1.fixed.filter { $0 >= a && $0 <= b }.count }, ws.reduce(0) { $0 + $1.extra.filter { $0.t >= a && $0.t <= b }.count }, a > td - 1)
        }
    }
}

private struct LabOptimiseTab: View {
    @ObservedObject var game: IslandGame
    let history: [WordMasteryHistory]
    let c: LabColors
    let open: (String) -> Void
    @ObservedObject private var hearts = OmniLearningHeartManager.shared
    @State private var showUpgrade = false
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    var body: some View {
        let sim = LabSimulation(game.learnedVocabs)
        let real = history.filter { $0.mode == "extraordinary" && ($0.decision == "hold" || $0.decision == "jump") }
        let maxG = max(0.1, sim.groups.flatMap { [$0.fixed, $0.extra] }.max() ?? 1), maxW = max(1, sim.weeks.flatMap { [$0.f, $0.e] }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            if !hearts.isExtra {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bạn đang dùng Ditandnary").font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
                    Text("Lịch ôn của bạn đang theo nhịp cố định. Phần dưới là mô phỏng nếu Extra lập lịch trên chính các từ bạn đã học.").font(.omniBody(13, weight: 500)).foregroundStyle(c.muted)
                    Button("Nâng cấp Extraordinary") { showUpgrade = true }.buttonStyle(IslandButtonStyle(kind: .primary))
                }
                .labCard(c).overlay(RoundedRectangle(cornerRadius: 18).stroke(c.violet, lineWidth: 2))
            }
            Text("Lịch cố định cho mọi từ ôn cùng một nhịp. Extra nhìn điểm M sau mỗi lần ôn để quyết định: từ yếu được ôn lại sớm, từ vững được dời ra xa.").font(.omniBody(13.5, weight: 500)).foregroundStyle(c.muted)
            if !real.isEmpty {
                Text("Những lần Extra ra tay thật").font(.omniBody(16, weight: 800)).foregroundStyle(c.text)
                ForEach(real.suffix(4).reversed()) { h in
                    let v = game.vocabs.first { $0.id == h.user_vocabulary_id }
                    Button { if v != nil { open(h.user_vocabulary_id) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(h.decision == "hold" ? "Ôn bù kịp lúc" : "Nhảy cấp").font(.omniBody(11, weight: 800)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(h.decision == "hold" ? Color(hex: 0xe0603a) : Color(hex: 0x2f9e6a), in: Capsule())
                                Text(v?.vocab ?? "Một từ").font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
                                Text(v?.V_meaning ?? "").font(.omniBody(12, weight: 500)).foregroundStyle(c.muted).lineLimit(1)
                            }
                            Text(h.decision == "hold" ? "M = \(h.mastery ?? 0), dưới ngưỡng an toàn. Extra hẹn ôn lại sớm thay vì đợi lịch cố định." : "M = \(h.mastery ?? 0), không tụt điểm. Extra bỏ qua một bậc và hẹn ôn xa hơn.")
                                .font(.omniBody(12.5, weight: 500)).foregroundStyle(c.muted)
                        }.labCard(c)
                    }.buttonStyle(.plain)
                }
            }
            Text("Mô phỏng 70 ngày trên \(sim.words.count) từ của bạn").font(.omniBody(16, weight: 800)).foregroundStyle(c.text)
            HStack(spacing: 8) {
                stat("+\(sim.holds)", "lượt ôn bù cho từ yếu", Color(hex: 0xe0603a))
                stat("−\(sim.trimmed)", "lượt bớt cho từ vững", Color(hex: 0x2f9e4f))
                let pct = sim.nextF == 0 ? 0 : Int(((1 - Double(sim.nextE) / Double(sim.nextF)) * 100).rounded())
                stat("\(pct >= 0 ? "−" : "+")\(abs(pct))%", "lượt ôn 30 ngày tới", c.text)
            }
            Text("Công sức ôn được chia cho ai").font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
            VStack(alignment: .leading, spacing: 10) {
                legend
                ForEach(sim.groups, id: \.name) { g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(g.name).font(.omniBody(13, weight: 800)).foregroundStyle(c.text); Text("\(g.n) từ").font(.omniBody(11.5, weight: 500)).foregroundStyle(c.muted) }
                        bar(g.fixed / maxG, c.ghost, String(format: "%.1f", g.fixed))
                        bar(g.extra / maxG, c.violet, String(format: "%.1f", g.extra))
                    }
                }
            }.labCard(c)
            if let weak = sim.groups.first, let strong = sim.groups.last {
                Text("Từ yếu được ôn \(String(format: "%.1f", weak.extra)) lượt thay vì \(String(format: "%.1f", weak.fixed)); từ vững chỉ cần \(String(format: "%.1f", strong.extra)) thay vì \(String(format: "%.1f", strong.fixed)). Tổng công sức gần như không đổi (\(sim.fixedDone) so với \(sim.extraDone) lượt), nhưng dồn về đúng chỗ.")
                    .font(.omniBody(13, weight: 500)).foregroundStyle(c.text).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(c.night ? Color(hex: 0x252c52) : Color(hex: 0xeef0ff), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Mỗi tuần ôn bao nhiêu lượt").font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
            VStack(alignment: .leading, spacing: 8) {
                legend
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<sim.weeks.count, id: \.self) { k in
                        let w = sim.weeks[k]
                        VStack(spacing: 3) {
                            HStack(alignment: .bottom, spacing: 2) {
                                col(w.f, maxW, c.ghost); col(w.e, maxW, c.violet)
                            }.frame(height: 100, alignment: .bottom)
                            Text(w.future ? "dự kiến" : "tuần \(k + 1)").font(.omniBody(9.5, weight: 600)).foregroundStyle(c.muted)
                        }.opacity(w.future ? 0.55 : 1).frame(maxWidth: .infinity)
                    }
                }
            }.labCard(c)
            Text("Ba quy tắc của Extra").font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
            VStack(alignment: .leading, spacing: 8) {
                rule("Ôn bù", Color(hex: 0xc24a28), "M dưới 60, M tụt từ 20 điểm, hoặc sai lần đầu ở 2 dạng bài trở lên. Ôn lại ngay hôm sau, giữ nguyên bậc.")
                rule("Nhảy cấp", Color(hex: 0x24804f), "M từ 85 trở lên và không tụt quá 5 điểm. Bỏ qua 1 bậc trên thang 1, 3, 7, 15, 30, 60 ngày.")
                rule("Lên 1 bậc", Color(hex: 0x2f5bb0), "Các trường hợp còn lại, giống lịch cố định.")
            }.labCard(c)
        }
        .sheet(isPresented: $showUpgrade) { ExtraordinaryUpgradeSheet(interfaceModeRaw: $interfaceModeRaw) }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c.ghost).frame(width: 12, height: 12); Text("Lịch cố định") }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(c.violet).frame(width: 12, height: 12); Text("Lịch Extra") }
        }.font(.omniBody(11.5, weight: 600)).foregroundStyle(c.muted)
    }
    private func stat(_ v: String, _ l: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.omniDisplay(22)).foregroundStyle(color); Text(l).font(.omniBody(11, weight: 600)).foregroundStyle(c.muted).lineLimit(2) }
            .labCard(c, radius: 14)
    }
    private func bar(_ f: Double, _ color: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            GeometryReader { g in Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(f))) }.frame(height: 10)
            Text(label).font(.omniBody(11, weight: 700)).foregroundStyle(c.muted).frame(width: 30, alignment: .trailing)
        }
    }
    private func col(_ v: Int, _ maxV: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(v)").font(.omniBody(9, weight: 700)).foregroundStyle(c.muted)
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: max(2, 84 * CGFloat(v) / CGFloat(maxV)))
        }
    }
    private func rule(_ t: String, _ color: Color, _ d: String) -> some View {
        (Text(t + ": ").font(.omniBody(13, weight: 800)).foregroundColor(color) + Text(d).font(.omniBody(13, weight: 500)).foregroundColor(c.text))
    }
}

// MARK: - Bộ từ

private struct LabDeckTab: View {
    @ObservedObject var game: IslandGame
    let c: LabColors
    let open: (String) -> Void
    let add: () -> Void
    @State private var query = ""
    @AppStorage("lab_deck_filter") private var filter = "all"

    var body: some View {
        let now = Date(), q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = Vocabulary.sortedItems(game.vocabs).filter { v in
            (q.isEmpty || (v.vocab ?? "").lowercased().contains(q) || (v.V_meaning ?? "").lowercased().contains(q)) &&
            (filter == "all" || (filter == "due" && (v.learning_level ?? 0) >= 1 && ReviewScheduler.isDue(v, now: now))
             || (filter == "solid" && (v.id.flatMap { game.profiles[$0]?.lastMastery } ?? 0) >= 85) || (filter == "new" && (v.learning_level ?? 0) == 0))
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                NavigationLink(value: LabRoute.folders) {
                    Label("Thư mục & chủ đề", systemImage: "folder.fill").font(.omniBody(13.5, weight: 700)).foregroundStyle(c.text).frame(maxWidth: .infinity).labCard(c, radius: 14)
                }.buttonStyle(.plain)
                Button(action: add) {
                    Label("Thêm từ", systemImage: "plus").font(.omniBody(13.5, weight: 700)).foregroundStyle(.white).frame(maxWidth: .infinity)
                        .padding(12).background(Color(hex: 0x34b45a), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            TextField("Tìm từ hoặc nghĩa", text: $query).font(.omniBody(15, weight: 500)).padding(12)
                .background(c.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line))
            Picker("Lọc", selection: $filter) { Text("Tất cả").tag("all"); Text("Cần ôn").tag("due"); Text("Đã vững").tag("solid"); Text("Mới").tag("new") }.pickerStyle(.segmented)
            if list.isEmpty { Text("Không có từ nào khớp.").font(.omniBody(13, weight: 500)).foregroundStyle(c.muted) }
            LazyVStack(spacing: 10) {
                ForEach(list, id: \.vocabularyIdentity) { v in
                    Button { if let id = v.id { open(id) } } label: { WordCardView(vocab: v, mastery: v.id.flatMap { game.profiles[$0]?.lastMastery }, mode: .summary) }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct WordListSheet: View {
    let title: String, note: String, words: [Vocabulary]
    let open: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).font(.omniBody(20, weight: 800)); Spacer(); Button("Đóng") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain)) }
            if !note.isEmpty { Text(note).font(.omniBody(13, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)) }
            Text("\(words.count) từ. Chạm một từ để xem thẻ.").font(.omniBody(13, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            ScrollView {
                FlowLayout(spacing: 6) {
                    ForEach(words, id: \.vocabularyIdentity) { v in
                        Button { if let id = v.id { open(id) } } label: {
                            HStack(spacing: 5) {
                                Circle().fill(Color(hex: CEFRColors[v.CEFR?.uppercased() ?? ""] ?? 0x9aa2b2)).frame(width: 8, height: 8)
                                Text(v.vocab ?? "").font(.omniBody(13.5, weight: 700))
                                Text((v.learning_level ?? 0) > 0 ? "★\(v.learning_level ?? 0)" : "mới").font(.omniBody(11, weight: 600)).foregroundStyle(Color(hex: 0x5b6779))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6).background(.white, in: Capsule()).overlay(Capsule().stroke(Color(hex: 0xe3e9f2)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20).foregroundStyle(Color(hex: 0x17202e)).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
    }
}

// MARK: - One word

struct WordLabDetail: View {
    @ObservedObject var game: IslandGame
    let vocab: Vocabulary
    let history: [WordMasteryHistory]
    fileprivate let c: LabColors
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var profile: WordSkillProfile { vocab.id.flatMap { game.profiles[$0] } ?? .empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button { dismiss() } label: { Label("Bộ từ", systemImage: "chevron.left").font(.omniBody(15, weight: 700)).foregroundStyle(Color(hex: 0x2f6fd6)) }
                WordCardView(vocab: vocab, mastery: profile.lastMastery, mode: .full).frame(width: 300).frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Button("Nghe") { SpeechManager.shared.speak(word: vocab.vocab ?? "", ipa: vocab.IPA, rateMultiplier: 1) }.buttonStyle(IslandButtonStyle(kind: .plain))
                    if (vocab.learning_level ?? 0) >= 0 && ReviewScheduler.isDue(vocab, now: Date()) {
                        Button("Ôn ngay") { game.showLab = false; game.review([vocab]) }.buttonStyle(IslandButtonStyle(kind: .red))
                    }
                    Button("Tìm trên đảo") { if let id = vocab.id { game.findResident(id) } }.buttonStyle(IslandButtonStyle(kind: .plain))
                    Button("Sửa") { editing = true }.buttonStyle(IslandButtonStyle(kind: .plain))
                }.frame(maxWidth: .infinity)
                extras
                Text("Việc học từ này").font(.omniBody(16, weight: 800)).foregroundStyle(c.text)
                sub("So sánh hai lịch ôn"); lanes.labCard(c)
                sub("Điểm M qua các lần ôn")
                Group { if history.compactMap(\.mastery).isEmpty { Text("Chưa có lượt ôn nào có điểm M.").font(.omniBody(12.5, weight: 500)).foregroundStyle(c.muted) } else { masteryChart } }.labCard(c)
                sub("Hồ sơ kỹ năng")
                radar.frame(height: 210).labCard(c)
                if let weak = LearningSkill.allCases.min(by: { (profile.skills[$0] ?? 100) < (profile.skills[$1] ?? 100) }), let v = profile.skills[weak], v < 80 {
                    Text("Extra ưu tiên dạng bài cho kỹ năng \(weak.title.lowercased()) vì đây là kỹ năng yếu nhất của từ này.").font(.omniBody(12, weight: 500)).foregroundStyle(c.muted)
                }
                sub("Nhật ký học"); log.labCard(c)
            }
            .padding(16)
        }
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editing) { AddVocabView(existing: vocab) { Task { await game.load() } } }
    }

    private func sub(_ t: String) -> some View { Text(t.uppercased()).font(.omniBody(12.5, weight: 800)).tracking(0.6).foregroundStyle(c.muted) }

    @ViewBuilder private var extras: some View {
        let fields: [(String, String?)] = [("Họ từ", vocab.word_family), ("Từ đồng nghĩa", vocab.synonymous), ("Từ trái nghĩa", vocab.antonym), ("Cụm từ đi kèm", vocab.collocation), ("Cấu trúc", vocab.formula), ("Ghi chú", vocab.note), ("Mở rộng", vocab.bonus)]
        let present = fields.compactMap { k, v -> (String, String)? in guard let v = v?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }; return (k, v) }
        if !present.isEmpty {
            Text("Thông tin bổ sung").font(.omniBody(16, weight: 800)).foregroundStyle(c.text)
            ForEach(present, id: \.0) { k, v in
                VStack(alignment: .leading, spacing: 6) {
                    Text(k).font(.omniBody(13, weight: 800)).foregroundStyle(c.text)
                    if k == "Ghi chú" || k == "Mở rộng" { Text(v).font(.omniBody(13, weight: 500)).foregroundStyle(c.muted) }
                    else { FlowLayout(spacing: 5) { ForEach(v.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, id: \.self) { s in
                        Text(s).font(.omniBody(12, weight: 600)).foregroundStyle(c.text).padding(.horizontal, 9).padding(.vertical, 3).background(c.bg, in: Capsule()).overlay(Capsule().stroke(c.line)) } } }
                }.labCard(c)
            }
        }
    }

    private var dates: (start: Date, fixed: [Date], reviews: [(Date, String)], next: Date?) {
        let cal = Calendar.current
        let reviews = history.compactMap { h -> (Date, String)? in h.created_at.flatMap(ReviewDates.parse).map { ($0, h.decision ?? "advance") } }
        let start = cal.startOfDay(for: reviews.first?.0 ?? vocab.saved_at.flatMap(ReviewDates.parse) ?? Date())
        var fixed: [Date] = []; var t = start
        for gap in [1, 3, 7, 15, 30, 60] { t = cal.date(byAdding: .day, value: gap, to: t)!; fixed.append(t) }
        return (start, fixed, reviews, vocab.next_review.flatMap(ReviewDates.parse))
    }

    private var lanes: some View {
        let d = dates, cal = Calendar.current, now = Date()
        let end = max(cal.date(byAdding: .day, value: 20, to: now)!, d.next ?? now)
        let span = max(1, end.timeIntervalSince(d.start))
        return Canvas { ctx, size in
            let x = { (date: Date) -> CGFloat in 10 + CGFloat(date.timeIntervalSince(d.start) / span) * (size.width - 20) }
            ctx.draw(Text("Lịch cố định").font(.omniBody(10, weight: 600)).foregroundColor(c.muted), at: CGPoint(x: 10, y: 8), anchor: .leading)
            ctx.draw(Text("Lịch thật của bạn").font(.omniBody(10, weight: 600)).foregroundColor(c.muted), at: CGPoint(x: 10, y: 52), anchor: .leading)
            for y in [26.0, 70.0] { var p = Path(); p.move(to: CGPoint(x: 10, y: y)); p.addLine(to: CGPoint(x: size.width - 10, y: y)); ctx.stroke(p, with: .color(c.line), lineWidth: 1) }
            let tx = x(now); var tl = Path(); tl.move(to: CGPoint(x: tx, y: 16)); tl.addLine(to: CGPoint(x: tx, y: 80))
            ctx.stroke(tl, with: .color(Color(hex: 0xe0603a)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            ctx.draw(Text("hôm nay").font(.omniBody(9, weight: 600)).foregroundColor(c.muted), at: CGPoint(x: tx + 3, y: 88), anchor: .leading)
            for f in d.fixed where f <= end { ctx.stroke(Path(ellipseIn: CGRect(x: x(f) - 5, y: 21, width: 10, height: 10)), with: .color(c.muted), lineWidth: 1.5) }
            for (r, decision) in d.reviews {
                let color = decision == "hold" ? Color(hex: 0xe0603a) : decision == "jump" ? Color(hex: 0x2f9e6a) : Color(hex: 0x3f6fca)
                ctx.fill(Path(ellipseIn: CGRect(x: x(r) - 5.5, y: 64.5, width: 11, height: 11)), with: .color(color))
            }
            if let n = d.next, n <= end { ctx.fill(Path(ellipseIn: CGRect(x: x(n) - 5.5, y: 64.5, width: 11, height: 11)), with: .color(c.violet.opacity(0.45))) }
        }
        .frame(height: 96)
    }

    private var masteryChart: some View {
        let pts = history.compactMap(\.mastery)
        return Canvas { ctx, size in
            let y = { (m: Int) -> CGFloat in size.height - 14 - CGFloat(m) / 100 * (size.height - 24) }
            let x = { (k: Int) -> CGFloat in 26 + CGFloat(k) * ((size.width - 40) / CGFloat(max(1, pts.count - 1))) }
            for (v, col) in [(60, Color(hex: 0xe0603a)), (85, Color(hex: 0x2f9e4f))] {
                var p = Path(); p.move(to: CGPoint(x: 22, y: y(v))); p.addLine(to: CGPoint(x: size.width, y: y(v)))
                ctx.stroke(p, with: .color(col.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ctx.draw(Text("\(v)").font(.omniBody(9, weight: 600)).foregroundColor(c.muted), at: CGPoint(x: 18, y: y(v)), anchor: .trailing)
            }
            var line = Path()
            for (k, m) in pts.enumerated() { let p = CGPoint(x: pts.count == 1 ? size.width / 2 : x(k), y: y(m)); if k == 0 { line.move(to: p) } else { line.addLine(to: p) } }
            ctx.stroke(line, with: .color(c.violet), lineWidth: 2)
            for (k, m) in pts.enumerated() { let p = CGPoint(x: pts.count == 1 ? size.width / 2 : x(k), y: y(m)); ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(m < 60 ? Color(hex: 0xe0603a) : m >= 85 ? Color(hex: 0x2f9e4f) : Color(hex: 0x3f6fca))) }
        }
        .frame(height: 120)
    }

    private var radar: some View {
        let skills = LearningSkill.allCases, vals = skills.map { profile.skills[$0] ?? 0 }
        return Canvas { ctx, size in
            let cx = Double(size.width / 2), cy = Double(size.height / 2 + 4), R0 = Double(min(size.width, size.height) / 2 - 34), n = Double(skills.count)
            func pt(_ k: Int, _ r: Double) -> CGPoint { CGPoint(x: cx + sin(Double(k) / n * .pi * 2) * r, y: cy - cos(Double(k) / n * .pi * 2) * r) }
            for v in [0.25, 0.5, 0.75, 1.0] { var p = Path(); for k in 0..<skills.count { let q = pt(k, R0 * v); if k == 0 { p.move(to: q) } else { p.addLine(to: q) } }; p.closeSubpath(); ctx.stroke(p, with: .color(c.line), lineWidth: 1) }
            var poly = Path(); for k in 0..<skills.count { let q = pt(k, R0 * vals[k] / 100); if k == 0 { poly.move(to: q) } else { poly.addLine(to: q) } }; poly.closeSubpath()
            ctx.fill(poly, with: .color(c.violet.opacity(0.28))); ctx.stroke(poly, with: .color(c.violet), lineWidth: 2)
            for (k, s) in skills.enumerated() {
                let l = pt(k, R0 + 16), v = Int(vals[k].rounded())
                ctx.draw(Text("\(s.title) · \(v)").font(.omniBody(10, weight: 700)).foregroundColor(v == 0 ? c.muted : v < 60 ? Color(hex: 0xd8453b) : v < 85 ? Color(hex: 0xe89a2a) : Color(hex: 0x2f9e4f)),
                         at: l, anchor: l.x < cx - 5 ? .trailing : l.x > cx + 5 ? .leading : .center)
            }
        }
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 8) {
            let saved = vocab.saved_at.flatMap(ReviewDates.parse)
            row(color: 0x2a2440, date: saved, title: "Lưu từ vào bộ từ", detail: "Thẻ cư dân được tạo")
            ForEach(history) { h in
                let d = h.decision ?? ""
                row(color: d == "hold" ? 0xe0603a : d == "jump" ? 0x2f9e6a : 0x3f6fca, date: h.created_at.flatMap(ReviewDates.parse),
                    title: d == "hold" ? "Ôn bù, hẹn lại sớm" : d == "jump" ? "Nhảy cấp" : "Lên 1 bậc",
                    detail: "M = \(h.mastery.map(String.init) ?? "--")" + (h.stored_level.map { " · \(LearningLevelDisplay.title(for: $0))" } ?? ""))
            }
            if let n = vocab.next_review.flatMap(ReviewDates.parse) {
                row(color: 0x8f6bff, date: n, title: n <= Date() ? "Tới lượt ôn" : "Lượt ôn dự kiến", detail: "Điểm M lúc đó sẽ quyết định bước tiếp").opacity(0.75)
            }
        }
    }
    private func row(color: UInt32, date: Date?, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color(hex: color)).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text((date.map { $0.formatted(.dateTime.day().month(.defaultDigits).year()) } ?? "—") + " · " + title).font(.omniBody(13, weight: 700)).foregroundStyle(c.text)
                Text(detail).font(.omniBody(11.5, weight: 500)).foregroundStyle(c.muted)
            }
        }
    }
}
