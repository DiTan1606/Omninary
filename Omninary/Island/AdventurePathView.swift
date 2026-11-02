import SwiftUI

// Lộ trình: a vertical sea of one region's 15 islands. Each island is a map of 6 levels (flags on
// its quest spots); a sailboat waits at the current island's dock and sails on when the island is done.

private let ink = Color(hex: 0x2a2440)
private let seaColor = Color(hex: 0x2b66ae)
/// The deep sea under the stage maps' night tint.
private let nightSeaColor = Color(hex: 0x0c2347)

enum PathSprites {
    /// A small sailboat with the player (purple cap, yellow shirt), drawn with the engine's pen.
    static let boat: CGImage? = {
        let c = PixelCanvas(width: 48, height: 44)
        c.R(23, 2, 2, 24, OL); c.R(23, 3, 1, 22, 0x8a5a3a)
        for j in 0..<16 { let w = Double(j) * 0.9; c.R(25, 4 + Double(j), w + 2, 1, OL); if w > 0 { c.R(25, 4 + Double(j), w, 1, j < 3 ? 0xffffff : 0xf3ead8) } }
        c.R(25, 20, 16, 1, OL)
        c.person(15, 33, 0x6b3a20, 0xffcf3a, .init(hat: 0x5b3fc9))
        IslandDraw.boat(c, 8, 22, 32)
        return c.makeImage()
    }()
}

/// Where everything sits on the sea, in points, for one region.
struct PathLayout {
    struct Isle {
        let map: Int; let art: IsleArt
        /// The whole picture (land and its shallow water) and the land alone.
        let frame: CGRect; let land: CGRect
        /// The name card under the land, and where the boat waits beside it.
        let label: CGPoint; let boat: CGPoint
        func point(_ p: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: frame.minX + (p.x - art.crop.minX) * k, y: frame.minY + (p.y - art.crop.minY) * k) }
    }
    let isles: [Isle]
    let scale: CGFloat
    let height: CGFloat
    /// Centre of the card announcing the next region, above the bottom buttons once scrolled down.
    let nextCard: CGFloat
    let route: Path

    static func labelWidth(_ map: Int) -> CGFloat {
        let text = "\(map % 15 + 1) · \(AdventureMaps.name(map))" as NSString
        return text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .heavy)]).width + 30
    }

    init(region: Int, width: CGFloat, arts: [Int: IsleArt]) {
        let f = width / 390, k = 0.56 * f
        var y: CGFloat = 250 * f, list: [Isle] = []
        for g in 0..<15 {
            let map = region * 15 + g
            guard let art = arts[map] else { continue }
            let lw = art.land.width * k, lh = art.land.height * k
            let lx = g % 2 == 0 ? 26 * f : width - lw - 26 * f
            let land = CGRect(x: lx, y: y, width: lw, height: lh)
            let frame = CGRect(x: lx - (art.land.minX - art.crop.minX) * k, y: y - (art.land.minY - art.crop.minY) * k,
                               width: art.crop.width * k, height: art.crop.height * k)
            let label = CGPoint(x: land.midX, y: land.maxY + 8)
            // The boat waits beside the name card: right of it for islands on the left, left of it otherwise.
            let half = PathLayout.labelWidth(map) / 2, bx = g % 2 == 0 ? label.x + half + 36 : label.x - half - 36
            let boat = CGPoint(x: min(width - 34, max(34, bx)), y: label.y - 4)
            list.append(Isle(map: map, art: art, frame: frame, land: land, label: label, boat: boat))
            y += lh + 120 * f
        }
        var route = Path()
        for (a, b) in zip(list, list.dropFirst()) {
            route.move(to: CGPoint(x: a.boat.x, y: a.boat.y + 16))
            route.addQuadCurve(to: CGPoint(x: b.boat.x, y: b.boat.y + 16), control: CGPoint(x: (a.map % 2 == 0 ? 330 : 60) * f, y: (a.boat.y + b.boat.y) / 2))
        }
        isles = list; scale = k; nextCard = y + 30 * f; height = y + 330 * f; self.route = route
    }

    func boatSpot(_ g: Int) -> CGPoint {
        guard g < isles.count else { return CGPoint(x: 170, y: height - 80) }
        return isles[g].boat
    }
}

struct AdventurePathView: View {
    @ObservedObject var game: IslandGame
    @State private var arts: [Int: IsleArt] = [:]
    /// The region on screen; while the boat sails off a finished region it stays the old one.
    @State private var shownRegion: Int?
    @State private var boat: CGPoint?
    @State private var boatFlip = false
    @State private var sailing = false
    /// Where the sea is scrolled to; set to the island being learned whenever the path opens.
    @State private var position = ScrollPosition(edge: .top)
    /// Height of the screen the sea scrolls in.
    @State private var viewport: CGFloat = 700

    private var conquest: AdventureConquest { game.conquest }
    private var region: Int { shownRegion ?? min(3, conquest.map / 15) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView(showsIndicators: false) {
                    let regionArts = (0..<15).compactMap { arts[region * 15 + $0] }
                    if regionArts.count == 15 {
                        let L = PathLayout(region: region, width: width, arts: arts)
                        sea(L, width: width)
                            .frame(width: width, height: L.height)
                            .onAppear { focusCurrent(L, viewport: geo.size.height) }
                            // The learner's place comes from the server after the path is already
                            // on screen (island 1 until then): focus again once it is known.
                            .onChange(of: game.conquest) { _, _ in focusCurrent(L, viewport: geo.size.height) }
                    } else {
                        ProgressView().tint(.white).frame(width: width, height: geo.size.height)
                    }
                }
                .scrollPosition($position)
                .background((game.night ? nightSeaColor : seaColor).ignoresSafeArea())
                .onChange(of: game.sailFrom) { _, from in if from != nil { sail(width: width) } }
                .task(id: region) { await loadRegion(region) }
                .onAppear { viewport = geo.size.height; if game.sailFrom != nil { sail(width: width) } }
                .onChange(of: geo.size.height) { _, h in viewport = h }
        }
    }

    // MARK: sea

    private func sea(_ L: PathLayout, width: CGFloat) -> some View {
        let f = width / 390
        let currentMap = conquest.map, levelsDone = min(6, conquest.words / 5)
        return ZStack(alignment: .topLeading) {
            SeaWaves(scale: L.scale, night: game.night)
            L.route.stroke(.white.opacity(game.night ? 0.4 : 0.65), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 11]))
            if let puff = CloudArt.puff {
                // Home clouds drifting slowly across the sea, wrapping around the sides.
                TimelineView(.animation(minimumInterval: 1 / 20)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<6, id: \.self) { i in
                            let span = width + 120 * f, speed = 4 + Double(i % 3) * 2.5
                            let x = CGFloat((Double(i) * 137 + t * speed).truncatingRemainder(dividingBy: Double(span))) - 60 * f
                            Image(decorative: puff, scale: 1).resizable().interpolation(.none).frame(width: 78 * f, height: 42 * f)
                                .position(x: x, y: L.height * [0.1, 0.27, 0.44, 0.6, 0.76, 0.9][i])
                        }
                    }
                }
                .opacity(game.night ? 0.35 : 1)
                .allowsHitTesting(false)
            }
            ForEach(Array(L.isles.enumerated()), id: \.offset) { g, isle in
                let got = isle.map < currentMap, cur = isle.map == currentMap
                island(isle, scale: L.scale, got: got, cur: cur, done: got ? 6 : cur ? levelsDone : 0)
                // The id goes on the 1 pt marker itself: placed after .position it would name the whole
                // sea (position fills its parent), and scrolling to it would land mid-region.
                Color.clear.frame(width: 1, height: 1).id("isle-\(g)").position(x: isle.land.midX, y: isle.land.midY)
            }
            if region < 3 {
                VStack(spacing: 2) {
                    Text(AdventureRegion.all[region + 1].name).font(.omniBody(17, weight: 800))
                    Text("Mở khi chinh phục đảo 15 · thuyền sẽ ra khơi").font(.omniBody(12.5, weight: 600)).opacity(0.9)
                }
                .foregroundStyle(.white).padding(12).frame(width: width - 48)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                .position(x: width / 2, y: L.nextCard)
            }
            if let img = PathSprites.boat {
                let p = boat ?? L.boatSpot(currentMap - region * 15)
                Image(decorative: img, scale: 1).resizable().interpolation(.none).frame(width: 62 * f, height: 57 * f)
                    .scaleEffect(x: boatFlip ? -1 : 1, y: 1)
                    .position(p)
                    .accessibilityHidden(true)
            }
        }
    }

    private func island(_ isle: PathLayout.Isle, scale k: CGFloat, got: Bool, cur: Bool, done: Int) -> some View {
        let locked = !got && !cur
        let g = isle.map % 15
        return ZStack(alignment: .topLeading) {
            Image(decorative: game.night ? isle.art.nightImage : isle.art.image, scale: 1).resizable().interpolation(.none)
                .frame(width: isle.frame.width, height: isle.frame.height)
                .saturation(locked ? 0.3 : 1).brightness(locked ? 0.06 : 0)
                .position(x: isle.frame.midX, y: isle.frame.midY)
                .onTapGesture { if got { game.visit(isle.map) } }
            if locked {
                Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                    .frame(width: 36, height: 36).background(.white, in: Circle()).overlay(Circle().stroke(ink, lineWidth: 3))
                    .position(x: isle.land.midX, y: isle.land.midY)
            } else {
                ForEach(Array(isle.art.levels.enumerated()), id: \.offset) { i, spot in
                    flag(i, done: done, current: cur, map: isle.map).position(isle.point(spot, k))
                }
            }
            label(isle, got: got, cur: cur, locked: locked, done: done)
                .position(isle.label)
            if got {
                Text("ĐÃ CHINH PHỤC").font(.omniDisplay(12)).foregroundStyle(Color(hex: 0x1f7a37))
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .background(Color(hex: 0xe2f6e6), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x34b45a), lineWidth: 2))
                    .rotationEffect(.degrees(-6))
                    .position(x: isle.land.midX, y: isle.land.minY + 10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Đảo \(g + 1), \(AdventureMaps.name(isle.map))")
        .accessibilityHint(got ? "Bấm để vào đảo" : "")
    }

    @ViewBuilder
    private func flag(_ i: Int, done: Int, current: Bool, map: Int) -> some View {
        let state = i < done ? 0 : (i == done && current ? 1 : 2)
        let size: CGFloat = state == 1 ? 36 : 26
        Button {
            if state == 1 { game.play() }
            else if state == 0 && !current { game.visit(map) }
            else if state == 0 { game.showToast("Màn \(i + 1) đã qua") }
            else { game.showToast("Qua màn \(done + 1) trước nhé") }
        } label: {
            Text(state == 0 ? "✓" : state == 1 ? "!" : "\(i + 1)")
                .font(.omniDisplay(state == 1 ? 19 : 13))
                .foregroundStyle(state == 0 ? .white : state == 1 ? ink : Color(hex: 0x5b6779))
                .frame(width: size, height: size)
                .background(state == 0 ? Color(hex: 0x34b45a) : state == 1 ? Color(hex: 0xf0b429) : .white.opacity(0.92), in: Circle())
                .overlay(Circle().stroke(state == 2 ? ink.opacity(0.55) : ink, lineWidth: 3))
                .modifier(Beat(on: state == 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Màn \(i + 1)" + (state == 0 ? ", đã qua" : state == 1 ? ", đang học" : ", chưa mở"))
    }

    private func label(_ isle: PathLayout.Isle, got: Bool, cur: Bool, locked: Bool, done: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(isle.map % 15 + 1) · \(AdventureMaps.name(isle.map))").font(.omniBody(14, weight: 800)).foregroundStyle(Color(hex: 0x17202e))
            Text(got ? "✓ 6/6 màn" : cur ? "Màn \(min(6, done + 1))/6 · đang học" : "6 màn").font(.omniBody(11.5, weight: 700)).foregroundStyle(Color(hex: 0x5b6779))
        }
        .lineLimit(1).fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(cur ? Color(hex: 0xfff6dc) : locked ? Color(hex: 0xeef1f6) : .white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(locked ? Color(hex: 0x8994a8) : ink, lineWidth: 3))
        .background(RoundedRectangle(cornerRadius: 14).fill(locked ? Color(hex: 0x8994a8) : ink).offset(y: 4))
    }

    // MARK: loading, scrolling, sailing

    private func loadRegion(_ r: Int) async {
        // Islands already drawn this run come straight from memory, so the path opens at once.
        for g in 0..<15 where arts[r * 15 + g] == nil {
            if let art = IslandArt.cached(r * 15 + g) { arts[r * 15 + g] = art }
        }
        for g in 0..<15 where arts[r * 15 + g] == nil {
            let map = r * 15 + g
            let art = await Task.detached(priority: .userInitiated) { IslandArt.isle(map) }.value
            arts[map] = art
        }
    }

    /// Puts the island being learned in the middle of the screen, by offset (no anchor lookup).
    private func focusCurrent(_ L: PathLayout, viewport: CGFloat) {
        guard game.sailFrom == nil, !sailing, !L.isles.isEmpty else { return }
        let g = max(0, min(L.isles.count - 1, conquest.map - region * 15))
        let y = min(max(0, L.isles[g].land.midY - viewport / 2), max(0, L.height - viewport))
        position.scrollTo(y: y)
        // once more after the first layout pass, in case the content size was not final yet
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard game.sailFrom == nil, !sailing else { return }
            position.scrollTo(y: y)
        }
    }

    /// The boat sails from the island just finished to the next one; after island 15 it sails
    /// off the bottom, the clouds close, and the next region's sea opens with the boat at island 1.
    private func sail(width: CGFloat) {
        guard let from = game.sailFrom, !sailing else { return }
        let fromRegion = min(3, from / 15)
        guard (0..<15).allSatisfy({ arts[fromRegion * 15 + $0] != nil }) else {
            shownRegion = fromRegion
            Task { await loadRegion(fromRegion); sail(width: width) }
            return
        }
        sailing = true
        shownRegion = fromRegion
        let L = PathLayout(region: fromRegion, width: width, arts: arts), g = from % 15
        let start = L.boatSpot(g)
        boat = start
        // The camera rides with the boat: every move of the boat moves the sea under it by the same
        // amount, in the same animation, so the boat stays in the middle of the screen.
        position.scrollTo(y: camera(start.y, L))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            if g < 14 {
                let next = L.boatSpot(g + 1), mid = CGPoint(x: (g % 2 == 0 ? 300 : 90) * width / 390, y: (start.y + next.y) / 2)
                boatFlip = mid.x < start.x
                withAnimation(.easeInOut(duration: 1.3)) { boat = mid; position.scrollTo(y: camera(mid.y, L)) }
                try? await Task.sleep(for: .milliseconds(1300))
                boatFlip = next.x < mid.x
                withAnimation(.easeInOut(duration: 1.3)) { boat = next; position.scrollTo(y: camera(next.y, L)) }
                try? await Task.sleep(for: .milliseconds(1300))
                game.showToast("Tới \(AdventureMaps.name(from + 1))")
            } else {
                // off the bottom of this region's sea, the clouds close, the next sea opens at its top
                let exit = CGPoint(x: width / 2, y: L.height - 40)
                withAnimation(.easeIn(duration: 2)) { boat = exit; position.scrollTo(y: camera(exit.y, L)) }
                try? await Task.sleep(for: .milliseconds(1500))
                let nextRegion = min(3, fromRegion + 1)
                await game.curtain {
                    await loadRegion(nextRegion)
                    shownRegion = nextRegion
                    boat = CGPoint(x: width / 2, y: 40)
                    position.scrollTo(y: 0)
                }
                let L2 = PathLayout(region: nextRegion, width: width, arts: arts), first = L2.boatSpot(0)
                withAnimation(.easeOut(duration: 1.6)) { boat = first; position.scrollTo(y: camera(first.y, L2)) }
                try? await Task.sleep(for: .milliseconds(1600))
                game.showToast("Chào mừng tới \(AdventureMaps.region(from + 1).name)")
            }
            try? await Task.sleep(for: .milliseconds(400))
            boat = nil; boatFlip = false; shownRegion = nil; sailing = false
            game.sailFrom = nil
        }
    }

    /// The scroll offset that puts `y` in the middle of the screen, kept inside the sea.
    private func camera(_ y: CGFloat, _ L: PathLayout) -> CGFloat {
        min(max(0, y - viewport / 2), max(0, L.height - viewport))
    }
}

/// The open sea, painted by the engine's water: deep blue with glints that twinkle and drift.
struct SeaWaves: View {
    let scale: CGFloat
    var night = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.19)) { ctx in
            let frames = night ? SeaArt.nightFrames : SeaArt.frames
            if !frames.isEmpty {
                let k = Int(ctx.date.timeIntervalSinceReferenceDate / 0.19) % frames.count
                Rectangle().fill(ImagePaint(image: Image(decorative: frames[k], scale: 1 / scale).interpolation(.none), scale: 1))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct Beat: ViewModifier {
    let on: Bool
    @State private var up = false
    func body(content: Content) -> some View {
        content.scaleEffect(on && up ? 1.12 : 1)
            .onAppear { guard on else { return }; withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { up = true } }
    }
}

/// The scene change: two cloud banks close over the screen from the sides, then part again.
struct CloudCurtain: View {
    let closed: Bool
    var body: some View {
        GeometryReader { geo in
            if let l = CloudArt.left, let r = CloudArt.right {
                let w = geo.size.width * 0.62, h = geo.size.height + 40
                ZStack {
                    Image(decorative: l, scale: 1).resizable().interpolation(.none).frame(width: w, height: h)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(x: closed ? 0 : -w * 1.15)
                    Image(decorative: r, scale: 1).resizable().interpolation(.none).frame(width: w, height: h)
                        .scaleEffect(x: -1, y: 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(x: closed ? 0 : w * 1.15)
                }
                .offset(y: -20)
                .animation(.timingCurve(0.6, 0, 0.3, 1, duration: 0.6), value: closed)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(closed)
        .accessibilityHidden(true)
    }
}
