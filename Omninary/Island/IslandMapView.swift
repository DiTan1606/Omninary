import SwiftUI
import UIKit

// The island map on screen: a zoomable pixel picture with walking people and floating labels.

enum SpriteCache {
    private static var cache: [String: CGImage] = [:]
    static let size = (w: 20, h: 40), anchor = (x: 10.0, y: 36.0)

    static func person(hair: UInt32, cloth: UInt32, hat: UInt32?, night: Bool, waiting: Bool = false) -> CGImage? {
        let key = "\(hair)-\(cloth)-\(hat ?? 0)-\(night)-\(waiting)"
        if let c = cache[key] { return c }
        let c = PixelCanvas(width: size.w, height: size.h)
        c.person(anchor.x, anchor.y, hair, cloth, .init(hat: hat))
        if waiting { // a little parcel bubble: waiting for a house
            let cx = anchor.x + 2 - 6, cy = anchor.y - 36 + 2
            c.R(cx - 1, cy - 1, 13, 10, OL); c.R(cx, cy, 11, 8, 0xffffff); c.R(cx + 3, cy + 3, 5, 4, 0xc98a4b); c.R(cx + 2, cy + 2, 7, 1, 0xe8463f)
        }
        if night { c.multiplyRect(0, 0, c.width, c.height, by: (0x9a, 0xa6, 0xd8)) }
        let img = c.makeImage(); cache[key] = img; return img
    }

    static func player(night: Bool) -> CGImage? { person(hair: 0x2b2238, cloth: 0xffcf3a, hat: 0x8f6bff, night: night) }

    static func arrow() -> CGImage? {
        if let c = cache["arrow"] { return c }
        let c = PixelCanvas(width: 9, height: 6)
        c.R(0, 0, 9, 6, OL); c.R(1, 1, 7, 2, 0xffcf3a); c.R(2, 3, 5, 1, 0xffcf3a); c.R(3, 4, 3, 1, 0xffcf3a)
        let img = c.makeImage(); cache["arrow"] = img; return img
    }
}

let CEFRColors: [String: UInt32] = ["A1": 0x4fae52, "A2": 0x2fb3c0, "B1": 0x3f6fca, "B2": 0x8e5bd6, "C1": 0xf39a3a, "C2": 0xe8463f]

/// Lets touches through except on its own buttons.
final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

final class IslandMapUIView: UIView, UIScrollViewDelegate {
    weak var game: IslandGame?
    private let scroll = UIScrollView()
    private let content = UIView()
    private let waterLayer = CALayer(), topLayer = CALayer()
    private let lockedFill = CAShapeLayer(), lockedLine = CAShapeLayer(), pulse = CAShapeLayer()
    private let actors = CALayer()
    private let overlay = PassThroughView()
    private var sprites: [Int: CALayer] = [:]
    private let playerLayer = CALayer(), arrowLayer = CALayer()
    private var playerImage: CGImage?
    private var particleLayers: [CALayer] = []
    private var pills: [Int: UILabel] = [:]
    private var badges: [String: UIButton] = [:]
    private var marks: [Int: UILabel] = [:]
    private var link: CADisplayLink?
    private weak var shownScene: IslandScene?
    private var lastTick: CFTimeInterval = 0, lastWater: CFTimeInterval = 0, waterBusy = false
    private let waterQueue = DispatchQueue(label: "omninary.island.water", qos: .userInitiated)
    private var lastCameraID: UUID?
    var topInset: CGFloat = 70, bottomInset: CGFloat = 150

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0x2b / 255, green: 0x66 / 255, blue: 0xae / 255, alpha: 1)
        scroll.delegate = self
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.bouncesZoom = true; scroll.decelerationRate = .normal
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll); scroll.addSubview(content)
        for l in [waterLayer, topLayer, actors] { l.magnificationFilter = .nearest; l.minificationFilter = .nearest; l.anchorPoint = .zero }
        content.layer.addSublayer(waterLayer); content.layer.addSublayer(topLayer)
        lockedFill.fillColor = UIColor.white.withAlphaComponent(0.10).cgColor
        lockedLine.fillColor = nil; lockedLine.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor; lockedLine.lineWidth = 1.6; lockedLine.lineDashPattern = [5, 4]
        pulse.fillColor = nil; pulse.strokeColor = UIColor(red: 1, green: 214 / 255, blue: 58 / 255, alpha: 0.9).cgColor; pulse.lineWidth = 3
        content.layer.addSublayer(lockedFill); content.layer.addSublayer(lockedLine); content.layer.addSublayer(pulse)
        content.layer.addSublayer(actors)
        playerLayer.magnificationFilter = .nearest; arrowLayer.magnificationFilter = .nearest
        actors.addSublayer(playerLayer); actors.addSublayer(arrowLayer)
        addSubview(overlay)
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        scroll.addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, link == nil {
            let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common); link = l
        } else if window == nil { link?.invalidate(); link = nil }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds; overlay.frame = bounds
        scroll.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        updateZoomLimits()
    }

    // MARK: scene

    private func show(_ scene: IslandScene) {
        shownScene = scene
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let w = CGFloat(scene.width), h = CGFloat(scene.height)
        scroll.minimumZoomScale = 0.05; scroll.zoomScale = 1
        content.frame = CGRect(x: 0, y: 0, width: w, height: h)
        scroll.contentSize = content.frame.size
        topLayer.frame = CGRect(x: 0, y: 0, width: w, height: h); topLayer.contents = scene.top
        actors.frame = topLayer.frame
        waterLayer.contents = nil
        let night = scene.night
        backgroundColor = night ? UIColor(red: 0x0d / 255, green: 0x24 / 255, blue: 0x4a / 255, alpha: 1) : UIColor(red: 0x2b / 255, green: 0x66 / 255, blue: 0xae / 255, alpha: 1)
        let fillPath = CGMutablePath(), linePath = CGMutablePath(), T = CGFloat(TILE), cols = scene.map.cols
        for L in scene.locked {
            for (x, y) in L.tiles {
                fillPath.addRect(CGRect(x: CGFloat(x) * T, y: CGFloat(y) * T, width: T, height: T))
                func out(_ i: Int, _ j: Int) -> Bool { !L.set.contains(j * cols + i) && !scene.map.isLand(i, j) }
                let X = CGFloat(x) * T, Y = CGFloat(y) * T
                if out(x, y - 1) { linePath.move(to: CGPoint(x: X, y: Y)); linePath.addLine(to: CGPoint(x: X + T, y: Y)) }
                if out(x, y + 1) { linePath.move(to: CGPoint(x: X, y: Y + T)); linePath.addLine(to: CGPoint(x: X + T, y: Y + T)) }
                if out(x - 1, y) { linePath.move(to: CGPoint(x: X, y: Y)); linePath.addLine(to: CGPoint(x: X, y: Y + T)) }
                if out(x + 1, y) { linePath.move(to: CGPoint(x: X + T, y: Y)); linePath.addLine(to: CGPoint(x: X + T, y: Y + T)) }
            }
        }
        lockedFill.path = fillPath; lockedLine.path = linePath
        for (_, l) in sprites { l.removeFromSuperlayer() }; sprites = [:]
        for (_, p) in pills { p.removeFromSuperview() }; pills = [:]
        for (_, b) in badges { b.removeFromSuperview() }; badges = [:]
        for (_, m) in marks { m.removeFromSuperview() }; marks = [:]
        playerImage = SpriteCache.player(night: night); arrowLayer.contents = SpriteCache.arrow()
        CATransaction.commit()
        updateZoomLimits()
        lastWater = 0
    }

    private var fitZoom: CGFloat {
        guard let s = shownScene, bounds.width > 0 else { return 1 }
        return min(bounds.width / CGFloat(s.width), (bounds.height - topInset - bottomInset) / CGFloat(s.height))
    }
    private func updateZoomLimits() {
        guard shownScene != nil else { return }
        scroll.minimumZoomScale = max(0.2, fitZoom * 0.95); scroll.maximumZoomScale = 4
    }

    func center(on x: Double, _ y: Double, zoom: Double, animated: Bool) {
        guard shownScene != nil else { return }
        let z = min(scroll.maximumZoomScale, max(scroll.minimumZoomScale, CGFloat(zoom)))
        scroll.setZoomScale(z, animated: false)
        scroll.contentOffset = clampedOffset(CGPoint(x: CGFloat(x) * z - bounds.width / 2, y: CGFloat(y) * z - bounds.height / 2))
    }
    private func clampedOffset(_ p: CGPoint) -> CGPoint {
        let maxX = max(0, scroll.contentSize.width - bounds.width), maxY = max(-topInset, scroll.contentSize.height + bottomInset - bounds.height)
        return CGPoint(x: min(max(0, p.x), maxX), y: min(max(-topInset, p.y), maxY))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // keep a small map centred horizontally
        let dx = max(0, (bounds.width - scroll.contentSize.width) / 2)
        content.frame.origin.x = dx
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { game?.follow = false }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { game?.follow = false }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: content)
        game?.tap(wx: Double(p.x), wy: Double(p.y))
    }

    private func toScreen(_ x: Double, _ y: Double) -> CGPoint { content.convert(CGPoint(x: x, y: y), to: self) }

    // MARK: frame loop

    @objc private func frame(_ link: CADisplayLink) {
        guard let game else { return }
        let ts = link.timestamp, dt = lastTick == 0 ? 0 : min(0.1, ts - lastTick); lastTick = ts
        if let scene = game.scene, scene !== shownScene {
            show(scene)
            if let t = game.cameraTarget { lastCameraID = t.id; center(on: t.x, t.y, zoom: t.zoom, animated: false) }
            else { center(on: Double((22 + OX) * TILE), Double((26 + OY) * TILE), zoom: max(Double(fitZoom) * 1.3, 1), animated: false) }
        }
        guard let scene = shownScene else { return }
        if let t = game.cameraTarget, t.id != lastCameraID { lastCameraID = t.id; center(on: t.x, t.y, zoom: t.zoom, animated: false) }
        game.step(dt)
        if game.follow && !game.player.path.isEmpty && !scroll.isTracking && !scroll.isZooming {
            let z = scroll.zoomScale, target = CGPoint(x: CGFloat(game.player.x) * z - bounds.width / 2, y: CGFloat(game.player.y - 20) * z - bounds.height / 2)
            let cur = scroll.contentOffset, k = CGFloat(min(1, dt * 4))
            scroll.contentOffset = clampedOffset(CGPoint(x: cur.x + (target.x - cur.x) * k, y: cur.y + (target.y - cur.y) * k))
        }
        let vis = content.convert(bounds, from: self)
        game.currentCamera = (Double(vis.midX), Double(vis.midY), Double(scroll.zoomScale))
        updateWater(scene, ts, vis)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        drawActors(game, scene, ts)
        drawPulse(game, ts)
        CATransaction.commit()
        drawLabels(game, scene, ts)
    }

    private func updateWater(_ scene: IslandScene, _ ts: CFTimeInterval, _ vis: CGRect) {
        let still = UIAccessibility.isReduceMotionEnabled
        guard !waterBusy, ts - lastWater > 0.16, !(still && lastWater > 0) else { return }
        lastWater = ts; waterBusy = true
        let r = vis.insetBy(dx: -8, dy: -8)
        let rect = (Int(r.minX.rounded(.down)), Int(r.minY.rounded(.down)), Int(r.maxX.rounded(.up)), Int(r.maxY.rounded(.up)))
        let t = ts
        waterQueue.async { [weak self] in
            let img = scene.waterImage(rect, t: t)
            DispatchQueue.main.async {
                guard let self else { return }
                self.waterBusy = false
                guard scene === self.shownScene, let img else { return }
                CATransaction.begin(); CATransaction.setDisableActions(true)
                let x0 = max(0, rect.0), y0 = max(0, rect.1)
                self.waterLayer.frame = CGRect(x: x0, y: y0, width: img.width, height: img.height)
                self.waterLayer.contents = img
                CATransaction.commit()
            }
        }
    }

    private func place(_ layer: CALayer, _ img: CGImage?, x: Double, y: Double) {
        guard let img else { return }
        layer.contents = img
        layer.frame = CGRect(x: CGFloat(x - SpriteCache.anchor.x), y: CGFloat(y - SpriteCache.anchor.y), width: CGFloat(img.width), height: CGFloat(img.height))
        layer.zPosition = CGFloat(y)
    }

    private func drawActors(_ game: IslandGame, _ scene: IslandScene, _ ts: CFTimeInterval) {
        let home = game.mode == .home
        var seen = Set<Int>()
        if home {
            for r in game.residents {
                seen.insert(r.id)
                let layer = sprites[r.id] ?? { let l = CALayer(); l.magnificationFilter = .nearest; actors.addSublayer(l); sprites[r.id] = l; return l }()
                let lvl = r.level, cloth = lvl > 0 ? (CEFRColors[r.vocab.CEFR?.uppercased() ?? ""] ?? 0x3f6fca) : 0xa8a2b8
                let bob = !r.walker.path.isEmpty ? (sin(ts / 0.09 + Double(r.id)) * 0.6).rounded() : 0
                place(layer, SpriteCache.person(hair: r.hair, cloth: cloth, hat: lvl >= 7 ? 0xffcf3a : nil, night: scene.night, waiting: r.waiting), x: r.walker.x.rounded(), y: r.walker.y.rounded() + bob)
            }
        }
        for (id, l) in sprites where !seen.contains(id) { l.removeFromSuperlayer(); sprites[id] = nil }
        let p = game.player, bob = p.path.isEmpty ? 0 : (sin(ts / 0.08) * 0.7).rounded()
        place(playerLayer, playerImage, x: p.x.rounded(), y: p.y.rounded() + bob)
        arrowLayer.frame = CGRect(x: p.x.rounded() - 4, y: p.y.rounded() + bob - 34 + (sin(ts / 0.22) * 1.5).rounded(), width: 9, height: 6)
        arrowLayer.zPosition = CGFloat(p.y) + 0.5
        while particleLayers.count < game.particles.count { let l = CALayer(); actors.addSublayer(l); particleLayers.append(l) }
        for (i, l) in particleLayers.enumerated() {
            if i < game.particles.count {
                let q = game.particles[i]; l.isHidden = false
                l.frame = CGRect(x: q.x, y: q.y, width: 2, height: 2); l.zPosition = 9999
                l.backgroundColor = UIColor(rgb: q.color).cgColor
            } else { l.isHidden = true }
        }
    }

    private func drawPulse(_ game: IslandGame, _ ts: CFTimeInterval) {
        if let p = game.pulseLot, Date() < p.until {
            let l = p.lot, T = CGFloat(TILE)
            pulse.path = CGPath(rect: CGRect(x: CGFloat(l.x) * T + 1, y: CGFloat(l.y) * T + 1, width: CGFloat(l.w) * T - 2, height: CGFloat(l.h) * T - 2), transform: nil)
            pulse.opacity = Float(0.5 + 0.4 * sin(ts / 0.15))
        } else { pulse.path = nil }
    }

    private func drawLabels(_ game: IslandGame, _ scene: IslandScene, _ ts: CFTimeInterval) {
        let blink = Int(ts / 0.5) % 2 == 0
        // due words in red above their residents
        var seen = Set<Int>()
        if game.mode == .home && scroll.zoomScale >= 1.1 {
            // at most eight labels, the ones nearest the middle of the screen
            let mid = CGPoint(x: bounds.midX, y: bounds.midY)
            var candidates: [(IslandResident, CGPoint, CGFloat)] = []
            let maxY = bounds.height - 170
            for r in game.residents where r.due && game.openResident?.id != r.id {
                let p = toScreen(r.walker.x, r.walker.y - 30)
                guard p.x > 0, p.x < bounds.width, p.y > 110, p.y < maxY else { continue }
                candidates.append((r, p, hypot(p.x - mid.x, p.y - mid.y)))
            }
            candidates.sort { $0.2 < $1.2 }
            let shown = candidates.prefix(8).map { ($0.0, $0.1) }
            for (r, s) in shown {
                seen.insert(r.id)
                let l = pills[r.id] ?? { let l = PaddedLabel(); l.font = .omniDisplay(13); l.textColor = .white; l.layer.cornerRadius = 9; l.layer.masksToBounds = true; l.layer.borderColor = UIColor(rgb: 0x2a2440).cgColor; l.layer.borderWidth = 2; overlay.addSubview(l); pills[r.id] = l; return l }()
                l.text = "! " + (r.vocab.vocab ?? "")
                l.backgroundColor = UIColor(rgb: blink ? 0xe8463f : 0xff6b5e)
                l.sizeToFit(); l.center = s
            }
        }
        for (id, l) in pills where !seen.contains(id) { l.removeFromSuperview(); pills[id] = nil }
        // regions for sale
        var seenB = Set<String>()
        if game.mode == .home {
            let z = scroll.zoomScale
            for L in scene.locked {
                let s = toScreen((Double(L.region.center.0) + 0.5) * 16, (Double(L.region.center.1) + 0.5) * 16)
                guard s.x > -90, s.x < bounds.width + 90, s.y > 110, s.y < bounds.height - 190 else { continue }
                seenB.insert(L.region.id)
                let b = badges[L.region.id] ?? makeBadge(L.region)
                let compact = z < 0.55
                b.subviews.forEach { $0.isHidden = false }
                if let name = b.viewWithTag(2), let cost = b.viewWithTag(3) as? UILabel {
                    name.isHidden = compact; cost.isHidden = compact
                    cost.textColor = UIColor(rgb: game.omni >= L.region.cost ? 0x5b3fc9 : 0xa02a22)
                }
                b.frame.size = compact ? CGSize(width: 32, height: 32) : CGSize(width: 150, height: 84)
                b.center = compact ? s : CGPoint(x: s.x, y: s.y + 2)
                layoutBadge(b, compact: compact, affordable: game.omni >= L.region.cost)
            }
        }
        for (id, b) in badges where !seenB.contains(id) { b.removeFromSuperview(); badges[id] = nil }
        // quest markers
        var seenM = Set<Int>()
        if game.mode == .stage, let run = game.stage {
            for (k, q) in run.quests.enumerated() {
                let s = toScreen(Double(q.x * 16 + 8), Double(q.y * 16) - 10 + sin(ts / 0.26 + Double(q.x)) * 2)
                guard s.x > -20, s.x < bounds.width + 20, s.y > -20, s.y < bounds.height + 20 else { continue }
                seenM.insert(k)
                let m = marks[k] ?? { let m = UILabel(); m.textAlignment = .center; m.font = .omniDisplay(13); m.textColor = UIColor(rgb: 0x2a2440); m.layer.cornerRadius = 11; m.layer.masksToBounds = true; m.layer.borderWidth = 2; m.layer.borderColor = UIColor(rgb: 0x2a2440).cgColor; overlay.addSubview(m); marks[k] = m; return m }()
                let done = q.remaining == 0
                m.text = done ? "✓" : "!"
                m.backgroundColor = UIColor(rgb: done ? 0x5ad152 : 0xffcf3a)
                m.frame = CGRect(x: s.x - 11, y: s.y - 11, width: 22, height: 22)
            }
        }
        for (k, m) in marks where !seenM.contains(k) { m.removeFromSuperview(); marks[k] = nil }
    }

    private func makeBadge(_ region: IslandRegion) -> UIButton {
        let b = UIButton(type: .custom)
        b.addAction(UIAction { [weak self] _ in self?.game?.openRegion = region }, for: .touchUpInside)
        let plus = UIView(); plus.tag = 1; plus.isUserInteractionEnabled = false
        let name = UILabel(); name.tag = 2; name.text = region.name; name.font = .omniDisplay(15); name.textColor = UIColor(rgb: 0x2a2440); name.textAlignment = .center
        let cost = UILabel(); cost.tag = 3; cost.text = "\(region.cost) Omni"; cost.font = .omniDisplay(13); cost.textAlignment = .center
        let card = UIView(); card.tag = 4; card.backgroundColor = UIColor(rgb: 0xfffaf0); card.layer.cornerRadius = 11; card.layer.borderWidth = 3; card.layer.borderColor = UIColor(rgb: 0x2a2440).cgColor; card.isUserInteractionEnabled = false
        for v in [card, name, cost, plus] { b.addSubview(v); v.isUserInteractionEnabled = false }
        overlay.addSubview(b); badges[region.id] = b
        return b
    }

    private func layoutBadge(_ b: UIButton, compact: Bool, affordable: Bool) {
        guard let plus = b.viewWithTag(1), let name = b.viewWithTag(2), let cost = b.viewWithTag(3), let card = b.viewWithTag(4) else { return }
        let w = b.bounds.width
        plus.frame = compact ? CGRect(x: 3, y: 3, width: 26, height: 26) : CGRect(x: w / 2 - 15, y: 0, width: 30, height: 30)
        plus.layer.cornerRadius = plus.bounds.width / 2
        plus.backgroundColor = UIColor(rgb: affordable ? 0xffcf3a : 0xfffaf0)
        plus.layer.borderWidth = 3; plus.layer.borderColor = UIColor(rgb: 0x2a2440).cgColor
        if plus.layer.sublayers?.isEmpty ?? true {
            let h = CALayer(), v = CALayer(); h.backgroundColor = UIColor(rgb: 0x2a2440).cgColor; v.backgroundColor = h.backgroundColor
            plus.layer.addSublayer(h); plus.layer.addSublayer(v)
        }
        let s = plus.bounds.width, bar: CGFloat = 3.5, len = s * 0.5
        plus.layer.sublayers?[0].frame = CGRect(x: (s - len) / 2, y: (s - bar) / 2, width: len, height: bar)
        plus.layer.sublayers?[1].frame = CGRect(x: (s - bar) / 2, y: (s - len) / 2, width: bar, height: len)
        card.isHidden = compact
        card.frame = CGRect(x: 0, y: 34, width: w, height: 44)
        name.frame = CGRect(x: 4, y: 37, width: w - 8, height: 20)
        cost.frame = CGRect(x: 4, y: 56, width: w - 8, height: 18)
    }
}

final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.insetBy(dx: 7, dy: 2)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { let s = super.sizeThatFits(size); return CGSize(width: s.width + 14, height: s.height + 6) }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

extension UIFont {
    static func omniDisplay(_ size: CGFloat) -> UIFont {
        OmniFonts.register()
        return UIFont(name: "Baloo2-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }
}

struct IslandMapView: UIViewRepresentable {
    @ObservedObject var game: IslandGame
    func makeUIView(context: Context) -> IslandMapUIView { let v = IslandMapUIView(); v.game = game; return v }
    func updateUIView(_ v: IslandMapUIView, context: Context) { v.game = game }
}
