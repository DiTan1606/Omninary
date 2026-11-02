import SwiftUI

// The card a quest opens on the stage map: who gives it, what they say, which exercises
// it holds, and (first quest only) the adventure's five words with the option to swap them.

extension QuestionType {
    var questTitle: String {
        switch self {
        case .multipleChoice: "Chọn nghĩa"
        case .listenAndType: "Nghe viết"
        case .meaningAndType: "Viết từ"
        case .sentenceScramble: "Ghép câu"
        case .pronunciationExample: "Đọc to"
        }
    }
}

struct QuestCardView: View {
    @ObservedObject var game: IslandGame
    let run: StageRun
    let quest: Int
    let swapWords: () -> Void

    private var isRetry: Bool { quest >= run.planned.count }
    /// Light by day, Học ngữ pháp's night colours by night, like the quiz itself.
    private var p: QuizPalette { QuizPalette(dark: game.night) }
    private var act: (String, String) {
        if isRetry { return ("Làm lại câu sai", "Còn mấy chữ cháu chưa nhớ, mình làm lại lần nữa nhé!") }
        return AdventureRegion.acts[run.spot(quest).act] ?? ("Nhiệm vụ", "Trả lời đúng để hoàn thành nhiệm vụ nhé!")
    }

    var body: some View {
        let tasks = run.tasks(of: quest)
        ZStack {
            Color(red: 20 / 255, green: 16 / 255, blue: 36 / 255).opacity(0.55).ignoresSafeArea()
                .onTapGesture { game.questCard = nil }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    NPCPortrait(act: run.spot(quest).act, dark: game.night)
                    Text(act.1)
                        .font(.omniBody(14.5, weight: 600)).foregroundStyle(p.text)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.soft, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(p.line, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("NHIỆM VỤ \(quest + 1)/\(run.questCount)" + (isRetry ? " · LÀM LẠI" : ""))
                        .font(.omniBody(12, weight: 800)).tracking(0.5).foregroundStyle(p.muted)
                    HStack {
                        Text(act.0).font(.omniBody(20, weight: 800)).foregroundStyle(p.text)
                        Spacer()
                        Text("\(tasks.count) câu").font(.omniBody(13.5, weight: 600)).foregroundStyle(p.muted)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                        Text(task.type.questTitle).font(.omniBody(12, weight: 700)).foregroundStyle(p.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(p.soft, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if quest == 0 && run.answered == 0 { wordList }
                Button("Làm nhiệm vụ") { game.playQuest() }
                    .buttonStyle(IslandButtonStyle(kind: .primary)).frame(maxWidth: .infinity)
            }
            .padding(18).frame(maxWidth: 380)
            .background(p.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(p.line, lineWidth: game.night ? 1 : 0))
            .padding(16)
        }
        .environment(\.colorScheme, game.night ? .dark : .light)
        .transition(.opacity)
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(run.words.count) TỪ CỦA LẦN PHIÊU LƯU NÀY").font(.omniBody(12, weight: 800)).tracking(0.5).foregroundStyle(p.muted)
                Spacer()
                Button("Đổi từ", action: swapWords).font(.omniBody(13, weight: 700)).foregroundStyle(p.link)
            }
            ForEach(run.words, id: \.vocabularyIdentity) { v in
                let status = WordCardStyle.status(v)
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: CEFRColors[v.CEFR?.uppercased() ?? ""] ?? 0x9aa2b2)).frame(width: 8, height: 8)
                    Text(v.vocab ?? "").font(.omniBody(14, weight: 800)).foregroundStyle(p.text).fixedSize()
                    // the meaning gives way first, so it ends in "…" rather than vanishing
                    Text(v.V_meaning ?? "").font(.omniBody(12.5, weight: 500)).foregroundStyle(p.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(status.0).font(.omniBody(11, weight: 700)).fixedSize()
                        .foregroundStyle(status.1 == 2 ? p.verdict(.bad).text : status.1 == 1 ? p.verdict(.near).text
                                         : game.night ? Color(hex: 0xa6afc8) : Color(hex: 0x1d4fa3))
                }
            }
        }
    }
}

/// The quest giver, drawn with the island's pixel people until the NPC illustrations are ready.
struct NPCPortrait: View {
    let act: String
    var dark = false
    var body: some View {
        Group {
            if let img = Self.image(act) {
                Image(decorative: img, scale: 1).resizable().interpolation(.none).frame(width: 84, height: 112)
            }
        }
        .frame(width: 92, height: 116, alignment: .bottom)
        .background(Color(hex: dark ? 0x233e43 : 0xe6f4d8), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(dark ? Color(hex: 0x2b3457) : Color(hex: 0x2a2440), lineWidth: 3))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private static var cache: [String: CGImage] = [:]
    static func image(_ act: String) -> CGImage? {
        if let c = cache[act] { return c }
        let h = act.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } & 0xffff
        let look = IslandMaps.npcLook[act] ?? (IslandGame.hairs[h % IslandGame.hairs.count], ROOFS[(h / 7) % ROOFS.count], nil)
        let canvas = PixelCanvas(width: 21, height: 28)
        canvas.person(10.5, 27, look.0, look.1, .init(hat: look.2))
        let img = canvas.makeImage()
        cache[act] = img
        return img
    }
}
