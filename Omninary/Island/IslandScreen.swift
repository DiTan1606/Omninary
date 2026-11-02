import SwiftUI

// Học từ vựng: the path of islands (lộ trình), the stage of the current level, and the doors to
// Nghiên cứu and Khám phá.

private let ink = Color(hex: 0x2a2440)

struct IslandScreen: View {
    /// A boat ride to play on opening, from Setting, without changing progress.
    enum SailPreview: String, Identifiable {
        case sameRegion, newRegion
        var id: String { rawValue }
    }
    var sailPreview: SailPreview? = nil

    init(sailPreview: SailPreview? = nil) { self.sailPreview = sailPreview }

    @StateObject private var game = IslandGame()
    @ObservedObject private var hearts = OmniLearningHeartManager.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OmniAppearanceMode.storageKey) private var appearanceRaw = OmniAppearanceMode.auto.rawValue
    @AppStorage("lab_tab") private var labTab = "prog"
    @State private var swappingWords = false
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            if game.mode == .stage {
                // the open sea all round the island, under the buttons too, as on the path
                GeometryReader { g in
                    ZStack {
                        Color(hex: game.night ? 0x0c2347 : 0x2b66ae)
                        SeaWaves(scale: 0.56 * g.size.width / 390, night: game.night)
                    }
                }
                .ignoresSafeArea()
                IslandMapView(game: game).ignoresSafeArea()
            }
            else { AdventurePathView(game: game).ignoresSafeArea(edges: .bottom) }
            VStack(spacing: 0) {
                hud
                if game.mode == .home { regionCard }
                Spacer()
                bar
            }
            if let t = game.toast {
                Text(t).font(.omniBody(14, weight: 600)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(hex: 0x17202e).opacity(0.92), in: Capsule())
                    .padding(.top, 130).frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity).allowsHitTesting(false)
            }
            if game.isLoading || game.busy { loading }
            if let err = game.loadError, game.server == nil { errorView(err) }
            if game.mode == .stage, let run = game.stage, game.questMounted { questSession(run) }
            if let k = game.questCard, let run = game.stage, !game.questVisible {
                QuestCardView(game: game, run: run, quest: k) { game.questCard = nil; swappingWords = true }
            }
            if let clear = game.stageClear, game.stage != nil, !game.questVisible { levelClearCard(clear) }
            CloudCurtain(closed: game.curtainClosed)
        }
        .animation(.easeInOut(duration: 0.2), value: game.toast)
        .animation(.easeInOut(duration: 0.15), value: game.questCard)
        .sheet(isPresented: $swappingWords) {
            if let run = game.stage {
                WordPickSheet(game: game, region: run.region, index: run.index, limit: AdventureQuests.wordCount(isExtra: hearts.isExtra)) { words in
                    swappingWords = false
                    Task { await game.swapAdventureWords(words) }
                }
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $confirmLeave) {
            leaveSheet.presentationDetents([.height(240)])
                // a solid card (white by day, navy by night), not the glass sheet
                .presentationBackground(QuizPalette(dark: game.night).card)
        }
        .fullScreenCover(isPresented: $game.showLab) { LabScreen(game: game) }
        .task {
            game.setNight((OmniAppearanceMode(rawValue: appearanceRaw) ?? .auto).isNight(isDay: OmniWeather.shared.isEnabled ? OmniWeather.shared.isDay : nil))
            await game.load()
            if let sailPreview {
                // from the current island to the next one, or from the last island of this region
                let map = min(AdventureMaps.count - 2, game.conquest.map), region = min(2, map / 15)
                game.sailFrom = sailPreview == .sameRegion ? (map % 15 == 14 ? map - 1 : map) : region * 15 + 14
            }
        }
        .onChange(of: appearanceRaw) { _, raw in game.setNight((OmniAppearanceMode(rawValue: raw) ?? .auto).isNight(isDay: OmniWeather.shared.isEnabled ? OmniWeather.shared.isDay : nil)) }
        .statusBarHidden(false)
        .environment(\.colorScheme, .light)
    }

    private var regionName: String { AdventureMaps.region(min(AdventureMaps.count - 1, game.conquest.map)).name }

    // MARK: top bar

    private var hud: some View {
        HStack(spacing: 6) {
            roundButton("chevron.left") {
                if game.mode == .stage { if game.stage == nil { game.backToPath() } else { confirmLeave = true } } else { dismiss() }
            }
            .accessibilityLabel(game.mode == .stage ? (game.stage == nil ? "Về lộ trình" : "Rời màn") : "Quay lại")
            VStack(alignment: .leading, spacing: 0) {
                if game.mode == .stage, let run = game.stage {
                    let map = AdventureMaps.index(run.region, run.index)
                    Text(AdventureMaps.name(map)).font(.omniBody(15, weight: 800)).lineLimit(1)
                    Text("Màn \(min(6, game.conquest.words / 5 + 1))/6 · đảo \(run.index + 1)/15").font(.omniBody(11, weight: 500)).foregroundStyle(qp.muted).lineLimit(1)
                } else if game.mode == .stage, let map = game.freeMap {
                    Text(AdventureMaps.name(map)).font(.omniBody(15, weight: 800)).lineLimit(1)
                    Text("Đảo \(map % 15 + 1)/15 · đã chinh phục").font(.omniBody(11, weight: 500)).foregroundStyle(qp.muted).lineLimit(1)
                } else {
                    Text("Học từ vựng").font(.omniBody(15, weight: 800))
                    Text(regionName).font(.omniBody(11, weight: 600)).foregroundStyle(qp.muted).lineLimit(1)
                }
            }
            .foregroundStyle(qp.text)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(qp.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.15), radius: 6, y: 4)
            chip(pixel: "coin", value: "\(game.omni)")
            chip(pixel: "heart", value: hearts.isExtra ? "∞" : "\(hearts.remainingHearts)")
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    /// The region's progress, fixed under the top bar: islands and levels conquered.
    private var regionCard: some View {
        let map = game.conquest.map, regionStart = min(3, map / 15) * 15
        let isles = min(15, map - regionStart), levels = isles * 6 + (map < AdventureMaps.count ? min(6, game.conquest.words / 5) : 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(regionName).font(.omniBody(15, weight: 800)).foregroundStyle(qp.text)
                Spacer()
                Text("\(isles)/15 đảo · \(levels)/90 màn").font(.omniBody(12.5, weight: 700)).foregroundStyle(qp.muted)
            }
            GeometryReader { g in
                Capsule().fill(qp.line)
                    .overlay(alignment: .leading) { Capsule().fill(LinearGradient(colors: [Color(hex: 0xffd66b), Color(hex: 0xf0b429)], startPoint: .top, endPoint: .bottom)).frame(width: g.size.width * CGFloat(levels) / 90) }
                    .overlay(Capsule().stroke(ink, lineWidth: 2))
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(qp.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.18), radius: 8, y: 6)
        .padding(.horizontal, 12).padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private func roundButton(_ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .heavy)).foregroundStyle(tint ?? qp.text)
                .frame(width: 42, height: 42).background(qp.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.16), radius: 6, y: 4)
        }.buttonStyle(.plain)
    }
    private func chip(pixel: String, value: String) -> some View {
        HStack(spacing: 3) {
            PixelIcon(pixel, size: 18)
            Text(value).font(.omniDisplay(15)).monospacedDigit().foregroundStyle(qp.text)
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background(qp.card.opacity(0.96), in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.15), radius: 6, y: 4)
    }

    /// Cards over the map: white by day, the night navy of the quest card by night.
    private var qp: QuizPalette { QuizPalette(dark: game.night) }

    // MARK: bottom bar

    private var bar: some View {
        // side · hero · side in a 1 : 1.7 : 1 grid, as in the demo
        GeometryReader { g in
            let unit = (g.size.width - 20) / 3.7
            barContent.environment(\.islandBarUnit, unit)
        }
        .frame(height: 112)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var barContent: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if game.mode == .stage, let run = game.stage {
                sideButton("Rời màn", symbol: "flag.fill") { confirmLeave = true }
                heroButton(small: "Nhiệm vụ \(min(run.doneQuests + 1, run.questCount))/\(run.questCount)", title: "Đi tới") { game.nextQuest() }
                sideButton("Nghiên cứu", symbol: "chart.bar.fill") { labTab = "prog"; game.showLab = true }
            } else if game.mode == .stage {
                sideButton("Nghiên cứu", symbol: "chart.bar.fill") { labTab = "prog"; game.showLab = true }
                heroButton(small: "Đã chinh phục", title: "Về lộ trình") { game.backToPath() }
                sideButton("Khám phá", symbol: "square.stack.fill") { labTab = "deck"; game.showLab = true }
            } else {
                sideButton("Nghiên cứu", symbol: "chart.bar.fill") { labTab = "prog"; game.showLab = true }
                let due = game.dueVocabs.count
                heroButton(small: due > 0 ? "\(due) từ cần ôn hôm nay" : "Ôn từ mới", title: "Phiêu lưu") { game.play() }
                sideButton("Khám phá", symbol: "square.stack.fill") { labTab = "deck"; game.showLab = true }
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func sideButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        BarSlot(weight: 1) { Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(ink).frame(height: 44)
                Text(title).font(.omniDisplay(14)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(LinearGradient(colors: [Color(hex: 0xffe27a), Color(hex: 0xffcf3a), Color(hex: 0xf0a71f)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(ink, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 20).fill(ink).offset(y: 6))
        }
        .buttonStyle(PressDownStyle()) }
    }
    private func heroButton(small: String, title: String, action: @escaping () -> Void) -> some View {
        BarSlot(weight: 1.7) { Button(action: action) {
            VStack(spacing: 2) {
                Text(small.uppercased()).font(.omniBody(11, weight: 700)).foregroundStyle(.white.opacity(0.92)).lineLimit(1).minimumScaleFactor(0.7)
                Text(title.uppercased()).font(.omniDisplay(title.count > 10 ? 22 : 30)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 92).padding(.horizontal, 6)
            .background(LinearGradient(colors: [Color(hex: 0x7be56b), Color(hex: 0x5ad152), Color(hex: 0x2f9e3a)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(ink, lineWidth: 4))
            .background(RoundedRectangle(cornerRadius: 24).fill(ink).offset(y: 7))
        }
        .buttonStyle(PressDownStyle()) }
    }

    // MARK: overlays

    private var loading: some View {
        ProgressView().controlSize(.large).tint(.white)
            .padding(20).background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorView(_ err: String) -> some View {
        VStack(spacing: 12) {
            Text("Chưa tải được dữ liệu").font(.omniBody(17, weight: 800))
            Text(err).font(.omniBody(13, weight: 500)).multilineTextAlignment(.center).foregroundStyle(qp.muted)
            HStack {
                Button("Quay lại") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain))
                Button("Thử lại") { Task { await game.load() } }.buttonStyle(IslandButtonStyle(kind: .primary))
            }
        }
        .padding(20).background(qp.card, in: RoundedRectangle(cornerRadius: 20)).padding(30)
        .environment(\.colorScheme, game.night ? .dark : .light)
    }

    private func questSession(_ run: StageRun) -> some View {
        LearningSessionView(
            sessionID: run.session.id, tasks: run.session.tasks, learningVocabGroups: run.session.groups, reasons: run.session.reasons,
            onClose: { game.questVisible = false },
            questMode: LearningQuestMode(
                isVisible: game.questVisible,
                planned: run.planned,
                resume: run.resume,
                onStep: { game.questStepped($0) },
                onHide: { game.questVisible = false },
                onSettled: {
                    game.stageSettled($0, $1)
                    // all five quests done: the day's first finished adventure lights the streak
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { OmniIgniteCenter.shared.showPending() }
                },
                place: AdventureMaps.name(AdventureMaps.index(run.region, run.index))
            )
        )
        .id(run.session.id)
        .environment(\.colorScheme, game.night ? .dark : .light)
        .opacity(game.questVisible ? 1 : 0)
        .allowsHitTesting(game.questVisible)
        .accessibilityHidden(!game.questVisible)
        .transition(.opacity)
    }

    /// Qua màn x/6: the level's six steps, what was earned, the words to watch, and — when the
    /// island is finished — the boat ride to the next one.
    private func levelClearCard(_ clear: AdventureClear) -> some View {
        let won = clear.collected != nil
        let card = VStack(spacing: 10) {
                    Text("Qua màn \(clear.levelAfter)/6!").font(.omniDisplay(28)).foregroundStyle(qp.text)
                    Text("\(clear.planned) câu · đúng ngay \(clear.firstTry) câu" + (clear.retryQuests > 0 ? " · \(clear.retryQuests) nhiệm vụ làm lại" : ""))
                        .font(.omniBody(13, weight: 500)).foregroundStyle(qp.muted).multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        reward("+\(clear.earned + clear.sessionPoints)", "Omni")
                        if !hearts.isExtra { reward("−1", "tim · còn \(hearts.remainingHearts)", tint: 0xe8463f) }
                        reward("+\(clear.words)", "từ", tint: 0x23893f)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(AdventureMaps.name(clear.mapBefore).uppercased()).font(.omniBody(11.5, weight: 800)).tracking(0.4).foregroundStyle(qp.muted).lineLimit(1)
                            Spacer()
                            Text("\(clear.levelAfter)/6 màn").font(.omniDisplay(16)).foregroundStyle(qp.text)
                        }
                        LevelSteps(before: clear.levelBefore, after: clear.levelAfter)
                    }
                    .padding(12).background(qp.soft, in: RoundedRectangle(cornerRadius: 14))
                    if won, let art = IslandArt.cached(clear.mapBefore) {
                        VStack(spacing: 6) {
                            Image(decorative: art.image, scale: 1).resizable().interpolation(.none).scaledToFit().frame(height: 130)
                            Text("ĐÃ CHINH PHỤC").font(.omniDisplay(13)).foregroundStyle(Color(hex: 0x1f7a37))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x34b45a), lineWidth: 2)).rotationEffect(.degrees(-4))
                        }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(Color(hex: 0x2b66ae), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink, lineWidth: 3))
                    }
                    if !clear.weak.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CẦN CHÚ Ý · SẼ GẶP LẠI SỚM").font(.omniBody(11.5, weight: 800)).tracking(0.4).foregroundStyle(qp.muted)
                            FlowLayout(spacing: 6) {
                                ForEach(clear.weak, id: \.self) { w in
                                    Text(w).font(.omniBody(13, weight: 700)).foregroundStyle(game.night ? Color(hex: 0xf6d2a8) : Color(hex: 0x8a5a00))
                                        .padding(.horizontal, 10).padding(.vertical, 5).background(game.night ? Color(hex: 0x3a2a16) : Color(hex: 0xfff1d1), in: Capsule())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if clear.earned == 0 { Text("Hôm nay bạn đã nhận đủ 500 điểm Omni, phần thưởng màn không cộng thêm.").font(.omniBody(11.5, weight: 500)).foregroundStyle(qp.muted).multilineTextAlignment(.center) }
                    Button(won ? (clear.mapBefore % 15 == 14 ? "Ra khơi sang vùng mới" : "Chèo thuyền sang đảo mới") : "Về lộ trình") { game.backToPath() }
                        .buttonStyle(IslandButtonStyle(kind: .primary)).padding(.top, 4)
                }
                .padding(22).frame(maxWidth: 360).background(qp.card, in: RoundedRectangle(cornerRadius: 24)).padding(20)
                .frame(maxWidth: .infinity)
        return ZStack {
            Color(red: 20 / 255, green: 16 / 255, blue: 36 / 255).opacity(0.55).ignoresSafeArea()
            // in the middle of the screen; scrolls only when it is taller than the screen
            ViewThatFits(in: .vertical) {
                card
                ScrollView { card }.scrollBounceBehavior(.basedOnSize)
            }
        }
        .environment(\.colorScheme, game.night ? .dark : .light)
    }
    private func reward(_ v: String, _ label: String, tint: UInt32 = 0x5b3fc9) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.omniDisplay(22)).foregroundStyle(Color(hex: tint))
            Text(label).font(.omniBody(11, weight: 500)).foregroundStyle(qp.muted)
        }
        .frame(maxWidth: .infinity).padding(8).background(qp.soft, in: RoundedRectangle(cornerRadius: 14))
    }

    private var leaveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            let done = game.stage?.doneQuests ?? 0, total = game.stage?.questCount ?? 0
            Text("Rời màn?").font(.omniBody(21, weight: 800)).foregroundStyle(QuizPalette(dark: game.night).text)
            Text(done > 0 ? "Đã lưu \(done)/\(total) nhiệm vụ. Bấm Phiêu lưu lần sau để làm tiếp; câu đang làm dở trong nhiệm vụ này sẽ làm lại."
                          : "Chưa xong nhiệm vụ nào. Bấm Phiêu lưu lần sau để bắt đầu lại với cùng các từ này.")
                .font(.omniBody(14, weight: 500)).foregroundStyle(QuizPalette(dark: game.night).muted)
            HStack {
                Button("Ở lại") { confirmLeave = false }.buttonStyle(IslandButtonStyle(kind: .plain))
                Button("Rời màn") { confirmLeave = false; game.backToPath() }.buttonStyle(IslandButtonStyle(kind: .red))
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, game.night ? .dark : .light)
    }
}

/// The six levels of an island as steps: done in green, the one just passed pops in.
private struct LevelSteps: View {
    let before: Int
    let after: Int
    @State private var shown = false
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<6, id: \.self) { i in
                Capsule().fill(i < before || (shown && i < after) ? Color(hex: 0x34b45a) : Color(hex: 0xdfe5ee))
                    .overlay(Capsule().stroke(ink, lineWidth: 2))
                    .frame(height: 12)
                    .scaleEffect(shown && i >= before && i < after ? 1 : (i >= before && i < after ? 0.6 : 1))
            }
        }
        .onAppear { withAnimation(.spring(duration: 0.6).delay(0.4)) { shown = true } }
        .accessibilityElement().accessibilityLabel("\(after) trên 6 màn")
    }
}

struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 4 : 0).animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct IslandButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, red }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let dark = scheme == .dark
        let (bg, shadow, fg): (Color, Color, Color) = {
            if !isEnabled { return dark ? (Color(hex: 0x252c52), .clear, Color(hex: 0x7d87a6)) : (Color(hex: 0xeef3fb), .clear, Color(hex: 0x5b6779)) }
            switch kind {
            case .primary: return (Color(hex: 0x34b45a), Color(hex: 0x23893f), .white)
            case .red: return (Color(hex: 0xe8463f), Color(hex: 0xb3302a), .white)
            case .plain: return dark ? (Color(hex: 0x252c52), .clear, Color(hex: 0xeef1fb)) : (Color(hex: 0xeef3fb), .clear, Color(hex: 0x17202e))
            }
        }()
        configuration.label
            .font(kind == .plain ? .omniBody(14, weight: 700) : .omniDisplay(15))
            .foregroundStyle(fg)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if kind == .plain { RoundedRectangle(cornerRadius: 14).stroke(dark ? Color(hex: 0x2b3457) : Color(hex: 0xe3e9f2)) } }
            .background(RoundedRectangle(cornerRadius: 14).fill(shadow).offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

private struct IslandBarUnitKey: EnvironmentKey { static let defaultValue: CGFloat = 100 }
extension EnvironmentValues { var islandBarUnit: CGFloat { get { self[IslandBarUnitKey.self] } set { self[IslandBarUnitKey.self] = newValue } } }

private struct BarSlot<C: View>: View {
    let weight: CGFloat
    @ViewBuilder let content: () -> C
    @Environment(\.islandBarUnit) private var unit
    var body: some View { content().frame(width: unit * weight) }
}
