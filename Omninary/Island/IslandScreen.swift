import SwiftUI

// Đảo nhà: the learner's island, the door to Phiêu lưu and Nhà nghiên cứu.

private let ink = Color(hex: 0x2a2440)

struct IslandScreen: View {
    @StateObject private var game = IslandGame()
    @ObservedObject private var hearts = OmniLearningHeartManager.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OmniAppearanceMode.storageKey) private var appearanceRaw = OmniAppearanceMode.auto.rawValue
    @State private var showAdventure = false
    @State private var showNotes = false
    @State private var showBag = false
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            IslandMapView(game: game).ignoresSafeArea()
            VStack(spacing: 0) {
                hud
                Spacer()
                bar
            }
            if let t = game.toast {
                Text(t).font(.omniBody(14, weight: 600)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(hex: 0x17202e).opacity(0.92), in: Capsule())
                    .padding(.top, 120).frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity).allowsHitTesting(false)
            }
            if game.isLoading || game.busy { loading }
            if let err = game.loadError, game.scene == nil { errorView(err) }
            if let r = game.openResident { residentOverlay(r) }
            if game.mode == .stage, let run = game.stage, game.questMounted { questSession(run) }
            if let clear = game.stageClear, let run = game.stage, !game.questVisible { stageClearCard(clear, run) }
        }
        .animation(.easeInOut(duration: 0.2), value: game.toast)
        .sheet(item: $game.openLot) { lot in LotSheet(game: game, lot: lot).presentationDetents([.medium, .large]) }
        .sheet(item: $game.openRegion) { r in RegionSheet(game: game, region: r).presentationDetents([.height(320)]) }
        .sheet(item: $game.openBuilding) { lot in BuildingSheet(game: game, lot: lot).presentationDetents([.height(300)]) }
        .sheet(isPresented: $showBag) { BagSheet { showBag = false; dismiss(); NotificationCenter.default.post(name: .switchToMyOmniTab, object: nil) }.presentationDetents([.medium]) }
        .sheet(isPresented: $confirmLeave) { leaveSheet.presentationDetents([.height(240)]) }
        .fullScreenCover(isPresented: $showNotes) { IslandNotesPage(game: game) }
        .fullScreenCover(isPresented: $game.showLab) { LabScreen(game: game) }
        .fullScreenCover(isPresented: $showAdventure) { AdventurePage(game: game) }
        .fullScreenCover(item: $game.reviewSession) { s in
            LearningSessionView(sessionID: s.id, tasks: s.tasks, learningVocabGroups: s.groups, reasons: s.reasons) {
                game.reviewSession = nil
                Task { await game.load() }
            }
        }
        .task {
            game.setNight((OmniAppearanceMode(rawValue: appearanceRaw) ?? .auto).isNight())
            await game.load()
        }
        .onChange(of: appearanceRaw) { _, raw in game.setNight((OmniAppearanceMode(rawValue: raw) ?? .auto).isNight()) }
        .statusBarHidden(false)
        .environment(\.colorScheme, .light)
    }

    // MARK: top bar

    private var hud: some View {
        HStack(spacing: 6) {
            roundButton("chevron.left") {
                if game.mode == .stage { confirmLeave = true } else { dismiss() }
            }
            .accessibilityLabel(game.mode == .stage ? "Rời màn" : "Quay lại")
            VStack(alignment: .leading, spacing: 0) {
                if game.mode == .stage, let run = game.stage {
                    Text("\(run.region.name) · Màn \(run.index + 1)").font(.omniBody(15, weight: 800)).lineLimit(1)
                    Text("\(run.doneQuests)/\(run.quests.count) nhiệm vụ · \(run.words.count) từ").font(.omniBody(11, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)).lineLimit(1)
                } else {
                    Text("Đảo nhà").font(.omniBody(15, weight: 800))
                    if game.homeless > 0 { Text("\(game.homeless) cư dân chờ nhà ở").font(.omniBody(11, weight: 700)).foregroundStyle(Color(hex: 0xe8463f)).lineLimit(1) }
                }
            }
            .foregroundStyle(Color(hex: 0x17202e))
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.15), radius: 6, y: 4)
            if game.mode == .home { chip(system: "person.fill", tint: Color(hex: 0x3f6fca), value: "\(game.learnedVocabs.count)") }
            chip(pixel: "coin", value: "\(game.omni)")
            chip(pixel: "heart", value: hearts.isExtra ? "∞" : "\(hearts.remainingHearts)")
            if game.mode == .home {
                roundButton("bell.fill", tint: Color(hex: 0xffcf3a)) { showNotes = true }
                    .overlay(alignment: .topTrailing) {
                        let n = (game.dueVocabs.isEmpty ? 0 : 1) + (game.homeless > 0 ? 1 : 0)
                        if n > 0 { Text("\(n)").font(.omniBody(11, weight: 800)).foregroundStyle(.white).frame(width: 18, height: 18).background(Color(hex: 0xe8463f), in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2)).offset(x: 4, y: -4) }
                    }
                    .accessibilityLabel("Thông báo")
            }
        }
        .padding(.horizontal, 10).padding(.top, 6)
    }

    private func roundButton(_ symbol: String, tint: Color = Color(hex: 0x17202e), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 42, height: 42).background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.16), radius: 6, y: 4)
        }.buttonStyle(.plain)
    }
    private func chip(pixel: String? = nil, system: String? = nil, tint: Color = .clear, value: String) -> some View {
        HStack(spacing: 3) {
            if let pixel { PixelIcon(pixel, size: 18) }
            if let system { Image(systemName: system).font(.system(size: 13, weight: .bold)).foregroundStyle(tint) }
            Text(value).font(.omniDisplay(15)).monospacedDigit().foregroundStyle(Color(hex: 0x17202e))
        }
        .padding(.horizontal, 8).frame(height: 42)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.15), radius: 6, y: 4)
    }

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
                heroButton(small: "\(run.doneQuests)/\(run.quests.count) đã xong", title: "Nhiệm vụ tiếp") { game.nextQuest() }
                sideButton("Nghiên cứu", symbol: "flask.fill") { game.labWord = nil; game.showLab = true }
            } else {
                sideButton("Nghiên cứu", symbol: "flask.fill") { game.labWord = nil; game.showLab = true }
                let r = AdventureRegion.all.first { game.isOpen($0) && game.progress($0) < 15 } ?? AdventureRegion.all[0]
                heroButton(small: "\(r.name) · Màn \(min(15, game.progress(r) + 1))", title: "Phiêu lưu") { showAdventure = true }
                sideButton("Túi đồ", symbol: "bag.fill") { showBag = true }
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
            Text("Chưa tải được đảo").font(.omniBody(17, weight: 800))
            Text(err).font(.omniBody(13, weight: 500)).multilineTextAlignment(.center).foregroundStyle(Color(hex: 0x5b6779))
            HStack {
                Button("Quay lại") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain))
                Button("Thử lại") { Task { await game.load() } }.buttonStyle(IslandButtonStyle(kind: .primary))
            }
        }
        .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20)).padding(30)
    }

    private func residentOverlay(_ r: IslandResident) -> some View {
        ZStack {
            Color(red: 20 / 255, green: 16 / 255, blue: 36 / 255).opacity(0.55).ignoresSafeArea().onTapGesture { game.openResident = nil }
            VStack(spacing: 12) {
                WordCardView(vocab: r.vocab, mastery: r.vocab.id.flatMap { game.profiles[$0]?.lastMastery }, mode: .summary).frame(maxWidth: 360)
                HStack(spacing: 8) {
                    Button("Nghe") { SpeechManager.shared.speak(word: r.vocab.vocab ?? "", ipa: r.vocab.IPA, rateMultiplier: 1) }.buttonStyle(IslandButtonStyle(kind: .plain))
                    if r.due { Button("Ôn ngay") { game.openResident = nil; game.review([r.vocab]) }.buttonStyle(IslandButtonStyle(kind: .red)) }
                    Button("Xem chi tiết") { game.openResident = nil; game.labWord = r.vocab.id; game.showLab = true }.buttonStyle(IslandButtonStyle(kind: .primary))
                }
            }
            .padding(16)
        }
        .transition(.opacity)
    }

    private func questSession(_ run: StageRun) -> some View {
        LearningSessionView(
            sessionID: run.session.id, tasks: run.session.tasks, learningVocabGroups: run.session.groups, reasons: run.session.reasons,
            onClose: { game.questVisible = false },
            questMode: LearningQuestMode(
                isVisible: game.questVisible,
                onStep: { a, t in game.questStepped(answered: a, total: t) },
                onHide: { game.questVisible = false },
                onSettled: { game.stageSettled($0) }
            )
        )
        .environment(\.colorScheme, game.night ? .dark : .light)
        .opacity(game.questVisible ? 1 : 0)
        .allowsHitTesting(game.questVisible)
        .accessibilityHidden(!game.questVisible)
        .transition(.opacity)
    }

    private func stageClearCard(_ clear: (earned: Int, sessionPoints: Int), _ run: StageRun) -> some View {
        ZStack {
            Color(red: 20 / 255, green: 16 / 255, blue: 36 / 255).opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("★★★").font(.system(size: 40, weight: .heavy)).foregroundStyle(Color(hex: 0xffcf3a)).shadow(color: Color(hex: 0xc99a2a), radius: 0, y: 3)
                Text("Hoàn thành màn!").font(.omniDisplay(26)).foregroundStyle(Color(hex: 0x17202e))
                Text("\(run.region.name) · Màn \(run.index + 1): \(run.region.stages[run.index])").font(.omniBody(13, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    reward("+\(clear.earned + clear.sessionPoints)", "Omni")
                    reward("\(run.words.count)", "từ đã ôn")
                    reward("\(run.quests.count)", "nhiệm vụ")
                }
                if clear.earned == 0 { Text("Hôm nay bạn đã nhận đủ 500 điểm Omni, phần thưởng màn không cộng thêm.").font(.omniBody(11.5, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)).multilineTextAlignment(.center) }
                Button("Về đảo nhà") { game.leaveStage() }.buttonStyle(IslandButtonStyle(kind: .primary)).padding(.top, 4)
            }
            .padding(22).frame(maxWidth: 360).background(.white, in: RoundedRectangle(cornerRadius: 24)).padding(20)
        }
    }
    private func reward(_ v: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.omniDisplay(22)).foregroundStyle(Color(hex: 0x5b3fc9))
            Text(label).font(.omniBody(11, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
        }
        .frame(maxWidth: .infinity).padding(8).background(Color(hex: 0xf6f8fc), in: RoundedRectangle(cornerRadius: 14))
    }

    private var leaveSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rời màn?").font(.omniBody(21, weight: 800))
            Text("Phiên học của màn chỉ được lưu khi xong hết nhiệm vụ. Rời bây giờ thì phần đã trả lời chưa được tính.").font(.omniBody(14, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            HStack {
                Button("Ở lại") { confirmLeave = false }.buttonStyle(IslandButtonStyle(kind: .plain))
                Button("Rời màn") { confirmLeave = false; game.leaveStage() }.buttonStyle(IslandButtonStyle(kind: .red))
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .light)
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
    func makeBody(configuration: Configuration) -> some View {
        let (bg, shadow, fg): (Color, Color, Color) = {
            if !isEnabled { return (Color(hex: 0xeef3fb), .clear, Color(hex: 0x5b6779)) }
            switch kind {
            case .primary: return (Color(hex: 0x34b45a), Color(hex: 0x23893f), .white)
            case .red: return (Color(hex: 0xe8463f), Color(hex: 0xb3302a), .white)
            case .plain: return (Color(hex: 0xeef3fb), .clear, Color(hex: 0x17202e))
            }
        }()
        configuration.label
            .font(kind == .plain ? .omniBody(14, weight: 700) : .omniDisplay(15))
            .foregroundStyle(fg)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(bg, in: RoundedRectangle(cornerRadius: 14))
            .overlay { if kind == .plain { RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xe3e9f2)) } }
            .background(RoundedRectangle(cornerRadius: 14).fill(shadow).offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

// MARK: - Sheets

enum IslandPreview {
    private static var cache: [String: CGImage] = [:]
    static func image(_ kind: IslandBuildingKind) -> CGImage? {
        if let c = cache[kind.key] { return c }
        let c = PixelCanvas(width: kind.w * TILE + 30, height: kind.h * TILE + 46)
        var o = IslandObject(kind: kind.kind, x: 0, y: 0, w: kind.w, h: kind.h)
        o.roof = kind.key == "home" ? 0x3f6fca : kind.roof; o.wall = kind.wall; o.mine = kind.mine; o.sign = kind.sign
        IslandDraw.drawAt(o, c, dx: 14, dy: 32)
        let img = c.makeImage(); cache[kind.key] = img; return img
    }
}

extension IslandDraw {
    /// Draw one object with its top-left at (dx, dy) instead of its tile position.
    static func drawAt(_ o: IslandObject, _ X: PixelCanvas, dx: Double, dy: Double) {
        let shiftX = Int(dx) / TILE, shiftY = Int(dy) / TILE
        var moved = o; moved.x = shiftX; moved.y = shiftY
        let canvas = PixelCanvas(width: X.width + TILE, height: X.height + TILE)
        canvas.R(0, 0, canvas.width, canvas.height, 0x8fd16a)
        draw(moved, canvas)
        // copy back with the leftover sub-tile offset
        let ox = Int(dx) - shiftX * TILE, oy = Int(dy) - shiftY * TILE
        for y in 0..<X.height { for x in 0..<X.width {
            let sx = x - ox, sy = y - oy
            if sx >= 0, sy >= 0, sx < canvas.width, sy < canvas.height { X.pixels[y * X.width + x] = canvas.pixels[sy * canvas.width + sx] }
        } }
    }
}

private struct SheetHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        HStack {
            Text(title).font(.omniBody(21, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
            Spacer()
            Button("Đóng") { dismiss() }.buttonStyle(IslandButtonStyle(kind: .plain))
        }
    }
}

struct LotSheet: View {
    @ObservedObject var game: IslandGame
    let lot: IslandLot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SheetHeader(title: "Ô đất trống")
            Text("Chọn công trình để xây ngay trên ô này.").font(.omniBody(14, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(IslandCatalog.buildable, id: \.key) { k in
                        let locked = k.need > 0 && game.learnedCount < k.need, ok = game.omni >= k.cost
                        Button { Task { await game.build(lot, k) } } label: {
                            HStack(spacing: 10) {
                                if let img = IslandPreview.image(k) { Image(decorative: img, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10)) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.name).font(.omniBody(15, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
                                    Text((locked ? "Cần học \(k.need) từ. " : "") + k.desc).font(.omniBody(12, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)).multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 4)
                                HStack(spacing: 3) { PixelIcon("coin", size: 16); Text("\(k.cost)").font(.omniDisplay(15)).foregroundStyle(ok ? Color(hex: 0x17202e) : Color(hex: 0xa02a22)) }
                            }
                            .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0xe3e9f2)))
                            .opacity(locked || !ok ? 0.55 : 1)
                        }
                        .buttonStyle(.plain).disabled(locked || !ok || game.busy)
                    }
                }
            }
        }
        .padding(20).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
    }
}

struct RegionSheet: View {
    @ObservedObject var game: IslandGame
    let region: IslandRegion
    var body: some View {
        let ok = game.omni >= region.cost, w = region.rect[2], h = region.rect[3]
        let kids = IslandRegion.all.filter { $0.parent == region.id }
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: region.name)
            Text((region.isJoin ? "Vùng nối giữa \(region.needs.compactMap { IslandRegion.byID[$0]?.name }.joined(separator: " và ")), khoảng \(w)×\(h) ô." : "Vùng đất \(w)×\(h) ô, lớp mở rộng thứ \(region.layer).")
                 + " Có sẵn ô đất để xây, cây cối kiểu \(region.themeName)." + (kids.isEmpty ? "" : " Mở xong sẽ lộ thêm vùng \(kids.map(\.name).joined(separator: ", ")) ở phía ngoài."))
                .font(.omniBody(14, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            Button { Task { await game.buy(region) } } label: { HStack(spacing: 4) { Text("Mở vùng đất ·"); PixelIcon("coin", size: 16); Text("\(region.cost)") } }
                .buttonStyle(IslandButtonStyle(kind: .primary)).disabled(!ok || game.busy)
            if !ok { Text("Chưa đủ điểm Omni. Ôn bài và qua màn phiêu lưu để kiếm thêm.").font(.omniBody(13, weight: 500)).foregroundStyle(Color(hex: 0x5b6779)) }
            Spacer(minLength: 0)
        }
        .padding(20).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
    }
}

struct BuildingSheet: View {
    @ObservedObject var game: IslandGame
    let lot: IslandLot
    var body: some View {
        let k = IslandCatalog.byKey[lot.building ?? ""]
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: k?.name ?? "Công trình")
            Text(k?.desc ?? "").font(.omniBody(14, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            if let k, k.capacity > 0 {
                let lots = (game.scene?.lots ?? []).filter { ($0.building.flatMap { IslandCatalog.byKey[$0]?.capacity } ?? 0) > 0 }
                let before = lots.prefix { $0.key != lot.key }.reduce(0) { $0 + (IslandCatalog.byKey[$1.building ?? ""]?.capacity ?? 0) }
                let living = max(0, min(k.capacity, game.learnedVocabs.count - before))
                Text("Đang ở: \(living)/\(k.capacity) cư dân").font(.omniBody(15, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
            }
            if lot.building == "clinic", !game.dueVocabs.isEmpty {
                Button("Ôn \(min(10, game.dueVocabs.count)) từ đang chờ") { game.openBuilding = nil; game.review(Array(game.dueVocabs.prefix(10))) }.buttonStyle(IslandButtonStyle(kind: .red))
            }
            if lot.building == "shop" {
                Button("Mở My Omni") { game.openBuilding = nil; NotificationCenter.default.post(name: .switchToMyOmniTab, object: nil) }.buttonStyle(IslandButtonStyle(kind: .primary))
            }
            Spacer(minLength: 0)
        }
        .padding(20).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
    }
}

struct BagSheet: View {
    let openMyOmni: () -> Void
    private let items: [(String, String, String)] = [
        ("heart", "Trái tim bên lề", "Cộng 1 lượt học trong ngày."), ("spark", "Nhân đôi điểm", "Nhân đôi điểm Omni tới hết ngày."),
        ("snow", "Mùa đông không lạnh", "Giữ chuỗi ngày học khi lỡ một ngày."), ("flame", "Người giữ lửa", "Khôi phục chuỗi vừa mất (Extra).")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetHeader(title: "Túi đồ")
            Text("Vật phẩm mua bằng điểm Omni và dùng ngay ở My Omni.").font(.omniBody(14, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items, id: \.1) { icon, name, desc in
                    VStack(alignment: .leading, spacing: 4) {
                        PixelIcon(icon, size: 24)
                        Text(name).font(.omniBody(14, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
                        Text(desc).font(.omniBody(11.5, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
                    }
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading).padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0xe3e9f2)))
                }
            }
            Button("Mở My Omni", action: openMyOmni).buttonStyle(IslandButtonStyle(kind: .primary))
            Spacer(minLength: 0)
        }
        .padding(20).background(Color(hex: 0xeef3fb)).environment(\.colorScheme, .light)
    }
}

struct IslandNotesPage: View {
    @ObservedObject var game: IslandGame
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(Color(hex: 0x17202e)).frame(width: 42, height: 42).background(.white, in: RoundedRectangle(cornerRadius: 14)) }
                Text("Thông báo").font(.omniBody(24, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
            }
            ScrollView {
                VStack(spacing: 10) {
                    let due = game.dueVocabs
                    if !due.isEmpty {
                        note(icon: "!", color: 0xe8463f, title: "\(due.count) từ tới hạn ôn", text: due.prefix(12).compactMap(\.vocab).joined(separator: ", ") + ". Các cư dân này đang chờ ở trạm xá.") {
                            Button("Ôn ngay") { dismiss(); game.review(Array(due.prefix(10))) }.buttonStyle(IslandButtonStyle(kind: .red))
                        }
                    }
                    if game.homeless > 0 {
                        note(icon: "⌂", color: 0xd98a3a, title: "\(game.homeless) cư dân mới chờ nhà ở", text: "Đảo đã hết chỗ ở. Xây Nhà ở trên ô đất trống.") {
                            Button("Tìm ô đất trống") { dismiss(); game.showEmptyLot() }.buttonStyle(IslandButtonStyle(kind: .primary))
                        }
                    }
                    if due.isEmpty && game.homeless == 0 {
                        note(icon: "✓", color: 0x34b45a, title: "Đảo đang yên bình", text: "Không có từ tới hạn và ai cũng có nhà ở.") { EmptyView() }
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0xeef3fb).ignoresSafeArea()).environment(\.colorScheme, .light)
    }
    private func note<A: View>(icon: String, color: UInt32, title: String, text: String, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon).font(.omniDisplay(18)).foregroundStyle(.white).frame(width: 36, height: 36).background(Color(hex: color), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.omniBody(15, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
                Text(text).font(.omniBody(13, weight: 500)).foregroundStyle(Color(hex: 0x5b6779))
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0xe3e9f2)))
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
