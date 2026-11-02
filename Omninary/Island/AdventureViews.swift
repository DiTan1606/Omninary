import SwiftUI

// Phiêu lưu word picker: swap the words of an adventure before it starts.

struct WordPickSheet: View {
    @ObservedObject var game: IslandGame
    let region: AdventureRegion
    let index: Int
    /// Adventure: pick exactly this many words.
    var limit: Int? = nil
    let start: ([Vocabulary]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @ObservedObject private var hearts = OmniLearningHeartManager.shared

    // Worked out once when the sheet opens; recomputing them on every redraw made the sheet slow to appear.
    @State private var candidates: [ReviewCandidate] = []
    @State private var due: [ReviewCandidate] = []
    @State private var fresh: [ReviewCandidate] = []
    private var p: QuizPalette { QuizPalette(dark: game.night) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(region.name) · Màn \(index + 1)").font(.omniBody(20, weight: 800)).foregroundStyle(p.text)
                Spacer()
                Button("Đóng") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain))
            }
            Text(limit.map { "Chọn \($0) từ cho lần phiêu lưu này. Mỗi từ gặp đủ 5 dạng bài." } ?? "\(region.stages[index]). Chọn từ để rải vào nhiệm vụ của màn. Mỗi từ gặp đủ các dạng bài; Extra tự thêm câu cho kỹ năng yếu.")
                .font(.omniBody(13.5, weight: 500)).foregroundStyle(p.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if candidates.isEmpty {
                        Text("Hôm nay chưa có từ nào tới hạn hoặc từ mới để học. Lưu thêm từ ở Khám phá hoặc quay lại khi có từ tới hạn.")
                            .font(.omniBody(13.5, weight: 600)).foregroundStyle(p.muted).padding(.vertical, 8)
                    }
                    if !due.isEmpty { section("Từ cần ôn", due) }
                    if !fresh.isEmpty { section("Từ mới", fresh) }
                }
            }
            if !hearts.canStudy { Text("Bạn đã hết lượt học hôm nay.").font(.omniBody(13, weight: 700)).foregroundStyle(Color(hex: 0xe8463f)) }
            Button { start(candidates.filter { selected.contains($0.id) }.map(\.vocabulary)) } label: { Text(limit == nil ? "Vào màn · \(selected.count) từ" : "Chọn \(selected.count)/\(limit ?? 0) từ").frame(maxWidth: .infinity) }
                .buttonStyle(IslandButtonStyle(kind: .primary))
                // a level takes its full count of words (fewer only when fewer can be picked)
                .disabled(selected.isEmpty || selected.count < min(limit ?? 0, candidates.count) || !hearts.canStudy || game.busy)
        }
        .padding(20).background(p.page).environment(\.colorScheme, game.night ? .dark : .light)
        .onAppear {
            guard candidates.isEmpty else { return }
            candidates = ReviewPriority.candidates(from: game.vocabs, profiles: game.profiles, now: Date())
            due = candidates.filter { !$0.isNew }
            fresh = candidates.filter { $0.isNew }
            selected = Set(limit.map { Array((due + fresh).prefix($0)).map(\.id) } ?? (due.prefix(6).map(\.id) + fresh.prefix(2).map(\.id)))
        }
    }

    private func section(_ title: String, _ list: [ReviewCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.omniBody(12, weight: 800)).tracking(0.6).foregroundStyle(p.muted)
            FlowLayout(spacing: 6) {
                ForEach(list) { c in
                    let on = selected.contains(c.id)
                    Button { if on { selected.remove(c.id) } else if selected.count < (limit ?? .max) { selected.insert(c.id) } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: CEFRColors[c.vocabulary.CEFR?.uppercased() ?? ""] ?? 0x9aa2b2)).frame(width: 9, height: 9)
                            Text(c.vocabulary.vocab ?? "").font(.omniBody(14, weight: 700)).foregroundStyle(on ? .white : p.text)
                            Text(c.isNew ? "từ mới" : c.overdueDays > 0 ? "quá hạn" : "tới hạn").font(.omniBody(11, weight: 600)).foregroundStyle(on ? .white.opacity(0.85) : p.muted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(on ? Color(hex: 0x2f6fd6) : p.card, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : p.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
