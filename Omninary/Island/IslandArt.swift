import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Pictures for the adventure path, drawn by the island engine on the device and cached on disk:
// each stage island cut out of its sea with a soft shallow-water edge, plus its dock and level spots.

struct IsleArt {
    let image: CGImage
    /// The same island at night: tinted blue with its windows and lamps lit.
    let nightImage: CGImage
    /// Where the cut-out sits in the stage map, in map pixels (land plus its shallow water).
    let crop: CGRect
    /// The land alone, in map pixels: what the path lines up and labels.
    let land: CGRect
    let dock: CGPoint
    /// The six level flags, nearest the dock first, in map pixels.
    let levels: [CGPoint]
}

enum IslandArt {
    private static let version = 6
    private static var memory: [Int: IsleArt] = [:]
    private static let lock = NSLock()

    static func cached(_ map: Int) -> IsleArt? { lock.lock(); defer { lock.unlock() }; return memory[map] }

    /// The island of map `map` (0…59). Slow the first time: call it off the main thread.
    static func isle(_ map: Int) -> IsleArt {
        if let art = cached(map) { return art }
        let art = loadFromDisk(map) ?? render(map)
        lock.lock(); memory[map] = art; lock.unlock()
        return art
    }

    /// The deep sea colour the engine's water settles on; the path's sea is painted in it too.
    static let deep: UInt32 = 0x2b66ae

    // MARK: render

    /// Cliff face under the land, light sand at the top to dark earth at the waterline.
    private static let cliff: [UInt32] = [0xe6c284, 0xd4a86a, 0xc09158, 0xab7b49, 0x96673d, 0x825633, 0x6f472b, 0x5e3b25, 0x4f3120]

    /// The stage map's land as the engine paints it, raised off the water: a cliff face under its
    /// south edge, a thin line of foam around it and its shadow cast down-right on the sea. The
    /// sea itself is left to the path, which paints the open water around every island the same way.
    private static func render(_ map: Int) -> IsleArt {
        let M = AdventureMaps.region(map).map(AdventureMaps.stage(map))
        let canvas = IslandPaint.still(M, t: 0)
        let W = canvas.width, H = canvas.height, n = W * H
        // index of each sea colour (0 white foam … 9 deep), in the canvas' byte order
        var seaIndex: [UInt32: Int] = [:]
        for (k, c) in IslandPaint.sea.enumerated() { seaIndex[UInt32(c.0) | (UInt32(c.1) << 8) | (UInt32(c.2) << 16) | 0xFF00_0000] = k }
        var water = [Int](repeating: -1, count: n)
        for i in 0..<n { water[i] = seaIndex[canvas.pixels[i]] ?? -1 }
        // distance to the coast: white next to land is a detail of the island, not foam
        let dist = IslandFields.distance(W, H) { water[$0] < 0 }
        var land = [Bool](repeating: false, count: n)
        for i in 0..<n { land[i] = water[i] < 0 || (water[i] == 0 && dist[i] <= 1) }
        func L(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && land[y * W + x] }
        // the island with its cliff: land, or land up to 9 px above
        var body = [Bool](repeating: false, count: n), cliffRow = [Int](repeating: -1, count: n)
        for y in 0..<H { for x in 0..<W {
            let i = y * W + x
            if land[i] { body[i] = true; continue }
            for d in 1...9 where L(x, y - d) { body[i] = true; cliffRow[i] = d - 1; break }
        } }
        func B(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < W && y < H && body[y * W + x] }
        func rgba(_ hex: UInt32, _ a: UInt32) -> UInt32 {
            let r = (hex >> 16) & 0xFF, g = (hex >> 8) & 0xFF, b = hex & 0xFF
            return (r * a / 255) | ((g * a / 255) << 8) | ((b * a / 255) << 16) | (a << 24)
        }
        let foam = rgba(0xffffff, 220), shadow = rgba(0x103068, 150)
        var out = [UInt32](repeating: 0, count: n)
        var minX = W, minY = H, maxX = 0, maxY = 0, lx0 = W, ly0 = H, lx1 = 0, ly1 = 0
        for y in 0..<H { for x in 0..<W {
            let i = y * W + x
            if land[i] { out[i] = canvas.pixels[i]; lx0 = min(lx0, x); lx1 = max(lx1, x); ly0 = min(ly0, y); ly1 = max(ly1, y) }
            else if cliffRow[i] >= 0 { out[i] = rgba(cliff[cliffRow[i]], 255) }
            else if (-2...2).contains(where: { dy in (-2...2).contains { dx in B(x + dx, y + dy) } }) { out[i] = foam }
            else if (4..<20).contains(where: { d in B(x - d / 2, y - d) }) { out[i] = shadow }
            else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let x0 = max(0, minX - 1), y0 = max(0, minY - 1), x1 = min(W, maxX + 2), y1 = min(H, maxY + 2)
        let cw = x1 - x0, ch = y1 - y0
        var crop = [UInt32](repeating: 0, count: cw * ch)
        for y in 0..<ch { for x in 0..<cw { crop[y * cw + x] = out[(y + y0) * W + (x + x0)] } }
        let image = makeImage(crop, cw, ch)!
        // night: the engine's night pass on the land, the cliff, foam and shadow dimmed to match
        canvas.nightPass()
        let tint: (UInt32, UInt32, UInt32) = (0x4b, 0x5a, 0xa6)
        var nightCrop = [UInt32](repeating: 0, count: cw * ch)
        for y in 0..<ch { for x in 0..<cw {
            let i = (y + y0) * W + (x + x0), d = out[i]
            if land[i] { nightCrop[y * cw + x] = canvas.pixels[i]; continue }
            let r = (d & 0xFF) * tint.0 / 255, g = ((d >> 8) & 0xFF) * tint.1 / 255, b = ((d >> 16) & 0xFF) * tint.2 / 255
            nightCrop[y * cw + x] = r | (g << 8) | (b << 16) | (d & 0xFF00_0000)
        } }
        let nightImage = makeImage(nightCrop, cw, ch)!
        let dock = M.dock.map { CGPoint(x: $0.0 * TILE + 8, y: $0.1 * TILE + 8) } ?? CGPoint(x: (lx0 + lx1) / 2, y: ly1)
        let spots = M.quests.map { CGPoint(x: $0.x * TILE + 8, y: $0.y * TILE + 8) }
        let art = IsleArt(image: image, nightImage: nightImage, crop: CGRect(x: x0, y: y0, width: cw, height: ch),
                          land: CGRect(x: lx0, y: ly0, width: max(1, lx1 - lx0 + 1), height: max(1, ly1 - ly0 + 1)),
                          dock: dock, levels: levelSpots(spots, dock: dock))
        saveToDisk(map, art)
        return art
    }

    /// Six quest spots as far apart as possible, ordered from the dock inwards.
    static func levelSpots(_ spots: [CGPoint], dock: CGPoint) -> [CGPoint] {
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        var pool = spots.sorted { d($0, dock) < d($1, dock) }
        guard !pool.isEmpty else { return [] }
        var chosen = [pool.removeFirst()]
        while chosen.count < 6, !pool.isEmpty {
            let best = pool.indices.max { a, b in chosen.map { d($0, pool[a]) }.min()! < chosen.map { d($0, pool[b]) }.min()! }!
            chosen.append(pool.remove(at: best))
        }
        return chosen.sorted { d($0, dock) < d($1, dock) }
    }

    static func makeImage(_ pixels: [UInt32], _ w: Int, _ h: Int) -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: disk cache

    private struct Meta: Codable { let crop: [Double]; let land: [Double]; let dock: [Double]; let levels: [[Double]] }
    private static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("island-art-v\(version)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func saveToDisk(_ map: Int, _ art: IsleArt) {
        let png = folder.appendingPathComponent("map-\(map).png")
        if let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, art.image, nil); CGImageDestinationFinalize(dest)
        }
        let nightPNG = folder.appendingPathComponent("map-\(map)-night.png")
        if let dest = CGImageDestinationCreateWithURL(nightPNG as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, art.nightImage, nil); CGImageDestinationFinalize(dest)
        }
        let meta = Meta(crop: [art.crop.minX, art.crop.minY, art.crop.width, art.crop.height], land: [art.land.minX, art.land.minY, art.land.width, art.land.height],
                        dock: [art.dock.x, art.dock.y], levels: art.levels.map { [$0.x, $0.y] })
        try? JSONEncoder().encode(meta).write(to: folder.appendingPathComponent("map-\(map).json"))
    }
    private static func loadFromDisk(_ map: Int) -> IsleArt? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("map-\(map).json")),
              let meta = try? JSONDecoder().decode(Meta.self, from: data), meta.crop.count == 4, meta.land.count == 4,
              let src = CGImageSourceCreateWithURL(folder.appendingPathComponent("map-\(map).png") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let nightSrc = CGImageSourceCreateWithURL(folder.appendingPathComponent("map-\(map)-night.png") as CFURL, nil),
              let nightImage = CGImageSourceCreateImageAtIndex(nightSrc, 0, nil) else { return nil }
        return IsleArt(image: image, nightImage: nightImage, crop: CGRect(x: meta.crop[0], y: meta.crop[1], width: meta.crop[2], height: meta.crop[3]),
                       land: CGRect(x: meta.land[0], y: meta.land[1], width: meta.land[2], height: meta.land[3]),
                       dock: CGPoint(x: meta.dock[0], y: meta.dock[1]), levels: meta.levels.map { CGPoint(x: $0[0], y: $0[1]) })
    }
}

// MARK: - The open sea of the path

enum SeaArt {
    /// A tile of open sea painted by the engine's water at a few moments, for the glints to twinkle.
    static let frames = paint(night: false)
    /// The same water under the night tint the stage maps use.
    static let nightFrames = paint(night: true)

    private static func paint(night: Bool) -> [CGImage] {
        let M = TileMap("sea", 12, 12)
        let F = IslandFields(M)
        return (0..<8).compactMap { k in
            let c = PixelCanvas(width: F.W, height: F.H)
            IslandPaint.water(F, c, t: Double(k) * 0.19)
            if night { c.multiplyRect(0, 0, c.width, c.height, by: (0x4b, 0x5a, 0xa6)) }
            return c.makeImage()
        }
    }
}

// MARK: - Pixel clouds: plain white with blocky puffs

enum CloudArt {
    private static let white: UInt32 = 0xFFFFFFFF

    private struct Rand {
        var s: UInt32
        mutating func int(_ lo: Int, _ hi: Int) -> Int { s = s &* 1_664_525 &+ 1_013_904_223; return lo + Int(s >> 8) % (hi - lo + 1) }
    }

    /// Puffs along a vertical edge at `base`, radius rmin…rmax, spaced so the scallops stay deep.
    private static func edge(_ r: inout Rand, base: Int, rmin: Int, rmax: Int, height: Int) -> [(Double, Double, Double)] {
        var out: [(Double, Double, Double)] = [], y = -2
        while y < height + 10 {
            let rad = r.int(rmin, rmax)
            out.append((Double(base + r.int(-2, 2)), Double(y), Double(rad)))
            y += Int(Double(rad) * 1.75)
        }
        return out
    }

    private static func raster(_ w: Int, _ h: Int, _ layer: (Double, Double) -> UInt32?) -> CGImage? {
        var px = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { px[y * w + x] = layer(Double(x) + 0.5, Double(y) + 0.5) ?? 0 } }
        return IslandArt.makeImage(px, w, h)
    }

    /// A tall white cloud bank for one side of the scene change: flat on the outside, puffy on
    /// the inside edge. Drawn small so the puffs come out as chunky blocks.
    static func column(seed: UInt32) -> CGImage? {
        let w = 32, h = 70
        var r = Rand(s: seed)
        let puffs = edge(&r, base: 13, rmin: 6, rmax: 10, height: h)
        return raster(w, h) { x, y in
            x < 13 || puffs.contains { (x - $0.0) * (x - $0.0) + (y - $0.1) * (y - $0.1) <= $0.2 * $0.2 } ? white : nil
        }
    }
    static let left = column(seed: 5)
    static let right = column(seed: 11)

    /// One small white cloud drifting over the sea.
    static let puff: CGImage? = raster(26, 14) { x, y in
        let top: [(Double, Double, Double)] = [(8, 8, 4.5), (14, 6, 5.5), (19.5, 8.5, 4)]
        let base: [(Double, Double, Double)] = [(6, 10, 4), (13, 9.5, 5.5), (20, 10, 4.5)]
        func hit(_ list: [(Double, Double, Double)]) -> Bool { list.contains { (x - $0.0) * (x - $0.0) + (y - $0.1) * (y - $0.1) <= $0.2 * $0.2 } }
        return (hit(top) && y < 10) || hit(base) || (y >= 9 && y < 13.5 && x > 3 && x < 23) ? white : nil
    }
}
