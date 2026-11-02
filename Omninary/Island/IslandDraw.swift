import Foundation

// Every object the island and the stage maps can show, drawn pixel by pixel as in the demo.

let ROOFS: [UInt32] = [0x3f6fca, 0x2f9e8f, 0xc0563f, 0xd98a3a, 0x5b8a5a]

enum IslandDraw {
    static func draw(_ o: IslandObject, _ X: PixelCanvas) {
        let x = Double(o.x * TILE), y = Double(o.y * TILE), w = Double(o.w * TILE), h = Double(o.h * TILE)
        switch o.kind {
        case "house": house(o, X, x, y, w, h)
        case "school": school(X, x, y, w, h)
        case "hospital": hospital(X, x, y, w, h)
        case "bakery": bakery(X, x, y, w, h)
        case "greenhouse": greenhouse(X, x, y, w, h)
        case "windmill": windmill(X, x, y, w, h)
        case "lighthouse": lighthouse(X, x, y, w, h)
        case "pagoda": pagoda(X, x, y, w, h)
        case "statue": statue(X, x, y, w, h)
        case "fountain": fountain(X, x, y, w, h)
        case "portal": portal(X, x, y, w, h)
        case "mailbox": mailbox(X, x, y)
        case "boat": boat(X, x, y, w)
        case "dock": dock(X, x, y, w, h)
        case "field": field(o, X, x, y, w, h)
        case "tent": tent(X, x, y, w, h)
        case "camp": camp(X, x, y)
        case "tree": tree(o, X, x, y)
        case "bush": bush(o, X, x, y)
        case "flowers": flowers(o, X, x, y)
        case "fern": fern(X, x, y)
        case "rock": rock(X, x, y)
        case "mushbig": mushbig(X, x, y)
        case "herb": herb(X, x, y)
        case "log": log(X, x, y)
        case "stump": stump(X, x, y)
        case "shellpile": shellpile(X, x, y)
        case "reedbig": reedbig(X, x, y)
        case "lotuspad": lotuspad(X, x, y)
        case "fishspot": fishspot(X, x, y)
        case "npc": X.person(x + 8, y + 14, o.hair, o.cloth, .init(hat: o.hat, bubble: o.bubble))
        case "lab": lab(X, x, y, w, h)
        case "lot": lot(X, x, y, w, h)
        case "scaffold": scaffold(X, x, y, w, h)
        case "flowerbed": flowerbed(o, X, x, y, w, h)
        case "apartment": apartment(o, X, x, y, w, h)
        case "office": office(o, X, x, y, w, h)
        case "bookstore": bookstore(o, X, x, y, w, h)
        case "cafe": cafe(o, X, x, y, w, h)
        case "clocktower": clocktower(X, x, y, w, h)
        case "park": X.R(x + 1, y + 1, w - 2, h - 2, 0x7fc760); for i in 0..<6 { X.R(x + 6 + Double(i * 7), y + 26, 4, 2, 0xebd39b) }
        case "bench": bench(X, x, y)
        case "car": car(o, X, x, y)
        case "lamp": lamp(X, x, y)
        case "signpost": signpost(X, x, y)
        case "poster": poster(X, x, y)
        case "newsstand": newsstand(X, x, y)
        case "letterbox": letterbox(X, x, y)
        case "pyramid": pyramid(X, x, y, w, h)
        case "column": column(o, X, x, y)
        case "adobe": adobe(o, X, x, y, w, h)
        case "market": market(X, x, y, w, h)
        case "camel": camel(X, x, y)
        case "cactus": cactus(o, X, x, y)
        case "drybush": drybush(X, x, y)
        case "pottery": pottery(X, x, y)
        case "fossil": fossil(X, x, y)
        case "gem": gem(X, x, y)
        default: break
        }
    }

    // MARK: buildings

    static func house(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(o.wall ?? 0xf6ead2), roof: PC(o.roof ?? 0x3f6fca), planks: true, side: 6))
        if o.mine {
            X.chimney(x + 10, y - 6); X.smoke(x + 12, y - 12)
            let wl = b.fw < 50 ? 4.0 : 8, wr = b.fw < 50 ? b.fw - 12 : b.fw - 18
            X.windowAt(x + wl, b.wy + 6, 8, 8); X.windowAt(x + wr, b.wy + 6, 8, 8); X.flowerBox(x + wl - 1, b.wy + 16, 10); X.flowerBox(x + wr - 1, b.wy + 16, 10)
            X.doorAt(x + (b.fw / 2).rounded(.down) - 4, b.wy + b.wallH - 13, 8, 13)
            var i = 0.0
            while i < 18 { X.R(x - 8 + i - 1, y + h + 1, 3, 7, OL); X.R(x - 8 + i, y + h + 2, 1, 5, 0xffffff); i += 3 }
            X.R(x - 9, y + h + 4, 19, 1, 0xffffff)
        } else if o.sign == "bag" {
            let ww = b.fw < 50 ? 8.0 : 12
            X.windowAt(x + (b.fw < 50 ? 4 : 6), b.wy + 5, ww, 10, 0x8fd2ef); X.windowAt(x + b.fw - ww - (b.fw < 50 ? 4 : 6), b.wy + 5, ww, 10, 0x8fd2ef)
            X.doorAt(x + (b.fw / 2).rounded(.down) - 4, b.wy + b.wallH - 13, 9, 13, 0x6b4fb0)
            X.awning(x + 2, b.wy - 1, b.fw - 2, 0x9a5fd6)
            let sx = x + (b.fw / 2).rounded(.down) - 11, sy = y + 2
            X.R(sx - 1, sy - 1, 24, 13, OL); X.R(sx, sy, 22, 11, 0xffe3a3); X.R(sx, sy + 9, 22, 2, 0xe0b867)
            X.R(sx + 7, sy + 3, 8, 6, 0xc98a4b); X.R(sx + 8, sy + 1, 1, 2, OL); X.R(sx + 13, sy + 1, 1, 2, OL); X.R(sx + 9, sy, 4, 1, OL)
            X.crate(x + w + 2, y + h - 8); X.crate(x + w + 3, y + h - 15, 5, 0xd79b5c); X.barrel(x - 9, y + h - 9)
        } else {
            X.windowAt(x + 6, b.wy + 6); X.windowAt(x + b.fw - 12, b.wy + 6); X.doorAt(x + (b.fw / 2).rounded(.down) - 3, b.wy + b.wallH - 11)
        }
    }

    static func school(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(0xec9461), roof: PC(0x3f6fca), brick: true, side: 7))
        if b.fw < 50 { X.windowAt(x + 4, b.wy + 6, 7, 9); X.windowAt(x + b.fw - 11, b.wy + 6, 7, 9) }
        else { for i in 0..<4 { X.windowAt(x + 5 + Double(i * 12) + (i > 1 ? 10 : 0), b.wy + 6, 7, 9) } }
        X.doorAt(x + (b.fw / 2).rounded(.down) - 5, b.wy + b.wallH - 14, 11, 14, 0x5b3f9a)
        let tx = x + (b.fw / 2).rounded(.down) - 7, ty = y - 18
        X.box(tx, ty + 6, 14, 16, 0xf6ead2); X.R(tx + 10, ty + 6, 4, 16, 0xd8c8a8)
        for j in 0..<7 { X.R(tx - 2 + Double(j), ty + 6 - Double(j), 18 - Double(j * 2), 1, j == 0 ? OL : shade(0x3f6fca, 0.2 - Double(j) * 0.05)) }
        X.R(tx + 6, ty - 3, 2, 3, OL)
        X.odisc(tx + 7, ty + 13, 4, 0xffffff); X.R(tx + 7, ty + 10, 1, 3, OL); X.R(tx + 7, ty + 13, 3, 1, OL)
        X.R(x + w + 4, y - 14, 1, h + 12, 0x8d8d9a); X.R(x + w + 5, y - 14, 10, 7, OL); X.R(x + w + 5, y - 13, 9, 5, 0xe8463f); X.R(x + w + 8, y - 12, 3, 2, 0xffd35a)
    }

    static func hospital(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(0xfbfbfd), roof: PC(0xcfe7e9), flat: true, side: 6, lift: 6))
        X.R(x + 9, y - 2, 12, 4, 0xe8463f); X.R(x + 13, y - 6, 4, 12, 0xe8463f)
        for i in 0..<3 { X.windowAt(x + 4 + Double(i * 11), b.wy + 4, 7, 6, 0x9fd8ee) }
        X.R(x + 1, b.wy + 12, b.fw - 2, 2, 0x3fb7a8)
        X.doorAt(x + (b.fw / 2).rounded(.down) - 5, b.wy + b.wallH - 12, 11, 12, 0x86c9ea)
        X.R(x + (b.fw / 2).rounded(.down) - 1, b.wy + b.wallH - 12, 1, 12, 0xffffff)
    }

    static func bakery(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(0xf8cfd2), roof: PC(0x8a5a3a), planks: true, side: 6))
        X.chimney(x + w - 16, y - 6, 0xc9a07a); X.smoke(x + w - 14, y - 12)
        X.awning(x + 1, b.wy, b.fw, 0xff6b8a)
        X.windowAt(x + 4, b.wy + 9, 11, 8, 0xffe9b5); X.doorAt(x + b.fw - 14, b.wy + b.wallH - 13, 9, 13, 0xc0563f)
        let sx = x + 6, sy = y + 1
        X.R(sx - 1, sy - 1, 20, 11, OL); X.R(sx, sy, 18, 9, 0xfff3df); X.disc(sx + 9, sy + 5, 5, 0xd98a3a, 3); X.R(sx + 5, sy + 4, 8, 1, 0xf2b867)
        X.R(x + 5, b.wy + 13, 9, 1, 0xd98a3a)
    }

    static func greenhouse(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.shadow(x + 3, y + 5, w + 2, h - 2)
        let top = y - 2, mid = y + Double(jsRound(h * 0.45))
        X.R(x - 1, top - 1, w + 2, h + 3, OL)
        var yy = top
        while yy < mid { X.R(x, yy, w, 1, shade(0xc6f0f5, 0.3 - (yy - top) / (mid - top) * 0.25)); yy += 1 }
        X.R(x, mid, w, y + h - mid, 0xa9e2ec)
        var i = 4.0
        while i < w { X.R(x + i, top, 1, h + 2, 0xffffff); i += 7 }
        X.R(x, mid, w, 1, 0xffffff); X.R(x, top, w, 1, 0xffffff)
        i = 0
        while i < w { X.disc(x + i + 3, y + h - 4, 3, 0x5aa853); X.R(x + i + 2, y + h - 6, 1, 1, 0xff6b8a); i += 7 }
        for k in 0..<3 { X.R(x + 3 + Double(k * 14), top + 2, 1, 6, 0xffffff); X.R(x + 4 + Double(k * 14), top + 2, 1, 3, 0xffffff) }
        X.R(x + w - 5, top, 5, h + 2, PC(r: 40, g: 90, b: 110, a: 0.18)); X.R(x, y + h, w, 2, 0xb7aa98); X.light(x + 2, mid + 1, w - 6, 3)
    }

    static func windmill(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + w / 2, by = y + h; X.shadow(cx - 6, by - 6, 22, 7)
        for yy in 0..<36 { let hw = Double(jsRound(9 - Double(yy) * 0.12)), fy = Double(yy)
            X.R(cx - hw - 1, by - fy - 1, hw * 2 + 2, 1, OL); X.R(cx - hw, by - fy, hw * 2, 1, 0xf3ece0); X.R(cx + hw - 4, by - fy, 4, 1, 0xd6cab6) }
        var yy = 4.0
        while yy < 36 { X.R(cx - 8, by - yy, 13, 1, 0xe2d8c6); yy += 6 }
        X.doorAt(cx - 3, by - 11, 6, 9, 0x8a5a3a); X.windowAt(cx - 2, by - 24, 4, 5)
        for j in 0..<9 { let fj = Double(j)
            X.R(cx - 6 + (fj * 0.6).rounded(.down) - 1, by - 37 - fj, 14 - (fj * 1.3).rounded(.down) + 2, 1, j == 8 ? OL : shade(0xb0563a, 0.15 - fj * 0.04)) }
        let hx = cx, hy = by - 33
        for (sx, sy) in [(1.0, 1.0), (1, -1), (-1, 1), (-1, -1)] {
            for k in 2..<19 { X.R(hx + sx * Double(k) - 1, hy + sy * Double(k) - 1, 3, 3, OL) }
            for k in 2..<19 { let fk = Double(k)
                X.R(hx + sx * fk, hy + sy * fk, 1, 1, 0x8a5a3a)
                if k > 5 { X.R(hx + sx * fk + (sx > 0 ? 1 : -3), hy + sy * fk + (sy > 0 ? -3 : 1), 3, 3, k % 3 != 0 ? 0xfff6e6 : 0xe8dcc6) }
            }
        }
        X.odisc(hx, hy, 2, 0xffd35a)
    }

    static func lighthouse(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + w / 2, by = y + h; X.shadow(cx - 4, by - 4, 22, 6)
        for (a, b2, r) in [(-10.0, -2.0, 7.0), (7, -1, 6), (-3, 1, 6)] { X.odisc(cx + a, by + b2, r, 0x9a9aaa, r * 0.7) }
        for yy in 0..<40 { let fy = Double(yy), hw = Double(jsRound(8 - fy * 0.07)), band: UInt32 = (yy / 8) % 2 == 1 ? 0xffffff : 0xe8463f
            X.R(cx - hw - 1, by - 2 - fy, hw * 2 + 2, 1, OL); X.R(cx - hw, by - 2 - fy, hw * 2, 1, band); X.R(cx + hw - 4, by - 2 - fy, 4, 1, shade(band, -0.25)); X.R(cx - hw + 1, by - 2 - fy, 1, 1, shade(band, 0.3)) }
        X.doorAt(cx - 3, by - 12, 6, 9, 0x3f6fca)
        X.box(cx - 9, by - 45, 18, 3, 0x3a3550); X.box(cx - 6, by - 53, 12, 8, 0xffe27a); X.R(cx - 6, by - 53, 3, 8, 0xfff6c4); X.R(cx + 2, by - 53, 4, 8, 0xf0c040); X.light(cx - 6, by - 53, 12, 8)
        for j in 0..<5 { let fj = Double(j); X.R(cx - 7 + fj, by - 54 - fj, 14 - fj * 2, 1, j == 4 ? OL : PC(0xc63a34)) }
        X.R(cx, by - 60, 1, 2, OL)
        X.beams.append((cx, by - 49))
    }

    static func pagoda(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + w / 2, by = y + h; X.shadow(cx - 18, by - 10, 40, 10)
        X.box(cx - 20, by - 5, 40, 5, 0xcfc3ad); X.R(cx - 20, by - 1, 40, 1, 0xa99c84)
        var yy = by - 5
        for (hw, th) in [(20.0, 12.0), (15, 10), (11, 9)] {
            X.R(cx - hw + 3 - 1, yy - th - 1, (hw - 3) * 2 + 2, th + 1, OL); X.R(cx - hw + 3, yy - th, (hw - 3) * 2, th, 0xd0473c); X.R(cx + hw - 8, yy - th, 5, th, 0xa8352d)
            var k = -hw + 6
            while k < hw - 6 { X.R(cx + k, yy - th + 3, 3, th - 3, 0xffd35a); X.light(cx + k, yy - th + 3, 3, th - 3); k += 6 }
            let ry = yy - th - 5
            for j in 0..<5 { let rw = hw + 4 - Double(j); X.R(cx - rw - 1, ry + Double(j), rw * 2 + 2, 1, OL); X.R(cx - rw, ry + Double(j), rw * 2, 1, shade(0x2f6f5f, 0.25 - Double(j) * 0.1)) }
            X.R(cx - hw - 6, ry + 1, 2, 2, OL); X.R(cx + hw + 4, ry + 1, 2, 2, OL); X.R(cx - hw - 5, ry, 1, 1, 0x2f6f5f); X.R(cx + hw + 4, ry, 1, 1, 0x2f6f5f)
            yy = ry
        }
        X.R(cx - 1, yy - 8, 2, 8, OL); X.odisc(cx, yy - 9, 2, 0xffd35a)
    }

    static func statue(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + 8, by = y + h; X.shadow(cx - 4, by - 8, 16, 7)
        X.box(cx - 8, by - 12, 16, 10, 0xc9c3d3); X.R(cx - 8, by - 12, 16, 3, 0xe4e0ec); X.R(cx + 4, by - 9, 4, 7, 0xa49ebb)
        let g1: UInt32 = 0xffcf3a, g2: UInt32 = 0xe0a020, g3: UInt32 = 0xfff3a6
        X.R(cx - 4, by - 26, 8, 13, OL); X.R(cx - 3, by - 25, 6, 12, g1); X.R(cx + 1, by - 25, 2, 12, g2)
        X.odisc(cx, by - 29, 3, g1); X.R(cx - 2, by - 31, 1, 2, g3)
        X.R(cx + 3, by - 36, 2, 12, OL); X.R(cx + 3, by - 35, 1, 10, g1); X.box(cx + 2, by - 40, 5, 4, g3); X.light(cx + 2, by - 40, 5, 4)
        X.R(cx - 2, by - 24, 1, 8, g3)
    }

    static func fountain(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + w / 2, cy = y + h / 2 + 4; X.eshadow(cx + 3, cy + 5, 23, 11)
        X.odisc(cx, cy, 22, 0xc9c3d3, 12); X.disc(cx, cy - 1, 20, 0xe4e0ec, 10); X.disc(cx, cy + 1, 17, 0x4db0dd, 8); X.disc(cx - 3, cy, 12, 0x64c7e5, 5)
        X.R(cx - 12, cy - 2, 5, 1, 0xdcf7fb); X.R(cx + 6, cy + 3, 4, 1, 0xdcf7fb)
        X.R(cx - 3, cy - 14, 6, 14, OL); X.R(cx - 2, cy - 13, 4, 13, 0xd8d2e2); X.R(cx + 1, cy - 13, 1, 13, 0xa49ebb); X.odisc(cx, cy - 15, 5, 0xc9c3d3, 2)
        for i in [-1.0, 1] { for k in 0..<9 { let fk = Double(k); X.R(cx + i * fk, cy - 20 + Double(jsRound(fk * fk * 0.2)), 1, 2, k % 2 == 1 ? 0xdcf7fb : 0xffffff) } }
        X.R(cx - 1, cy - 26, 2, 7, 0xffffff)
    }

    static func portal(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let x0 = x - 16, x1 = x + w + 16, by = y + h, top = y - 22
        X.shadow(x0 + 4, by - 4, x1 - x0, 6)
        var yy = top + 8
        while yy < by { let t = (yy - top) / (by - top); X.R(x0 + 6, yy, x1 - x0 - 12, 1, PC(r: (150 - t * 60).rounded(), g: (90 - t * 40).rounded(), b: (240 - t * 50).rounded())); yy += 1 }
        for k in 0..<18 { let a = Double(k) * 0.7, r = 3 + Double(k) * 0.9; X.R(x + w / 2 + cos(a) * r, by - 16 + sin(a) * r * 0.8, 2, 2, k % 3 != 0 ? 0xe9dcff : 0xffffff) }
        for px in [x0, x1 - 8] {
            X.box(px, top + 4, 8, by - top - 4, 0xbdb6cf); X.R(px + 5, top + 4, 3, by - top - 4, 0x9089a8)
            var y2 = top + 10; while y2 < by { X.R(px, y2, 8, 1, 0x9089a8); y2 += 7 }
            X.box(px - 2, by - 4, 12, 4, 0x9089a8); X.box(px - 1, top + 1, 10, 3, 0xd8d2e2)
        }
        X.box(x0 - 2, top - 3, x1 - x0 + 4, 5, 0xd8d2e2); X.R(x0 - 2, top + 1, x1 - x0 + 4, 1, 0x9089a8)
        X.odisc(x + w / 2, top - 1, 4, 0xb38bff); X.R(x + w / 2 - 1, top - 3, 2, 2, 0xffffff)
    }

    static func lab(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y + 6, w, h - 6, .init(wall: PC(0xefeaff), roof: PC(0x7a5ad6), brick: true, side: 6, lift: 2))
        let cx = x + 20, cy = y + 4
        X.disc(cx, cy, 13, OL, 11); X.disc(cx, cy, 12, 0xc9c3d3, 10); X.disc(cx - 3, cy - 3, 7, 0xe4e0ec, 6); X.R(cx - 12, cy, 24, 3, 0xa49ebb)
        X.R(cx + 1, cy - 9, 3, 11, 0x3a3550)
        for k in 0..<9 { let fk = Double(k); X.R(cx + 3 + fk, cy - 12 - fk, 3, 3, OL); X.R(cx + 4 + fk, cy - 11 - fk, 1, 1, 0xffcf3a) }
        X.R(x - 1, cy + 9, w + 2, 2, OL)
        X.windowAt(x + 4, b.wy + 5, 8, 8, 0xbfe6ff); X.doorAt(x + b.fw - 13, b.wy + b.wallH - 12, 8, 12, 0x5b3fc9)
        let sx = x + 4, sy = b.wy + 15
        X.R(sx - 1, sy - 1, 12, 9, OL); X.R(sx, sy, 10, 7, 0xfffaf0); X.R(sx + 1, sy + 4, 2, 2, 0xe0603a); X.R(sx + 4, sy + 2, 2, 4, 0x3f6fca); X.R(sx + 7, sy + 1, 2, 5, 0x2f9e6a)
    }

    static func lot(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.R(x + 3, y + 5, w - 6, h - 8, PC(r: 140, g: 100, b: 60, a: 0.35))
        var i = x + 6; while i < x + w - 6 { X.R(i, y + 8, 3, h - 14, PC(r: 120, g: 80, b: 50, a: 0.25)); i += 6 }
        for (a, b) in [(x + 2, y + 3), (x + w - 4, y + 3), (x + 2, y + h - 6), (x + w - 4, y + h - 6)] { X.R(a - 1, b - 1, 4, 7, OL); X.R(a, b, 2, 5, 0xd79b5c) }
        X.R(x + 4, y + 4, w - 8, 1, 0xfff3df); X.R(x + 4, y + h - 5, w - 8, 1, 0xfff3df); X.R(x + 3, y + 5, 1, h - 10, 0xfff3df); X.R(x + w - 3, y + 5, 1, h - 10, 0xfff3df)
        let sx = x + w / 2 - 9, sy = y + h / 2 - 9
        X.R(sx - 1, sy - 1, 20, 12, OL); X.R(sx, sy, 18, 10, 0xffe3a3); X.R(sx + 8, sy + 2, 2, 6, 0x8a5a3a); X.R(sx + 6, sy + 4, 6, 2, 0x8a5a3a); X.R(sx + 8, sy + 11, 2, 6, 0x7a5228)
    }

    static func scaffold(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.R(x + 3, y + 5, w - 6, h - 8, PC(r: 140, g: 100, b: 60, a: 0.4))
        let top = y - 6
        var i = x + 6; while i <= x + w - 8 { X.R(i - 1, top - 1, 4, y + h - top - 2, OL); X.R(i, top, 2, y + h - top - 4, 0xd79b5c); i += 10 }
        var j = top + 6; while j < y + h - 4 { X.R(x + 5, j - 1, w - 10, 4, OL); X.R(x + 6, j, w - 12, 2, 0xc98a4b); j += 10 }
        X.R(x + 10, y + 12, w - 20, 12, PC(r: 240, g: 230, b: 210, a: 0.9)); X.crate(x + w - 14, y + h - 10); X.barrel(x + 4, y + h - 12)
    }

    static func flowerbed(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.R(x + 2, y + 6, w - 4, h - 8, OL); X.R(x + 3, y + 7, w - 6, h - 10, 0x8a5a3a)
        let pal: [UInt32] = [0xff6b8a, 0xffd35a, 0xffffff, 0xb38bff]
        for k in 0..<14 {
            let a = x + 5 + (hash(o.x, o.y, k) * (w - 10)).rounded(.down), c = y + 9 + (hash(o.x, o.y, k + 20) * (h - 14)).rounded(.down)
            X.R(a, c + 1, 1, 2, 0x4f9a3f); X.R(a - 1, c, 3, 1, pal[k % 4]); X.R(a, c - 1, 1, 3, pal[k % 4])
        }
    }

    // MARK: small things

    static func mailbox(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.shadow(cx, by - 2, 9, 3); X.R(cx - 1, by - 9, 2, 9, 0x8a5a3a); X.box(cx - 5, by - 16, 10, 7, 0x3f6fca); X.R(cx - 5, by - 16, 10, 2, 0x6f97e0); X.R(cx + 5, by - 18, 1, 6, OL); X.R(cx + 6, by - 18, 3, 3, 0xe8463f)
    }
    static func boat(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double) {
        let by = y + 11
        X.R(x - 1, by - 7, w + 2, 9, OL); X.R(x, by - 6, w, 7, 0xa8743c); X.R(x + 3, by - 5, w - 6, 3, 0x6b4626); X.R(x, by - 6, w, 1, 0xd79b5c); X.R(x, by, w, 1, 0x7a5228)
        X.R(x - 3, by - 5, 3, 4, OL); X.R(x + w, by - 5, 3, 4, OL); X.R(x - 2, by - 4, 2, 2, 0xa8743c); X.R(x + w, by - 4, 2, 2, 0xa8743c)
        X.R(x + 9, by - 9, 14, 1, 0xd79b5c); X.R(x + 2, by + 2, w - 4, 1, PC(r: 255, g: 255, b: 255, a: 0.7))
    }
    static func dock(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.shadow(x + 3, y + 3, w, h)
        var i = 0.0
        while i < h { X.R(x - 1, y + i - 1, w + 2, 5, OL); X.R(x, y + i, w, 3, Int(i) % 8 != 0 ? 0xc98a4b : 0xd79b5c); X.R(x, y + i + 3, w, 1, 0x8a5a3a); i += 4 }
        for (a, b) in [(0.0, h - 2), (w - 3, h - 2), (0, 8), (w - 3, 8)] { X.R(x + a - 1, y + b - 1, 5, 7, OL); X.R(x + a, y + b, 3, 5, 0x7a5228); X.R(x + a, y + b + 5, 3, 1, 0xdcf7fb) }
    }
    static func field(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.shadow(x + 2, y + 2, w, h)
        X.R(x - 1, y - 1, w + 2, h + 2, 0x6b4626); X.R(x, y, w, h, 0x9a6a3e)
        var r = 2.0
        while r < h {
            X.R(x, y + r, w, 2, 0x7a5228)
            var c = 3.0
            while c < w - 2 {
                let crop = o.crop.isEmpty ? nil : o.crop[(Int(r) + Int(c)) % o.crop.count]
                X.R(x + c, y + r - 3, 2, 3, 0x5aa853); X.R(x + c - 1, y + r - 4, 1, 2, 0x7cc860); X.R(x + c + 2, y + r - 4, 1, 2, 0x7cc860)
                if let crop { X.R(x + c, y + r - 1, 2, 2, crop) }
                c += 6
            }
            r += 5
        }
        var i = -3.0
        while i < w + 3 { X.R(x + i, y - 5, 1, 4, 0xffffff); X.R(x + i, y + h + 1, 1, 4, 0xffffff); i += 4 }
        X.R(x - 3, y - 4, w + 6, 1, 0xffffff); X.R(x - 3, y + h + 2, w + 6, 1, 0xffffff)
    }
    static func tent(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let cx = x + w / 2, by = y + h; X.shadow(cx - 10, by - 8, 30, 8)
        for j in 0..<22 { let fj = Double(j), hw = Double(jsRound(fj * 0.78)); X.R(cx - hw - 1, by - 22 + fj, hw * 2 + 2, 1, OL); X.R(cx - hw, by - 22 + fj, hw, 1, 0xf39a3a); X.R(cx, by - 22 + fj, hw, 1, 0xcc7424) }
        for j in 8..<22 { let fj = Double(j), hw = Double(jsRound((fj - 8) * 0.35)); X.R(cx - hw, by - 22 + fj, hw * 2, 1, 0x4a2c18) }
        X.R(cx - 1, by - 25, 2, 4, OL); X.R(cx - 18, by - 1, 36, 1, 0xcc7424)
    }
    static func camp(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, cy = y + 10
        for (a, b) in [(-5.0, 2.0), (5, 2), (0, 4), (-4, -2), (4, -2)] { X.odisc(cx + a, cy + b, 2, 0x9a9aaa) }
        X.R(cx - 5, cy, 10, 2, 0x6b4626); X.R(cx - 2, cy - 7, 4, 7, 0xff8a2a); X.R(cx - 1, cy - 9, 2, 5, 0xffd35a); X.R(cx, cy - 11, 1, 3, 0xfff6c4); X.light(cx - 2, cy - 9, 4, 8)
    }
    static func tree(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14, v = hash(o.x, o.y, 3)
        if o.tree == "pine" {
            X.eshadow(cx + 4, by, 9, 3); X.R(cx - 2, by - 6, 4, 6, OL); X.R(cx - 1, by - 6, 2, 6, 0x7a5228)
            let cols: [UInt32] = [0x2f7d45, 0x3c9152, 0x4ea561]
            for (dy, hw) in [(20.0, 9.0), (14, 7), (8, 5)] {
                for j in 0..<9 { let ww = Double(jsRound(hw * Double(j) / 8)) + 1
                    X.R(cx - ww - 1, by - dy - 9 + Double(j), ww * 2 + 2, 1, OL); X.R(cx - ww, by - dy - 9 + Double(j), ww, 1, cols[2]); X.R(cx, by - dy - 9 + Double(j), ww, 1, cols[0]) }
                X.R(cx - hw, by - dy, hw * 2, 1, 0x24603a)
            }
            X.R(cx - 2, by - 25, 1, 3, 0x7fcf88)
        } else if o.tree == "palm" {
            X.eshadow(cx + 6, by, 9, 3)
            for k in 0..<16 { let tx = cx + Double(jsRound(sin(Double(k) / 6) * 4)); X.R(tx - 2, by - Double(k) - 1, 4, 1, OL); X.R(tx - 1, by - Double(k) - 1, 2, 1, k % 3 != 0 ? 0xb98a58 : 0x8a6038) }
            let tx = cx + 4, ty = by - 17
            let FR: [(Double, Double)] = [(-12, 2), (12, 2), (-9, -6), (9, -6), (-3, -10), (4, -10), (-10, 8), (10, 8)]
            func pts(_ a: Double, _ b: Double) -> [(Double, Double, Double)] { (0..<8).map { k in let f = Double(k) / 7; return (tx + a * f, ty + b * f + f * f * 5, 2.6 * (1 - f * 0.6)) } }
            for (a, b) in FR { for (x2, y2, r) in pts(a, b) { X.disc(x2, y2, r + 1, OL) } }
            for (i, (a, b)) in FR.enumerated() { for (k, (x2, y2, r)) in pts(a, b).enumerated() { X.disc(x2, y2, r, i < 4 ? 0x4fae52 : 0x3c9152); if k > 1 && k < 6 { X.R(x2, y2 - 1, 1, 1, 0x9be37a) } } }
            X.odisc(tx - 2, ty + 3, 2, 0x8a5a3a); X.odisc(tx + 2, ty + 3, 2, 0x7a4a2a)
        } else {
            X.eshadow(cx + 5, by, 11, 4); X.R(cx - 3, by - 8, 6, 8, OL); X.R(cx - 2, by - 8, 4, 8, 0x7a5228); X.R(cx + 1, by - 8, 1, 8, 0x5e3e1f)
            let c0: UInt32 = v < 0.5 ? 0x3f9a4c : 0x4aa24a
            let c1 = shade(c0, 0.18), c2 = shade(c0, 0.38), cD = shade(c0, -0.25)
            let blobs: [(Double, Double, Double)] = [(-5, -12, 7), (5, -12, 7), (0, -18, 8)]
            for (a, b, r) in blobs { X.disc(cx + a, by + b, r + 1, OL) }
            for (a, b, r) in blobs { X.disc(cx + a, by + b, r, c0) }
            X.disc(cx + 4, by - 10, 5, cD); X.disc(cx - 2, by - 18, 6, c1); X.disc(cx - 4, by - 20, 3, c2); X.R(cx - 6, by - 21, 2, 1, 0xc9f2a8)
            if o.fruit { for (a, b) in [(-6.0, -12.0), (3, -16), (6, -9), (-1, -10)] { X.R(cx + a - 1, by + b - 1, 3, 3, OL); X.R(cx + a, by + b, 1, 1, 0xff5a5a) } }
        }
    }
    static func bush(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13; X.eshadow(cx + 3, by, 8, 3)
        X.odisc(cx - 3, by - 4, 5, 0x4aa24a); X.odisc(cx + 3, by - 4, 5, 0x4aa24a); X.disc(cx - 3, by - 4, 5, 0x4aa24a); X.disc(cx - 2, by - 6, 3, 0x6fc160)
        if o.berries { for (a, b) in [(-4.0, -5.0), (1, -3), (4, -6), (-1, -7)] { X.R(cx + a, by + b, 2, 2, 0x7a3fb0); X.R(cx + a, by + b, 1, 1, 0xc79bff) } }
    }
    static func flowers(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let pal: [UInt32] = [0xff6b8a, 0xffd35a, 0xffffff, 0xb38bff]
        for k in 0..<6 {
            let a = (hash(o.x, o.y, k) * 13).rounded(.down) + 1, b = (hash(o.x, o.y, k + 9) * 12).rounded(.down) + 2
            X.R(x + a, y + b + 1, 1, 2, 0x4f9a3f); X.R(x + a - 1, y + b, 3, 1, pal[k % 4]); X.R(x + a, y + b - 1, 1, 3, pal[k % 4]); X.R(x + a, y + b, 1, 1, 0xfff2a8)
        }
    }
    static func fern(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13
        for k in -2...2 { for j in 0..<7 { X.R(cx + Double(k * 2) + Double(jsRound(Double(k * j) * 0.3)), by - Double(j), 1, 1, k % 2 != 0 ? 0x3c9152 : 0x5bb85a) } }
    }
    static func rock(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 12; X.eshadow(cx + 2, by, 7, 2); X.odisc(cx, by - 3, 6, 0xa7a3b8, 4); X.disc(cx - 1, by - 4, 4, 0xc9c5d8, 2); X.R(cx - 3, by - 6, 2, 1, 0xecebf3)
    }
    static func mushbig(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13; X.eshadow(cx + 2, by, 6, 2); X.R(cx - 3, by - 6, 6, 6, OL); X.R(cx - 2, by - 6, 4, 6, 0xfff3df); X.odisc(cx, by - 8, 7, 0xe8463f, 4); X.disc(cx - 1, by - 9, 5, 0xff6b5a, 2)
        for (a, b) in [(-4.0, -9.0), (2, -10), (4, -7), (-1, -11)] { X.R(cx + a, by + b, 2, 1, 0xffffff) }
    }
    static func herb(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13
        for k in -3...3 { let ak = Double(abs(k)); X.R(cx + Double(k), by - 6 + ak, 1, 6 - ak, 0x4f9a3f); X.R(cx + Double(k), by - 7 + ak, 1, 1, 0x9be37a) }
        X.R(cx - 1, by - 9, 3, 2, 0xffffff)
    }
    static func log(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 12; X.shadow(cx - 6, by - 1, 14, 3); X.box(cx - 7, by - 6, 12, 5, 0x8a5a3a); X.R(cx - 7, by - 6, 12, 1, 0xb98a58); X.odisc(cx + 6, by - 4, 3, 0xd7b07a); X.disc(cx + 6, by - 4, 1, 0xa8743c)
    }
    static func stump(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13; X.eshadow(cx + 2, by, 7, 2); X.box(cx - 5, by - 7, 10, 7, 0x7a5228); X.odisc(cx, by - 8, 5, 0xd7b07a, 2); X.disc(cx, by - 8, 2, 0xa8743c, 1)
        X.R(cx - 4, by - 18, 8, 9, OL); X.R(cx - 3, by - 17, 6, 8, 0xa07a5a); X.R(cx - 2, by - 14, 4, 4, 0xe6d2b0); X.R(cx - 3, by - 16, 2, 2, 0xffd35a); X.R(cx + 1, by - 16, 2, 2, 0xffd35a); X.R(cx - 2, by - 15, 1, 1, OL); X.R(cx + 2, by - 15, 1, 1, OL); X.R(cx, by - 13, 1, 1, 0xf39a3a)
    }
    static func shellpile(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 12
        for (a, b, c) in [(-4.0, 0.0, UInt32(0xffd0d6)), (3, -1, 0xfff3df), (0, -4, 0xffb0bd)] {
            X.odisc(cx + a, by + b, 3, c, 2); X.R(cx + a - 1, by + b - 1, 1, 2, shade(c, -0.2)); X.R(cx + a + 1, by + b - 1, 1, 2, shade(c, -0.2))
        }
    }
    static func reedbig(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14
        for k in stride(from: -3, through: 3, by: 2) { let ak = Double(abs(k)), fk = Double(k)
            X.R(cx + fk, by - 13 + ak, 1, 13 - ak, 0x5a9a3a); X.R(cx + fk - 1, by - 15 + ak, 3, 4, OL); X.R(cx + fk, by - 14 + ak, 1, 3, 0x8a5a3a) }
    }
    static func lotuspad(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, cy = y + 9; X.odisc(cx, cy, 6, 0x4aa24a, 4); X.R(cx, cy - 4, 1, 4, 0x3a8a3a); X.odisc(cx + 1, cy - 2, 2, 0xff9ab8); X.R(cx + 1, cy - 3, 1, 1, 0xffffff)
    }
    static func fishspot(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, cy = y + 8
        for k in 0..<2 { let r = 4 + Double(k * 4); var a = 0.0; while a < 6.28 { X.R(cx + cos(a) * r, cy + sin(a) * r * 0.5, 1, 1, PC(r: 255, g: 255, b: 255, a: 0.8)); a += 0.5 } }
        X.R(cx - 2, cy - 1, 5, 2, 0x2f74bb); X.R(cx + 3, cy - 2, 1, 1, 0x2f74bb)
    }

    // MARK: Phố Chữ

    static let glyphs: [Character: String] = ["A": "010101111101101", "B": "110101110101110", "C": "011100100100011", "O": "010101101101010", "K": "101110100110101", "S": "011100010001110", "T": "111010010010010", "E": "111100110100111", "F": "111100110100100"]
    static func word(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: String, _ c: UInt32) {
        for (i, ch) in w.enumerated() { guard let g = glyphs[ch] else { continue }
            for (k, bit) in g.enumerated() where bit == "1" { X.R(x + Double(i * 4 + k % 3), y + Double(k / 3), 1, 1, c) } }
    }
    static func apartment(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let fl = o.floors, ext = Double(fl * 11 - 14), wall = o.wall ?? 0xe9a77b
        let b = X.building(x, y - ext, w, h + ext, .init(wall: PC(wall), roof: PC(0x9a97a8), flat: true, side: 7, wallH: h + ext - 18))
        for f in 0..<fl { for i in 0..<4 {
            let wy = b.wy + 4 + Double(f * 11); if f == fl - 1 && (i == 1 || i == 2) { continue }
            X.windowAt(x + 4 + Double(i * 9), wy, 6, 7, 0x86c9ea); X.R(x + 3 + Double(i * 9), wy + 8, 8, 1, shade(wall, -0.35))
        } }
        X.doorAt(x + 17, b.wy + b.wallH - 11, 8, 11, 0x5b6b8a)
        X.box(x + 6, y - ext - 2, 8, 5, 0xc9c5d8); X.R(x + 7, y - ext - 2, 6, 1, 0xecebf3); X.odisc(x + 30, y - ext, 4, 0xb98a58, 3)
    }
    static func office(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let fl = o.floors, ext = Double(fl * 10 - 12)
        let b = X.building(x, y - ext, w, h + ext, .init(wall: PC(0x7fb0de), roof: PC(0xb9c3d0), flat: true, side: 7, wallH: h + ext - 16))
        var yy = b.wy + 3
        while yy < b.wy + b.wallH - 12 { var xx = x + 2; while xx < x + b.fw - 2 { X.R(xx, yy, 4, 4, Int(xx + yy) % 3 != 0 ? 0xa9d4f2 : 0xd6efff); X.light(xx, yy, 4, 4); xx += 5 }; yy += 5 }
        X.R(x + 1, b.wy + 2, 3, b.wallH - 14, PC(r: 255, g: 255, b: 255, a: 0.35))
        X.doorAt(x + 14, b.wy + b.wallH - 11, 12, 11, 0x5d8fc0)
    }
    static func bookstore(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(o.wall ?? 0xc7b6e8), roof: PC(0x4f6f8f), planks: true, side: 6))
        X.awning(x + 1, b.wy, b.fw - 1, 0x3f8a5a, 0xf6efd6)
        X.windowAt(x + 4, b.wy + 9, 14, 10, 0xf6e3b5)
        for (i, c) in [UInt32(0xe8463f), 0x3f6fca, 0xffcf3a, 0x5aa853].enumerated() { X.R(x + 6 + Double(i * 3), b.wy + 15, 2, 4, c) }
        X.doorAt(x + b.fw - 14, b.wy + b.wallH - 13, 9, 13, 0x3f5f4a)
        let sx = x + 9, sy = y + 1; X.R(sx - 1, sy - 1, 26, 10, OL); X.R(sx, sy, 24, 8, 0xfff3df); word(X, sx + 2, sy + 2, "BOOKS", 0x3f5f4a)
    }
    static func cafe(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let b = X.building(x, y, w, h, .init(wall: PC(o.wall ?? 0xf2d17c), roof: PC(0x7a4a3a), brick: true, side: 6))
        X.awning(x + 1, b.wy, b.fw - 1, 0xe8463f)
        X.windowAt(x + 4, b.wy + 9, 12, 9, 0xffe9b5); X.doorAt(x + b.fw - 13, b.wy + b.wallH - 13, 9, 13, 0x7a4a3a)
        let sx = x + 11, sy = y + 1; X.R(sx - 1, sy - 1, 22, 10, OL); X.R(sx, sy, 20, 8, 0x2b2238); word(X, sx + 2, sy + 2, "CAFE", 0xffd35a)
        for (a, c) in [(x + 6, y + h + 6), (x + 22, y + h + 6)] { X.R(a, c - 9, 1, 9, 0x6b6b7a); X.odisc(a, c - 10, 6, 0xfff3df, 2); X.R(a - 6, c - 10, 12, 1, 0xe8463f) }
    }
    static func clocktower(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        X.R(x, y, w, h, 0xe6ddd0)
        var i = 0.0; while i < w { X.R(x + i, y, 1, h, 0xcfc3ad); i += 8 }
        var j = 0.0; while j < h { X.R(x, y + j, w, 1, 0xcfc3ad); j += 8 }
        let cx = x + w / 2, by = y + h - 8; X.shadow(cx - 6, by - 10, 22, 10)
        X.box(cx - 9, by - 54, 18, 54, 0xd8c8a8); X.R(cx + 4, by - 54, 5, 54, 0xb8a684)
        var yy = by - 50; while yy < by { X.R(cx - 9, yy, 13, 1, 0xc4b393); yy += 6 }
        X.odisc(cx - 2, by - 42, 6, 0xffffff); X.R(cx - 2, by - 47, 1, 5, OL); X.R(cx - 2, by - 42, 4, 1, OL)
        X.doorAt(cx - 5, by - 12, 7, 12, 0x5b3f9a); X.windowAt(cx - 4, by - 30, 4, 7)
        for j in 0..<12 { let fj = Double(j); X.R(cx - 10 + fj * 0.8, by - 55 - fj, 20 - fj * 1.6, 1, j == 11 ? OL : shade(0x3f6fca, 0.2 - fj * 0.04)) }
        X.R(cx - 1, by - 70, 2, 4, 0xffd35a)
        X.odisc(x + 7, y + h - 6, 4, 0x5aa853); X.odisc(x + w - 7, y + h - 6, 4, 0x5aa853)
    }
    static func bench(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let bx = x + 2, by = y + 10; X.R(bx - 1, by - 5, 14, 5, OL); X.R(bx, by - 4, 12, 2, 0xb98a58); X.R(bx, by - 2, 12, 1, 0x8a5a3a); X.R(bx + 1, by, 1, 3, OL); X.R(bx + 10, by, 1, 3, OL)
    }
    static func car(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let c = o.color
        if o.horizontal {
            let cx = x + 1, cy = y + 4; X.shadow(cx + 2, cy + 3, 14, 6); X.R(cx - 1, cy - 1, 16, 10, OL); X.R(cx, cy, 14, 8, c); X.R(cx, cy, 14, 2, shade(c, 0.35)); X.R(cx + 4, cy + 1, 6, 4, 0xbfe6f7); X.R(cx + 4, cy + 1, 2, 4, 0xe9f8ff); X.R(cx + 13, cy + 2, 1, 2, 0xfff6c4); X.R(cx + 1, cy + 8, 3, 1, OL); X.R(cx + 10, cy + 8, 3, 1, OL)
        } else {
            let cx = x + 4, cy = y + 1; X.shadow(cx + 2, cy + 3, 8, 14); X.R(cx - 1, cy - 1, 10, 16, OL); X.R(cx, cy, 8, 14, c); X.R(cx, cy, 2, 14, shade(c, 0.35)); X.R(cx + 1, cy + 3, 6, 4, 0xbfe6f7); X.R(cx + 1, cy + 3, 6, 1, 0xe9f8ff); X.R(cx + 2, cy + 13, 4, 1, 0xff6b5a)
        }
    }
    static func lamp(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.R(cx - 1, by - 3, 3, 3, OL); X.R(cx, by - 20, 1, 18, 0x4a4a5e); X.R(cx - 3, by - 23, 7, 4, OL); X.R(cx - 2, by - 22, 5, 2, 0xfff2a8); X.light(cx - 2, by - 22, 5, 2)
    }
    static func signpost(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.shadow(cx, by - 2, 8, 3); X.R(cx - 1, by - 12, 2, 12, 0x7a5228); X.R(cx - 8, by - 20, 16, 9, OL); X.R(cx - 7, by - 19, 14, 7, 0xffe3a3); word(X, cx - 5, by - 18, "ABC", 0x8a5a3a)
    }
    static func poster(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.eshadow(cx + 2, by, 6, 2); X.R(cx - 5, by - 22, 10, 22, OL); X.R(cx - 4, by - 21, 8, 21, 0x3f8a5a); X.R(cx - 3, by - 18, 5, 7, 0xffd35a); X.R(cx - 3, by - 10, 5, 6, 0xff6b8a); X.R(cx + 2, by - 21, 2, 21, 0x2f6a45); X.R(cx - 5, by - 24, 10, 3, OL); X.R(cx - 4, by - 23, 8, 1, 0x5aa853)
    }
    static func newsstand(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let bx = x + 1, by = y + 14; X.shadow(bx + 3, by - 4, 15, 5); X.box(bx, by - 11, 14, 11, 0x3f6fca); X.R(bx + 2, by - 9, 10, 5, 0xfff3df)
        for (a, c) in [(3.0, UInt32(0xe8463f)), (6, 0xffcf3a), (9, 0x5aa853)] { X.R(bx + a, by - 8, 2, 3, c) }
        X.awning(bx - 1, by - 17, 16, 0xffcf3a)
    }
    static func letterbox(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.shadow(cx, by - 3, 8, 3); X.box(cx - 4, by - 16, 8, 16, 0xe8463f); X.R(cx - 4, by - 18, 8, 3, 0xc63a34); X.R(cx - 2, by - 12, 4, 1, OL); X.R(cx + 2, by - 15, 2, 15, 0xc63a34); X.R(cx + 5, by - 9, 6, 4, OL); X.R(cx + 6, by - 8, 4, 2, 0xffffff)
    }

    // MARK: Sa Mạc Vang

    static func pyramid(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let ax = x + Double(jsRound(w * 0.45)), ay = y - 22, bl = x, br = x + Double(jsRound(w * 0.78)), by = y + h - 2, rx = x + w, ry = y + h - 16
        typealias P = (Double, Double)
        func tri(_ p: P, _ q: P, _ r: P, _ col: (Double, Double, Double) -> Void) {
            let ys = [p.1, q.1, r.1]
            var yy = ys.min()!.rounded(.up)
            while yy <= ys.max()!.rounded(.down) {
                var xs: [Double] = []
                for (u, v) in [(p, q), (q, r), (r, p)] where ((u.1 <= yy && v.1 >= yy) || (v.1 <= yy && u.1 >= yy)) && u.1 != v.1 { xs.append(u.0 + (yy - u.1) / (v.1 - u.1) * (v.0 - u.0)) }
                if xs.count >= 2 { col(Double(jsRound(xs.min()!)), Double(jsRound(xs.max()!)), yy) }
                yy += 1
            }
        }
        tri((ax, ay), (rx + 24, ry + 8), (br + 12, by + 6)) { l, r2, yy in X.shadow(l, yy, r2 - l, 1) }
        tri((ax, ay), (br, by), (rx, ry)) { l, r2, yy in X.R(l, yy, r2 - l + 1, 1, OL); X.R(l + 1, yy, r2 - l - 1, 1, Int(yy - ay) % 5 == 0 ? 0xb0803f : 0xc99858) }
        tri((ax, ay), (bl, by), (br, by)) { l, r2, yy in X.R(l - 1, yy, r2 - l + 2, 1, OL); X.R(l, yy, r2 - l, 1, Int(yy - ay) % 5 == 0 ? 0xe0b071 : 0xf2cb8a); X.R(l, yy, 1, 1, 0xfff0c8) }
        X.R(bl - 1, by, br - bl + 2, 1, OL)
        X.R(ax - 2, ay - 1, 4, 3, 0xffd35a); X.doorAt(ax - 3, by - 10, 7, 9, 0x4a2c18)
    }
    static func column(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14, hh: Double = o.broken ? 12 : 22
        X.shadow(cx, by - 3, 9, 3); X.box(cx - 4, by - hh, 8, hh, 0xefe2c8); X.R(cx + 1, by - hh, 3, hh, 0xd2c3a4)
        var i = cx - 3; while i < cx + 3 { X.R(i, by - hh, 1, hh, 0xe2d3b4); i += 2 }
        X.box(cx - 6, by - 3, 12, 3, 0xd2c3a4)
        if !o.broken { X.box(cx - 6, by - hh - 3, 12, 3, 0xefe2c8) } else { X.R(cx - 4, by - hh - 2, 3, 2, 0xefe2c8); X.R(cx + 5, by - 2, 4, 2, 0xd2c3a4) }
    }
    static func adobe(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let wall = o.wall ?? 0xe0a86a
        let b = X.building(x, y, w, h, .init(wall: PC(wall), roof: shade(wall, -0.08), flat: true, side: 5, lift: 2))
        for i in 0..<3 { X.R(x + 4 + Double(i * 9), b.wy - 2, 4, 2, OL); X.R(x + 5 + Double(i * 9), b.wy - 2, 2, 1, 0x8a5a3a) }
        X.windowAt(x + 4, b.wy + 5, 5, 5, 0x4a3020, shade(wall, -0.2)); X.doorAt(x + 15, b.wy + b.wallH - 11, 7, 11, 0x8a5a3a)
        X.R(x + 2, y + 2, 8, 4, 0xd9534f); X.R(x + 2, y + 4, 8, 1, 0xffcf3a)
    }
    static func market(_ X: PixelCanvas, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        let by = y + h + 2; X.shadow(x + 3, by - 6, w, 6)
        for px in [x + 1, x + w - 3] { X.R(px, by - 18, 2, 18, 0x7a5228) }
        X.box(x + 2, by - 8, w - 4, 7, 0xb98a58)
        for (c, a) in [(UInt32(0xff8a2a), 4.0), (0xe8463f, 10), (0xffcf3a, 16), (0x7fc760, 22)] where a < w - 6 { X.odisc(x + a + 2, by - 9, 2, c) }
        X.R(x - 1, by - 22, w + 2, 7, OL)
        var i = 0.0; while i < w { X.R(x + i, by - 21, min(4, w - i), 5, Int(i / 4) % 2 == 1 ? 0xffffff : 0x2fb3c0); i += 4 }
    }
    static func camel(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.eshadow(cx + 2, by, 9, 3); let c: UInt32 = 0xd6a35e, d: UInt32 = 0xb9854a
        for a in [-6.0, -3, 3, 6] { X.R(cx + a - 1, by - 7, 3, 7, OL); X.R(cx + a, by - 7, 1, 6, d) }
        X.R(cx - 8, by - 13, 17, 7, OL); X.R(cx - 7, by - 12, 15, 5, c); X.odisc(cx - 2, by - 14, 3, c, 2); X.odisc(cx + 3, by - 14, 3, c, 2)
        X.R(cx + 8, by - 20, 3, 9, OL); X.R(cx + 9, by - 19, 1, 8, c); X.R(cx + 8, by - 22, 6, 4, OL); X.R(cx + 9, by - 21, 4, 2, c); X.R(cx + 12, by - 21, 1, 1, OL); X.R(cx - 4, by - 18, 6, 3, 0xd9534f)
    }
    static func cactus(_ o: IslandObject, _ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.eshadow(cx + 3, by, 6, 2); let g: UInt32 = 0x5aa853, gd: UInt32 = 0x3f8a45
        X.R(cx - 3, by - 20, 6, 20, OL); X.R(cx - 2, by - 19, 4, 19, g); X.R(cx + 1, by - 19, 1, 19, gd); X.R(cx - 1, by - 21, 2, 1, OL)
        X.R(cx - 8, by - 14, 6, 4, OL); X.R(cx - 7, by - 13, 5, 2, g); X.R(cx - 8, by - 19, 4, 7, OL); X.R(cx - 7, by - 18, 2, 6, g)
        X.R(cx + 2, by - 11, 6, 4, OL); X.R(cx + 2, by - 10, 5, 2, g); X.R(cx + 4, by - 16, 4, 7, OL); X.R(cx + 5, by - 15, 2, 6, g)
        if hash(o.x, o.y, 3) < 0.5 { X.R(cx - 1, by - 22, 2, 2, 0xff6b8a) }
    }
    static func drybush(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 12
        for k in 0..<10 { let a = Double(k) * 0.63; X.R(cx + cos(a) * 4, by - 3 + sin(a) * 3, 2, 1, 0xa8743c); X.R(cx + cos(a) * 2, by - 3 + sin(a) * 2, 1, 1, 0xc99a5c) }
    }
    static func pottery(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 14; X.eshadow(cx + 2, by, 7, 2); X.odisc(cx - 2, by - 5, 4, 0xc0563f, 5); X.R(cx - 4, by - 11, 4, 2, OL); X.R(cx - 3, by - 10, 2, 1, 0xc0563f); X.R(cx - 4, by - 6, 4, 1, 0xf2d17c); X.odisc(cx + 4, by - 3, 3, 0xd98a3a, 3); X.R(cx + 3, by - 3, 3, 1, 0xfff3df)
    }
    static func fossil(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 12
        for k in 0..<5 { let fk = Double(k); X.R(cx - 6 + fk * 3, by - 6 + Double(k % 2), 2, 6, OL); X.R(cx - 5 + fk * 3, by - 5 + Double(k % 2), 1, 4, 0xfff6e6) }
        X.R(cx - 7, by - 2, 15, 2, OL); X.R(cx - 6, by - 2, 13, 1, 0xfff6e6); X.odisc(cx + 8, by - 4, 2, 0xfff6e6)
    }
    static func gem(_ X: PixelCanvas, _ x: Double, _ y: Double) {
        let cx = x + 8, by = y + 13; X.eshadow(cx + 1, by, 5, 2); X.R(cx - 4, by - 10, 8, 9, OL); X.R(cx - 3, by - 9, 6, 7, 0xb38bff); X.R(cx - 3, by - 9, 2, 4, 0xe9dcff); X.R(cx + 1, by - 6, 2, 4, 0x7a4fd0); X.R(cx - 1, by - 13, 1, 2, 0xffffff); X.R(cx - 2, by - 12, 3, 1, 0xffffff); X.light(cx - 3, by - 9, 2, 2)
    }
}
