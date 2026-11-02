import Foundation

// Tile maps → per-pixel island art, ported from the demo (16 art pixels per tile).

let TILE = 16
let N4: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]

/// One placed thing on the map: buildings, trees, props, characters.
struct IslandObject {
    var kind: String
    var x: Int, y: Int, w: Int = 1, h: Int = 1
    var tree: String = "oak"
    var fruit = false, berries = false
    var roof: UInt32? = nil, wall: UInt32? = nil
    var mine = false
    var sign: String? = nil
    var crop: [UInt32?] = []
    var hair: UInt32 = 0x2b2238, cloth: UInt32 = 0x3f6fca, hat: UInt32? = nil, bubble = false
    var floors = 2
    var broken = false
    var horizontal = false
    var color: UInt32 = 0xe8463f
}

/// Tile codes: w/a/h water, g grass, f forest, d desert, p path, r road, W pavement, k dock, s sand.
enum Tile {
    static let w = UInt8(ascii: "w"), a = UInt8(ascii: "a"), h = UInt8(ascii: "h"), g = UInt8(ascii: "g"), f = UInt8(ascii: "f")
    static let d = UInt8(ascii: "d"), p = UInt8(ascii: "p"), r = UInt8(ascii: "r"), W = UInt8(ascii: "W"), k = UInt8(ascii: "k"), s = UInt8(ascii: "s")
    @inline(__always) static func isWater(_ c: UInt8) -> Bool { c == w || c == a || c == h }
}

final class TileMap {
    let name: String
    let cols: Int, rows: Int
    var g: [UInt8]
    var solid: [Bool]
    var objs: [IslandObject] = []
    var beachExtra: Double = 0
    /// Quest spots for a stage map.
    var quests: [(act: String, x: Int, y: Int)] = []
    var dock: (Int, Int)? = nil
    var fieldsCache: IslandFields?

    init(_ name: String, _ cols: Int, _ rows: Int) {
        self.name = name; self.cols = cols; self.rows = rows
        g = [UInt8](repeating: Tile.w, count: cols * rows)
        solid = [Bool](repeating: false, count: cols * rows)
    }

    @inline(__always) func inb(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < cols && y < rows }
    @inline(__always) func at(_ x: Int, _ y: Int) -> UInt8 { inb(x, y) ? g[y * cols + x] : Tile.w }
    @inline(__always) func set(_ x: Int, _ y: Int, _ c: UInt8) { if inb(x, y) { g[y * cols + x] = c } }
    @inline(__always) func isSolid(_ x: Int, _ y: Int) -> Bool { inb(x, y) && solid[y * cols + x] }
    @inline(__always) func setSolid(_ x: Int, _ y: Int, _ v: Bool = true) { if inb(x, y) { solid[y * cols + x] = v } }
    @inline(__always) func isLand(_ x: Int, _ y: Int) -> Bool { inb(x, y) && !Tile.isWater(g[y * cols + x]) }

    func obj(_ o: IslandObject, solid isSolid: Bool = true) {
        objs.append(o)
        if isSolid { for j in o.y..<(o.y + o.h) { for i in o.x..<(o.x + o.w) { setSolid(i, j) } } }
    }
    func obj(_ kind: String, _ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, solid isSolid: Bool = true, _ edit: (inout IslandObject) -> Void = { _ in }) {
        var o = IslandObject(kind: kind, x: x, y: y, w: w, h: h); edit(&o); obj(o, solid: isSolid)
    }
    func tree(_ x: Int, _ y: Int, _ kind: String = "auto", fruit: Bool = false) {
        let t = kind == "auto" ? (at(x, y) == Tile.f ? (hash(x, y, 2) < 0.55 ? "pine" : "oak") : "oak") : kind
        obj("tree", x, y) { $0.tree = t; $0.fruit = fruit }
    }
    func nearPath(_ x: Int, _ y: Int) -> Bool { N4.contains { inb(x + $0.0, y + $0.1) && at(x + $0.0, y + $0.1) == Tile.p } || at(x, y) == Tile.p }
    func nearSolid(_ x: Int, _ y: Int) -> Bool {
        for j in -1...1 { for i in -1...1 where isSolid(x + i, y + j) { return true } }
        return false
    }
    func setPath(_ x: Int, _ y: Int) { if isLand(x, y) { set(x, y, Tile.p) } }
    func lpath(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
        for x in min(x0, x1)...max(x0, x1) { setPath(x, y0) }
        for y in min(y0, y1)...max(y0, y1) { setPath(x1, y) }
    }
    func fillRects(_ add: [[Int]], _ cut: [[Int]], _ base: UInt8) {
        func inR(_ r: [Int], _ x: Int, _ y: Int) -> Bool { x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3] }
        for y in 0..<rows { for x in 0..<cols {
            g[y * cols + x] = add.contains { inR($0, x, y) } && !cut.contains { inR($0, x, y) } ? base : Tile.w
        } }
    }
    /// Knock off one-tile spikes so blocks keep a clean, stepped coast.
    func tidy() {
        for _ in 0..<2 { for y in 1..<(rows - 1) { for x in 1..<(cols - 1) {
            let n = N4.filter { isLand(x + $0.0, y + $0.1) }.count
            if isLand(x, y) && n <= 1 { set(x, y, Tile.w) }
            if !isLand(x, y) && n >= 3 {
                set(x, y, at(x + 1, y) != Tile.w ? at(x + 1, y) : at(x - 1, y) != Tile.w ? at(x - 1, y) : at(x, y + 1) != Tile.w ? at(x, y + 1) : at(x, y - 1))
            }
        } } }
    }
    var fields: IslandFields { if let fieldsCache { return fieldsCache }; let f = IslandFields(self); fieldsCache = f; return f }
}

// MARK: - Fields: land mask with a soft-blocky coast, distance to shore in and out

final class IslandFields {
    let W: Int, H: Int
    var land: [UInt8], path: [UInt8], forest: [Float], desert: [Float], dOut: [Float], dIn: [Float]

    init(_ M: TileMap) {
        let W = M.cols * TILE, H = M.rows * TILE
        self.W = W; self.H = H
        let N = W * H, C2 = M.cols + 2, R2 = M.rows + 2
        var tl = [Float](repeating: 0, count: C2 * R2), tp = tl, tf = tl, td = tl
        for j in 0..<M.rows { for i in 0..<M.cols {
            let c = M.g[j * M.cols + i], k = (j + 1) * C2 + i + 1
            tl[k] = !Tile.isWater(c) && c != Tile.k ? 1 : 0; tp[k] = c == Tile.p ? 1 : 0; tf[k] = c == Tile.f ? 1 : 0; td[k] = c == Tile.d ? 1 : 0
        } }
        var land = [UInt8](repeating: 0, count: N), path = land
        var forest = [Float](repeating: 0, count: N), desert = forest
        let T = Float(TILE), Hh = H, Ww = W
        tl.withUnsafeBufferPointer { tl in tp.withUnsafeBufferPointer { tp in tf.withUnsafeBufferPointer { tf in td.withUnsafeBufferPointer { td in
        land.withUnsafeMutableBufferPointer { land in path.withUnsafeMutableBufferPointer { path in
        forest.withUnsafeMutableBufferPointer { forest in desert.withUnsafeMutableBufferPointer { desert in
            for py in 0..<Hh {
                let fy = (Float(py) + 0.5) / T - 0.5, y0 = Int(fy.rounded(.down)), ty = fy - Float(y0)
                for px in 0..<Ww {
                    let fx = (Float(px) + 0.5) / T - 0.5, x0 = Int(fx.rounded(.down)), tx = fx - Float(x0), b = (y0 + 1) * C2 + x0 + 1, i = py * Ww + px
                    let w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty
                    let L = tl[b] * w00 + tl[b + 1] * w10 + tl[b + C2] * w01 + tl[b + C2 + 1] * w11
                    if L == 0 { continue }
                    let n1 = Float(nz(Double(px) / 2.2, Double(py) / 2.2)) - 0.5
                    land[i] = L + n1 * 0.22 > 0.5 ? 1 : 0
                    let pv = tp[b] * w00 + tp[b + 1] * w10 + tp[b + C2] * w01 + tp[b + C2 + 1] * w11 + n1 * 0.12
                    path[i] = pv > 0.62 ? 2 : pv > 0.5 ? 1 : 0
                    forest[i] = tf[b] * w00 + tf[b + 1] * w10 + tf[b + C2] * w01 + tf[b + C2 + 1] * w11
                    desert[i] = td[b] * w00 + td[b + 1] * w10 + td[b + C2] * w01 + td[b + C2 + 1] * w11
                }
            }
        } } } } } } } }
        let landMask = land
        let dOut = IslandFields.distance(W, H) { landMask[$0] == 1 }
        let dIn = IslandFields.distance(W, H) { i in landMask[i] == 0 || i % W == 0 || i % W == W - 1 || i < W || i >= N - W }
        self.land = land; self.path = path; self.forest = forest; self.desert = desert; self.dOut = dOut; self.dIn = dIn
    }

    /// Two-pass chamfer distance transform from the seed pixels.
    static func distance(_ W: Int, _ H: Int, _ seed: (Int) -> Bool) -> [Float] {
        var d = [Float](repeating: 1e4, count: W * H)
        for i in 0..<(W * H) where seed(i) { d[i] = 0 }
        let A: Float = 1, B: Float = 1.414
        d.withUnsafeMutableBufferPointer { d in
            for y in 0..<H { for x in 0..<W {
                let i = y * W + x; var v = d[i]; if v == 0 { continue }
                if x > 0 { v = min(v, d[i - 1] + A) }
                if y > 0 { v = min(v, d[i - W] + A); if x > 0 { v = min(v, d[i - W - 1] + B) }; if x < W - 1 { v = min(v, d[i - W + 1] + B) } }
                d[i] = v
            } }
            for y in stride(from: H - 1, through: 0, by: -1) { for x in stride(from: W - 1, through: 0, by: -1) {
                let i = y * W + x; var v = d[i]; if v == 0 { continue }
                if x < W - 1 { v = min(v, d[i + 1] + A) }
                if y < H - 1 { v = min(v, d[i + W] + A); if x < W - 1 { v = min(v, d[i + W + 1] + B) }; if x > 0 { v = min(v, d[i + W - 1] + B) } }
                d[i] = v
            } }
        }
        return d
    }
}

// MARK: - Painting the sea and the land

private func rgb(_ hex: UInt32) -> (UInt8, UInt8, UInt8) { (UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF)) }

enum IslandPaint {
    static let sea: [(UInt8, UInt8, UInt8)] = [0xffffff, 0xdcf7fb, 0xaeeaf1, 0x86dbea, 0x64c7e5, 0x4db0dd, 0x3d99d3, 0x3485c8, 0x2f74bb, 0x2b66ae].map(rgb)
    static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { $0 / 16 - 0.5 }
    static let dstops: [(Double, Double)] = [(0, 0), (1.6, 1), (4, 2), (12, 3), (24, 4), (38, 5), (56, 6), (80, 7), (110, 8), (160, 9)]

    static func seaIndex(_ d: Double) -> Double {
        for k in 1..<dstops.count where d < dstops[k].0 {
            let (a, ia) = dstops[k - 1], (b, ib) = dstops[k]
            return ia + (d - a) / (b - a) * (ib - ia)
        }
        return 9
    }

    /// Paint the moving sea into `canvas` for the rectangle x0..<x1, y0..<y1 at time t (seconds).
    static func water(_ F: IslandFields, _ canvas: PixelCanvas, t: Double, rect: (Int, Int, Int, Int)? = nil) {
        let W = F.W, H = F.H
        let (x0, y0, x1, y1) = rect ?? (0, 0, W, H)
        let sx = max(0, x0), sy = max(0, y0), ex = min(W, x1), ey = min(H, y1)
        guard sx < ex, sy < ey else { return }
        F.land.withUnsafeBufferPointer { land in F.dOut.withUnsafeBufferPointer { dOut in canvas.pixels.withUnsafeMutableBufferPointer { out in
            for py in sy..<ey { for px in sx..<ex {
                let i = py * W + px; if land[i] != 0 { continue }
                let dO = Double(dOut[i])
                var d = max(dO, 175 - Double(min(px, py, W - 1 - px, H - 1 - py)) * 2.4)
                let n = nz(Double(px) / 3 + t * 1.5, Double(py) / 3), n2 = nz(Double(px) / 1.3 - t * 2, Double(py) / 1.1 + 40)
                d += (n - 0.5) * min(18, d * 0.55)
                var k = seaIndex(d)
                let sw = 7 + sin(t * 1.3 + Double(px) * 0.03 + Double(py) * 0.02) * 2.5
                if abs(dO - sw) < 0.9 && n2 > 0.42 { k = min(k, 1.2) }
                if abs(dO - sw - 7) < 0.7 && n2 > 0.6 { k -= 0.9 }
                if dO > 26 && py % 5 == 0 {
                    let gl = hash(Int(((Double(px) + t * 6) / 9).rounded(.down)), py / 5, 11)
                    if gl > 0.955 && (px + Int((t * 6).rounded(.down))) % 9 < 4 { k = 4.2 }
                }
                let ki = max(0, min(9, Int((k + bayer[(py & 3) * 4 + (px & 3)] * 0.9 + 0.5).rounded(.down))))
                let c = sea[ki]
                out[i] = UInt32(c.0) | (UInt32(c.1) << 8) | (UInt32(c.2) << 16) | 0xFF00_0000
            } }
        } } }
    }

    static let SAND = rgb(0xf5dea2), SAND2 = rgb(0xecd08c), SAND3 = rgb(0xfff1c6), WET = rgb(0xddbb7c), LIP = rgb(0x5e9f45), LIP2 = rgb(0x73b752)
    static let GR = [0x84c35f, 0x8fd16a, 0x9bda76].map(rgb), FO = [0x4f9a4a, 0x5aa853, 0x66b45c].map(rgb), TUFT = rgb(0x6aa94b), TUFTF = rgb(0x3f8240)
    static let PATH = rgb(0xebd39b), PATHE = rgb(0xc9a46c), PEB = rgb(0xd4b67e)
    static let ASPH = rgb(0x6c7180), ASPH2 = rgb(0x626775), LANE = rgb(0xf6efd6), CURB = rgb(0xa9a39a), PAVE = rgb(0xdcd6cc), PAVE2 = rgb(0xc9c1b4), PAVE3 = rgb(0xe9e4dc)
    static let DS = [0xe1aa66, 0xecbc78, 0xf4cc8c].map(rgb), DSR = rgb(0xd49a58), DSL = rgb(0xf9dca6), DSP = rgb(0xc98f50)

    static func cityPx(_ M: TileMap, _ px: Int, _ py: Int, _ tc: UInt8) -> (UInt8, UInt8, UInt8) {
        let tx = px >> 4, ty = py >> 4, lx = px & 15, ly = py & 15
        func g(_ a: Int, _ b: Int) -> UInt8 { M.at(tx + a, ty + b) }
        if tc == Tile.W {
            if (ly >= 14 && g(0, 1) == Tile.r) || (ly <= 1 && g(0, -1) == Tile.r) || (lx <= 1 && g(-1, 0) == Tile.r) || (lx >= 14 && g(1, 0) == Tile.r) { return CURB }
            return (lx % 8 == 0 || ly % 8 == 0) ? PAVE2 : hash(px, py, 3) < 0.04 ? PAVE3 : PAVE
        }
        let hz = g(-1, 0) == Tile.r || g(1, 0) == Tile.r, vt = g(0, -1) == Tile.r || g(0, 1) == Tile.r
        var c = hash(px >> 1, py >> 1, 4) < 0.1 ? ASPH2 : ASPH
        if hz && !vt && (ly == 7 || ly == 8) && ((px >> 2) & 1) == 1 { c = LANE }
        if vt && !hz && (lx == 7 || lx == 8) && ((py >> 2) & 1) == 1 { c = LANE }
        if hz && vt {
            if g(0, 1) != Tile.r && ly > 11 && (lx & 2) != 0 { c = LANE }
            if g(0, -1) != Tile.r && ly < 4 && (lx & 2) != 0 { c = LANE }
            if g(1, 0) != Tile.r && lx > 11 && (ly & 2) != 0 { c = LANE }
            if g(-1, 0) != Tile.r && lx < 4 && (ly & 2) != 0 { c = LANE }
        }
        return c
    }

    static func desertPx(_ px: Int, _ py: Int) -> (UInt8, UInt8, UInt8) {
        let n = nz(Double(px) / 5, Double(py) / 5), r = sin(Double(px) * 0.16 + Double(py) * 0.5 + nz(Double(px) / 3 + 20, Double(py) / 3) * 7)
        if hash(px >> 1, py >> 1, 9) < 0.008 { return DSP }
        if r > 0.93 { return DSR }; if r < -0.96 { return DSL }
        return DS[n < 0.38 ? 0 : n > 0.62 ? 2 : 1]
    }

    static func land(_ F: IslandFields, _ canvas: PixelCanvas, _ M: TileMap) {
        let W = F.W, H = F.H
        for py in 0..<H { for px in 0..<W {
            let i = py * W + px; if F.land[i] == 0 { continue }
            let d = Double(F.dIn[i]), n = nz(Double(px) / 2, Double(py) / 2), tile = M.g[(py / TILE) * M.cols + px / TILE]
            let beach = 4.5 + n * 3.5 + M.beachExtra + (tile == Tile.s ? 99 : 0)
            let c: (UInt8, UInt8, UInt8)
            if d < 1.3 { c = WET }
            else if d < beach { let h = hash(px, py, 5); c = h < 0.07 ? SAND2 : h < 0.11 ? SAND3 : SAND }
            else if tile == Tile.r || tile == Tile.W { c = cityPx(M, px, py, tile) }
            else if d < beach + 1.6 && F.path[i] == 0 && F.desert[i] < 0.5 { c = LIP }
            else if d < beach + 2.6 && F.path[i] == 0 && F.desert[i] < 0.5 { c = LIP2 }
            else if F.path[i] != 0 { c = F.path[i] == 1 ? PATHE : hash(px >> 1, py >> 1, 6) < 0.05 ? PEB : PATH }
            else if F.desert[i] > 0.5 { c = desertPx(px, py) }
            else {
                let fo = F.forest[i] > 0.5, P = fo ? FO : GR, nn = nz(Double(px) / 1.4 + 9, Double(py) / 1.4)
                var cc = P[nn < 0.36 ? 0 : nn > 0.64 ? 2 : 1]
                if hash(px >> 1, py >> 1, 8) < 0.018 && (px & 1) == 0 { cc = fo ? TUFTF : TUFT }
                c = cc
            }
            canvas.put(i, c)
        } }
    }

    /// Land and objects on a transparent layer, so the sea underneath can move.
    static func topLayer(_ M: TileMap) -> PixelCanvas {
        let F = M.fields, canvas = PixelCanvas(width: F.W, height: F.H)
        land(F, canvas, M)
        drawObjects(M, canvas)
        return canvas
    }

    static func drawObjects(_ M: TileMap, _ canvas: PixelCanvas) {
        canvas.lights = []; canvas.beams = []
        let list = M.objs.sorted { ($0.y + $0.h, $0.x) < ($1.y + $1.h, $1.x) }
        for o in list { IslandDraw.draw(o, canvas) }
    }

    /// A whole still picture (sea + land + objects), for thumbnails.
    static func still(_ M: TileMap, t: Double = 0) -> PixelCanvas {
        let F = M.fields, canvas = PixelCanvas(width: F.W, height: F.H)
        land(F, canvas, M); water(F, canvas, t: t); drawObjects(M, canvas)
        return canvas
    }
}
