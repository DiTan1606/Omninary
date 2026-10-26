import CoreGraphics
import Foundation

// Pixel art kit ported from the island demo: an RGBA buffer painted with whole-pixel rectangles.

/// A colour with straight (non-premultiplied) alpha.
struct PixelColor: Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ hex: UInt32, _ alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF); g = Double((hex >> 8) & 0xFF); b = Double(hex & 0xFF); a = alpha
    }
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// Lighten toward white (f > 0) or darken toward black (f < 0), as the demo's shade().
    func shade(_ f: Double) -> PixelColor {
        func m(_ v: Double) -> Double { max(0, min(255, (f >= 0 ? v + (255 - v) * f : v * (1 + f)).rounded())) }
        return PixelColor(r: m(r), g: m(g), b: m(b), a: a)
    }

    var packed: UInt32 {
        // premultiplied RGBA in memory order R, G, B, A (little endian UInt32)
        let pa = a
        let pr = UInt32((r * pa).rounded()), pg = UInt32((g * pa).rounded()), pb = UInt32((b * pa).rounded()), aa = UInt32((pa * 255).rounded())
        return pr | (pg << 8) | (pb << 16) | (aa << 24)
    }
}

typealias PC = PixelColor
let OL = PC(0x3a2b3f)

/// Shade a hex colour, keeping it as a colour.
func shade(_ hex: UInt32, _ f: Double) -> PC { PC(hex).shade(f) }

// MARK: - Deterministic noise and random numbers, bit-compatible with the demo

@inline(__always) func hash(_ x: Int, _ y: Int, _ i: Int) -> Double {
    let s = Int64(x) &* 374_761_393 &+ Int64(y) &* 668_265_263 &+ Int64(i) &* 1_442_695_041
    var h = UInt32(truncatingIfNeeded: s)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    return Double(h ^ (h >> 16)) / 4_294_967_296
}

/// mulberry32, as rng32() in the demo.
struct Rng32 {
    var seed: UInt32
    init(_ seed: Int) { self.seed = UInt32(truncatingIfNeeded: seed) }
    mutating func next() -> Double {
        seed = seed &+ 0x6D2B_79F5
        var t = (seed ^ (seed >> 15)) &* (1 | seed)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
    mutating func callAsFunction() -> Double { next() }
}

enum Noise {
    static let size = 128
    static let table: [Float] = {
        var g = [Double](repeating: 0, count: 256)
        for i in 0..<256 { g[i] = hash(i % 16, i >> 4, 77) }
        func sm(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        func G(_ i: Int, _ j: Int) -> Double { g[(j & 15) * 16 + (i & 15)] }
        var out = [Float](repeating: 0, count: size * size)
        for y in 0..<size { for x in 0..<size {
            let fx = Double(x) / 8, fy = Double(y) / 8, x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
            let tx = sm(fx - Double(x0)), ty = sm(fy - Double(y0))
            out[y * size + x] = Float((G(x0, y0) * (1 - tx) + G(x0 + 1, y0) * tx) * (1 - ty) + (G(x0, y0 + 1) * (1 - tx) + G(x0 + 1, y0 + 1) * tx) * ty)
        } }
        return out
    }()
}

/// Smooth value noise sampled at a point (fraction truncated toward zero like JS `| 0`).
@inline(__always) func nz(_ x: Double, _ y: Double) -> Double {
    let xi = Int(x.rounded(.towardZero)) & (Noise.size - 1), yi = Int(y.rounded(.towardZero)) & (Noise.size - 1)
    return Double(Noise.table[yi * Noise.size + xi])
}

@inline(__always) func jsRound(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

// MARK: - The canvas

final class PixelCanvas {
    let width: Int, height: Int
    var pixels: [UInt32]
    /// Window panes and lamps that glow at night, in canvas pixels.
    var lights: [(Double, Double, Double, Double)] = []
    /// Lighthouse lamp positions for the night beam.
    var beams: [(Double, Double)] = []

    init(width: Int, height: Int, fill: UInt32 = 0) {
        self.width = width; self.height = height
        pixels = [UInt32](repeating: fill, count: width * height)
    }

    /// Opaque write of a packed colour, no blending (terrain painting).
    @inline(__always) func put(_ i: Int, _ rgb: (UInt8, UInt8, UInt8)) {
        pixels[i] = UInt32(rgb.0) | (UInt32(rgb.1) << 8) | (UInt32(rgb.2) << 16) | 0xFF00_0000
    }

    /// Source-over fill of a rectangle, with JS-style rounding of the corners.
    func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: PC) {
        guard w > 0, h > 0, c.a > 0 else { return }
        let x0 = jsRound(x), y0 = jsRound(y), x1 = x0 + jsRound(w), y1 = y0 + jsRound(h)
        let cx0 = max(0, x0), cy0 = max(0, y0), cx1 = min(width, x1), cy1 = min(height, y1)
        guard cx0 < cx1, cy0 < cy1 else { return }
        let src = c.packed
        if c.a >= 1 {
            pixels.withUnsafeMutableBufferPointer { p in
                for yy in cy0..<cy1 { let row = yy * width; for xx in cx0..<cx1 { p[row + xx] = src } }
            }
            return
        }
        let sr = src & 0xFF, sg = (src >> 8) & 0xFF, sb = (src >> 16) & 0xFF, sa = src >> 24, inv = 255 - sa
        pixels.withUnsafeMutableBufferPointer { p in
            for yy in cy0..<cy1 { let row = yy * width; for xx in cx0..<cx1 {
                let d = p[row + xx]
                let dr = d & 0xFF, dg = (d >> 8) & 0xFF, db = (d >> 16) & 0xFF, da = d >> 24
                let r = sr + (dr * inv + 127) / 255, g = sg + (dg * inv + 127) / 255, b = sb + (db * inv + 127) / 255, a = sa + (da * inv + 127) / 255
                p[row + xx] = min(r, 255) | (min(g, 255) << 8) | (min(b, 255) << 16) | (min(a, 255) << 24)
            } }
        }
    }
    func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: UInt32) { R(x, y, w, h, PC(hex)) }
    func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: UInt32) { R(Double(x), Double(y), Double(w), Double(h), PC(hex)) }

    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: PC, _ ol: PC = OL) { R(x - 1, y - 1, w + 2, h + 2, ol); R(x, y, w, h, c) }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: UInt32) { box(x, y, w, h, PC(hex)) }

    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: PC, _ ryIn: Double? = nil) {
        let ry = ryIn ?? r
        let lim = Int(ry.rounded(.up))
        for j in -lim...lim {
            let s = 1 - pow(Double(j) / ry, 2); if s < 0 { continue }
            let hw = Double(jsRound(r * s.squareRoot()))
            R(cx - hw, cy + Double(j), hw * 2, 1, c)
        }
    }
    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ hex: UInt32, _ ry: Double? = nil) { disc(cx, cy, r, PC(hex), ry) }
    func odisc(_ cx: Double, _ cy: Double, _ r: Double, _ c: PC, _ ryIn: Double? = nil) {
        let ry = ryIn ?? r
        disc(cx, cy, r + 1, OL, ry + 1); disc(cx, cy, r, c, ry)
    }
    func odisc(_ cx: Double, _ cy: Double, _ r: Double, _ hex: UInt32, _ ry: Double? = nil) { odisc(cx, cy, r, PC(hex), ry) }

    func shadow(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { R(x, y, w, h, PC(r: 25, g: 45, b: 40, a: 0.28)) }
    func eshadow(_ cx: Double, _ cy: Double, _ r: Double, _ ry: Double) {
        let c = PC(r: 25, g: 45, b: 40, a: 0.26), lim = Int(ry)
        for j in -lim...lim {
            let hw = Double(jsRound(r * max(0, 1 - pow(Double(j) / ry, 2)).squareRoot()))
            R(Double(jsRound(cx - hw)), Double(jsRound(cy + Double(j))), hw * 2, 1, c)
        }
    }
    func light(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { lights.append((x, y, w, h)) }

    func makeImage() -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A copy of a rectangle as an image (for the moving sea, redrawn only where the camera looks).
    func makeImage(x: Int, y: Int, w: Int, h: Int) -> CGImage? {
        guard w > 0, h > 0 else { return nil }
        var sub = [UInt32](repeating: 0, count: w * h)
        for j in 0..<h { let sy = y + j; guard sy >= 0, sy < height else { continue }
            for i in 0..<w { let sx = x + i; if sx >= 0, sx < width { sub[j * w + i] = pixels[sy * width + sx] } } }
        let data = sub.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Shared drawing helpers (windows, doors, buildings, people)

extension PixelCanvas {
    func windowAt(_ x: Double, _ y: Double, _ w: Double = 6, _ h: Double = 7, _ glass: UInt32 = 0x86c9ea, _ frame: PC = PC(0xffffff)) {
        R(x - 1, y - 1, w + 2, h + 2, OL); R(x, y, w, h, frame); R(x + 1, y + 1, w - 2, h - 2, PC(glass))
        R(x + 1, y + 1, 1, h - 3, 0xc8ecfa); R(x + 2, y + 1, 1, 1, 0xe9f8ff)
        R(x + (w / 2).rounded(.down), y + 1, 1, h - 2, frame); R(x + 1, y + (h / 2).rounded(.down), w - 2, 1, frame)
        R(x - 1, y + h + 1, w + 2, 1, frame.shade(-0.25)); light(x + 1, y + 1, w - 2, h - 2)
    }
    func doorAt(_ x: Double, _ y: Double, _ w: Double = 7, _ h: Double = 10, _ c: UInt32 = 0x8a5a3a) {
        R(x - 1, y - 1, w + 2, h + 1, OL); R(x, y, w, h, c); R(x + 1, y + 1, w - 2, h - 1, shade(c, 0.12)); R(x + 1, y + 1, 1, h - 1, shade(c, 0.3))
        R(x + w - 2, y + (h / 2).rounded(.down), 1, 1, 0xffd35a); R(x - 2, y + h, w + 4, 2, 0xb7aa98); R(x - 2, y + h + 2, w + 4, 1, 0x8d8170); light(x + 1, y + 1, w - 2, 3)
    }

    struct BuildingStyle {
        var wall: PC, roof: PC
        var planks = false, brick = false, flat = false
        var side: Double = 5
        var wallH: Double? = nil
        var lift: Double = 4
    }
    struct BuildingBox { let wy: Double, wallH: Double, fw: Double, ry: Double }

    /// Generic 3/4 building: footprint, front wall with a side face, sloped or flat roof.
    @discardableResult
    func building(_ px: Double, _ py: Double, _ pw: Double, _ ph: Double, _ o: BuildingStyle) -> BuildingBox {
        let wallH = o.wallH ?? Double(jsRound(ph * 0.48)), side = o.side, wy = py + ph - wallH, wall = o.wall, roof = o.roof
        shadow(px + 4, py + 6, pw + 2, ph - 2)
        R(px - 1, wy - 1, pw + 2, wallH + 2, OL)
        R(px, wy, pw - side, wallH, wall); R(px + pw - side, wy, side, wallH, wall.shade(-0.22))
        if o.brick {
            var y = wy + 2
            while y < wy + wallH {
                R(px, y, pw - side, 1, wall.shade(-0.12))
                // JS: (y / 3) % 2 ? 2 : 5 — any non-zero remainder counts as true
                let rem = (y / 3).truncatingRemainder(dividingBy: 2)
                var x = px + (rem != 0 ? 2 : 5)
                while x < px + pw - side { R(x, y - 2, 1, 2, wall.shade(-0.12)); x += 6 }
                y += 3
            }
        }
        if o.planks { var y = wy + 3; while y < wy + wallH { R(px, y, pw - side, 1, wall.shade(-0.08)); y += 3 } }
        R(px, wy + wallH - 2, pw - side, 2, wall.shade(-0.3)); R(px + pw - side, wy + wallH - 2, side, 2, wall.shade(-0.45))
        R(px + pw - side, wy, 1, wallH, wall.shade(-0.35))
        let ry = py - o.lift, rh = wy - ry + 3, rx = px - 2, rw = pw + 4
        if o.flat {
            R(rx - 1, ry - 1, rw + 2, rh + 2, OL); R(rx, ry, rw, rh, roof.shade(0.1)); R(rx + 2, ry + 2, rw - 4, rh - 5, roof); R(rx + 2, ry + 2, rw - 4, 1, roof.shade(-0.15))
            R(rx, ry + rh - 3, rw, 3, roof.shade(-0.25))
        } else {
            R(rx - 1, ry - 1, rw + 2, rh + 2, OL)
            var y = 0.0
            while y < rh { let f = y / rh; R(rx, ry + y, rw, 1, roof.shade(0.22 - f * 0.38)); y += 1 }
            y = 3
            while y < rh - 2 {
                R(rx, ry + y, rw, 1, roof.shade(-0.18 - y / rh * 0.2))
                let rem = (y / 3).truncatingRemainder(dividingBy: 2)
                var x = rx + (rem != 0 ? 1 : 4)
                while x < rx + rw { R(x, ry + y - 2, 1, 2, roof.shade(-0.15)); x += 6 }
                y += 3
            }
            R(rx, ry, rw, 2, roof.shade(0.4)); R(rx + 1, ry, rw - 2, 1, roof.shade(0.6))
            y = 0
            while y < rh { let w = min(side + 2, Double(jsRound(y * (side + 2) / rh)) + 2); R(rx + rw - w, ry + y, w, 1, roof.shade(-0.3 - y / rh * 0.2)); y += 1 }
            R(rx, ry + rh - 1, rw, 1, roof.shade(-0.5))
        }
        R(px, wy + 2, pw - side, 2, PC(r: 30, g: 20, b: 40, a: 0.25))
        return BuildingBox(wy: wy, wallH: wallH, fw: pw - side, ry: ry)
    }

    func chimney(_ x: Double, _ y: Double, _ c: UInt32 = 0xb9806a) { R(x - 1, y - 1, 7, 10, OL); R(x, y, 5, 9, c); R(x + 4, y, 1, 9, shade(c, -0.3)); R(x - 1, y - 2, 7, 3, shade(c, -0.2)); R(x, y - 2, 5, 1, shade(c, 0.2)) }
    func smoke(_ x: Double, _ y: Double) {
        for (a, b, r) in [(0.0, 0.0, 3.0), (2, -5, 3.6), (-1, -11, 4.2)] {
            disc(x + a, y + b, r + 1, PC(r: 120, g: 120, b: 140, a: 0.25)); disc(x + a, y + b, r, PC(r: 250, g: 250, b: 255, a: 0.85))
        }
    }
    func awning(_ x: Double, _ y: Double, _ w: Double, _ c1: UInt32, _ c2: UInt32 = 0xffffff) {
        R(x - 1, y - 1, w + 2, 7, OL)
        var i = 0.0
        while i < w { let c = Int(i / 4) % 2 == 1 ? c2 : c1; R(x + i, y, min(4, w - i), 5, c); R(x + i, y + 4, min(4, w - i), 1, shade(c, -0.25)); i += 4 }
        i = 0
        while i < w { let c = Int(i / 4) % 2 == 1 ? c2 : c1; R(x + i, y + 5, min(4, w - i), 1, OL); R(x + i + 1, y + 5, max(0, min(2, w - i - 1)), 1, c); i += 4 }
        R(x, y, w, 1, PC(r: 255, g: 255, b: 255, a: 0.35))
    }
    func crate(_ x: Double, _ y: Double, _ s: Double = 6, _ c: UInt32 = 0xc98a4b) { R(x - 1, y - 1, s + 2, s + 2, OL); R(x, y, s, s, c); R(x, y, s, 2, shade(c, 0.25)); R(x + s - 1, y + 2, 1, s - 2, shade(c, -0.25)); R(x + 1, y + 3, s - 2, 1, shade(c, -0.2)) }
    func barrel(_ x: Double, _ y: Double, _ c: UInt32 = 0xa8743c) { R(x, y - 1, 6, 1, OL); R(x - 1, y, 8, 8, OL); R(x, y, 6, 8, c); R(x, y, 6, 2, shade(c, 0.3)); R(x, y + 3, 6, 1, 0x6b6b7a); R(x, y + 6, 6, 1, 0x6b6b7a); R(x + 4, y + 2, 2, 6, shade(c, -0.2)) }
    func flowerBox(_ x: Double, _ y: Double, _ w: Double) {
        R(x - 1, y - 1, w + 2, 4, OL); R(x, y, w, 2, 0x8a5a3a)
        var i = 1.0
        while i < w - 1 { R(x + i, y - 2, 1, 2, [0xff6b8a, 0xffd35a, 0xffffff][Int(i) % 3]); i += 2 }
    }

    struct PersonLook { var hat: UInt32? = nil; var bubble = false }
    func person(_ cx: Double, _ by: Double, _ hair: UInt32, _ cloth: UInt32, _ o: PersonLook = PersonLook()) {
        eshadow(cx, by, 5, 2)
        R(cx - 3, by - 5, 2, 5, OL); R(cx + 1, by - 5, 2, 5, OL); R(cx - 2, by - 5, 1, 4, 0x4a3b5e); R(cx + 1, by - 5, 1, 4, 0x4a3b5e)
        R(cx - 5, by - 13, 10, 9, OL); R(cx - 4, by - 12, 8, 7, cloth); R(cx + 2, by - 12, 2, 7, shade(cloth, -0.25)); R(cx - 4, by - 12, 8, 1, shade(cloth, 0.3))
        R(cx - 5, by - 22, 10, 10, OL); R(cx - 4, by - 21, 8, 8, 0xffd9b8); R(cx + 2, by - 21, 2, 8, 0xf1bf98)
        R(cx - 4, by - 22, 8, 4, hair); R(cx - 4, by - 18, 2, 3, hair); R(cx + 3, by - 18, 1, 2, hair)
        R(cx - 2, by - 16, 1, 1, OL); R(cx + 1, by - 16, 1, 1, OL)
        if let hat = o.hat { R(cx - 6, by - 23, 12, 2, OL); R(cx - 5, by - 23, 10, 1, hat); R(cx - 3, by - 26, 6, 3, OL); R(cx - 2, by - 25, 4, 2, hat) }
        if o.bubble {
            let bx = cx + 2, byy = by - 36
            R(bx - 1, byy - 1, 11, 11, OL); R(bx, byy, 9, 9, 0xffd35a); R(bx, byy, 9, 1, 0xfff2a8); R(bx + 4, byy + 2, 2, 4, OL); R(bx + 4, byy + 7, 2, 1, OL); R(bx + 1, byy + 10, 2, 2, OL)
        }
    }
}

// MARK: - Night lighting

extension PixelCanvas {
    /// Multiply a rectangle by a colour (premultiplied pixels keep their alpha).
    func multiplyRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, by c: (UInt32, UInt32, UInt32)) {
        let sx = max(0, x0), sy = max(0, y0), ex = min(width, x1), ey = min(height, y1)
        guard sx < ex, sy < ey else { return }
        pixels.withUnsafeMutableBufferPointer { p in
            for y in sy..<ey { let row = y * width; for x in sx..<ex {
                let d = p[row + x]
                let r = (d & 0xFF) * c.0 / 255, g = ((d >> 8) & 0xFF) * c.1 / 255, b = ((d >> 16) & 0xFF) * c.2 / 255
                p[row + x] = r | (g << 8) | (b << 16) | (d & 0xFF00_0000)
            } }
        }
    }

    /// The demo's night: everything tinted blue, windows and lamps glowing warm.
    func nightPass() {
        multiplyRect(0, 0, width, height, by: (0x4b, 0x5a, 0xa6))
        for (x, y, w, h) in lights {
            let cx = x + w / 2, cy = y + h / 2
            let x0 = Int(x - 24), y0 = Int(y - 24), x1 = Int(x + w + 24), y1 = Int(y + h + 24)
            pixels.withUnsafeMutableBufferPointer { p in
                for yy in max(0, y0)..<min(height, y1) { for xx in max(0, x0)..<min(width, x1) {
                    let d = hypot(Double(xx) + 0.5 - cx, Double(yy) + 0.5 - cy)
                    let a = 0.42 * max(0, 1 - (d - 1) / 21)
                    guard a > 0.004 else { continue }
                    let i = yy * width + xx, px = p[i], da = px >> 24
                    guard da > 0 else { continue }
                    let inv = 1 - a
                    let r = UInt32(min(255, 255 * a + Double(px & 0xFF) * inv)), g = UInt32(min(255, 210 * a + Double((px >> 8) & 0xFF) * inv)), b = UInt32(min(255, 110 * a + Double((px >> 16) & 0xFF) * inv))
                    p[i] = r | (g << 8) | (b << 16) | (da << 24)
                } }
            }
        }
        for (x, y, w, h) in lights { R(x, y, w, h, 0xffd76a); R(x, y, max(1, (w / 2).rounded(.down)), 1, 0xfff2b8) }
        for (bx, by) in beams {
            // a soft cone toward the east
            for i in 0..<130 { let f = Double(i) / 130, top = by - 46 * f, bottom = by + 24 * f
                R(bx + Double(i), top, 1, max(1, bottom - top), PC(r: 255, g: 240, b: 170, a: 0.16)) }
        }
    }
}
