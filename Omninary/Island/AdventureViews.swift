import SwiftUI

// Phiêu lưu: pick a region, follow the stage path, choose the words, then play the stage on the map.

struct AdventurePage: View {
    @ObservedObject var game: IslandGame
    @Environment(\.dismiss) private var dismiss
    @AppStorage("adventure_last_region") private var lastRegion = "forest"
    @State private var thumbs: [String: CGImage] = [:]
    @State private var picking: PickRequest?

    struct PickRequest: Identifiable { let region: AdventureRegion; let index: Int; var id: String { "\(region.key)-\(index)" } }

    private var current: AdventureRegion { AdventureRegion.all.first { $0.key == lastRegion } ?? AdventureRegion.all[0] }
    private var night: Bool { game.night }
    private var pageBG: Color { night ? Color(hex: 0x10142a) : Color(hex: 0xeef3fb) }
    private var cardBG: Color { night ? Color(hex: 0x1b2140) : .white }
    private var line: Color { night ? Color(hex: 0x2b3457) : Color(hex: 0xe3e9f2) }
    private var text: Color { night ? Color(hex: 0xeef1fb) : Color(hex: 0x17202e) }
    private var muted: Color { night ? Color(hex: 0xa6afc8) : Color(hex: 0x5b6779) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(text).frame(width: 42, height: 42).background(cardBG, in: RoundedRectangle(cornerRadius: 14)) }
                    .accessibilityLabel("Về đảo nhà")
                Text("Phiêu lưu").font(.omniBody(24, weight: 800)).foregroundStyle(text)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            ScrollView {
                VStack(spacing: 14) {
                    regionTabs
                    regionCard
                    stagePath
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .background(pageBG.ignoresSafeArea())
        .sheet(item: $picking) { req in
            WordPickSheet(game: game, region: req.region, index: req.index) { words in
                picking = nil
                dismiss()
                Task { await game.enterStage(req.region, req.index, words: words) }
            }
            .presentationDetents([.large])
        }
        .task(id: lastRegion) { await loadThumb(current) }
        .environment(\.colorScheme, night ? .dark : .light)
    }

    private var regionTabs: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(AdventureRegion.all) { r in
                let open = game.isOpen(r), on = r.key == current.key
                Button { lastRegion = r.key } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.omniBody(14, weight: 800)).foregroundStyle(on ? .white : text)
                        Text(open ? "\(game.progress(r))/15 màn" : "Cần \(r.need) từ").font(.omniBody(11.5, weight: 600)).foregroundStyle(on ? .white.opacity(0.85) : muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    .background(on ? Color(hex: 0x34b45a) : cardBG, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? .clear : line))
                    .opacity(open ? 1 : 0.6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var regionCard: some View {
        let r = current, open = game.isOpen(r), done = game.progress(r)
        return HStack(spacing: 12) {
            Group {
                if let img = thumbs[r.key], open { Image(decorative: img, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fill) }
                else { Color(hex: 0x2b66ae).overlay(Image(systemName: "lock.fill").font(.title2).foregroundStyle(.white.opacity(0.7))) }
            }
            .frame(width: 92, height: 110).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 6) {
                Text(r.name).font(.omniBody(18, weight: 800)).foregroundStyle(text)
                Text(open ? "Đã qua \(done)/15 màn · màn tiếp theo: \(r.stages[min(14, done)])" : "Mở khi học \(r.need) từ (đang có \(game.learnedCount))")
                    .font(.omniBody(12.5, weight: 500)).foregroundStyle(muted)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(line)
                        Capsule().fill(Color(hex: 0xf0b429)).frame(width: g.size.width * CGFloat(done) / 15)
                    }
                }.frame(height: 8)
            }
        }
        .padding(12).background(cardBG, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(line))
    }

    private var stagePath: some View {
        let r = current, open = game.isOpen(r), done = game.progress(r)
        let xs: [CGFloat] = [0.18, 0.5, 0.82, 0.5], step: CGFloat = 92
        return GeometryReader { g in
            let w = g.size.width
            let pts = (0..<15).map { CGPoint(x: w * xs[$0 % 4], y: 40 + CGFloat($0) * step) }
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for k in 0..<14 {
                        let a = pts[k], b = pts[k + 1], my = (a.y + b.y) / 2
                        var p = Path(); p.move(to: a); p.addCurve(to: b, control1: CGPoint(x: a.x, y: my), control2: CGPoint(x: b.x, y: my))
                        let walked = open && k < done
                        ctx.stroke(p, with: .color(walked ? Color(hex: 0xf0b429) : (night ? Color(hex: 0x3a4472) : Color(hex: 0xc9d2df))),
                                   style: StrokeStyle(lineWidth: walked ? 7 : 5, lineCap: .round, dash: walked ? [] : [2, 11]))
                    }
                }
                ForEach(0..<15, id: \.self) { i in
                    let state = !open ? 2 : i < done ? 0 : i == done ? 1 : 2
                    Button { picking = PickRequest(region: r, index: i) } label: {
                        VStack(spacing: 4) {
                            Text(state == 0 ? "★" : "\(i + 1)").font(.omniDisplay(22)).foregroundStyle(state == 2 ? muted : .white)
                                .frame(width: 58, height: 58)
                                .background(state == 0 ? Color(hex: 0xf0b429) : state == 1 ? Color(hex: 0x34b45a) : (night ? Color(hex: 0x252c52) : Color(hex: 0xdfe5ee)), in: Circle())
                                .overlay(Circle().stroke(state == 1 ? .white : .clear, lineWidth: 4))
                                .shadow(color: state == 1 ? Color(hex: 0x34b45a).opacity(0.6) : .clear, radius: 10)
                            Text(r.stages[i]).font(.omniBody(11.5, weight: 700)).foregroundStyle(state == 2 ? muted : text).lineLimit(1).fixedSize()
                                .padding(.horizontal, 8).padding(.vertical, 3).background(cardBG.opacity(0.9), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain).disabled(state == 2)
                    .position(x: pts[i].x, y: pts[i].y + 14)
                }
            }
        }
        .frame(height: 40 + 14 * step + 70)
    }

    private func loadThumb(_ r: AdventureRegion) async {
        guard thumbs[r.key] == nil, game.isOpen(r) else { return }
        let idx = min(14, game.progress(r))
        let img = await Task.detached(priority: .userInitiated) { IslandPaint.still(r.map(idx)).makeImage() }.value
        if let img { thumbs[r.key] = img }
    }
}

struct WordPickSheet: View {
    @ObservedObject var game: IslandGame
    let region: AdventureRegion
    let index: Int
    let start: ([Vocabulary]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @ObservedObject private var hearts = OmniLearningHeartManager.shared

    // Worked out once when the sheet opens; recomputing them on every redraw made the sheet slow to appear.
    @State private var candidates: [ReviewCandidate] = []
    @State private var due: [ReviewCandidate] = []
    @State private var fresh: [ReviewCandidate] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(region.name) · Màn \(index + 1)").font(.omniBody(20, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
                Spacer()
                Button("Đóng") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain))
            }
            Text("\(region.stages[index]). Chọn từ để rải vào nhiệm vụ của màn. Mỗi từ gặp đủ các dạng bài; Extra tự thêm câu cho kỹ năng yếu.")
                .font(.omniBody(13.5, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if candidates.isEmpty {
                        Text("Hôm nay chưa có từ nào tới hạn hoặc từ mới để học. Lưu thêm từ ở Khám phá hoặc quay lại khi có từ tới hạn.")
                            .font(.omniBody(13.5, weight: 600)).foregroundStyle(Color(hex: 0x5b6779)).padding(.vertical, 8)
                    }
                    if !due.isEmpty { section("Từ cần ôn", due) }
                    if !fresh.isEmpty { section("Từ mới", fresh) }
                }
            }
            if !hearts.canStudy { Text("Bạn đã hết lượt học hôm nay.").font(.omniBody(13, weight: 700)).foregroundStyle(Color(hex: 0xe8463f)) }
            Button { start(candidates.filter { selected.contains($0.id) }.map(\.vocabulary)) } label: { Text("Vào màn · \(selected.count) từ").frame(maxWidth: .infinity) }
                .buttonStyle(IslandButtonStyle(kind: .primary)).disabled(selected.isEmpty || !hearts.canStudy || game.busy)
        }
        .padding(20).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
        .onAppear {
            guard candidates.isEmpty else { return }
            candidates = ReviewPriority.candidates(from: game.vocabs, profiles: game.profiles, now: Date())
            due = candidates.filter { !$0.isNew }
            fresh = candidates.filter { $0.isNew }
            selected = Set(due.prefix(6).map(\.id) + fresh.prefix(2).map(\.id))
        }
    }

    private func section(_ title: String, _ list: [ReviewCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.omniBody(12, weight: 800)).tracking(0.6).foregroundStyle(Color(hex: 0x5b6779))
            FlowLayout(spacing: 6) {
                ForEach(list) { c in
                    let on = selected.contains(c.id)
                    Button { if on { selected.remove(c.id) } else { selected.insert(c.id) } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: CEFRColors[c.vocabulary.CEFR?.uppercased() ?? ""] ?? 0x9aa2b2)).frame(width: 9, height: 9)
                            Text(c.vocabulary.vocab ?? "").font(.omniBody(14, weight: 700)).foregroundStyle(on ? .white : Color(hex: 0x17202e))
                            Text(c.isNew ? "từ mới" : c.overdueDays > 0 ? "quá hạn" : "tới hạn").font(.omniBody(11, weight: 600)).foregroundStyle(on ? .white.opacity(0.85) : Color(hex: 0x5b6779))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(on ? Color(hex: 0x2f6fd6) : .white, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : Color(hex: 0xe3e9f2)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
