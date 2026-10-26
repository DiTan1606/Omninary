import Foundation

// The home island (with its two rings of regions to buy) and one generated island per adventure stage.

// MARK: - Buildings catalogue (prices in Omni must match island_build on the server)

struct IslandBuildingKind {
    let key: String, name: String, kind: String, w: Int, h: Int
    var cost = 0, capacity = 0, need = 0
    var fixed = false
    var roof: UInt32? = nil, wall: UInt32? = nil, mine = false, sign: String? = nil
    let desc: String
}

enum IslandCatalog {
    static let all: [IslandBuildingKind] = [
        .init(key: "home", name: "Nhà ở", kind: "house", w: 3, h: 2, cost: 200, capacity: 16, desc: "Chỗ ở cho 16 cư dân. Từ mới học xong cần có nhà mới dọn vào được."),
        .init(key: "fountain", name: "Đài phun nước", kind: "fountain", w: 3, h: 3, cost: 200, desc: "Trang trí. Cư dân hay tụ tập quanh đây."),
        .init(key: "windmill", name: "Cối xay gió", kind: "windmill", w: 2, h: 3, cost: 150, desc: "Trang trí, quay đều cả ngày."),
        .init(key: "bakery", name: "Tiệm bánh", kind: "bakery", w: 3, h: 3, cost: 300, desc: "Mùi bánh mới nướng mỗi sáng làm cả đảo vui hơn."),
        .init(key: "cafe", name: "Quán cà phê", kind: "cafe", w: 3, h: 3, cost: 500, wall: 0xf2d17c, desc: "Góc ngồi ôn bài quen thuộc của cư dân."),
        .init(key: "greenhouse", name: "Nhà kính", kind: "greenhouse", w: 3, h: 2, cost: 500, desc: "Trồng thảo dược và hoa quanh năm."),
        .init(key: "school", name: "Trường học", kind: "school", w: 3, h: 3, cost: 800, desc: "Ngôi trường có tháp chuông cho cả đảo."),
        .init(key: "library", name: "Thư viện", kind: "bookstore", w: 3, h: 3, cost: 800, wall: 0xc7b6e8, desc: "Nơi cất giữ sách và thẻ từ của đảo."),
        .init(key: "pagoda", name: "Chùa ba tầng", kind: "pagoda", w: 3, h: 3, cost: 1500, need: 100, desc: "Dựng được khi đã học 100 từ."),
        .init(key: "statue", name: "Tượng vàng", kind: "statue", w: 1, h: 2, cost: 2000, need: 200, desc: "Dựng được khi đã học 200 từ. Ai ghé đảo cũng thấy."),
        .init(key: "myhouse", name: "Nhà của bạn", kind: "house", w: 3, h: 3, capacity: 6, fixed: true, roof: 0xd9534f, mine: true, desc: "Nhà của bạn trên đảo, có chỗ cho 6 cư dân."),
        .init(key: "shop", name: "Cửa hàng Cô Mai", kind: "house", w: 3, h: 3, fixed: true, roof: 0x8e5bd6, wall: 0xfff3df, sign: "bag", desc: "Vật phẩm mua bằng điểm Omni nằm ở My Omni."),
        .init(key: "lab", name: "Nhà nghiên cứu", kind: "lab", w: 3, h: 3, fixed: true, desc: "Xem tiến độ, lịch ôn của bạn, cách Extra tối ưu nó và bộ thẻ từ."),
        .init(key: "clinic", name: "Trạm xá", kind: "hospital", w: 3, h: 3, fixed: true, desc: "Cư dân có từ tới hạn ôn sẽ tới đây chờ bạn.")
    ]
    static let byKey: [String: IslandBuildingKind] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    static var buildable: [IslandBuildingKind] { all.filter { !$0.fixed } }
}

// MARK: - Regions to buy around the home island

let OX = 30, OY = 29
let ISLAND_CENTER = (22 + OX, 28 + OY)

final class IslandRegion: Identifiable {
    let id: String, name: String, layer: Int, theme: String
    let parent: String?, needs: [String]
    let rects: [[Int]]
    let rect: [Int]
    let isJoin: Bool
    var cost: Int { layer == 1 ? 800 : 1500 }
    private(set) var cuts: [[Int]] = []
    private(set) var center: (Int, Int) = (0, 0)

    init(id: String, name: String, layer: Int, theme: String, parent: String?, needs: [String], rects: [[Int]], isJoin: Bool) {
        self.id = id; self.name = name; self.layer = layer; self.theme = theme; self.parent = parent; self.needs = needs; self.rects = rects; self.isJoin = isJoin
        let x0 = rects.map { $0[0] }.min()!, y0 = rects.map { $0[1] }.min()!, x1 = rects.map { $0[0] + $0[2] }.max()!, y1 = rects.map { $0[1] + $0[3] }.max()!
        rect = [x0, y0, x1 - x0, y1 - y0]
        makeCuts()
        var sx = 0, sy = 0, n = 0
        for j in rect[1]..<(rect[1] + rect[3]) { for i in rect[0]..<(rect[0] + rect[2]) where has(i, j) { sx += i; sy += j; n += 1 } }
        center = (jsRound(Double(sx) / Double(max(1, n))), jsRound(Double(sy) / Double(max(1, n))))
    }

    /// Bitten corners and notches, never on the side that faces the island.
    private func makeCuts() {
        var cuts: [[Int]] = []
        if isJoin {
            let ch = Int(id.unicodeScalars.dropFirst().first?.value ?? 0)
            var R2 = Rng32(ch * 53)
            for r in rects where R2() < 0.7 {
                let (x, y, w, h) = (r[0], r[1], r[2], r[3]), s = 2 + Int((R2() * 3).rounded(.down))
                cuts.append([R2() < 0.5 ? x : x + w - s, R2() < 0.5 ? y : y + h - s, s, s])
            }
        } else {
            let ch = Int(id.unicodeScalars.first?.value ?? 0)
            var R2 = Rng32(ch * 131 + layer * 7)
            let (x, y, w, h) = (rect[0], rect[1], rect[2], rect[3]), cx = Double(x) + Double(w) / 2, cy = Double(y) + Double(h) / 2
            let ic = (Double(ISLAND_CENTER.0), Double(ISLAND_CENTER.1))
            let toward = abs(ic.0 - cx) > abs(ic.1 - cy) ? (ic.0 < cx ? "L" : "R") : (ic.1 < cy ? "T" : "B")
            for (v, hz) in [("T", "L"), ("T", "R"), ("B", "L"), ("B", "R")] {
                if v == toward || hz == toward { continue }
                let s = 2 + Int((R2() * 4).rounded(.down))
                cuts.append([hz == "L" ? x : x + w - s, v == "T" ? y : y + h - s, s, s])
            }
            for s in ["T", "B", "L", "R"] where s != toward {
                if R2() < 0.35 { continue }
                let d = 1 + Int((R2() * 3).rounded(.down)), len = 3 + Int((R2() * 4).rounded(.down))
                if s == "T" || s == "B" { let a = x + 3 + Int((R2() * Double(w - len - 6)).rounded(.down)); cuts.append([a, s == "T" ? y : y + h - d, len, d]) }
                else { let a = y + 3 + Int((R2() * Double(h - len - 6)).rounded(.down)); cuts.append([s == "L" ? x : x + w - d, a, d, len]) }
            }
        }
        self.cuts = cuts
    }

    func has(_ i: Int, _ j: Int) -> Bool {
        rects.contains { i >= $0[0] && i < $0[0] + $0[2] && j >= $0[1] && j < $0[1] + $0[3] }
            && !cuts.contains { i >= $0[0] && i < $0[0] + $0[2] && j >= $0[1] && j < $0[1] + $0[3] }
    }

    static let all: [IslandRegion] = {
        func sh(_ r: [Int]) -> [Int] { [r[0] + OX, r[1] + OY, r[2], r[3]] }
        let layered: [(String, String, Int, String, [Int], String?)] = [
            ("A", "Đồi Bắc", 1, "meadow", [8, -9, 15, 17], nil), ("B", "Rừng Đông Bắc", 1, "forest", [35, -5, 16, 15], nil), ("C", "Bờ Đông", 1, "beach", [40, 14, 15, 16], nil), ("D", "Đồng Đông Nam", 1, "farm", [38, 31, 16, 16], nil),
            ("E", "Bãi Nam", 1, "beach", [15, 49, 17, 14], nil), ("F", "Đồng Tây", 1, "farm", [-11, 18, 16, 16], nil), ("G", "Rừng Tây Nam", 1, "forest", [-7, 35, 16, 15], nil), ("H", "Mũi Tây Bắc", 1, "meadow", [-10, 1, 16, 15], nil),
            ("A2", "Núi Sương", 2, "forest", [5, -25, 17, 17], "A"), ("B2", "Rừng Thông", 2, "forest", [50, -14, 16, 16], "B"), ("C2", "Đồi Gió", 2, "meadow", [54, 11, 15, 17], "C"), ("D2", "Bãi Ngọc", 2, "beach", [52, 40, 16, 15], "D"),
            ("E2", "Mũi Cực Nam", 2, "beach", [14, 62, 17, 15], "E"), ("F2", "Thảo Nguyên", 2, "farm", [-26, 14, 16, 17], "F"), ("G2", "Đầm Lau", 2, "meadow", [-22, 44, 16, 15], "G"), ("H2", "Vách Đá", 2, "meadow", [-25, -6, 16, 15], "H")
        ]
        var out = layered.map { IslandRegion(id: $0.0, name: $0.1, layer: $0.2, theme: $0.3, parent: $0.5, needs: [], rects: [sh($0.4)], isJoin: false) }
        let joins: [(String, String, String, [[Int]], [String])] = [
            ("J1", "Thung Lũng Mây", "meadow", [[-10, -20, 16, 21]], ["A2", "H2"]), ("J2", "Đồi Trăng", "forest", [[22, -20, 15, 25], [37, -17, 13, 12]], ["A2", "B2"]),
            ("J3", "Bãi Cỏ Tây", "farm", [[-26, 31, 19, 13]], ["F2", "G2"]), ("J4", "Rừng Phong", "forest", [[-6, 50, 21, 22]], ["G2", "E2"]),
            ("J5", "Mỏm Đá Đông", "beach", [[54, 28, 13, 12]], ["C2", "D2"]), ("J6", "Vườn Nam", "meadow", [[32, 55, 20, 16], [45, 47, 10, 9]], ["D2", "E2"])
        ]
        out += joins.map { IslandRegion(id: $0.0, name: $0.1, layer: 2, theme: $0.2, parent: nil, needs: $0.4, rects: $0.3.map(sh), isJoin: true) }
        return out
    }()
    static let byID: [String: IslandRegion] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    var themeName: String { ["forest": "rừng", "meadow": "đồng cỏ hoa", "farm": "trang trại", "beach": "bãi biển"][theme] ?? theme }
}

// MARK: - Lots and the home map

struct IslandLot: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let x: Int, y: Int, w: Int, h: Int
    var building: String?
    var region: String?
}

/// Everything the island needs from the learner's saved state.
struct IslandLayout {
    var openRegions: Set<String>
    var buildings: [String: String]
}

struct HomeIsland {
    let map: TileMap
    let lots: [IslandLot]
    /// Regions on sale: their tiles still under water, for the dashed outline.
    let locked: [(region: IslandRegion, tiles: [(Int, Int)], set: Set<Int>)]
    let walk: [(Int, Int)]
    let portal: (Int, Int)
}

enum IslandMaps {
    static let mapCols = 104, mapRows = 110

    /// Fixed lots on the home island; four are prebuilt and free, two starter homes too.
    static let baseLots: [(Int, Int, String?)] = [
        (8, 8, "myhouse"), (13, 8, "lab"), (26, 7, "shop"), (30, 10, "home"), (12, 19, "clinic"), (16, 20, "home"), (26, 19, nil), (30, 20, nil), (13, 29, nil), (27, 29, nil), (31, 28, nil), (14, 36, nil), (24, 37, nil), (17, 40, nil),
        (8, 21, nil), (8, 28, nil), (35, 19, nil), (37, 23, nil), (29, 37, nil), (34, 37, nil), (30, 42, nil)
    ]
    static let starterBuildings: [String: String] = Dictionary(uniqueKeysWithValues: baseLots.compactMap { l in l.2.map { ("\(l.0 + OX),\(l.1 + OY)", $0) } })

    static func visibleRegions(_ open: Set<String>) -> [IslandRegion] {
        IslandRegion.all.filter { g in
            !open.contains(g.id) && (g.isJoin ? g.needs.allSatisfy { open.contains($0) } : g.layer == 1 || (g.parent.map { open.contains($0) } ?? false))
        }
    }

    private static func baseShape(_ M: TileMap) {
        func sh(_ r: [Int]) -> [Int] { [r[0] + OX, r[1] + OY, r[2], r[3]] }
        M.fillRects([[9, 12, 27, 33], [5, 7, 13, 10], [23, 5, 14, 10], [16, 43, 10, 8], [8, 39, 8, 5], [39, 52, 4, 3], [4, 20, 8, 13], [34, 17, 8, 12], [27, 35, 13, 12]].map(sh),
                    [[18, 5, 5, 8], [9, 33, 4, 5], [35, 29, 4, 5], [34, 5, 4, 3], [36, 44, 4, 3], [4, 20, 3, 3], [5, 7, 3, 3], [8, 43, 3, 1]].map(sh), Tile.g)
    }

    /// Lots of a region are placed on a map holding only the base island and that region,
    /// so they never move when other regions open later.
    static func regionLots(_ g: IslandRegion) -> [IslandLot] {
        let M = TileMap("lots", mapCols, mapRows)
        baseShape(M)
        let (x, y, w, h) = (g.rect[0], g.rect[1], g.rect[2], g.rect[3])
        for j in y..<(y + h) { for i in x..<(x + w) where g.has(i, j) { M.set(i, j, Tile.g) } }
        M.tidy()
        var R2 = Rng32(Int(g.id.unicodeScalars.first!.value) * 977 + g.layer)
        var lots: [IslandLot] = []
        func lotTile(_ i: Int, _ j: Int) -> Bool { lots.contains { i >= $0.x && i < $0.x + $0.w && j >= $0.y && j < $0.y + $0.h } }
        var t = 0
        while t < 400 && lots.count < 3 {
            t += 1
            let lx = x + 1 + Int((R2() * Double(w - 5)).rounded(.down)), ly = y + 1 + Int((R2() * Double(h - 5)).rounded(.down))
            var ok = true
            for j in (ly - 1)...(ly + 3) where ok { for i in (lx - 1)...(lx + 3) where ok { if !M.isLand(i, j) || lotTile(i, j) || !g.has(i, j) { ok = false } } }
            if ok && M.isLand(lx + 1, ly + 3) { lots.append(IslandLot(key: "\(lx),\(ly)", x: lx, y: ly, w: 3, h: 3, building: nil, region: g.id)) }
        }
        return lots
    }
    static let regionLotCache: [String: [IslandLot]] = Dictionary(uniqueKeysWithValues: IslandRegion.all.map { ($0.id, regionLots($0)) })

    static func buildHome(_ state: IslandLayout) -> HomeIsland {
        let M = TileMap("home", mapCols, mapRows)
        baseShape(M)
        let opened = IslandRegion.all.filter { state.openRegions.contains($0.id) }
        for g in opened { for j in g.rect[1]..<(g.rect[1] + g.rect[3]) { for i in g.rect[0]..<(g.rect[0] + g.rect[2]) where g.has(i, j) { M.set(i, j, Tile.g) } } }
        M.tidy()
        func P(_ a: Int, _ b: Int, _ c: Int, _ d: Int) { M.lpath(a + OX, b + OY, c + OX, d + OY) }
        func ob(_ k: String, _ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ edit: (inout IslandObject) -> Void = { _ in }) { M.obj(k, x + OX, y + OY, w, h, edit) }
        P(10, 13, 10, 16); P(10, 16, 30, 16); P(30, 12, 30, 16); P(21, 14, 21, 80); P(5, 26, 40, 26); P(21, 34, 33, 34); P(14, 41, 21, 41)
        ob("portal", 20, 13, 2, 1); M.setSolid(19 + OX, 13 + OY); M.setSolid(22 + OX, 13 + OY)
        ob("fountain", 22, 28, 3, 3); ob("mailbox", 17, 17); ob("statue", 18, 22, 1, 2)
        ob("windmill", 5, 23, 2, 3); ob("field", 4, 30, 3, 2) { $0.crop = [0xff8a2a, nil, 0xe8463f, nil] }; ob("lighthouse", 39, 18, 2, 3)

        var lots: [IslandLot] = baseLots.map { IslandLot(key: "\($0.0 + OX),\($0.1 + OY)", x: $0.0 + OX, y: $0.1 + OY, w: 3, h: 3, building: nil, region: nil) }
        for g in opened { lots += regionLotCache[g.id] ?? [] }
        for i in lots.indices { lots[i].building = state.buildings[lots[i].key] }
        func lotTile(_ x: Int, _ y: Int) -> Bool { lots.contains { x >= $0.x && x < $0.x + $0.w && y >= $0.y && y < $0.y + $0.h } }
        func free(_ x: Int, _ y: Int) -> Bool { M.isLand(x, y) && M.at(x, y) == Tile.g && !M.isSolid(x, y) && !lotTile(x, y) }

        // a lane over land joining each new region to the paths that already exist
        func lane(_ sx: Int, _ sy: Int) {
            var prev: [Int: Int] = [sy * M.cols + sx: -1]; var q = [(sx, sy)]; var end: (Int, Int)?; var h = 0
            while h < q.count && end == nil {
                let (x, y) = q[h]; h += 1
                for (a, b) in N4 {
                    let nx = x + a, ny = y + b, k = ny * M.cols + nx
                    if !M.inb(nx, ny) || prev[k] != nil { continue }
                    if M.at(nx, ny) == Tile.p { prev[k] = y * M.cols + x; end = (nx, ny); break }
                    if !free(nx, ny) { continue }
                    prev[k] = y * M.cols + x; q.append((nx, ny))
                }
            }
            var c = end.map { $0.1 * M.cols + $0.0 } ?? -1
            while c >= 0 { M.setPath(c % M.cols, c / M.cols); c = prev[c] ?? -1 }
        }
        for g in opened {
            let (x, y, w, h) = (g.rect[0], g.rect[1], g.rect[2], g.rect[3]), (cx, cy) = g.center
            var s: (Int, Int)?
            for r in 0..<6 where s == nil { for j in -r...r where s == nil { for i in -r...r where s == nil { if free(cx + i, cy + j) { s = (cx + i, cy + j) } } } }
            guard let s else { continue }
            lane(s.0, s.1)
            if x + 2 < x + w - 2 { for i in (x + 2)..<(x + w - 2) where free(i, s.1) && N4.allSatisfy({ M.isLand(i + $0.0, s.1 + $0.1) }) { M.setPath(i, s.1) } }
            let lm: (String, Int, Int) = ["forest": ("tent", 2, 2), "meadow": ("windmill", 2, 3), "farm": ("field", 4, 3), "beach": ("lighthouse", 2, 3)][g.theme]!
            var R3 = Rng32(Int(g.id.unicodeScalars.first!.value) * 31 + g.layer * 5)
            for _ in 0..<300 {
                let lx = x + 1 + Int((R3() * Double(w - lm.1 - 2)).rounded(.down)), ly = y + 1 + Int((R3() * Double(h - lm.2 - 2)).rounded(.down))
                var ok = true
                for j in ly..<(ly + lm.2) where ok { for i in lx..<(lx + lm.1) where ok { if !free(i, j) || M.nearPath(i, j) { ok = false } } }
                if ok {
                    M.obj(lm.0, lx, ly, lm.1, lm.2) { if lm.0 == "field" { $0.crop = [0xffcf3a, nil, 0x5aa853, 0xff8a2a] } }
                    if lm.0 == "tent" && free(lx + 2, ly + 1) { M.obj("camp", lx + 2, ly + 1) }
                    break
                }
            }
        }
        var sy = M.rows - 1
        while sy > 0 && !M.isLand(21 + OX, sy) { sy -= 1 }
        M.lpath(21 + OX, sy - 6, 21 + OX, sy)
        M.set(21 + OX, sy + 1, Tile.k); M.set(21 + OX, sy + 2, Tile.k)
        M.obj("dock", 21 + OX, sy + 1, 1, 2, solid: false); M.obj("boat", 22 + OX, sy + 2, 2, 1, solid: false)
        M.dock = (21 + OX, sy)

        func ok(_ x: Int, _ y: Int) -> Bool { M.isLand(x, y) && !lotTile(x, y) && !M.isSolid(x, y) }
        for l in lots {
            for j in l.y..<(l.y + l.h) { for k in l.x..<(l.x + l.w) { M.setSolid(k, j) } }
            let fx = l.x + 1, fy = l.y + l.h
            if !ok(fx, fy) && M.at(fx, fy) != Tile.p { continue }
            var best: (Int, Int, Int)?
            for y in max(0, fy - 20)..<min(M.rows, fy + 20) { for x in max(0, fx - 20)..<min(M.cols, fx + 20) where M.at(x, y) == Tile.p {
                let d = abs(x - fx) + abs(y - fy); if best == nil || d < best!.2 { best = (x, y, d) }
            } }
            guard let (px, py, _) = best else { continue }
            var r0: [(Int, Int)] = [], r1: [(Int, Int)] = []
            for y in min(fy, py)...max(fy, py) { r0.append((fx, y)) }; for x in min(fx, px)...max(fx, px) { r0.append((x, py)) }
            for x in min(fx, px)...max(fx, px) { r1.append((x, fy)) }; for y in min(fy, py)...max(fy, py) { r1.append((px, y)) }
            if let r = [r0, r1].first(where: { $0.allSatisfy { M.at($0.0, $0.1) == Tile.p || ok($0.0, $0.1) } }) { for (x, y) in r { M.setPath(x, y) } }
        }
        for (n, l) in lots.enumerated() {
            guard let b = l.building, let c = IslandCatalog.byKey[b] else { M.obj("lot", l.x, l.y, l.w, l.h); continue }
            M.obj(c.kind, l.x + (l.w - c.w) / 2, l.y + (l.h - c.h), c.w, c.h) { o in
                o.roof = c.roof; o.wall = c.wall; o.mine = c.mine; o.sign = c.sign
                if b == "home" { o.roof = ROOFS[(l.x + l.y + n * 0) % ROOFS.count] }
            }
        }
        func themeAt(_ x: Int, _ y: Int) -> String { opened.first { $0.has(x, y) }?.theme ?? "home" }
        for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) {
            if M.at(x, y) != Tile.g || M.isSolid(x, y) || M.nearPath(x, y) || M.nearSolid(x, y) { continue }
            let coast = N4.contains { !M.isLand(x + $0.0, y + $0.1) }, r = hash(x, y, 1), th = themeAt(x, y)
            if coast { if r < (th == "beach" ? 0.45 : 0.28) { M.obj("tree", x, y) { $0.tree = "palm" } } else if r < 0.34 { M.obj("rock", x, y) }; continue }
            switch th {
            case "forest": if r < 0.55 { M.obj("tree", x, y) { $0.tree = hash(x, y, 2) < 0.6 ? "pine" : "oak" } } else if r < 0.66 { M.obj("fern", x, y, solid: false) } else if r < 0.7 { M.obj("mushbig", x, y) }
            case "beach": if r < 0.18 { M.obj("tree", x, y) { $0.tree = "palm" } } else if r < 0.24 { M.obj("rock", x, y) } else if r < 0.3 { M.obj("shellpile", x, y, solid: false) }
            case "farm": if r < 0.12 { M.tree(x, y, "oak", fruit: true) } else if r < 0.2 { M.obj("bush", x, y) { $0.berries = true } } else if r < 0.3 { M.obj("flowers", x, y, solid: false) }
            case "meadow": if r < 0.16 { M.tree(x, y, "oak") } else if r < 0.42 { M.obj("flowers", x, y, solid: false) } else if r < 0.46 { M.obj("rock", x, y) }
            default: if r < 0.32 { M.tree(x, y, "oak", fruit: hash(x, y, 4) < 0.3) } else if r < 0.46 { M.obj("flowers", x, y, solid: false) } else if r < 0.5 { M.obj("bush", x, y) }
            }
        } }
        let locked = visibleRegions(state.openRegions).map { g -> (region: IslandRegion, tiles: [(Int, Int)], set: Set<Int>) in
            var tiles: [(Int, Int)] = []
            for j in g.rect[1]..<(g.rect[1] + g.rect[3]) { for i in g.rect[0]..<(g.rect[0] + g.rect[2]) where g.has(i, j) && !M.isLand(i, j) { tiles.append((i, j)) } }
            return (g, tiles, Set(tiles.map { $0.1 * M.cols + $0.0 }))
        }
        var walk: [(Int, Int)] = []
        for y in 0..<M.rows { for x in 0..<M.cols where M.at(x, y) == Tile.p { walk.append((x, y)) } }
        return HomeIsland(map: M, lots: lots, locked: locked, walk: walk, portal: (21 + OX, 14 + OY))
    }

    // MARK: - Stage islands

    static func shapeIsland(_ M: TileMap, _ rects: [[Int]], _ base: UInt8) {
        M.fillRects(rects, [], base)
        var cut: [(Int, Int)] = []
        for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) where M.isLand(x, y) {
            func L(_ a: Int, _ b: Int) -> Bool { M.isLand(x + a, y + b) }
            let n = N4.filter { L($0.0, $0.1) }.count
            if n <= 1 || (n == 2 && !(L(1, 0) && L(-1, 0)) && !(L(0, 1) && L(0, -1))) { cut.append((x, y)) }
        } }
        for (x, y) in cut { M.set(x, y, Tile.w) }
    }

    static func stageRects(_ R: inout Rng32, _ M: TileMap) -> [[Int]] {
        var rects = [[8, 12, 14, 16]]
        let n = 5 + Int((R() * 3).rounded(.down))
        for _ in 0..<n {
            let p = rects[Int((R() * Double(rects.count)).rounded(.down))], (px, py, pw, ph) = (p[0], p[1], p[2], p[3])
            let w = 6 + Int((R() * 5).rounded(.down)), h = 6 + Int((R() * 5).rounded(.down)), side = Int((R() * 4).rounded(.down))
            var x = 0, y = 0
            if side == 0 { x = px + Int((R() * Double(pw - 2)).rounded(.down)) - 2; y = py - h + 2 }
            else if side == 1 { x = px + pw - 2; y = py + Int((R() * Double(ph - 2)).rounded(.down)) - 2 }
            else if side == 2 { x = px + Int((R() * Double(pw - 2)).rounded(.down)) - 2; y = py + ph - 2 }
            else { x = px - w + 2; y = py + Int((R() * Double(ph - 2)).rounded(.down)) - 2 }
            rects.append([max(4, min(M.cols - 5 - w, x)), max(5, min(M.rows - 9 - h, y)), w, h])
        }
        return rects
    }

    static let stageActs: [String: (land: [String], npc: [String], water: [String])] = [
        "forest": (["mushroom", "berry", "herb", "log"], ["owl", "woodcutter"], ["stream"]),
        "lake": (["shell", "reeds"], ["buyfish", "net"], ["fish", "lotus"])
    ]
    static let npcLook: [String: (UInt32, UInt32, UInt32?)] = [
        "woodcutter": (0x5a3a22, 0xc0563f, 0x8a5a3a), "buyfish": (0x2b2238, 0x2fb3c0, nil), "net": (0xc9c2b0, 0x3f6fca, 0xe6c57d),
        "bookseller": (0x3a2a22, 0x5b8a5a, nil), "postman": (0x2b2238, 0x3f6fca, 0x3f6fca),
        "merchant": (0x2b2238, 0xd9534f, 0xf2d17c), "nomad": (0x5a3a22, 0xf2e6c8, 0xe8e0cc)
    ]

    static func genStage(_ type: String, _ idx: Int) -> TileMap {
        var R = Rng32(idx * 977 + (type == "lake" ? 4001 : 17))
        let M = TileMap(type + "\(idx)", 30, 42)
        let rects = stageRects(&R, M)
        let base = type == "forest" ? Tile.f : Tile.g
        shapeIsland(M, rects, base)
        func C(_ r: [Int]) -> (Int, Int) { (r[0] + r[2] / 2, r[1] + r[3] / 2) }
        let (hx, hy) = C(rects[0])
        if type == "lake" {
            let pcx = Double(hx) + 0.5, pcy = Double(hy) - 0.5, prx = 4.2, pry = 3.6
            for y in 0..<M.rows { for x in 0..<M.cols where M.isLand(x, y) {
                let d = pow((Double(x) + 0.5 - pcx) / prx, 2) + pow((Double(y) + 0.5 - pcy) / pry, 2)
                if d <= 1 { M.set(x, y, Tile.h) } else if d <= 2.4 && d > 1.7 { M.set(x, y, Tile.p) }
            } }
            for r in rects.dropFirst() { let (cx, cy) = C(r); M.lpath(cx, cy, hx, cy > hy ? hy + 5 : hy - 5) }
        } else { for r in rects.dropFirst() { let (cx, cy) = C(r); M.lpath(cx, cy, hx, hy) } }
        var sy = M.rows - 1
        while sy > 0 && !M.isLand(hx, sy) { sy -= 1 }
        M.lpath(hx, sy, hx, type == "lake" ? hy + 5 : hy)
        M.set(hx, sy + 1, Tile.k); M.set(hx, sy + 2, Tile.k)
        M.obj("dock", hx, sy + 1, 1, 2, solid: false); M.obj("boat", hx + 1, sy + 2, 2, 1, solid: false)
        M.dock = (hx, sy)
        let A = stageActs[type]!
        var spots: [(Int, Int)] = []
        func taken(_ x: Int, _ y: Int) -> Bool { spots.contains { abs($0.0 - x) + abs($0.1 - y) < 3 - (spots.count > 8 ? 1 : 0) } || abs(x - hx) + abs(y - sy) < 3 }
        var landC: [(Int, Int)] = [], waterC: [(Int, Int)] = []
        for y in 2..<(M.rows - 2) { for x in 2..<(M.cols - 2) {
            let nb = N4.map { M.at(x + $0.0, y + $0.1) }, g = M.at(x, y)
            if (g == Tile.f || g == Tile.g) && nb.contains(Tile.p) { landC.append((x, y)) }
            if (g == Tile.h || (g == Tile.w && type == "forest")) && nb.contains(Tile.p) { waterC.append((x, y)) }
            if g == Tile.w && type == "lake" && nb.contains(where: { $0 != Tile.w }) { waterC.append((x, y)) }
        } }
        func pick(_ list: [(Int, Int)]) -> (Int, Int)? {
            guard !list.isEmpty else { return nil }
            for _ in 0..<1500 { let c = list[Int((R() * Double(list.count)).rounded(.down))]; if !taken(c.0, c.1) { spots.append(c); return c } }
            return nil
        }
        var chosen: [(String, (Int, Int))] = []
        for i in 0..<(type == "lake" ? 7 : 2) { if let c = pick(waterC) { chosen.append((A.water[i % A.water.count], c)) } }
        for a in A.npc { if let c = pick(landC) { chosen.append((a, c)) } }
        var li = 0
        while chosen.count < 18 { guard let c = pick(landC) else { break }; chosen.append((A.land[li % A.land.count], c)); li += 1 }
        let kindOf = ["mushroom": "mushbig", "berry": "bush", "herb": "herb", "log": "log", "owl": "stump", "shell": "shellpile", "reeds": "reedbig", "lotus": "lotuspad", "fish": "fishspot", "stream": "fishspot"]
        M.quests = chosen.map { ($0.0, $0.1.0, $0.1.1) }
        for (act, (x, y)) in chosen {
            if let look = npcLook[act] { M.obj("npc", x, y) { $0.hair = look.0; $0.cloth = look.1; $0.hat = look.2 } }
            else { M.obj(kindOf[act] ?? "rock", x, y, solid: !["lotus", "fish", "stream"].contains(act)) { $0.berries = act == "berry" } }
        }
        let lm: (String, Int, Int) = type == "forest" ? ("tent", 2, 2) : ("lighthouse", 2, 3)
        for _ in 0..<300 {
            let r = rects[1 + Int((R() * Double(rects.count - 1)).rounded(.down))]
            let x = r[0] + 1 + Int((R() * Double(max(1, r[2] - lm.1 - 1))).rounded(.down)), y = r[1] + 1 + Int((R() * Double(max(1, r[3] - lm.2 - 1))).rounded(.down))
            var ok = true
            for j in -1...lm.2 { for i in -1...lm.1 { let g = M.at(x + i, y + j); if !M.inb(x + i, y + j) || g == Tile.p || Tile.isWater(g) || M.isSolid(x + i, y + j) { ok = false } } }
            if ok { M.obj(lm.0, x, y, lm.1, lm.2); if type == "forest" { M.obj("camp", x + 2, y + 1) }; break }
        }
        for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) {
            if M.at(x, y) != base || M.isSolid(x, y) || M.nearPath(x, y) || spots.contains(where: { abs($0.0 - x) + abs($0.1 - y) <= 1 }) { continue }
            let r = hash(x, y, 1 + idx), coast = N4.contains { !M.isLand(x + $0.0, y + $0.1) }
            if type == "forest" { if r < 0.58 { M.tree(x, y) } else if r < 0.72 { M.obj("fern", x, y, solid: false) } else if r < 0.76 { M.obj("rock", x, y) } }
            else { if r < 0.2 { M.obj("tree", x, y) { $0.tree = coast || hash(x, y, 6) < 0.5 ? "palm" : "oak" } } else if r < 0.3 { M.obj("flowers", x, y, solid: false) } else if r < 0.33 { M.obj("rock", x, y) } }
        } }
        return M
    }

    private static func addDock(_ M: TileMap, _ hx: Int, _ fill: UInt8) {
        var sy = M.rows - 1
        while sy > 0 && !M.isLand(hx, sy) { sy -= 1 }
        var y = sy
        while y > 0 && M.isLand(hx, y) && M.at(hx, y) != fill && M.at(hx, y) != Tile.r { M.set(hx, y, fill); y -= 1 }
        M.set(hx, sy + 1, Tile.k); M.set(hx, sy + 2, Tile.k)
        M.obj("dock", hx, sy + 1, 1, 2, solid: false); M.obj("boat", hx + 1, sy + 2, 2, 1, solid: false)
        M.dock = (hx, sy)
    }

    private static func placeSpots(_ M: TileMap, _ R: inout Rng32, _ cands: [(Int, Int)], land: [String], npc: [String], kindOf: [String: String], want: Int = 17) {
        var spots: [(Int, Int)] = []
        func taken(_ x: Int, _ y: Int) -> Bool { spots.contains { abs($0.0 - x) + abs($0.1 - y) < (spots.count > 8 ? 2 : 3) } || M.isSolid(x, y) }
        func pick() -> (Int, Int)? {
            guard !cands.isEmpty else { return nil }
            for _ in 0..<1500 { let c = cands[Int((R() * Double(cands.count)).rounded(.down))]; if !taken(c.0, c.1) { spots.append(c); return c } }
            return nil
        }
        M.quests = []
        for a in npc { if let c = pick(), let look = npcLook[a] { M.obj("npc", c.0, c.1) { $0.hair = look.0; $0.cloth = look.1; $0.hat = look.2 }; M.quests.append((a, c.0, c.1)) } }
        var li = 0
        while spots.count < want { guard let c = pick() else { break }; let a = land[li % land.count]; li += 1; M.obj(kindOf[a] ?? "rock", c.0, c.1); M.quests.append((a, c.0, c.1)) }
    }

    static func genCity(_ idx: Int) -> TileMap {
        var R = Rng32(idx * 977 + 8009)
        let M = TileMap("city\(idx)", 30, 42), rects = stageRects(&R, M)
        shapeIsland(M, rects, Tile.g); M.beachExtra = 6
        var x0 = 99, x1 = 0, y0 = 99, y1 = 0
        for y in 0..<M.rows { for x in 0..<M.cols where M.isLand(x, y) { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        _ = (x1, y1)
        let ox = x0 + 2 + Int((R() * 3).rounded(.down)), oy = y0 + 2 + Int((R() * 3).rounded(.down)), SP = 6
        func isRoadX(_ x: Int) -> Bool { (x - ox) % SP == 0 }
        func isRoadY(_ y: Int) -> Bool { (y - oy) % SP == 0 }
        for y in 0..<M.rows { for x in 0..<M.cols where M.isLand(x, y) && ((x >= ox && isRoadX(x)) || (y >= oy && isRoadY(y))) { M.set(x, y, Tile.r) } }
        for _ in 0..<3 { for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) where M.at(x, y) == Tile.r && N4.filter({ M.at(x + $0.0, y + $0.1) == Tile.r }).count <= 1 && N4.filter({ M.isLand(x + $0.0, y + $0.1) }).count < 3 { M.set(x, y, Tile.g) } } }
        for y in 0..<M.rows { for x in 0..<M.cols where M.at(x, y) == Tile.g {
            var near = false
            for j in -1...1 { for i in -1...1 where M.inb(x + i, y + j) && M.at(x + i, y + j) == Tile.r { near = true } }
            if near { M.set(x, y, Tile.W) }
        } }
        func C(_ r: [Int]) -> (Int, Int) { (r[0] + r[2] / 2, r[1] + r[3] / 2) }
        let (hx, hy) = C(rects[0])
        addDock(M, hx, Tile.W)
        func free(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool {
            for j in y..<(y + h) { for i in x..<(x + w) { if !M.inb(i, j) || M.at(i, j) != Tile.g || M.isSolid(i, j) { return false } } }
            return true
        }
        var blocks: [(Int, Int)] = []
        var by = oy - SP
        while by < M.rows { var bx = ox - SP; while bx < M.cols { blocks.append((bx + 2, by + 2)); bx += SP }; by += SP }
        blocks.sort { hypot(Double($0.0 + 1 - hx), Double($0.1 + 1 - hy)) < hypot(Double($1.0 + 1 - hx), Double($1.1 + 1 - hy)) }
        let PAL: [UInt32] = [0xe9a77b, 0x9fc5e8, 0xf2d17c, 0xc7b6e8, 0xa8d8b0, 0xf4b6c2]
        for (k, (bx, by)) in blocks.enumerated() {
            if k == 0 && free(bx, by, 3, 3) { M.obj("clocktower", bx, by, 3, 3); continue }
            if free(bx, by, 3, 3) {
                let r = R(), wall = PAL[Int((R() * Double(PAL.count)).rounded(.down))]
                if r < 0.14 { M.obj("park", bx, by, 3, 3, solid: false); for (a, b) in [(bx, by), (bx + 2, by + 1)] { M.tree(a, b, "oak") }; M.obj("bench", bx + 1, by + 2) }
                else if r < 0.42 { let fl = 2 + Int((R() * 3).rounded(.down)); M.obj("apartment", bx, by, 3, 3) { $0.wall = wall; $0.floors = fl } }
                else if r < 0.56 { let fl = 4 + Int((R() * 3).rounded(.down)); M.obj("office", bx, by, 3, 3) { $0.floors = fl } }
                else if r < 0.76 { M.obj("bookstore", bx, by, 3, 3) { $0.wall = wall } }
                else { M.obj("cafe", bx, by, 3, 3) { $0.wall = wall } }
                continue
            }
            var placed = false
            for (w, h, dy) in [(3, 2, 1), (3, 2, 0), (2, 2, 1), (2, 2, 0)] where !placed { for dx in [0, 1] where !placed && free(bx + dx, by + dy, w, h) {
                let roof = [UInt32(0xd9534f), 0x3f6fca, 0x2f9e8f, 0x8e5bd6][Int((R() * 4).rounded(.down))]
                M.obj("house", bx + dx, by + dy, w, h) { $0.roof = roof; $0.wall = 0xfff8e8 }; placed = true
            } }
        }
        for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) {
            let g = M.at(x, y)
            if g == Tile.r {
                let hz = M.at(x - 1, y) == Tile.r || M.at(x + 1, y) == Tile.r, vt = M.at(x, y - 1) == Tile.r || M.at(x, y + 1) == Tile.r
                if hz != vt && hash(x, y, 13 + idx) < 0.14 {
                    let col = [UInt32(0xe8463f), 0x3f6fca, 0xffcf3a, 0xffffff, 0x2fb3c0][Int((hash(x, y, 2) * 5).rounded(.down))]
                    M.obj("car", x, y, solid: false) { $0.horizontal = hz; $0.color = col }
                }
            }
            if g == Tile.W && !M.isSolid(x, y) {
                let diag = [(1, 1), (1, -1), (-1, 1), (-1, -1)].contains { M.at(x + $0.0, y + $0.1) == Tile.r && M.at(x + $0.0, y) != Tile.r && M.at(x, y + $0.1) != Tile.r }
                if diag && hash(x, y, 7) < 0.6 { M.obj("lamp", x, y) }
            }
            if g == Tile.g && !M.isSolid(x, y) {
                let coast = N4.contains { !M.isLand(x + $0.0, y + $0.1) }, r = hash(x, y, 1 + idx)
                if coast ? r < 0.25 : r < 0.45 { M.obj("tree", x, y) { $0.tree = coast ? "palm" : "oak" } } else if r < 0.55 { M.obj("flowers", x, y, solid: false) }
            }
        } }
        var cands: [(Int, Int)] = []
        for y in 2..<(M.rows - 2) { for x in 2..<(M.cols - 2) where M.at(x, y) == Tile.W && N4.contains(where: { M.at(x + $0.0, y + $0.1) == Tile.r }) { cands.append((x, y)) } }
        placeSpots(M, &R, cands, land: ["sign", "poster", "newsstand", "letter"], npc: ["bookseller", "postman"], kindOf: ["sign": "signpost", "poster": "poster", "newsstand": "newsstand", "letter": "letterbox"])
        return M
    }

    static func genDesert(_ idx: Int) -> TileMap {
        var R = Rng32(idx * 977 + 12007)
        let M = TileMap("desert\(idx)", 30, 42), rects = stageRects(&R, M)
        shapeIsland(M, rects, Tile.d)
        func C(_ r: [Int]) -> (Int, Int) { (r[0] + r[2] / 2, r[1] + r[3] / 2) }
        let (hx, hy) = C(rects[0])
        for r in rects.dropFirst() { let (cx, cy) = C(r); M.lpath(cx, cy, hx, hy) }
        addDock(M, hx, Tile.p)
        func fits(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Bool {
            for j in (y - 1)...(y + h) { for i in (x - 1)...(x + w) { if !M.inb(i, j) || M.at(i, j) != Tile.d || M.isSolid(i, j) { return false } } }
            return true
        }
        @discardableResult func place(_ kind: String, _ w: Int, _ h: Int, tries: Int = 400, _ edit: (inout IslandObject) -> Void = { _ in }) -> (Int, Int)? {
            for _ in 0..<tries {
                let r = rects[1 + Int((R() * Double(rects.count - 1)).rounded(.down))]
                let x = r[0] + Int((R() * Double(max(1, r[2] - w))).rounded(.down)), y = r[1] + Int((R() * Double(max(1, r[3] - h))).rounded(.down))
                if fits(x, y, w, h) { M.obj(kind, x, y, w, h, edit); return (x, y) }
            }
            return nil
        }
        if let pyr = place("pyramid", 4, 3) {
            for (a, b) in [(-1, 3), (4, 3)] { let x = pyr.0 + a, y = pyr.1 + b; if M.inb(x, y) && M.at(x, y) == Tile.d && !M.isSolid(x, y) { M.obj("column", x, y) { $0.broken = a > 0 } } }
        }
        for k in 0..<3 { let wall = [UInt32(0xe0a86a), 0xe8b77e, 0xd89a5c][k]; place("adobe", 2, 2) { $0.wall = wall } }
        place("market", 2, 1); place("camel", 1, 1); place("camel", 1, 1)
        for y in 1..<(M.rows - 1) { for x in 1..<(M.cols - 1) {
            if M.at(x, y) != Tile.d || M.isSolid(x, y) || M.nearPath(x, y) { continue }
            let r = hash(x, y, 1 + idx)
            if r < 0.09 { M.obj("cactus", x, y) } else if r < 0.14 { M.obj("rock", x, y) } else if r < 0.19 { M.obj("drybush", x, y, solid: false) }
        } }
        var cands: [(Int, Int)] = []
        for y in 2..<(M.rows - 2) { for x in 2..<(M.cols - 2) where M.at(x, y) == Tile.d && N4.contains(where: { M.at(x + $0.0, y + $0.1) == Tile.p }) { cands.append((x, y)) } }
        placeSpots(M, &R, cands, land: ["pottery", "fossil", "cactusfruit", "gem"], npc: ["merchant", "nomad"], kindOf: ["pottery": "pottery", "fossil": "fossil", "cactusfruit": "cactus", "gem": "gem"])
        return M
    }
}
