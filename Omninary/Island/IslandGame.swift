import CoreGraphics
import Foundation
import SwiftUI

// The island game: what the map shows, who walks on it, and what tapping does.

/// A rendered map ready for the screen: the still top layer and what the moving sea needs.
final class IslandScene {
    let map: TileMap
    let fields: IslandFields
    let top: CGImage
    let night: Bool
    let lots: [IslandLot]
    let locked: [(region: IslandRegion, tiles: [(Int, Int)], set: Set<Int>)]
    let walk: [(Int, Int)]
    let portal: (Int, Int)?
    /// Full-size buffer the sea is painted into, owned by the water queue.
    let waterCanvas: PixelCanvas
    var width: Int { fields.W }
    var height: Int { fields.H }

    init(map: TileMap, night: Bool, lots: [IslandLot] = [], locked: [(region: IslandRegion, tiles: [(Int, Int)], set: Set<Int>)] = [], walk: [(Int, Int)]? = nil, portal: (Int, Int)? = nil) {
        self.map = map; self.night = night; self.lots = lots; self.locked = locked; self.portal = portal
        fields = map.fields
        let topCanvas = IslandPaint.topLayer(map)
        if night { topCanvas.nightPass() }
        top = topCanvas.makeImage()!
        if let walk { self.walk = walk } else {
            var w: [(Int, Int)] = []
            for y in 0..<map.rows { for x in 0..<map.cols where map.at(x, y) == Tile.p || map.at(x, y) == Tile.W || map.at(x, y) == Tile.r { w.append((x, y)) } }
            self.walk = w
        }
        waterCanvas = PixelCanvas(width: fields.W, height: fields.H)
    }

    func walkable(_ x: Int, _ y: Int) -> Bool { map.inb(x, y) && (map.at(x, y) == Tile.k || (map.isLand(x, y) && !map.isSolid(x, y))) }

    /// Paint the sea for a rectangle at time t and hand back that piece as an image.
    func waterImage(_ rect: (Int, Int, Int, Int), t: Double) -> CGImage? {
        let (x0, y0, x1, y1) = (max(0, rect.0), max(0, rect.1), min(width, rect.2), min(height, rect.3))
        guard x0 < x1, y0 < y1 else { return nil }
        IslandPaint.water(fields, waterCanvas, t: t, rect: (x0, y0, x1, y1))
        if night { waterCanvas.multiplyRect(x0, y0, x1, y1, by: (0x4b, 0x5a, 0xa6)) }
        return waterCanvas.makeImage(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}

struct IslandWalker {
    var x: Double, y: Double
    var path: [(Int, Int)] = []
    var wait: Double = 0
}

struct IslandResident: Identifiable {
    let id: Int
    let vocab: Vocabulary
    var walker: IslandWalker
    let hair: UInt32
    var waiting: Bool
    var due: Bool
    var level: Int { vocab.learning_level ?? 0 }
}

struct IslandParticle { var x, y, vx, vy, life: Double; let color: UInt32 }

/// An adventure stage being played: its map, the quests on it and the learning session behind them.
struct StageRun {
    let region: AdventureRegion
    let index: Int
    let words: [Vocabulary]
    let session: ActiveLearningSession
    let initialTaskCount: Int
    var quests: [Quest]
    var activeQuest: Int?
    var answered = 0
    var total: Int
    var settled: VocabularyLearningSettlementResult?

    struct Quest { let act: String; let x: Int; let y: Int; var remaining: Int }
    var doneQuests: Int { quests.filter { $0.remaining == 0 }.count }
}

@MainActor
final class IslandGame: ObservableObject {
    enum Mode: Equatable { case home, stage }
    static let hairs: [UInt32] = [0x2b2238, 0x5a3a22, 0xc9c2b0, 0x7a3fb0, 0x3a2a22, 0xd9a441, 0x8a3a22]

    // Server and learning data
    @Published var server: IslandServerState?
    @Published var vocabs: [Vocabulary] = []
    @Published var profiles: [String: WordSkillProfile] = [:]
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var busy = false

    // What is on screen
    @Published var mode: Mode = .home
    @Published private(set) var scene: IslandScene?
    @Published var stage: StageRun?
    @Published var toast: String?
    @Published var night = OmniAppearanceMode(rawValue: UserDefaults.standard.string(forKey: OmniAppearanceMode.storageKey) ?? "auto")?.isNight() ?? false

    // Sheets and overlays driven by the map
    @Published var openLot: IslandLot?
    @Published var openBuilding: IslandLot?
    @Published var openRegion: IslandRegion?
    @Published var openResident: IslandResident?
    @Published var showLab = false
    @Published var labWord: String?
    @Published var reviewSession: ActiveLearningSession?
    @Published var questVisible = false
    /// The stage's learning session stays mounted once the first quest opens it.
    @Published var questMounted = false
    @Published var stageClear: (earned: Int, sessionPoints: Int)?

    // Simulation, read by the map view every frame
    var residents: [IslandResident] = []
    var player = IslandWalker(x: Double((9 + OX) * TILE + 8), y: Double((11 + OY) * TILE + 14))
    var playerThen: (() -> Void)?
    var follow = false
    var particles: [IslandParticle] = []
    var pulseLot: (lot: IslandLot, until: Date)?
    /// Bumped when the camera should jump (stage entry, find resident).
    @Published var cameraTarget: (x: Double, y: Double, zoom: Double, id: UUID)?
    private var homeScene: IslandScene?
    private var homeCamera: (x: Double, y: Double, zoom: Double)?
    var currentCamera: (x: Double, y: Double, zoom: Double) = (0, 0, 1)

    // MARK: - Derived counts

    var learnedVocabs: [Vocabulary] {
        Vocabulary.sortedItems(vocabs).filter { ($0.learning_level ?? 0) >= 1 }
    }
    var capacity: Int {
        (server?.buildings.values ?? [:].values).reduce(0) { $0 + (IslandCatalog.byKey[$1]?.capacity ?? 0) }
    }
    var learnedCount: Int { server?.learned_words ?? learnedVocabs.count }
    var housed: Int { min(learnedVocabs.count, capacity) }
    var homeless: Int { max(0, learnedVocabs.count - capacity) }
    var dueVocabs: [Vocabulary] { learnedVocabs.filter { ReviewScheduler.isDue($0, now: Date()) } }
    var omni: Int { server?.omni_points ?? UserDefaults.standard.integer(forKey: "omni_reward_points") }

    // MARK: - Loading

    func load() async {
        isLoading = scene == nil
        loadError = nil
        do {
            guard let userId = AuthManager.shared.currentUser?.id.uuidString else { throw NSError(domain: "Island", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bạn cần đăng nhập."]) }
            async let st = IslandRepository.fetchState()
            async let vs = VocabularyRepository.fetchUserVocabs(userId: userId)
            let (state, words) = try await (st, vs)
            profiles = (try? await LearningProfileRepository.fetchProfiles(userId: userId)) ?? [:]
            vocabs = words
            apply(state)
            if mode == .home { await rebuildHome() }
            syncResidents(arrive: false)
        } catch {
            loadError = IslandRepository.message(error)
        }
        isLoading = false
    }

    func apply(_ state: IslandServerState) {
        server = state
        if let p = state.omni_points { UserDefaults.standard.set(p, forKey: "omni_reward_points") }
    }

    func rebuildHome() async {
        guard let state = server else { return }
        let layout = state.layout, night = night
        let built = await Task.detached(priority: .userInitiated) { () -> IslandScene in
            let home = IslandMaps.buildHome(layout)
            return IslandScene(map: home.map, night: night, lots: home.lots, locked: home.locked, walk: home.walk, portal: home.portal)
        }.value
        homeScene = built
        if mode == .home { scene = built }
    }

    func setNight(_ value: Bool) {
        guard value != night else { return }
        night = value
        Task {
            if mode == .home { await rebuildHome() } else if let run = stage { await showStageMap(run.region, run.index) }
        }
    }

    // MARK: - Residents

    func syncResidents(arrive: Bool) {
        guard let scene = homeScene, !scene.walk.isEmpty else { return }
        let learned = learnedVocabs, H = min(learned.count, capacity), now = Date()
        var want: [Int: Bool] = [:] // index → waiting
        for i in 0..<min(28, H) { want[i] = false }
        for (i, v) in learned.enumerated() where i < H && ReviewScheduler.isDue(v, now: now) { want[i] = false }
        if H < learned.count { for i in H..<min(learned.count, H + 6) { want[i] = true } }
        residents.removeAll { want[$0.id] == nil }
        for (i, waiting) in want {
            let v = learned[i], due = ReviewScheduler.isDue(v, now: now)
            if let k = residents.firstIndex(where: { $0.id == i }) { residents[k].waiting = waiting; residents[k].due = due; continue }
            let dock = scene.map.dock ?? scene.walk[0]
            let t = (arrive || waiting) ? dock : scene.walk[Int(hash(i, 3, 9) * Double(scene.walk.count)) % scene.walk.count]
            residents.append(IslandResident(id: i, vocab: v, walker: IslandWalker(x: Double(t.0 * TILE + 8), y: Double(t.1 * TILE + 14), wait: hash(i, 1, 1) * 2),
                                            hair: Self.hairs[i % Self.hairs.count], waiting: waiting, due: due))
        }
    }

    private func bfs(_ scene: IslandScene, _ from: (Int, Int), _ to: (Int, Int)) -> [(Int, Int)] {
        let M = scene.map, cols = M.cols
        var prev: [Int: Int] = [from.1 * cols + from.0: -1]; var q = [from]; var h = 0
        while h < q.count { let (x, y) = q[h]; h += 1
            if x == to.0 && y == to.1 { break }
            for (a, b) in N4 { let nx = x + a, ny = y + b, k = ny * cols + nx
                if !M.inb(nx, ny) || M.at(nx, ny) != Tile.p || prev[k] != nil { continue }
                prev[k] = y * cols + x; q.append((nx, ny)) } }
        guard prev[to.1 * cols + to.0] != nil else { return [] }
        var out: [(Int, Int)] = []; var c = to.1 * cols + to.0
        while c >= 0 { out.insert((c % cols, c / cols), at: 0); c = prev[c] ?? -1 }
        return out
    }
    private func nearestWalk(_ scene: IslandScene, _ x: Double, _ y: Double) -> (Int, Int) {
        scene.walk.min { abs(Double($0.0) - x) + abs(Double($0.1) - y) < abs(Double($1.0) - x) + abs(Double($1.1) - y) } ?? (0, 0)
    }
    private var clinicSpot: (Int, Int)? {
        guard let l = homeScene?.lots.first(where: { $0.building == "clinic" }) else { return nil }
        return (l.x + 1, l.y + 3)
    }

    // MARK: - Frame step

    func step(_ dt: Double) {
        guard let scene else { return }
        if mode == .home && scene === homeScene {
            for i in residents.indices where openResident?.id != residents[i].id { stepResident(&residents[i], scene, dt) }
        }
        stepPlayer(scene, dt)
        particles = particles.compactMap { p in
            var p = p; p.life -= dt; guard p.life > 0 else { return nil }
            p.x += p.vx * dt; p.y += p.vy * dt; p.vy += 30 * dt; return p
        }
    }

    private func stepResident(_ r: inout IslandResident, _ scene: IslandScene, _ dt: Double) {
        if !r.walker.path.isEmpty {
            let (tx, ty) = r.walker.path[0], gx = Double(tx * TILE + 8), gy = Double(ty * TILE + 14), dx = gx - r.walker.x, dy = gy - r.walker.y, d = hypot(dx, dy), sp = (r.due ? 14 : 24) * dt
            if d <= sp { r.walker.x = gx; r.walker.y = gy; r.walker.path.removeFirst(); if r.walker.path.isEmpty { r.walker.wait = 1 + Double.random(in: 0..<3) } }
            else { r.walker.x += dx / d * sp; r.walker.y += dy / d * sp }
            return
        }
        r.walker.wait -= dt
        if r.walker.wait > 0 { return }
        let cur = nearestWalk(scene, (r.walker.x - 8) / 16, (r.walker.y - 14) / 16)
        var goal: (Int, Int)
        if r.waiting, let dock = scene.map.dock { goal = (dock.0, dock.1 - Int.random(in: 0..<3)) }
        else if r.due, let c = clinicSpot { goal = nearestWalk(scene, Double(c.0 + Int.random(in: -1...1)), Double(c.1 + 1)) }
        else { goal = scene.walk[Int.random(in: 0..<scene.walk.count)] }
        r.walker.path = Array(bfs(scene, cur, goal).prefix(18))
        if r.waiting { r.walker.wait = 2 }
    }

    private func stepPlayer(_ scene: IslandScene, _ dt: Double) {
        guard !player.path.isEmpty else { return }
        let (tx, ty) = player.path[0], gx = Double(tx * TILE + 8), gy = Double(ty * TILE + 14), dx = gx - player.x, dy = gy - player.y, d = hypot(dx, dy), sp = 130 * dt
        if d > sp { player.x += dx / d * sp; player.y += dy / d * sp; return }
        player.x = gx; player.y = gy; player.path.removeFirst()
        guard player.path.isEmpty else { return }
        let then = playerThen; playerThen = nil
        then?()
    }

    // MARK: - Walking and tapping

    func walkTo(_ goal: (Int, Int), then: (() -> Void)?) {
        guard let scene else { return }
        var (gx, gy) = goal
        if !scene.walkable(gx, gy) {
            var best: (Int, Int, Int)?
            for j in -2...2 { for i in -2...2 where scene.walkable(gx + i, gy + j) { let d = abs(i) + abs(j); if best == nil || d < best!.2 { best = (gx + i, gy + j, d) } } }
            guard let best else { showToast("Chỗ này không đi tới được"); return }
            gx = best.0; gy = best.1
        }
        let from = (Int(player.x / 16), Int((player.y - 1) / 16))
        if from.0 == gx && from.1 == gy { player.path = []; then?(); return }
        let M = scene.map, cols = M.cols
        var prev: [Int: Int] = [from.1 * cols + from.0: -1]; var q = [from]; var h = 0; var found = false
        while h < q.count && !found { let (x, y) = q[h]; h += 1
            for (a, b) in N4 { let nx = x + a, ny = y + b, k = ny * cols + nx
                if prev[k] != nil || !scene.walkable(nx, ny) { continue }
                prev[k] = y * cols + x
                if nx == gx && ny == gy { found = true; break }
                q.append((nx, ny)) } }
        guard found else { showToast("Chỗ này không đi tới được"); return }
        var path: [(Int, Int)] = []; var c = gy * cols + gx
        while c >= 0 { path.insert((c % cols, c / cols), at: 0); c = prev[c] ?? -1 }
        path.removeFirst()
        player.path = path; playerThen = then; follow = true
    }

    /// A tap on the map at world pixel (wx, wy).
    func tap(wx: Double, wy: Double) {
        guard let scene else { return }
        if mode == .stage { stageTap(wx, wy); return }
        if let r = residents.sorted(by: { $0.walker.y > $1.walker.y }).first(where: { wx > $0.walker.x - 7 && wx < $0.walker.x + 7 && wy > $0.walker.y - ($0.due ? 40 : 26) && wy < $0.walker.y + 3 }) {
            openResident = r; return
        }
        let tx = Int((wx / 16).rounded(.down)), ty = Int((wy / 16).rounded(.down))
        if let L = scene.locked.first(where: { $0.set.contains(ty * scene.map.cols + tx) }) { openRegion = L.region; return }
        if let l = scene.lots.first(where: { tx >= $0.x && tx < $0.x + $0.w && ty >= $0.y - 1 && ty < $0.y + $0.h }) {
            walkTo((l.x + 1, l.y + l.h)) { [weak self] in self?.openLotOrBuilding(l) }; return
        }
        if ty >= 12 + OY && ty <= 14 + OY && tx >= 19 + OX && tx <= 22 + OX, let p = scene.portal {
            walkTo(p) { [weak self] in self?.showToast("Cổng phiêu lưu: bấm nút Phiêu lưu để đi tiếp màn") }; return
        }
        walkTo((tx, ty), then: nil)
    }

    func openLotOrBuilding(_ l: IslandLot) {
        guard let b = l.building else { openLot = l; return }
        if b == "lab" { labWord = nil; showLab = true; return }
        openBuilding = l
    }

    func showToast(_ text: String) {
        toast = text
        let shown = text
        Task { try? await Task.sleep(for: .seconds(2.6)); if toast == shown { toast = nil } }
    }

    func burst(_ x: Double, _ y: Double, _ n: Int, _ colors: [UInt32] = [0xffcf3a, 0xffffff, 0xff6b8a, 0x7be56b, 0xb38bff]) {
        for k in 0..<n { particles.append(IslandParticle(x: x, y: y, vx: Double.random(in: -45...45), vy: -30 - Double.random(in: 0...60), life: 0.8 + Double.random(in: 0...0.6), color: colors[k % colors.count])) }
    }

    // MARK: - Building and buying

    func build(_ lot: IslandLot, _ kind: IslandBuildingKind) async {
        busy = true; defer { busy = false }
        do {
            let state = try await IslandRepository.build(lot: lot.key, building: kind.key)
            openLot = nil
            apply(state)
            await rebuildHome()
            syncResidents(arrive: false)
            burst(Double(lot.x * 16 + lot.w * 8), Double(lot.y * 16 + 16), 40)
            showToast("Đã xây xong \(kind.name)!")
        } catch { showToast(IslandRepository.message(error)) }
    }

    func buy(_ region: IslandRegion) async {
        busy = true; defer { busy = false }
        do {
            let state = try await IslandRepository.openRegion(region.id)
            openRegion = nil
            apply(state)
            await rebuildHome()
            let (x, y, w, h) = (region.rect[0], region.rect[1], region.rect[2], region.rect[3])
            cameraTarget = (Double((x + w / 2) * 16), Double((y + h / 2) * 16), max(currentCamera.zoom, 1), UUID())
            for _ in 0..<6 { burst(Double(x * 16) + Double.random(in: 0...Double(w * 16)), Double(y * 16) + Double.random(in: 0...Double(h * 16)), 20, [0xf5dea2, 0x8fd16a, 0xffffff, 0xffcf3a]) }
            showToast("\(region.name) đã nổi lên!")
        } catch { showToast(IslandRepository.message(error)) }
    }

    /// Point the camera at a free lot and pulse it.
    func showEmptyLot() {
        guard let l = scene?.lots.first(where: { $0.building == nil }) else { showToast("Hết ô đất trống. Mở thêm vùng đất ven biển nhé."); return }
        cameraTarget = (Double(l.x * 16 + l.w * 8), Double(l.y * 16 + l.h * 8), max(currentCamera.zoom, 2), UUID())
        pulseLot = (l, Date().addingTimeInterval(3.5))
        showToast("Bấm vào ô đất để xây Nhà ở")
    }

    func findResident(_ vocabID: String) {
        guard let r = residents.first(where: { $0.vocab.id == vocabID }) else {
            showToast("Cư dân này đang ở trong nhà"); return
        }
        showLab = false
        cameraTarget = (r.walker.x, r.walker.y, max(currentCamera.zoom, 2.2), UUID())
    }

    // MARK: - Reviewing from the island

    func review(_ words: [Vocabulary]) {
        let picked = words.filter { ReviewScheduler.isDue($0, now: Date()) }
        guard !picked.isEmpty else { showToast("Từ này chưa tới hạn ôn"); return }
        guard OmniLearningHeartManager.shared.canStudy else { showToast("Bạn đã hết lượt học hôm nay"); return }
        let plan = AdaptiveSessionBuilder.build(selected: picked, distractorPool: vocabs, profiles: profiles, isExtra: OmniLearningHeartManager.shared.isExtra)
        guard !plan.tasks.isEmpty else { showToast("Không thể tạo bài ôn từ dữ liệu hiện có"); return }
        reviewSession = ActiveLearningSession(id: UUID(), tasks: plan.tasks, groups: plan.selectedGroups, reasons: plan.reasons)
    }

    // MARK: - Adventure stages

    func progress(_ region: AdventureRegion) -> Int { server?.progress[region.key] ?? 0 }
    func isOpen(_ region: AdventureRegion) -> Bool { learnedCount >= region.need }

    private func showStageMap(_ region: AdventureRegion, _ index: Int) async {
        let night = night
        let built = await Task.detached(priority: .userInitiated) { IslandScene(map: region.map(index), night: night) }.value
        if mode == .stage { scene = built }
    }

    func enterStage(_ region: AdventureRegion, _ index: Int, words: [Vocabulary]) async {
        guard OmniLearningHeartManager.shared.canStudy else { showToast("Bạn đã hết lượt học hôm nay"); return }
        let plan = AdaptiveSessionBuilder.build(selected: words, distractorPool: vocabs, profiles: profiles, isExtra: OmniLearningHeartManager.shared.isExtra)
        guard !plan.tasks.isEmpty else { showToast("Không thể tạo nhiệm vụ từ các từ này"); return }
        busy = true; defer { busy = false }
        let night = night
        let built = await Task.detached(priority: .userInitiated) { IslandScene(map: region.map(index), night: night) }.value
        homeCamera = currentCamera
        let spots = built.map.quests
        let n = max(1, min(spots.count, plan.tasks.count))
        var quests = (0..<n).map { StageRun.Quest(act: spots[$0].act, x: spots[$0].x, y: spots[$0].y, remaining: 0) }
        for k in 0..<plan.tasks.count { quests[k % n].remaining += 1 }
        stage = StageRun(region: region, index: index, words: words,
                         session: ActiveLearningSession(id: UUID(), tasks: plan.tasks, groups: plan.selectedGroups, reasons: plan.reasons),
                         initialTaskCount: plan.tasks.count, quests: quests, total: plan.tasks.count)
        mode = .stage
        scene = built
        var start = built.map.dock.map { ($0.0, $0.1 - 1) } ?? (15, 20)
        while !built.walkable(start.0, start.1) && start.1 > 2 { start.1 -= 1 }
        player = IslandWalker(x: Double(start.0 * 16 + 8), y: Double(start.1 * 16 + 14))
        cameraTarget = (player.x, player.y - 40, 1.6, UUID())
        showToast("\(region.name) · Màn \(index + 1): \(quests.count) nhiệm vụ")
    }

    func leaveStage() {
        stage = nil; questVisible = false; questMounted = false; stageClear = nil
        mode = .home
        scene = homeScene
        player = IslandWalker(x: Double((9 + OX) * TILE + 8), y: Double((11 + OY) * TILE + 14))
        if let c = homeCamera { cameraTarget = (c.x, c.y, c.zoom, UUID()) }
        Task { await load() }
    }

    private func stageTap(_ wx: Double, _ wy: Double) {
        guard let run = stage else { return }
        let tx = Int((wx / 16).rounded(.down)), ty = Int((wy / 16).rounded(.down))
        if let k = run.quests.firstIndex(where: { $0.remaining > 0 && $0.x == tx && ty >= $0.y - 2 && ty <= $0.y }) { goQuest(k); return }
        walkTo((tx, ty), then: nil)
    }

    func nextQuest() {
        guard let run = stage else { return }
        let open = run.quests.enumerated().filter { $0.element.remaining > 0 }
        guard let k = open.min(by: { hypot(Double($0.element.x * 16) - player.x, Double($0.element.y * 16) - player.y) < hypot(Double($1.element.x * 16) - player.x, Double($1.element.y * 16) - player.y) })?.offset else { return }
        goQuest(k)
    }

    private func goQuest(_ k: Int) {
        guard let run = stage, let scene else { return }
        let q = run.quests[k]
        let open = { [weak self] in self?.stage?.activeQuest = k; self?.questMounted = true; self?.questVisible = true }
        if let best = [(0, 1), (1, 0), (-1, 0), (0, -1), (1, 1), (-1, 1)].first(where: { scene.walkable(q.x + $0.0, q.y + $0.1) }) {
            walkTo((q.x + best.0, q.y + best.1), then: open)
        } else { open() }
    }

    /// The session answered one more question (not the last).
    func questStepped(answered: Int, total: Int) {
        guard var run = stage else { return }
        questVisible = false
        if let k = run.activeQuest {
            run.quests[k].remaining = max(0, run.quests[k].remaining - 1)
            let left = total - answered, assigned = run.quests.reduce(0) { $0 + $1.remaining }
            if left > assigned { run.quests[k].remaining += left - assigned }
            if run.quests[k].remaining == 0 { burst(Double(run.quests[k].x * 16 + 8), Double(run.quests[k].y * 16), 26); showToast("Xong nhiệm vụ · còn \(run.quests.filter { $0.remaining > 0 }.count)") }
        }
        run.answered = answered; run.total = total; run.activeQuest = nil
        stage = run
    }

    /// The server saved the session; pay the stage.
    func stageSettled(_ result: VocabularyLearningSettlementResult) {
        guard var run = stage else { return }
        for k in run.quests.indices { run.quests[k].remaining = 0 }
        run.settled = result
        stage = run
        Task {
            do {
                let state = try await IslandRepository.completeStage(sessionID: run.session.id, region: run.region.key, stage: run.index, quests: run.initialTaskCount)
                apply(state)
                stageClear = (state.earned ?? 0, result.earned_points)
            } catch {
                stageClear = (0, result.earned_points)
                showToast(IslandRepository.message(error))
            }
        }
    }
}
