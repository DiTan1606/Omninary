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

/// What a finished adventure earned, for the result card.
struct AdventureClear {
    let earned: Int
    let sessionPoints: Int
    /// Questions answered right at the first try, out of the planned ones.
    let firstTry: Int
    let planned: Int
    let retryQuests: Int
    /// Words that needed a retry: they come back sooner.
    let weak: [String]
    let mapBefore: Int
    let wordsBefore: Int
    let gained: Int
    let collected: Int?
    /// Words learned in this adventure.
    let words: Int
    /// Levels (adventures of 5 words) done on the map before and after this one, out of 6.
    var levelBefore: Int { min(6, wordsBefore / 5) }
    var levelAfter: Int { collected != nil ? 6 : min(6, (wordsBefore + gained) / 5) }
}

struct IslandParticle { var x, y, vx, vy, life: Double; let color: UInt32 }

/// An adventure being played: its map, the quests on it and the learning session behind them.
/// Quests are groups of questions (`planned`, then retries five at a time), each at one spot.
struct StageRun {
    let region: AdventureRegion
    let index: Int
    let words: [Vocabulary]
    let session: ActiveLearningSession
    let planned: [Int]
    let spots: [Spot]
    /// Progress saved at the last finished quest, handed to the session when it mounts.
    var resume: LearningQuestProgress?
    var answered = 0
    var total: Int
    var settled: VocabularyLearningSettlementResult?

    struct Spot { let act: String; let x: Int; let y: Int }
    var ends: [Int] { AdventureQuests.ends(planned: planned, total: total) }
    var questCount: Int { ends.count }
    var doneQuests: Int { settled != nil ? questCount : AdventureQuests.done(answered: answered, ends: ends) }
    var activeQuest: Int? { doneQuests < questCount ? doneQuests : nil }
    func spot(_ k: Int) -> Spot { spots[k % max(1, spots.count)] }
    /// Questions of quest `k` as the session stands now.
    func tasks(of k: Int) -> ArraySlice<LearningTask> {
        let all = resume?.tasks ?? session.tasks, ends = AdventureQuests.ends(planned: planned, total: all.count)
        guard k < ends.count else { return [] }
        return all[(k == 0 ? 0 : ends[k - 1])..<ends[k]]
    }
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
    /// The quest whose card (NPC, line, exercise types) is open on the stage map.
    @Published var questCard: Int?
    @Published var stageClear: AdventureClear?
    /// A collected map opened for a free walk (no quests).
    @Published var freeMap: Int?
    /// The map just finished: the path sails the boat from it to the next one.
    @Published var sailFrom: Int?
    /// The cloud curtain of a scene change is closed over the screen.
    @Published var curtainClosed = false
    /// Size of the map view, to fit the stage island on screen.
    var viewSize = CGSize(width: 390, height: 844)
    /// The next camera move eases instead of jumping (the zoom down onto a stage).
    var cameraAnimated = false

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
    var dueVocabs: [Vocabulary] { learnedVocabs.filter { ReviewScheduler.isDue($0, now: Date()) } }
    var conquest: AdventureConquest { server?.conquest ?? AdventureConquest(map: 0, words: 0) }
    var omni: Int { server?.omni_points ?? UserDefaults.standard.integer(forKey: "omni_reward_points") }

    // MARK: - Loading

    func load() async {
        isLoading = server == nil
        loadError = nil
        do {
            guard let userId = AuthManager.shared.currentUser?.id.uuidString else { throw NSError(domain: "Island", code: 401, userInfo: [NSLocalizedDescriptionKey: "Bạn cần đăng nhập."]) }
            async let st = IslandRepository.fetchState()
            async let vs = VocabularyRepository.fetchUserVocabs(userId: userId)
            let (state, words) = try await (st, vs)
            profiles = (try? await LearningProfileRepository.fetchProfiles(userId: userId)) ?? [:]
            vocabs = words
            apply(state)
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
            if mode == .stage, let run = stage { await showStageMap(run.region, run.index) }
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

    /// Walks to `goal`, or to the reachable tile nearest it within `reach` tiles. The search starts
    /// from the player and keeps every tile it can get to, so a spot next to the goal that is
    /// walkable but cut off (behind a cliff or a fence) never stops the walk.
    func walkTo(_ goal: (Int, Int), within reach: Int = 2, then: (() -> Void)?) {
        guard let scene else { return }
        let cols = scene.map.cols
        let from = (Int(player.x / 16), Int((player.y - 1) / 16)), start = from.1 * cols + from.0
        func score(_ x: Int, _ y: Int) -> Int? {
            let dx = abs(x - goal.0), dy = abs(y - goal.1)
            return max(dx, dy) <= reach ? max(dx, dy) * 100 + dx + dy : nil
        }
        var prev: [Int: Int] = [start: -1], q = [from], h = 0
        var best: (key: Int, score: Int)? = score(from.0, from.1).map { (start, $0) }
        while h < q.count {
            let (x, y) = q[h]; h += 1
            for (a, b) in N4 {
                let nx = x + a, ny = y + b
                guard scene.walkable(nx, ny) else { continue }
                let k = ny * cols + nx
                if prev[k] != nil { continue }
                prev[k] = y * cols + x
                q.append((nx, ny))
                if let s = score(nx, ny), best == nil || s < best!.score { best = (k, s) }
            }
        }
        guard let best else { showToast("Chỗ này không đi tới được"); return }
        if best.key == start { player.path = []; then?(); return }
        var path: [(Int, Int)] = []; var c = best.key
        while c >= 0 && c != start { path.insert((c % cols, c / cols), at: 0); c = prev[c] ?? -1 }
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

    private func showStageMap(_ region: AdventureRegion, _ index: Int) async {
        let night = night
        let built = await Task.detached(priority: .userInitiated) { IslandScene(map: region.map(index), night: night) }.value
        if mode == .stage { scene = built }
    }

    /// The island stays still in the middle of the screen at 90% of its width; the camera
    /// starts close above it and eases down to that framing.
    func zoomOnto(_ crop: CGRect) {
        let top = 130.0, bottom = 160.0, w = Double(viewSize.width), h = Double(viewSize.height)
        let avail = h - top - bottom
        let z = min(0.9 * w / Double(crop.width), avail / Double(crop.height))
        let cx = Double(crop.midX), cy = Double(crop.midY) - (top + avail / 2 - h / 2) / z
        cameraAnimated = false
        cameraTarget = (cx, Double(crop.minY) + Double(crop.height) * 0.2, z * 2.4, UUID())
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            cameraAnimated = true
            cameraTarget = (cx, cy, z, UUID())
        }
    }

    /// Clouds close from both sides, the scene changes behind them, then they open.
    func curtain(_ change: @MainActor () async -> Void) async {
        curtainClosed = true
        try? await Task.sleep(for: .milliseconds(650))
        await change()
        try? await Task.sleep(for: .milliseconds(150))
        curtainClosed = false
    }

    /// PHIÊU LƯU or the current level's flag: into the stage behind the clouds.
    func play() {
        guard !curtainClosed, sailFrom == nil else { return }
        Task { await curtain { await startAdventure() } }
    }

    /// Back to the path behind the clouds; a finished island sends the boat on.
    func backToPath() {
        let collected = stageClear?.collected
        Task {
            // set before the path appears, so it opens on the finished island for the boat to sail
            // from instead of first jumping to the new current one
            await curtain { sailFrom = collected; leaveStage() }
        }
    }

    /// Phiêu lưu: carry on with the saved adventure, or start one on the current stage with
    /// the five most urgent words (due first, then new ones).
    func startAdventure() async {
        let saved = AdventureStore.load(userID: AuthManager.shared.currentUser?.id.uuidString)
        if let saved, let region = AdventureRegion.all.first(where: { $0.key == saved.region }) {
            let known = Set(vocabs.compactMap(\.id))
            if saved.words.allSatisfy({ $0.id.map(known.contains) ?? false }) {
                await enterStage(region, saved.stage, words: saved.words, saved: saved)
                return
            }
            AdventureStore.clear()
        }
        let words = adventureWords()
        guard !words.isEmpty else { showToast("Hôm nay chưa có từ tới hạn hay từ mới để ôn"); return }
        let map = min(AdventureMaps.count - 1, conquest.map)
        await enterStage(AdventureMaps.region(map), AdventureMaps.stage(map), words: words)
    }

    func adventureWords() -> [Vocabulary] {
        let count = AdventureQuests.wordCount(isExtra: OmniLearningHeartManager.shared.isExtra)
        let candidates = ReviewPriority.candidates(from: vocabs, profiles: profiles, now: Date())
        let due = (candidates.filter { !$0.isNew } + candidates.filter { $0.isNew }).map(\.vocabulary)
        // An adventure needs at least one word to settle; without any due or new word there is nothing to learn.
        guard !due.isEmpty else { return [] }
        var picked = Array(due.prefix(count))
        // A level always has its full count of words: when fewer are due, the learned words whose
        // review comes soonest fill it as extra practice (only due words are scored and rescheduled).
        if picked.count < count {
            var seen = Set(picked.compactMap(\.id))
            let soonest = vocabs
                .filter { ($0.learning_level ?? 0) > 0 }
                .sorted { ($0.next_review.flatMap(ReviewDates.parse) ?? .distantFuture) < ($1.next_review.flatMap(ReviewDates.parse) ?? .distantFuture) }
            for v in soonest where picked.count < count {
                guard let id = v.id, seen.insert(id).inserted else { continue }
                picked.append(v)
            }
        }
        return picked
    }

    func enterStage(_ region: AdventureRegion, _ index: Int, words: [Vocabulary], saved: AdventureSave? = nil) async {
        guard OmniLearningHeartManager.shared.canStudy else { showToast("Bạn đã hết lượt học hôm nay"); return }
        let session: ActiveLearningSession, planned: [Int]
        if let saved, let progress = saved.progress {
            session = ActiveLearningSession(id: saved.sessionID, tasks: progress.tasks, groups: saved.words.map { [$0] }, reasons: saved.reasons)
            planned = saved.planned
        } else {
            let plan = AdaptiveSessionBuilder.buildAdventure(selected: words, distractorPool: vocabs, profiles: profiles, isExtra: OmniLearningHeartManager.shared.isExtra)
            guard !plan.tasks.isEmpty else { showToast("Không thể tạo nhiệm vụ từ các từ này"); return }
            session = ActiveLearningSession(id: saved?.sessionID ?? UUID(), tasks: plan.tasks, groups: plan.selectedGroups, reasons: plan.reasons)
            planned = plan.questSizes
            if let userID = AuthManager.shared.currentUser?.id.uuidString {
                AdventureStore.save(AdventureSave(userID: userID, sessionID: session.id, region: region.key, stage: index,
                                                  words: plan.selectedGroups.flatMap { $0 }, planned: planned, reasons: plan.reasons))
            }
        }
        busy = true; defer { busy = false }
        let night = night
        let built = await Task.detached(priority: .userInitiated) { IslandScene(map: region.map(index), night: night) }.value
        if mode == .home { homeCamera = currentCamera }
        questVisible = false; questMounted = false; questCard = nil; stageClear = nil; freeMap = nil
        let progress = saved?.progress
        stage = StageRun(region: region, index: index, words: session.groups.flatMap { $0 }, session: session, planned: planned,
                         spots: built.map.quests.map { StageRun.Spot(act: $0.act, x: $0.x, y: $0.y) },
                         resume: progress, answered: progress?.answered ?? 0, total: progress?.tasks.count ?? session.tasks.count)
        mode = .stage
        scene = built
        var start = built.map.dock.map { ($0.0, $0.1 - 1) } ?? (15, 20)
        while !built.walkable(start.0, start.1) && start.1 > 2 { start.1 -= 1 }
        player = IslandWalker(x: Double(start.0 * 16 + 8), y: Double(start.1 * 16 + 14))
        let art = await Task.detached(priority: .userInitiated) { IslandArt.isle(AdventureMaps.index(region, index)) }.value
        zoomOnto(art.crop)
        if let run = stage {
            showToast(run.doneQuests > 0 ? "Làm tiếp từ nhiệm vụ \(run.doneQuests + 1)/\(run.questCount)" : "\(region.name) · \(run.questCount) nhiệm vụ")
        }
    }

    /// Leave the stage; an unfinished adventure stays saved for the next Phiêu lưu.
    func leaveStage() {
        stage = nil; questVisible = false; questMounted = false; questCard = nil; stageClear = nil; freeMap = nil
        mode = .home
        scene = homeScene
        player = IslandWalker(x: Double((9 + OX) * TILE + 8), y: Double((11 + OY) * TILE + 14))
        if let c = homeCamera { cameraTarget = (c.x, c.y, c.zoom, UUID()) }
        Task { await load() }
    }

    /// Start over with other words: only before any question is answered.
    func swapAdventureWords(_ words: [Vocabulary]) async {
        guard let run = stage, run.answered == 0 else { return }
        AdventureStore.clear()
        await enterStage(run.region, run.index, words: words)
    }

    /// Tapping the open quest shows its card right away; any other tap walks there,
    /// and stopping next to the open quest shows its card too.
    private func stageTap(_ wx: Double, _ wy: Double) {
        guard questCard == nil else { return }
        let tx = Int((wx / 16).rounded(.down)), ty = Int((wy / 16).rounded(.down))
        guard let run = stage else { walkTo((tx, ty), then: nil); return }
        if let k = run.activeQuest {
            let q = run.spot(k)
            if q.x == tx && ty >= q.y - 2 && ty <= q.y { questCard = k; return }
        }
        walkTo((tx, ty)) { [weak self] in self?.cardIfNearActiveQuest() }
    }

    private func cardIfNearActiveQuest() {
        guard let run = stage, let k = run.activeQuest else { return }
        let q = run.spot(k)
        let px = Int((player.x / 16).rounded(.down)), py = Int((player.y / 16).rounded(.down))
        if abs(px - q.x) <= 1 && abs(py - q.y) <= 1 { questCard = k }
    }

    /// "Đi tới": walk to the open quest, then show its card.
    func nextQuest() {
        guard let run = stage, let k = run.activeQuest else { return }
        let q = run.spot(k)
        // Next to the quest if any side of it can be reached, else as close as the paths allow.
        walkTo((q.x, q.y), within: 3) { [weak self] in self?.questCard = k }
    }

    /// The card's "Làm nhiệm vụ": show the session for this quest's questions.
    func playQuest() {
        questCard = nil
        questMounted = true
        questVisible = true
    }

    /// The session finished a quest that is not the last: save, mark it done on the map.
    func questStepped(_ progress: LearningQuestProgress) {
        guard var run = stage else { return }
        questVisible = false
        let finished = run.doneQuests
        run.resume = progress; run.answered = progress.answered; run.total = progress.tasks.count
        stage = run
        if var saved = AdventureStore.load(userID: AuthManager.shared.currentUser?.id.uuidString), saved.sessionID == run.session.id {
            saved.progress = progress
            AdventureStore.save(saved)
        }
        let q = run.spot(finished)
        burst(Double(q.x * 16 + 8), Double(q.y * 16), 26)
        showToast("Xong nhiệm vụ \(finished + 1) · còn \(run.questCount - run.doneQuests)")
    }

    /// The server saved the session: pay the adventure and add its words to the map.
    func stageSettled(_ result: VocabularyLearningSettlementResult, _ progress: LearningQuestProgress) {
        guard var run = stage else { return }
        AdventureStore.clear()
        run.settled = result
        stage = run
        let planned = run.planned.reduce(0, +)
        let first = progress.attempts.filter { $0.attempt_number == 1 }
        let names = Dictionary(run.words.compactMap { v in v.id.map { ($0, v.vocab ?? "") } }, uniquingKeysWith: { a, _ in a })
        let weak = Set(first.filter { !$0.is_correct }.flatMap(\.user_vocabulary_ids)).compactMap { names[$0] }.sorted()
        let before = conquest
        Task {
            var state: IslandServerState?
            do { state = try await IslandRepository.complete(sessionID: run.session.id, words: run.words.count, quests: planned) }
            catch { showToast(IslandRepository.message(error)) }
            if let state { apply(state) }
            stageClear = AdventureClear(
                earned: state?.earned ?? 0, sessionPoints: result.earned_points,
                firstTry: min(planned, first.filter(\.is_correct).count), planned: planned,
                retryQuests: max(0, run.questCount - run.planned.count), weak: weak,
                mapBefore: state?.map_before ?? before.map, wordsBefore: state?.words_before ?? before.words,
                gained: state?.gained ?? 0, collected: state?.collected, words: run.words.count)
        }
    }

    /// Walk around a collected map: no quests, just the place.
    func playFree(_ map: Int) async {
        let night = night, region = AdventureMaps.region(map), index = AdventureMaps.stage(map)
        busy = true; defer { busy = false }
        let built = await Task.detached(priority: .userInitiated) { IslandScene(map: region.map(index), night: night) }.value
        if mode == .home { homeCamera = currentCamera }
        stage = nil; questCard = nil; stageClear = nil
        freeMap = map
        mode = .stage
        scene = built
        var start = built.map.dock.map { ($0.0, $0.1 - 1) } ?? (15, 20)
        while !built.walkable(start.0, start.1) && start.1 > 2 { start.1 -= 1 }
        player = IslandWalker(x: Double(start.0 * 16 + 8), y: Double(start.1 * 16 + 14))
        let art = await Task.detached(priority: .userInitiated) { IslandArt.isle(map) }.value
        zoomOnto(art.crop)
    }

    /// A conquered island on the path: into it behind the clouds, to walk around freely.
    func visit(_ map: Int) {
        guard !curtainClosed, sailFrom == nil else { return }
        Task { await curtain { await playFree(map) } }
    }
}
