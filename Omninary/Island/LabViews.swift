import SwiftUI

// Nhà nghiên cứu (the fixed schedule, and what Extra does with it) and Khám phá (the deck of word cards and
// the ways to add words). One screen; the stored tab decides which of the two it is.

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
    @State private var showCode = false
    @State private var revealed: Vocabulary?
    @StateObject private var explore = OmniExploreStore()

    private var c: LabColors { LabColors(night: game.night) }
    private var exploring: Bool { tab == "deck" || tab == "add" }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(c.text).frame(width: 42, height: 42).background(c.card, in: RoundedRectangle(cornerRadius: 14)) }
                        .accessibilityLabel(exploring ? "Rời Khám phá" : "Rời Nhà nghiên cứu")
                    Text(exploring ? "Khám phá" : "Nhà nghiên cứu").font(.omniBody(24, weight: 800)).foregroundStyle(c.text)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                Picker("Mục", selection: $tab) {
                    if exploring { Text("Bộ từ").tag("deck"); Text("Thêm từ").tag("add") }
                    else { Text("Ditandnary").tag("prog"); Text("Extraordinary").tag("opt") }
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case "opt": LabExtraTab(game: game, history: history, c: c, list: { listSheet = $0 }, open: { path.append($0) })
                        case "deck": LabDeckTab(game: game, c: c) { path.append($0) }
                        case "add": LabAddTab(store: explore, c: c, openCode: { showCode = true }, addOwn: { showAdd = true })
                        default: LabDitanTab(game: game, history: history, c: c, list: { listSheet = $0 }, showExtra: { tab = "opt" })
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
        .sheet(isPresented: $showCode) {
            OmniCardCodeSheet { vocab in
                showCode = false
                // let the sheet slide away before the stage takes the screen
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { revealed = vocab }
            }
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: $revealed, onDismiss: { Task { await game.load() } }) { vocab in
            OmniCardRevealView(vocab: vocab, store: explore)
        }
        .alert("Thông báo", isPresented: $explore.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(explore.alertMessage)
        }
        // words downloaded from a set show up in the deck
        .onChange(of: tab) { _, new in if new == "deck" { Task { await game.load() } } }
        .task {
            if let id = game.labWord { tab = "deck"; path = [id] }
            if let uid = AuthManager.shared.currentUser?.id.uuidString { history = (try? await WordHistoryRepository.fetch(userId: uid)) ?? [] }
        }
        .environment(\.colorScheme, game.night ? .dark : .light)
    }
}

enum LabRoute: Hashable { case folders, oldReview }

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

// MARK: - Shared charts

private typealias LabList = (title: String, note: String, words: [Vocabulary])

private let labDayFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM"; return f }()
/// "02/11", whatever the device locale.
private func labDay(_ d: Date) -> String { labDayFormatter.string(from: d) }

private func labHeading(_ t: String, _ c: LabColors) -> some View { Text(t).font(.omniBody(16, weight: 800)).foregroundStyle(c.text) }

/// Every saved word by level: Mới, Cấp 1–5, Master, Super. A bar opens its words.
private struct LabLevelBars: View {
    @ObservedObject var game: IslandGame
    let c: LabColors
    let list: (LabList) -> Void

    var body: some View {
        let byLevel = (0...7).map { b in Vocabulary.sortedItems(game.vocabs).filter { LearningLevelDisplay.bucket(for: $0.learning_level ?? 0) == b } }
        let maxL = max(1, byLevel.map(\.count).max() ?? 1)
        VStack(spacing: 6) {
            ForEach(0...7, id: \.self) { b in
                let title = b == 0 ? "Mới" : LearningLevelDisplay.title(for: b == 7 ? 10 : b)
                Button { list((b == 0 ? "Từ mới" : title, "", byLevel[b])) } label: {
                    HStack(spacing: 8) {
                        Text(title).font(.omniBody(12.5, weight: 700)).foregroundStyle(c.muted).frame(width: 56, alignment: .leading)
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
    }
}

/// Five skills on five axes, 0–100, each label coloured by how strong it is.
private struct LabRadar: View {
    let values: [Double]
    let c: LabColors

    var body: some View {
        let skills = LearningSkill.allCases
        Canvas { ctx, size in
            let cx = Double(size.width / 2), cy = Double(size.height / 2 + 4), R0 = Double(min(size.width, size.height) / 2 - 34), n = Double(skills.count)
            func pt(_ k: Int, _ r: Double) -> CGPoint { CGPoint(x: cx + sin(Double(k) / n * .pi * 2) * r, y: cy - cos(Double(k) / n * .pi * 2) * r) }
            for v in [0.25, 0.5, 0.75, 1.0] { var p = Path(); for k in 0..<skills.count { let q = pt(k, R0 * v); if k == 0 { p.move(to: q) } else { p.addLine(to: q) } }; p.closeSubpath(); ctx.stroke(p, with: .color(c.line), lineWidth: 1) }
            var poly = Path(); for k in 0..<skills.count { let q = pt(k, R0 * values[k] / 100); if k == 0 { poly.move(to: q) } else { poly.addLine(to: q) } }; poly.closeSubpath()
            ctx.fill(poly, with: .color(c.violet.opacity(0.28))); ctx.stroke(poly, with: .color(c.violet), lineWidth: 2)
            for (k, s) in skills.enumerated() {
                let l = pt(k, R0 + 16), v = Int(values[k].rounded())
                ctx.draw(Text("\(s.title) · \(v)").font(.omniBody(10, weight: 700)).foregroundColor(v == 0 ? c.muted : v < 60 ? Color(hex: 0xd8453b) : v < 85 ? Color(hex: 0xe89a2a) : Color(hex: 0x2f9e4f)),
                         at: l, anchor: l.x < cx - 5 ? .trailing : l.x > cx + 5 ? .leading : .center)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(skills.enumerated().map { "\($1.title) \(Int(values[$0].rounded()))" }.joined(separator: ", "))
    }
}

/// The fixed 1-3-7-15-30-60… ladder run forward from a word's next review, ignoring how well it is known.
private enum FixedLadder {
    /// Day offsets from `today` (0 = today, overdue words included) on which `v` comes due within `days`.
    static func dueOffsets(_ v: Vocabulary, days: Int, today: Date) -> [Int] {
        guard let next = v.next_review.flatMap(ReviewDates.parse) else { return [] }
        let gaps = LabSimulation.ladder, cal = Calendar.current
        var d = max(0, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: next)).day ?? 0)
        var level = max(1, v.learning_level ?? 1)
        var out: [Int] = []
        while d < days { out.append(d); d += gaps[min(level, gaps.count - 1)]; level += 1 }
        return out
    }
}

// MARK: - Ditandnary

private struct LabDitanTab: View {
    @ObservedObject var game: IslandGame
    let history: [WordMasteryHistory]
    let c: LabColors
    let list: (LabList) -> Void
    let showExtra: () -> Void

    private static let days = 14
    private static let batchColors: [UInt32] = [0x2f6fd6, 0x8f6bff, 0xe0603a, 0x2f9e6a]
    private struct Batch { let day: Date; let count: Int; let cells: [Int] }

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date()), plan = plan(today: today)
        let top = max(1, plan.totals.max() ?? 1)
        VStack(alignment: .leading, spacing: 14) {
            labHeading("Số từ ở mỗi cấp", c)
            LabLevelBars(game: game, c: c, list: list)
            labHeading("Lịch ôn cố định theo đợt học", c)
            VStack(spacing: 8) {
                row(label: EmptyView()) { k in
                    Text(day(today, k).formatted(.dateTime.day(.twoDigits)))
                        .font(.omniBody(9, weight: 700)).foregroundStyle(k == 0 ? Color(hex: 0x2f6fd6) : c.muted)
                }
                if plan.batches.isEmpty {
                    Text("Chưa có từ nào trong lịch ôn.").font(.omniBody(12.5, weight: 500)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(plan.batches.enumerated()), id: \.offset) { i, b in
                    row(label: VStack(alignment: .leading, spacing: 0) {
                        Text("Đợt \(labDay(b.day))").font(.omniBody(11.5, weight: 800)).foregroundStyle(c.text)
                        Text("\(b.count) từ").font(.omniBody(10, weight: 600)).foregroundStyle(c.muted)
                    }) { k in
                        let n = b.cells[k]
                        Text(n > 0 ? "\(n)" : "").font(.omniBody(9.5, weight: 800)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(n > 0 ? Color(hex: Self.batchColors[i % Self.batchColors.count]) : c.ghost.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Rectangle().fill(c.line).frame(height: 1)
                row(label: Text("Từ đến hạn mỗi ngày").font(.omniBody(11, weight: 800)).foregroundStyle(c.text)) { k in
                    let n = plan.totals[k]
                    VStack(spacing: 2) {
                        Text(n > 0 ? "\(n)" : "").font(.omniBody(9, weight: 800)).foregroundStyle(c.muted).lineLimit(1).minimumScaleFactor(0.6)
                        RoundedRectangle(cornerRadius: 3).fill(n * 4 >= top * 3 ? Color(hex: 0xe0603a) : c.ghost)
                            .frame(height: max(3, 92 * CGFloat(n) / CGFloat(top)))
                    }
                    .frame(height: 112, alignment: .bottom)
                }
            }
            .labCard(c)
            if let note = insight(plan.totals, today) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(hex: 0xc2620f))
                    Text(note).font(.omniBody(13, weight: 600)).foregroundStyle(c.night ? Color(hex: 0xf6d2a8) : Color(hex: 0x6b3a07))
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(c.night ? Color(hex: 0x3a2a16) : Color(hex: 0xfff4e6), in: RoundedRectangle(cornerRadius: 14))
            }
            Button(action: showExtra) {
                Label("Xem Extra sắp xếp lại lịch này", systemImage: "sparkle").font(.omniBody(15, weight: 800)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(14).background(Color(hex: 0x2a2440), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    /// A label column, then one equal cell per day.
    private func row<L: View, C: View>(label: L, @ViewBuilder cell: @escaping (Int) -> C) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            label.frame(width: 74, alignment: .leading)
            ForEach(0..<Self.days, id: \.self) { k in cell(k).frame(maxWidth: .infinity) }
        }
    }

    private func day(_ today: Date, _ k: Int) -> Date { Calendar.current.date(byAdding: .day, value: k, to: today) ?? today }

    /// Words last studied on the same day are one batch; under the fixed ladder they keep coming due together.
    private func plan(today: Date) -> (batches: [Batch], totals: [Int]) {
        let cal = Calendar.current
        var last: [String: Date] = [:]
        for h in history { if let d = h.created_at.flatMap(ReviewDates.parse) { last[h.user_vocabulary_id] = max(last[h.user_vocabulary_id] ?? d, d) } }
        var totals = Array(repeating: 0, count: Self.days)
        var cells: [Date: [Int]] = [:], sizes: [Date: Int] = [:]
        for v in game.learnedVocabs where (v.learning_level ?? 0) < 10 {
            let due = FixedLadder.dueOffsets(v, days: Self.days, today: today)
            for d in due { totals[d] += 1 }
            guard let studied = v.id.flatMap({ last[$0] }) ?? v.saved_at.flatMap(ReviewDates.parse) else { continue }
            let key = cal.startOfDay(for: studied)
            var row = cells[key] ?? Array(repeating: 0, count: Self.days)
            for d in due { row[d] += 1 }
            cells[key] = row
            sizes[key, default: 0] += 1
        }
        let recent = cells.filter { $0.value.contains { $0 > 0 } }.keys.sorted(by: >).prefix(4).sorted()
        return (recent.map { Batch(day: $0, count: sizes[$0] ?? 0, cells: cells[$0] ?? []) }, totals)
    }

    private func insight(_ totals: [Int], _ today: Date) -> String? {
        guard let peak = totals.indices.max(by: { totals[$0] < totals[$1] }), totals[peak] > 1 else { return nil }
        let fmt: (Int) -> String = { labDay(day(today, $0)) }
        let head = "Từ học cùng đợt đến hạn cùng ngày, dù có từ đã vững và có từ sắp quên. Ngày \(fmt(peak)) bạn phải ôn \(totals[peak]) từ"
        if let empty = totals.firstIndex(of: 0) { return head + ", ngày \(fmt(empty)) không có từ nào." }
        let low = totals.indices.min(by: { totals[$0] < totals[$1] }) ?? 0
        return head + ", ngày \(fmt(low)) chỉ \(totals[low]) từ."
    }
}

// MARK: - Extraordinary

private struct LabExtraTab: View {
    @ObservedObject var game: IslandGame
    let history: [WordMasteryHistory]
    let c: LabColors
    let list: (LabList) -> Void
    let open: (String) -> Void
    @ObservedObject private var hearts = OmniLearningHeartManager.shared
    @State private var showUpgrade = false
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue

    private static let mBins: [(label: String, color: UInt32)] = [("<60", 0xe0603a), ("60–69", 0xf0a24a), ("70–79", 0xe0c04a), ("80–84", 0x9ccf6a), ("85–89", 0x4fb37a), ("90+", 0x2f9e6a)]
    private static func bin(_ m: Int) -> Int { m < 60 ? 0 : m < 70 ? 1 : m < 80 ? 2 : m < 85 ? 3 : m < 90 ? 4 : 5 }

    private struct Stats {
        var holds = Set<String>(), jumps = Set<String>(), jumpEvents = 0
        var mBins = Array(repeating: 0, count: 6)
        var skills = Array(repeating: 0.0, count: 5)
        var boosts: [LearningSkill: Int] = [:], boosted = 0
        var weekly: [(start: Date, m: Double)] = []
    }

    var body: some View {
        Group { if hearts.isExtra { content } else { locked } }
            .sheet(isPresented: $showUpgrade) { ExtraordinaryUpgradeSheet(interfaceModeRaw: $interfaceModeRaw) }
    }

    private var content: some View {
        let s = stats(), sim = LabSimulation(game.learnedVocabs)
        let pct = sim.nextF == 0 ? 0 : Int(((1 - Double(sim.nextE) / Double(sim.nextF)) * 100).rounded())
        let real = history.filter { $0.mode == "extraordinary" && ($0.decision == "hold" || $0.decision == "jump") }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                hero("\(pct >= 0 ? "−" : "+")\(abs(pct))%", "lượt ôn so với lịch cố định trong 30 ngày tới", Color(hex: 0x8fe0a6))
                hero("\(s.holds.count)", "từ được ôn bù trước khi kịp quên", Color(hex: 0xf2c94c))
            }
            labHeading("Số từ ở mỗi cấp", c)
            LabLevelBars(game: game, c: c, list: list)
            labHeading("Số từ theo điểm M", c)
            mChart(s.mBins)
            labHeading("Năm kỹ năng trung bình", c)
            LabRadar(values: s.skills, c: c).frame(height: 230).labCard(c)
            labHeading("Extra đã làm gì cho bạn", c)
            HStack(alignment: .top, spacing: 10) {
                did("Nhảy cấp", 0x2f9e6a, "\(s.jumps.count) từ", "bỏ bớt \(s.jumpEvents) lượt ôn thừa nhờ dời lịch xa hơn")
                did("Ôn bù", 0xe0603a, "\(s.holds.count) từ", "được gọi lại hôm sau thay vì chờ tới lịch cố định")
            }
            boostCard(s)
            labHeading("Số từ phải ôn mỗi ngày", c)
            loadCard(sim)
            if s.weekly.count >= 2 {
                labHeading("Điểm M trung bình theo tuần", c)
                weeklyCard(s.weekly)
            }
            if !real.isEmpty {
                labHeading("Những lần Extra ra tay gần đây", c)
                ForEach(real.suffix(4).reversed()) { h in
                    let v = game.vocabs.first { $0.id == h.user_vocabulary_id }
                    Button { if v != nil { open(h.user_vocabulary_id) } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(h.decision == "hold" ? "Ôn bù" : "Nhảy cấp").font(.omniBody(11, weight: 800)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2)
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
        }
    }

    // MARK: Locked for Ditandnary

    private var locked: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 14) {
                HStack(spacing: 10) { ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x2a2440)).frame(height: 96) } }
                VStack(spacing: 9) {
                    ForEach([0.92, 0.08, 0.1, 0.52, 0.24, 0.12], id: \.self) { w in
                        GeometryReader { g in Capsule().fill(c.violet).frame(width: g.size.width * w) }.frame(height: 10)
                    }
                }.labCard(c)
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array([0.3, 0.4, 0.65, 1, 0.58, 0.38].enumerated()), id: \.offset) { i, h in
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: Self.mBins[i].color)).frame(height: 118 * h)
                    }
                }.frame(height: 130, alignment: .bottom).labCard(c)
                LabRadar(values: [80, 72, 66, 76, 52], c: c).frame(height: 230).labCard(c)
            }
            .blur(radius: 6).opacity(0.5).accessibilityHidden(true)
            VStack(spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x2a2440))
                    .frame(width: 38, height: 38).background(.white, in: Circle()).overlay(Circle().stroke(Color(hex: 0x2a2440), lineWidth: 3))
                Text("Omni vẫn đang học dữ liệu học tập của bạn, hãy nâng cấp Extraordinary để những dữ liệu này tối ưu trải nghiệm học của bạn")
                    .font(.omniBody(13.5, weight: 700)).foregroundStyle(c.text)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Nâng cấp") { showUpgrade = true }
                    .buttonStyle(Quiz3DButtonStyle(tone: .amber, height: 42))
                    .frame(maxWidth: 180)
            }
            .padding(18)
            .background(c.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(c.line))
            .shadow(color: Color(red: 20 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18), radius: 15, y: 12)
            .padding(.horizontal, 20).padding(.top, 150)
        }
    }

    // MARK: Data

    private func stats() -> Stats {
        var s = Stats()
        for h in history where h.mode == "extraordinary" {
            if h.decision == "hold" { s.holds.insert(h.user_vocabulary_id) }
            if h.decision == "jump" { s.jumps.insert(h.user_vocabulary_id); s.jumpEvents += 1 }
        }
        var sums = Array(repeating: 0.0, count: 5), counts = Array(repeating: 0, count: 5)
        for v in game.learnedVocabs {
            guard let id = v.id, let p = game.profiles[id] else { continue }
            if let m = p.lastMastery { s.mBins[Self.bin(m)] += 1 }
            for (k, skill) in LearningSkill.allCases.enumerated() { if let x = p.skills[skill] { sums[k] += x; counts[k] += 1 } }
            let plan = ReinforcementPlanner.plan(for: p)
            if !plan.isEmpty { s.boosted += 1; for skill in Set(plan.map(\.skill)) { s.boosts[skill, default: 0] += 1 } }
        }
        s.skills = (0..<5).map { counts[$0] == 0 ? 0 : sums[$0] / Double(counts[$0]) }
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var byWeek: [Date: (sum: Int, n: Int)] = [:]
        for h in history {
            guard let m = h.mastery, let d = h.created_at.flatMap(ReviewDates.parse), let start = cal.dateInterval(of: .weekOfYear, for: d)?.start,
                  let ago = cal.dateComponents([.weekOfYear], from: start, to: thisWeek).weekOfYear, ago < 6 else { continue }
            byWeek[start, default: (0, 0)].sum += m
            byWeek[start, default: (0, 0)].n += 1
        }
        s.weekly = byWeek.keys.sorted().map { ($0, Double(byWeek[$0]!.sum) / Double(byWeek[$0]!.n)) }
        return s
    }

    // MARK: Pieces

    private func hero(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.omniDisplay(30)).foregroundStyle(color)
            Text(label).font(.omniBody(12, weight: 600)).foregroundStyle(Color(hex: 0xd6d1ef)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x2a2440), in: RoundedRectangle(cornerRadius: 18))
    }

    private func did(_ tag: String, _ color: UInt32, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tag).font(.omniBody(11, weight: 800)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 2).background(Color(hex: color), in: Capsule())
            Text(value).font(.omniDisplay(26)).foregroundStyle(c.text)
            Text(detail).font(.omniBody(12, weight: 600)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
        }
        .labCard(c, radius: 16).frame(maxHeight: .infinity)
    }

    private func mChart(_ bins: [Int]) -> some View {
        let top = max(1, bins.max() ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<bins.count, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text("\(bins[i])").font(.omniDisplay(13)).foregroundStyle(c.text)
                        RoundedRectangle(cornerRadius: 6).fill(Color(hex: Self.mBins[i].color)).frame(height: max(4, 96 * CGFloat(bins[i]) / CGFloat(top)))
                        Text(Self.mBins[i].label).font(.omniBody(10.5, weight: 700)).foregroundStyle(c.muted).lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150, alignment: .bottom)
            HStack(spacing: 14) {
                legend(0xe0603a, "Dưới 60 · ôn bù")
                legend(0x2f9e6a, "Từ 85 · nhảy cấp")
            }
        }
        .labCard(c)
    }

    private func legend(_ color: UInt32, _ text: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(Color(hex: color)).frame(width: 10, height: 10); Text(text) }
            .font(.omniBody(11.5, weight: 700)).foregroundStyle(c.muted)
    }

    private func boostCard(_ s: Stats) -> some View {
        let top = max(1, s.boosts.values.max() ?? 1)
        let order = LearningSkill.allCases.sorted { (s.boosts[$0] ?? 0) > (s.boosts[$1] ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Học tăng cường theo kỹ năng").font(.omniBody(14, weight: 800)).foregroundStyle(c.text)
                Spacer()
                Text("\(s.boosted) từ").font(.omniBody(12, weight: 700)).foregroundStyle(c.muted)
            }
            ForEach(order, id: \.self) { skill in
                let n = s.boosts[skill] ?? 0
                HStack(spacing: 8) {
                    Text(skill.title).font(.omniBody(12.5, weight: 700)).foregroundStyle(c.muted).lineLimit(1).minimumScaleFactor(0.8).frame(width: 110, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(c.violet.opacity(0.15)).overlay(alignment: .leading) {
                            Capsule().fill(c.violet).frame(width: g.size.width * CGFloat(n) / CGFloat(top))
                        }
                    }.frame(height: 10)
                    Text("\(n)").font(.omniDisplay(13)).foregroundStyle(c.text).frame(width: 26, alignment: .trailing)
                }
            }
        }
        .labCard(c)
    }

    private func loadCard(_ sim: LabSimulation) -> some View {
        let days = 14
        let fixed = (0..<days).map { k in sim.words.reduce(0) { $0 + $1.fixed.filter { $0 == sim.today + k }.count } }
        let extra = (0..<days).map { k in sim.words.reduce(0) { $0 + $1.extra.filter { $0.t == sim.today + k }.count } }
        let top = max(1, (fixed + extra).max() ?? 1)
        let today = Calendar.current.startOfDay(for: Date())
        return VStack(alignment: .leading, spacing: 8) {
            Text("Mô phỏng 14 ngày tới trên \(sim.words.count) từ của bạn").font(.omniBody(12, weight: 600)).foregroundStyle(c.muted)
            HStack(spacing: 14) { legend(0xd6dde8, "Lịch cố định"); legend(0x8f6bff, "Lịch Extra") }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<days, id: \.self) { k in
                    VStack(spacing: 3) {
                        HStack(alignment: .bottom, spacing: 1) {
                            RoundedRectangle(cornerRadius: 2).fill(c.ghost).frame(height: max(2, 120 * CGFloat(fixed[k]) / CGFloat(top)))
                            RoundedRectangle(cornerRadius: 2).fill(c.violet).frame(height: max(2, 120 * CGFloat(extra[k]) / CGFloat(top)))
                        }
                        Text((Calendar.current.date(byAdding: .day, value: k, to: today) ?? today).formatted(.dateTime.day(.twoDigits)))
                            .font(.omniBody(9, weight: 700)).foregroundStyle(c.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140, alignment: .bottom)
            HStack(spacing: 8) {
                pair("Ngày nặng nhất", "\(fixed.max() ?? 0) → \(extra.max() ?? 0) từ")
                pair("Tổng 14 ngày", "\(fixed.reduce(0, +)) → \(extra.reduce(0, +)) lượt")
            }
        }
        .labCard(c)
    }

    private func pair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.omniBody(11, weight: 700)).foregroundStyle(c.muted)
            Text(value).font(.omniBody(15, weight: 800)).foregroundStyle(c.text)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(c.ghost.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func weeklyCard(_ weeks: [(start: Date, m: Double)]) -> some View {
        Canvas { ctx, size in
            let left = 30.0, bottom = Double(size.height) - 20, topY = 10.0, w = Double(size.width) - left - 24
            func y(_ m: Double) -> Double { bottom - (max(40, min(100, m)) - 40) / 60 * (bottom - topY) }
            func x(_ k: Int) -> Double { left + (weeks.count == 1 ? w / 2 : w * Double(k) / Double(weeks.count - 1)) }
            for m in [50.0, 75, 100] {
                var p = Path(); p.move(to: CGPoint(x: left, y: y(m))); p.addLine(to: CGPoint(x: left + w, y: y(m)))
                ctx.stroke(p, with: .color(c.line), lineWidth: 1)
                ctx.draw(Text("\(Int(m))").font(.omniBody(9.5, weight: 700)).foregroundColor(c.muted), at: CGPoint(x: 2, y: y(m)), anchor: .leading)
            }
            var goal = Path(); goal.move(to: CGPoint(x: left, y: y(85))); goal.addLine(to: CGPoint(x: left + w, y: y(85)))
            ctx.stroke(goal, with: .color(Color(hex: 0x2f9e4f)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            var line = Path()
            for (k, wk) in weeks.enumerated() { let p = CGPoint(x: x(k), y: y(wk.m)); if k == 0 { line.move(to: p) } else { line.addLine(to: p) } }
            ctx.stroke(line, with: .color(c.violet), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            for (k, wk) in weeks.enumerated() {
                let p = CGPoint(x: x(k), y: y(wk.m))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(c.violet))
                ctx.draw(Text(labDay(wk.start)).font(.omniBody(9.5, weight: 700)).foregroundColor(c.muted),
                         at: CGPoint(x: p.x, y: bottom + 12))
            }
        }
        .frame(height: 140)
        .labCard(c)
        .accessibilityElement()
        .accessibilityLabel("Điểm M trung bình: " + weeks.map { String(Int($0.m.rounded())) }.joined(separator: ", "))
    }
}

// MARK: - Bộ từ

private struct LabDeckTab: View {
    @ObservedObject var game: IslandGame
    let c: LabColors
    let open: (String) -> Void
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
            NavigationLink(value: LabRoute.folders) {
                Label("Thư mục & chủ đề", systemImage: "folder.fill").font(.omniBody(13.5, weight: 700)).foregroundStyle(c.text).frame(maxWidth: .infinity).labCard(c, radius: 14)
            }.buttonStyle(.plain)
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

// MARK: - Thêm từ

private struct LabAddTab: View {
    @ObservedObject var store: OmniExploreStore
    let c: LabColors
    let openCode: () -> Void
    let addOwn: () -> Void

    var body: some View {
        let words = store.sets.reduce(0) { $0 + $1.words.count }
        VStack(spacing: 12) {
            OmniCardCodeButton(action: openCode)
                .accessibilityIdentifier("explore-card-code")
            NavigationLink {
                OmniWordSetsView(store: store)
            } label: {
                row("Khám phá bộ từ", store.sets.isEmpty ? "Bộ thẻ bài của Omninary" : "\(store.sets.count) bộ từ · \(words) thẻ và từ",
                    symbol: "rectangle.on.rectangle.angled", tint: 0x2F6FD6, tile: 0xE3EDFF)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("explore-vocabulary")
            Button(action: addOwn) {
                row("Tự thêm từ", "Nhập từ và nghĩa của bạn", symbol: "plus", tint: 0x2F9E4F, tile: 0xE2F5E7)
            }
            .buttonStyle(.plain)
        }
        .task { if store.sets.isEmpty { await store.load() } }
    }

    private func row(_ title: String, _ subtitle: String, symbol: String, tint: UInt32, tile: UInt32) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                .foregroundStyle(c.night ? Color(hex: tile) : Color(hex: tint))
                .frame(width: 56, height: 56)
                .background(c.night ? Color(hex: tint).opacity(0.35) : Color(hex: tile), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.omniBody(16, weight: 800)).foregroundStyle(c.text)
                Text(subtitle).font(.omniBody(12, weight: 500)).foregroundStyle(c.muted)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(c.muted)
        }
        .labCard(c)
        .contentShape(Rectangle())
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
    /// Opened from Explore: no back button or island actions; `owned` false hides editing and learning.
    var fromExplore = false
    var owned = true
    /// Explore's half-height popup: review status and extra details, without the learning section.
    var compact = false
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var profile: WordSkillProfile { vocab.id.flatMap { game.profiles[$0] } ?? .empty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !fromExplore {
                    Button { dismiss() } label: { Label("Bộ từ", systemImage: "chevron.left").font(.omniBody(15, weight: 700)).foregroundStyle(Color(hex: 0x2f6fd6)) }
                    WordCardView(vocab: vocab, mastery: profile.lastMastery, mode: .full).frame(width: 300).frame(maxWidth: .infinity)
                }
                // from Explore the card is already on the stage behind the popup
                if fromExplore && owned { reviewStatus }
                // from Explore the card itself reads aloud on tap, and the island actions do not apply
                if !fromExplore {
                    HStack(spacing: 8) {
                        Button("Nghe") { SpeechManager.shared.speak(word: vocab.vocab ?? "", ipa: vocab.IPA, rateMultiplier: 1) }.buttonStyle(IslandButtonStyle(kind: .plain))
                        if (vocab.learning_level ?? 0) >= 0 && ReviewScheduler.isDue(vocab, now: Date()) {
                            Button("Ôn ngay") { game.showLab = false; game.review([vocab]) }.buttonStyle(IslandButtonStyle(kind: .red))
                        }
                        Button("Sửa") { editing = true }.buttonStyle(IslandButtonStyle(kind: .plain))
                    }.frame(maxWidth: .infinity)
                }
                extras
                if owned && !compact { learning }
            }
            .padding(16)
        }
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editing) { AddVocabView(existing: vocab) { Task { await game.load() } } }
    }

    /// Review status under the card in Explore's popup, e.g. "Quá hạn 4 ngày".
    private var reviewStatus: some View {
        let (text, urgency) = WordCardStyle.status(vocab)
        let tint = urgency == 2 ? Color(hex: 0xd8453b) : urgency == 1 ? Color(hex: 0xe0603a) : c.muted
        return Label(text, systemImage: urgency > 0 ? "clock.badge.exclamationmark.fill" : "clock.fill")
            .font(.omniBody(14, weight: 800))
            .foregroundStyle(tint)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var learning: some View {
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

    private var radar: some View { LabRadar(values: LearningSkill.allCases.map { profile.skills[$0] ?? 0 }, c: c) }

    private var log: some View {
        VStack(alignment: .leading, spacing: 8) {
            let saved = vocab.saved_at.flatMap(ReviewDates.parse)
            row(color: 0x2a2440, date: saved, title: "Lưu từ vào bộ từ", detail: "Thẻ từ được tạo")
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

/// Nhà nghiên cứu's word page, opened from an Explore card when the learner swipes up.
struct ExploreWordDetail: View {
    let vocab: Vocabulary
    let profiles: [String: WordSkillProfile]
    let owned: Bool
    let night: Bool
    var compact = false
    @StateObject private var game = IslandGame()
    @State private var history: [WordMasteryHistory] = []

    var body: some View {
        WordLabDetail(game: game, vocab: vocab, history: history, c: LabColors(night: night), fromExplore: true, owned: owned, compact: compact)
            .task {
                game.profiles = profiles
                guard owned, let id = vocab.id, let userId = AuthManager.shared.currentUser?.id.uuidString else { return }
                history = (try? await WordHistoryRepository.fetch(userId: userId, userVocabularyId: id)) ?? []
            }
    }
}
