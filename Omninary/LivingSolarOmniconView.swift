import SwiftUI

// MARK: - Living Solar Omnicon View (C2 Supreme Tier)
/// Biểu tượng Omnicon C2 Cosmos Master ("Hệ Mặt Trời" / Solar System Omnicon):
/// - Trạng thái bình thường (`isAwakened == false`): Bản động trực tiếp 60-120 FPS ProMotion.
///   8 hành tinh (Thủy, Kim, Trái Đất cùng Mặt Trăng, Hỏa, Mộc, Thổ, Thiên Vương, Hải Vương) quay
///   quanh Mặt Trời theo đúng quy luật thiên văn học. Mảnh 4 & 5 là thấu kính pha lê trong suốt
///   lộ vệt quỹ đạo vàng bên dưới; mảnh 1, 2, 3, 6 là Men Lam Quý Tộc viền Đồng Thau Cổ 18K.
/// - Trạng thái nhấn giữ (`isAwakened == true`): Mặt Trời nở to cực đại (R = 18 -> 52.3px), siêu gia nhiệt,
///   xuất hiện lốc xoáy đồng tâm mờ ảo huyền bí và hút nuốt chửng hoàn toàn cả 8 hành tinh vào tâm;
///   6 mảnh chữ O tách tâm tịnh tiến ra ngoài ~8px và rung lắc dữ dội kháng cự siêu trọng lực!
/// - Khi thả tay ra: Trở lại bình thường, các mảnh hồi vị, Mặt Trời co về kích thước cũ và 8 hành tinh
///   lại tiếp tục quay êm ả quanh Thái Dương.
struct LivingSolarOmniconView: View {
    var isAwakened: Bool = false
    var size: CGFloat = 70
    var cornerRadius: CGFloat = 18

    // Trạng thái vật lý nội tại phục vụ chuyển động nở to & hồi vị
    @State private var pressStartTimestamp: Double? = nil
    @State private var releaseStartTimestamp: Double? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            SolarCanvasView(
                time: now,
                size: size,
                isAwakened: isAwakened,
                pressStartTime: pressStartTimestamp,
                releaseStartTime: releaseStartTimestamp
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: isAwakened) { _, awakened in
            let currentNow = Date().timeIntervalSinceReferenceDate
            if awakened {
                pressStartTimestamp = currentNow
                releaseStartTimestamp = nil
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } else {
                releaseStartTimestamp = currentNow
                pressStartTimestamp = nil
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}

// MARK: - Solar Canvas Render Engine (120 FPS High Performance)
private struct SolarCanvasView: View {
    let time: Double
    let size: CGFloat
    let isAwakened: Bool
    let pressStartTime: Double?
    let releaseStartTime: Double?

    // Planetary constants in 400x400 reference space
    private struct PlanetDef {
        let name: String
        let rOrbit: CGFloat
        let rBody: CGFloat
        let color: Color
        let haloColor: Color
        let speed: Double
        let initialAngle: Double
        var hasMoon: Bool = false
        var isJupiter: Bool = false
        var hasRings: Bool = false
        var hasTiltRing: Bool = false
        var isMars: Bool = false
        var isNeptune: Bool = false
        var isVenus: Bool = false
    }

    private let planets: [PlanetDef] = [
        PlanetDef(name: "Mercury", rOrbit: 30, rBody: 5.2, color: Color(red: 168/255.0, green: 178/255.0, blue: 195/255.0), haloColor: Color(red: 148/255.0, green: 163/255.0, blue: 184/255.0), speed: 4.15, initialAngle: 0.2),
        PlanetDef(name: "Venus",   rOrbit: 44, rBody: 7.0, color: Color(red: 252/255.0, green: 211/255.0, blue: 77/255.0),  haloColor: Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),  speed: -1.62, initialAngle: 1.5, isVenus: true),
        PlanetDef(name: "Earth",   rOrbit: 58, rBody: 8.0, color: Color(red: 56/255.0,  green: 189/255.0, blue: 248/255.0), haloColor: Color(red: 56/255.0,  green: 189/255.0, blue: 248/255.0), speed: 1.00, initialAngle: 3.2, hasMoon: true),
        PlanetDef(name: "Mars",    rOrbit: 72, rBody: 6.4, color: Color(red: 234/255.0, green: 88/255.0,  blue: 12/255.0),  haloColor: Color(red: 234/255.0, green: 88/255.0,  blue: 12/255.0),  speed: 0.53, initialAngle: 4.8, isMars: true),
        PlanetDef(name: "Jupiter", rOrbit: 92, rBody: 13.0, color: Color(red: 253/255.0, green: 224/255.0, blue: 71/255.0), haloColor: Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0), speed: 0.25, initialAngle: 0.8, isJupiter: true),
        PlanetDef(name: "Saturn",  rOrbit: 112, rBody: 10.5, color: Color(red: 234/255.0, green: 179/255.0, blue: 8/255.0), haloColor: Color(red: 234/255.0, green: 179/255.0, blue: 8/255.0),  speed: 0.18, initialAngle: 2.3, hasRings: true),
        PlanetDef(name: "Uranus",  rOrbit: 128, rBody: 8.8, color: Color(red: 103/255.0, green: 232/255.0, blue: 249/255.0), haloColor: Color(red: 103/255.0, green: 232/255.0, blue: 249/255.0), speed: 0.12, initialAngle: 5.1, hasTiltRing: true),
        PlanetDef(name: "Neptune", rOrbit: 144, rBody: 8.5, color: Color(red: 37/255.0,  green: 99/255.0,  blue: 235/255.0), haloColor: Color(red: 37/255.0,  green: 99/255.0,  blue: 235/255.0), speed: 0.08, initialAngle: 3.9, isNeptune: true)
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2.0
            let cy = h / 2.0
            let scale = w / 400.0 // Base reference coordinate system is 400x400

            // 1. Tính toán tỉ lệ nhấn giữ (Hold Progress: 0.0 -> 1.0)
            var holdProgress: Double = 0.0
            if isAwakened, let start = pressStartTime {
                let pressElapsed = max(0.0, time - start)
                holdProgress = min(1.0, pressElapsed / 2.0)
            } else if !isAwakened, let release = releaseStartTime {
                let releaseElapsed = max(0.0, time - release)
                if releaseElapsed < 0.6 {
                    holdProgress = max(0.0, 1.0 - (releaseElapsed / 0.6))
                }
            }

            let baseSunR = 18.0 * scale
            let maxSunR = 52.3 * scale
            let currentSunR = baseSunR + (maxSunR - baseSunR) * CGFloat(pow(holdProgress, 1.25))

            // 2. Bầu trời đêm sâu thẳm & tinh vân vàng ấm sau chữ O
            drawCosmicStarfield(context: &context, w: w, h: h, cx: cx, cy: cy, scale: scale, time: time)
            drawWarmSolarNebula(context: &context, cx: cx, cy: cy, scale: scale, time: time, progress: holdProgress)

            // 3. LAYER LỐC XOÁY PHÍA SAU (Background Well - Mờ ảo)
            if holdProgress > 0.02 {
                drawBackVortexWell(context: &context, cx: cx, cy: cy, scale: scale, time: time, currentSunR: currentSunR, progress: holdProgress)
            }

            // 4. VẼ CÁC QUỸ ĐẠO VÀNG DƯỚI THẤU KÍNH MẢNH 4 & 5
            // (Theo đúng thiết kế: Quỹ đạo chỉ lộ ra khi nhìn xuyên qua kính mảnh 4 và 5)
            drawClippedOrbitsUnderGlass(context: &context, cx: cx, cy: cy, scale: scale)

            // 5. VẼ 6 MẢNH CHỮ O (Men Lam & Thấu Kính Trong Suốt)
            // Kèm hiệu ứng tách tâm ra ngoài ~8px và rung lắc tần số cao khi nhấn giữ
            drawPiecesLayer(
                context: &context,
                cx: cx,
                cy: cy,
                scale: scale,
                time: time,
                progress: holdProgress
            )

            // 6. LAYER LỐC XOÁY PHÍA TRƯỚC (Concentric Rings & Sparkling White Stars)
            // Tinh chỉnh "càng ngày càng mờ mờ lại" - không che khuất chữ O
            if holdProgress > 0.02 {
                drawFrontConcentricVortex(context: &context, cx: cx, cy: cy, scale: scale, time: time, currentSunR: currentSunR, progress: holdProgress)
            }

            // 7. VẼ 8 HÀNH TINH (Bị hút xoắn ốc và nuốt chửng vào lòng Mặt Trời khi nhấn giữ)
            drawPlanetsLayer(
                context: &context,
                cx: cx,
                cy: cy,
                scale: scale,
                time: time,
                currentSunR: currentSunR,
                progress: holdProgress
            )

            // 8. MẶT TRỜI TRUNG TÂM (Rực rỡ, phình to cực đại, hào quang Corona & Tai lửa)
            drawCenterSunUnit(
                context: &context,
                cx: cx,
                cy: cy,
                scale: scale,
                time: time,
                currentSunR: currentSunR,
                progress: holdProgress
            )
        }
    }

    // MARK: - 1. Deep Cosmic Starfield
    private func drawCosmicStarfield(context: inout GraphicsContext, w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .color(Color(red: 2/255.0, green: 6/255.0, blue: 23/255.0))
        )

        let starCount = 38
        for i in 0..<starCount {
            let pseudoRandom1 = sin(Double(i) * 17.182 + 91.24) * 38241.523
            let pseudoRandom2 = cos(Double(i) * 43.123 + 27.81) * 19284.192
            let sx = CGFloat(pseudoRandom1 - floor(pseudoRandom1)) * w
            let sy = CGFloat(pseudoRandom2 - floor(pseudoRandom2)) * h
            let baseR = CGFloat(0.7 + (pseudoRandom1 - floor(pseudoRandom1)) * 1.3) * scale

            let twinkleSpeed = 1.0 + (pseudoRandom2 - floor(pseudoRandom2)) * 1.8
            let alpha = 0.35 + 0.65 * sin(time * twinkleSpeed + Double(i))

            let starRect = CGRect(x: sx - baseR, y: sy - baseR, width: baseR * 2, height: baseR * 2)
            context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(max(0.12, alpha))))
        }
    }

    // MARK: - 2. Warm Solar Nebula
    private func drawWarmSolarNebula(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double, progress: Double) {
        let pulse = 1.0 + 0.04 * sin(time * 2.2)
        let nebulaR = (165.0 + CGFloat(progress) * 15.0) * scale * pulse
        let rect = CGRect(x: cx - nebulaR, y: cy - nebulaR, width: nebulaR * 2, height: nebulaR * 2)

        let grad = Gradient(colors: [
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0).opacity(0.24 + progress * 0.12),
            Color(red: 234/255.0, green: 88/255.0,  blue: 12/255.0).opacity(0.10 + progress * 0.08),
            Color(red: 67/255.0,  green: 20/255.0,  blue: 7/255.0).opacity(0.04),
            Color.clear
        ])
        context.fill(Path(ellipseIn: rect), with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 15 * scale, endRadius: nebulaR))
    }

    // MARK: - 3. Layer Lốc Xoáy Phía Sau (Background Dark Well)
    private func drawBackVortexWell(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double, currentSunR: CGFloat, progress: Double) {
        // Càng về sau càng mờ mờ lại (misty curve)
        let mistyAlpha = progress <= 0.35
            ? (progress / 0.35) * 0.38
            : 0.38 - (progress - 0.35) * 0.20

        let wellR = 165.0 * scale
        let wellRect = CGRect(x: cx - wellR, y: cy - wellR, width: wellR * 2, height: wellR * 2)
        let wellGrad = Gradient(colors: [
            Color(red: 2/255.0, green: 6/255.0, blue: 23/255.0).opacity(0.55 * mistyAlpha),
            Color(red: 15/255.0, green: 23/255.0, blue: 42/255.0).opacity(0.35 * mistyAlpha),
            Color.clear
        ])
        context.fill(Path(ellipseIn: wellRect), with: .radialGradient(wellGrad, center: CGPoint(x: cx, y: cy), startRadius: currentSunR * 0.85, endRadius: wellR))
    }

    // MARK: - 4. Clipped Orbits strictly under Glass Pieces 4 & 5
    private func drawClippedOrbitsUnderGlass(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat) {
        let piece4Path = roundedPiecePath(cx: cx, cy: cy, outerR: 144 * scale, innerR: 74 * scale, cornerR: 13.5 * scale, startDeg: 313.0, endDeg: 350.0)
        let piece5Path = roundedPiecePath(cx: cx, cy: cy, outerR: 144 * scale, innerR: 74 * scale, cornerR: 13.5 * scale, startDeg: 5.0,   endDeg: 48.0)

        var combinedGlassPath = Path()
        combinedGlassPath.addPath(piece4Path)
        combinedGlassPath.addPath(piece5Path)

        context.drawLayer { glassCtx in
            glassCtx.clip(to: combinedGlassPath)

            // Vẽ các đường quỹ đạo vàng nét đứt chỉ hiển thị trong mặt kính
            let orbitRadii: [CGFloat] = [92, 112, 128, 144]
            for r in orbitRadii {
                let path = Path(ellipseIn: CGRect(x: cx - r * scale, y: cy - r * scale, width: r * 2 * scale, height: r * 2 * scale))
                glassCtx.stroke(
                    path,
                    with: .color(Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0).opacity(0.85)),
                    style: StrokeStyle(lineWidth: 1.3 * scale, dash: [4 * scale, 4 * scale])
                )
            }
        }
    }

    // MARK: - 5. Draw 6 Pieces of Letter O (Men Lam & Thấu Kính)
    private struct ShardCenterVector {
        let dx: CGFloat
        let dy: CGFloat
    }

    private let shardVectors: [ShardCenterVector] = [
        ShardCenterVector(dx: -80, dy: 0),   // 1. Thân trái (outward left)
        ShardCenterVector(dx: 5,   dy: -90), // 2. Đỉnh trên (outward top)
        ShardCenterVector(dx: 65,  dy: -70), // 3. Chéo trên phải (outward top-right)
        ShardCenterVector(dx: 95,  dy: -30), // 4. Mạn phải trên (outward right)
        ShardCenterVector(dx: 85,  dy: 65),  // 5. Mạn phải dưới (outward bottom-right)
        ShardCenterVector(dx: -10, dy: 95)   // 6. Đáy dưới (outward bottom)
    ]

    private func drawPiecesLayer(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        progress: Double
    ) {
        let outerR = 144.0 * scale
        let innerR = 74.0 * scale
        let cornerR = 13.5 * scale

        let piecesDeg: [(Double, Double)] = [
            (146.0, 260.0), // Piece 1: Men Lam Đặc (Thân trái lớn nhất)
            (268.0, 280.0), // Piece 2: Men Lam Đặc (Đỉnh trên)
            (288.0, 305.0), // Piece 3: Men Lam Đặc (Chéo trên phải)
            (313.0, 350.0), // Piece 4: THẤU KÍNH PHA LÊ TRONG SUỐT (Mạn phải trên)
            (5.0, 48.0),    // Piece 5: THẤU KÍNH PHA LÊ TRONG SUỐT (Mạn phải dưới)
            (58.0, 133.0)   // Piece 6: Men Lam Đặc (Đáy dưới)
        ]

        // Royal Celestial Brass Rim Gradient (Đồng Thau Hoàng Gia 18K)
        let brassGrad = Gradient(colors: [
            Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0), // #fffbeb
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0), // #fef08a
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),  // #f59e0b
            Color(red: 180/255.0, green: 83/255.0,  blue: 9/255.0),   // #b45309
            Color(red: 69/255.0,  green: 26/255.0,  blue: 3/255.0)    // #451a03
        ])

        // Midnight Blue Enamel Gradient (Men Lam Sâu Thẳm)
        let enamelGrad = Gradient(colors: [
            Color(red: 30/255.0, green: 58/255.0,  blue: 138/255.0), // #1e3a8a
            Color(red: 23/255.0, green: 37/255.0,  blue: 84/255.0),  // #172554
            Color(red: 12/255.0, green: 26/255.0,  blue: 48/255.0),  // #0c1a30
            Color(red: 3/255.0,  green: 7/255.0,   blue: 18/255.0)   // #030712
        ])

        // Transparent Crystal Glass Gradient for Pieces 4 & 5
        let glassGrad = Gradient(colors: [
            Color(red: 56/255.0,  green: 189/255.0, blue: 248/255.0).opacity(0.25),
            Color(red: 30/255.0,  green: 58/255.0,  blue: 138/255.0).opacity(0.12),
            Color(red: 2/255.0,   green: 6/255.0,   blue: 23/255.0).opacity(0.20)
        ])

        for (idx, pDeg) in piecesDeg.enumerated() {
            let vec = shardVectors[idx]
            let dist = sqrt(vec.dx * vec.dx + vec.dy * vec.dy)

            // TÁCH TÂM RA 1 XÍU XIU (~8px) KHI NHẤN GIỮ
            let pushAmount = CGFloat(progress) * 8.0 * scale
            let pushX = (vec.dx / dist) * pushAmount
            let pushY = (vec.dy / dist) * pushAmount

            // RUNG LẮC KHÁNG CỰ TẦN SỐ CAO
            var shakeX: CGFloat = 0
            var shakeY: CGFloat = 0
            var shakeRot: Double = 0
            if progress > 0.05 {
                let t = time * 45.0 + Double(idx) * 1.8
                let shakeAmp = CGFloat(progress) * 2.5 * scale
                shakeX = CGFloat(sin(t * 1.5)) * shakeAmp
                shakeY = CGFloat(cos(t * 1.7)) * shakeAmp
                shakeRot = sin(t * 1.3) * (progress * 1.8)
            }

            let totalTx = pushX + shakeX
            let totalTy = pushY + shakeY

            context.drawLayer { ctx in
                ctx.translateBy(x: totalTx, y: totalTy)
                if abs(shakeRot) > 0.01 {
                    ctx.rotate(by: Angle(degrees: shakeRot))
                }

                let piecePath = roundedPiecePath(cx: cx, cy: cy, outerR: outerR, innerR: innerR, cornerR: cornerR, startDeg: pDeg.0, endDeg: pDeg.1)

                let isGlassPiece = (idx == 3 || idx == 4) // Pieces 4 & 5

                // 1. Bóng đổ 3D
                ctx.drawLayer { sCtx in
                    sCtx.translateBy(x: 0, y: 3.5 * scale)
                    sCtx.fill(piecePath, with: .color(Color.black.opacity(isGlassPiece ? 0.25 : 0.45)))
                }

                // 2. Thân mảnh (Men Lam hoặc Kính Trong Suốt)
                if isGlassPiece {
                    ctx.fill(
                        piecePath,
                        with: .linearGradient(glassGrad, startPoint: CGPoint(x: cx, y: cy - outerR), endPoint: CGPoint(x: cx + outerR, y: cy + outerR))
                    )
                } else {
                    ctx.fill(
                        piecePath,
                        with: .radialGradient(enamelGrad, center: CGPoint(x: cx + vec.dx * scale * 0.35, y: cy + vec.dy * scale * 0.35), startRadius: 10 * scale, endRadius: outerR)
                    )
                }

                // 3. Viền đồng thau cổ hoàng gia 18K
                ctx.stroke(
                    piecePath,
                    with: .linearGradient(brassGrad, startPoint: CGPoint(x: cx - outerR, y: cy - outerR), endPoint: CGPoint(x: cx + outerR, y: cy + outerR)),
                    lineWidth: 2.2 * scale
                )

                // 4. Vệt phản chiếu ánh gương bóng loáng (Glass sheen & Metallic shine)
                if isGlassPiece {
                    let midRad = ((pDeg.0 + pDeg.1) / 2.0) * .pi / 180.0
                    let glossR = outerR - 4.5 * scale
                    let gx = cx + glossR * CGFloat(cos(midRad))
                    let gy = cy + glossR * CGFloat(sin(midRad))
                    var glossP = Path()
                    glossP.move(to: CGPoint(x: gx - 6 * scale, y: gy - 6 * scale))
                    glossP.addLine(to: CGPoint(x: gx + 6 * scale, y: gy + 6 * scale))
                    ctx.stroke(glossP, with: .color(Color.white.opacity(0.65)), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
                }
            }
        }
    }

    // MARK: - 6. Layer Lốc Xoáy Phía Trước (Concentric Rings & Sparkling White Stars)
    // Tinh chỉnh "Càng ngày càng mờ mờ lại" - không che khuất chữ O
    private func drawFrontConcentricVortex(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        currentSunR: CGFloat,
        progress: Double
    ) {
        // Đường cong mờ ảo huyền bí: khởi phát nhẹ, sau đó mờ dần về cuối để không che chữ O
        let frontMistyAlpha = progress <= 0.35
            ? (progress / 0.35) * 0.24
            : 0.24 - (progress - 0.35) * 0.14

        let concentricRadii: [CGFloat] = [34, 46, 58, 72, 86, 100, 114, 128, 142, 152, 164]

        // 1. Sóng co đồng tâm hút về tâm Mặt Trời (Gravity Waves)
        let numWaves = 4
        let waveTime = time * 0.85
        for w in 0..<numWaves {
            let waveProgress = (waveTime + Double(w) / Double(numWaves)).truncatingRemainder(dividingBy: 1.0)
            let waveR = (158.0 * (1.0 - waveProgress) + Double(currentSunR / scale) * waveProgress) * scale
            if waveR > currentSunR + 1 * scale {
                let waveAlpha = sin(waveProgress * .pi) * 0.18 * frontMistyAlpha
                let wavePath = Path(ellipseIn: CGRect(x: cx - waveR, y: cy - waveR, width: waveR * 2, height: waveR * 2))
                context.stroke(
                    wavePath,
                    with: .color(Color.white.opacity(waveAlpha)),
                    style: StrokeStyle(lineWidth: 0.8 * scale, dash: [4 * scale, 6 * scale])
                )
            }
        }

        // 2. Các vòng tròn đồng tâm xoay vi sai Kepler (Translucent dashed arcs)
        for (k, r) in concentricRadii.enumerated() {
            let scaledR = r * scale
            if scaledR < currentSunR * 0.85 { continue }

            let speed = (0.02 + progress * 0.05) * sqrt(140.0 / Double(r))
            let rotAng = time * speed * 35.0 + Double(k) * 0.8

            // Vòng tròn định vị đồng tâm mảnh mai
            let guidePath = Path(ellipseIn: CGRect(x: cx - scaledR, y: cy - scaledR, width: scaledR * 2, height: scaledR * 2))
            context.stroke(
                guidePath,
                with: .color(Color.white.opacity(0.08 * frontMistyAlpha)),
                lineWidth: 0.6 * scale
            )

            // Vệt xoáy đen mờ nhẹ xoay tròn (Translucent dark arc)
            let arcPath = Path(ellipseIn: CGRect(x: cx - scaledR, y: cy - scaledR, width: scaledR * 2, height: scaledR * 2))
            context.stroke(
                arcPath,
                with: .color(Color(red: 3/255.0, green: 7/255.0, blue: 18/255.0).opacity(0.28 * frontMistyAlpha)),
                style: StrokeStyle(lineWidth: 1.3 * scale, dash: [CGFloat(30 + (k % 4) * 12) * scale, CGFloat(26 + (k % 2) * 8) * scale], dashPhase: CGFloat(rotAng) * scale)
            )

            // Điểm sáng Starlight điểm xuyết dọc theo vành đứt
            context.stroke(
                arcPath,
                with: .color(Color.white.opacity(0.45 * frontMistyAlpha)),
                style: StrokeStyle(lineWidth: 0.9 * scale, dash: [6 * scale, CGFloat(52 + (k % 3) * 16) * scale], dashPhase: CGFloat(rotAng + 16) * scale)
            )
        }

        // 3. 40 Điểm Sao Kim Cương 4 Cánh & Bụi Sao Stardust Xoáy vào Tâm
        let starCount = 42
        let starsAlpha = min(0.9, 0.35 + progress * 0.55)
        for i in 0..<starCount {
            let pseudoRandom1 = sin(Double(i) * 21.84 + 11.23) * 29141.2
            let pseudoRandom2 = cos(Double(i) * 33.12 + 62.74) * 41923.4
            let initialDist = 26.0 + (pseudoRandom1 - floor(pseudoRandom1)) * 135.0
            let spinSpeed = 0.8 + (pseudoRandom2 - floor(pseudoRandom2)) * 1.5

            // Quỹ đạo xoắn ốc co vào tâm Mặt Trời
            let spiralSpeed = (1.0 + progress * 6.5) * spinSpeed
            let currentAngle = (time * spiralSpeed + Double(i) * 0.6).truncatingRemainder(dividingBy: .pi * 2)

            let suctionDist = initialDist - (time * (10.0 + progress * 35.0) + Double(i) * 12.0).truncatingRemainder(dividingBy: 140.0)
            let finalDist = max(Double(currentSunR / scale), suctionDist) * Double(scale)

            if finalDist <= Double(currentSunR) * 0.95 { continue }

            let px = cx + CGFloat(cos(currentAngle) * finalDist)
            let py = cy + CGFloat(sin(currentAngle) * finalDist)

            let isDiamond = (i % 3 == 0)
            if isDiamond && progress > 0.2 {
                // Ngôi sao 4 cánh lấp lánh (Diamond Star)
                let s = CGFloat(1.5 + (pseudoRandom1 - floor(pseudoRandom1)) * 1.4) * scale
                var diamondPath = Path()
                diamondPath.move(to: CGPoint(x: px, y: py - s * 1.8))
                diamondPath.addLine(to: CGPoint(x: px + s * 0.5, y: py))
                diamondPath.addLine(to: CGPoint(x: px, y: py + s * 1.8))
                diamondPath.addLine(to: CGPoint(x: px - s * 0.5, y: py))
                diamondPath.closeSubpath()

                context.fill(diamondPath, with: .color(Color.white.opacity(starsAlpha)))
            } else {
                // Hạt bụi sao tròn
                let r = CGFloat(0.9 + (pseudoRandom2 - floor(pseudoRandom2)) * 1.1) * scale
                context.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(starsAlpha)))
            }
        }
    }

    // MARK: - 7. Draw 8 Planets (Swallowed by Sun on Hold)
    private func drawPlanetsLayer(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        currentSunR: CGFloat,
        progress: Double
    ) {
        let isSwirling = progress > 0.01
        // Legibility enhancement for compact avatar sizes (e.g. 70pt avatar in ProfileView):
        let planetScale = scale * (scale < 0.25 ? 1.25 : 1.0)

        for (idx, p) in planets.enumerated() {
            var currentAngularSpeed = p.speed * 0.8
            if isSwirling {
                currentAngularSpeed *= (1.0 + progress * 7.5)
            }

            let angle = p.initialAngle + time * currentAngularSpeed

            // Khoảng cách quỹ đạo: Khi nhấn giữ, các hành tinh bị hút sâu vào tâm
            var currentDist = p.rOrbit * scale
            if isSwirling {
                let targetDist = CGFloat(6.0 + Double(idx) * 3.0) * scale
                currentDist = p.rOrbit * scale * CGFloat(1.0 - progress) + targetDist * CGFloat(progress)
            }

            // CƠ CHẾ NUỐT CHỬNG:
            // Khi hành tinh chìm vào bên trong bán kính Mặt Trời, độ mờ đục giảm nhanh về 0!
            var opacity: Double = 1.0
            if isSwirling && currentDist <= currentSunR * 0.95 {
                opacity = max(0.0, Double((currentDist - currentSunR * 0.45) / (currentSunR * 0.5)))
            }

            // Đã bị nuốt chửng hoàn toàn -> Không vẽ nữa!
            if opacity <= 0.01 { continue }

            let px = cx + CGFloat(cos(angle)) * currentDist
            let py = cy + CGFloat(sin(angle)) * currentDist

            context.drawLayer { pCtx in
                pCtx.opacity = opacity

                let r = p.rBody * planetScale

                // 1. Quầng hào quang khí quyển (Atmospheric Glow Halo)
                let haloR = r * 1.55
                let haloRect = CGRect(x: px - haloR, y: py - haloR, width: haloR * 2, height: haloR * 2)
                pCtx.fill(Path(ellipseIn: haloRect), with: .color(p.haloColor.opacity(0.35)))

                if p.isJupiter {
                    // SAO MỘC (Khí khổng lồ, sọc bão & Đốm Đỏ Lớn)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 154/255.0, green: 52/255.0, blue: 18/255.0)), lineWidth: 1.0 * scale)

                    // 3 Sọc bão nâu đỏ ngang thân Sao Mộc
                    let bandCol = Color(red: 154/255.0, green: 52/255.0, blue: 18/255.0).opacity(0.85)
                    pCtx.fill(Path(CGRect(x: px - r * 0.92, y: py - r * 0.45, width: r * 1.84, height: r * 0.22)), with: .color(bandCol))
                    pCtx.fill(Path(CGRect(x: px - r * 0.98, y: py - r * 0.12, width: r * 1.96, height: r * 0.24)), with: .color(bandCol))
                    pCtx.fill(Path(CGRect(x: px - r * 0.88, y: py + r * 0.28, width: r * 1.76, height: r * 0.20)), with: .color(bandCol))

                    // Đốm Đỏ Lớn (Great Red Spot) với viền xoáy trắng
                    let spotX = px + r * 0.35
                    let spotY = py + r * 0.18
                    let spotRx = r * 0.38
                    let spotRy = r * 0.25
                    pCtx.fill(Path(ellipseIn: CGRect(x: spotX - spotRx, y: spotY - spotRy, width: spotRx * 2, height: spotRy * 2)), with: .color(Color.white.opacity(0.9)))
                    pCtx.fill(Path(ellipseIn: CGRect(x: spotX - spotRx * 0.75, y: spotY - spotRy * 0.75, width: spotRx * 1.5, height: spotRy * 1.5)), with: .color(Color(red: 185/255.0, green: 28/255.0, blue: 28/255.0)))

                } else if p.hasRings {
                    // SAO THỔ (Hệ thống vành đai băng kép nghiêng 26 độ)
                    let rw = r * 2.5
                    let rh = r * 0.9
                    let ringRect = CGRect(x: px - rw, y: py - rh, width: rw * 2, height: rh * 2)

                    pCtx.drawLayer { rCtx in
                        rCtx.translateBy(x: px, y: py)
                        rCtx.rotate(by: Angle(degrees: -26.0))
                        rCtx.translateBy(x: -px, y: -py)

                        // Vành ngoài (Vàng sáng)
                        rCtx.stroke(Path(ellipseIn: ringRect), with: .color(Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0).opacity(0.95)), lineWidth: 2.2 * scale)

                        // Vành trong (Hổ phách)
                        let innerRw = r * 1.9
                        let innerRh = r * 0.65
                        let innerRingRect = CGRect(x: px - innerRw, y: py - innerRh, width: innerRw * 2, height: innerRh * 2)
                        rCtx.stroke(Path(ellipseIn: innerRingRect), with: .color(Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0).opacity(0.8)), lineWidth: 1.5 * scale)
                    }

                    // Thân hành tinh Sao Thổ
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 161/255.0, green: 98/255.0, blue: 7/255.0)), lineWidth: 1.0 * scale)

                } else if p.hasMoon {
                    // TRÁI ĐẤT (Đại dương xanh ngọc, lục địa xanh lá & Mặt Trăng)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color.white), lineWidth: 0.9 * scale)

                    // Mảng lục địa xanh lá sống động
                    let landRect1 = CGRect(x: px - r * 0.45, y: py - r * 0.45, width: r * 0.85, height: r * 0.75)
                    pCtx.fill(Path(ellipseIn: landRect1), with: .color(Color(red: 34/255.0, green: 197/255.0, blue: 94/255.0)))
                    let landRect2 = CGRect(x: px + r * 0.1, y: py + r * 0.1, width: r * 0.55, height: r * 0.45)
                    pCtx.fill(Path(ellipseIn: landRect2), with: .color(Color(red: 34/255.0, green: 197/255.0, blue: 94/255.0).opacity(0.85)))

                    // Dải mây trắng khí quyển
                    pCtx.stroke(
                        Path { p in
                            p.addArc(center: CGPoint(x: px, y: py), radius: r * 0.65, startAngle: Angle(degrees: 200), endAngle: Angle(degrees: 330), clockwise: false)
                        },
                        with: .color(Color.white.opacity(0.75)),
                        style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round)
                    )

                    // Mặt Trăng quay quanh Trái Đất
                    let moonAngle = time * 3.5
                    let moonDist = 12.0 * planetScale
                    let mx = px + CGFloat(cos(moonAngle)) * moonDist
                    let my = py + CGFloat(sin(moonAngle)) * moonDist
                    let moonR = 2.4 * planetScale
                    let moonRect = CGRect(x: mx - moonR, y: my - moonR, width: moonR * 2, height: moonR * 2)
                    pCtx.fill(Path(ellipseIn: moonRect), with: .color(Color(red: 226/255.0, green: 232/255.0, blue: 240/255.0)))
                    pCtx.stroke(Path(ellipseIn: moonRect), with: .color(Color.white.opacity(0.8)), lineWidth: 0.6 * scale)

                } else if p.isMars {
                    // SAO HỎA (Hành tinh đỏ, thung lũng & Chỏm băng cực Bắc trắng muốt)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 154/255.0, green: 52/255.0, blue: 18/255.0)), lineWidth: 0.9 * scale)

                    // Chỏm băng Bắc Cực
                    let iceCapRect = CGRect(x: px - r * 0.4, y: py - r * 0.92, width: r * 0.8, height: r * 0.45)
                    pCtx.fill(Path(ellipseIn: iceCapRect), with: .color(Color(red: 248/255.0, green: 250/255.0, blue: 252/255.0)))

                } else if p.hasTiltRing {
                    // SAO THIÊN VƯƠNG (Quay nghiêng ngang, vành đai đứng)
                    let rw = r * 0.8
                    let rh = r * 2.5
                    let ringRect = CGRect(x: px - rw, y: py - rh, width: rw * 2, height: rh * 2)
                    pCtx.stroke(Path(ellipseIn: ringRect), with: .color(Color(red: 165/255.0, green: 243/255.0, blue: 252/255.0).opacity(0.85)), lineWidth: 1.2 * scale)

                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 8/255.0, green: 145/255.0, blue: 178/255.0)), lineWidth: 0.9 * scale)

                } else if p.isNeptune {
                    // SAO HẢI VƯƠNG (Xanh thẳm đại dương băng, dải bão methane)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 147/255.0, green: 197/255.0, blue: 253/255.0)), lineWidth: 0.9 * scale)

                    // Dải bão trắng
                    pCtx.stroke(
                        Path { p in
                            p.addArc(center: CGPoint(x: px, y: py), radius: r * 0.65, startAngle: Angle(degrees: 190), endAngle: Angle(degrees: 350), clockwise: false)
                        },
                        with: .color(Color(red: 255/255.0, green: 255/255.0, blue: 255/255.0).opacity(0.7)),
                        style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round)
                    )

                } else if p.isVenus {
                    // SAO KIM (Bầu khí quyển mây vàng kim loại dày đặc)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0)), lineWidth: 0.9 * scale)

                    // Dải mây trắng ngà
                    pCtx.stroke(
                        Path { p in
                            p.addArc(center: CGPoint(x: px, y: py), radius: r * 0.6, startAngle: Angle(degrees: 30), endAngle: Angle(degrees: 160), clockwise: false)
                        },
                        with: .color(Color.white.opacity(0.65)),
                        style: StrokeStyle(lineWidth: 1.0 * scale, lineCap: .round)
                    )

                } else {
                    // SAO THỦY (Xám bạc, điểm phản quang sáng)
                    let bodyRect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    pCtx.fill(Path(ellipseIn: bodyRect), with: .color(p.color))
                    pCtx.stroke(Path(ellipseIn: bodyRect), with: .color(Color.white.opacity(0.9)), lineWidth: 0.8 * scale)

                    // Điểm phản quang
                    let specR = r * 0.35
                    let specRect = CGRect(x: px - r * 0.45, y: py - r * 0.45, width: specR * 2, height: specR * 2)
                    pCtx.fill(Path(ellipseIn: specRect), with: .color(Color.white.opacity(0.85)))
                }
            }
        }
    }

    // MARK: - 8. Draw Center Sun Unit
    private func drawCenterSunUnit(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        currentSunR: CGFloat,
        progress: Double
    ) {
        // Quầng hào quang rực lửa (Corona)
        let pulseCorona = 1.0 + 0.08 * sin(time * 3.5)
        let coronaR = (currentSunR + 10 * scale) * pulseCorona
        let coronaRect = CGRect(x: cx - coronaR, y: cy - coronaR, width: coronaR * 2, height: coronaR * 2)

        let coronaGrad = Gradient(colors: [
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0).opacity(0.55 + progress * 0.4),
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0).opacity(0.35 + progress * 0.3),
            Color(red: 234/255.0, green: 88/255.0,  blue: 12/255.0).opacity(0.15),
            Color.clear
        ])
        context.fill(Path(ellipseIn: coronaRect), with: .radialGradient(coronaGrad, center: CGPoint(x: cx, y: cy), startRadius: currentSunR * 0.6, endRadius: coronaR))

        // Lõi Mặt Trời (Sun Core Body)
        let coreRect = CGRect(x: cx - currentSunR, y: cy - currentSunR, width: currentSunR * 2, height: currentSunR * 2)
        let sunGradNormal = Gradient(colors: [
            Color.white,
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0),
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),
            Color(red: 234/255.0, green: 88/255.0,  blue: 12/255.0),
            Color(red: 220/255.0, green: 38/255.0,  blue: 38/255.0)
        ])

        let sunGradSuperheated = Gradient(colors: [
            Color.white,
            Color(red: 254/255.0, green: 249/255.0, blue: 195/255.0),
            Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0),
            Color(red: 249/255.0, green: 115/255.0, blue: 22/255.0),
            Color(red: 185/255.0, green: 28/255.0,  blue: 28/255.0)
        ])

        context.fill(
            Path(ellipseIn: coreRect),
            with: .radialGradient(progress > 0.4 ? sunGradSuperheated : sunGradNormal, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: currentSunR)
        )
        context.stroke(Path(ellipseIn: coreRect), with: .color(Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0)), lineWidth: 1.6 * scale)

        // Tai lửa Mặt Trời (Solar Prominences)
        let numProms = 8
        for i in 0..<numProms {
            let pAngle = (time * 0.05) + (Double(i) * .pi * 2.0 / Double(numProms))
            let pDist = currentSunR + (3.0 + CGFloat(sin(time * 2.5 + Double(i))) * 3.0) * (1.0 + CGFloat(progress) * 2.0) * scale
            let px = cx + CGFloat(cos(pAngle)) * pDist
            let py = cy + CGFloat(sin(pAngle)) * pDist
            let pR = (1.5 + CGFloat(progress) * 2.0) * scale
            context.fill(Path(ellipseIn: CGRect(x: px - pR, y: py - pR, width: pR * 2, height: pR * 2)), with: .color(Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0).opacity(0.85)))
        }
    }

    // MARK: - 9. Exact Rounded Piece Path Generator with Smooth 4-Corner Fillets
    private func roundedPiecePath(
        cx: CGFloat,
        cy: CGFloat,
        outerR: CGFloat,
        innerR: CGFloat,
        cornerR: CGFloat,
        startDeg: Double,
        endDeg: Double
    ) -> Path {
        let s = startDeg * .pi / 180.0
        let e = endDeg * .pi / 180.0
        let spanRad = abs(e - s)
        let maxAngleCorner = spanRad * 0.45
        let dOuter = min(Double(cornerR / outerR), maxAngleCorner)
        let dInner = min(Double(cornerR / innerR), maxAngleCorner)

        let effOuterCornerR = min(cornerR, outerR * CGFloat(dOuter))
        let effInnerCornerR = min(cornerR, innerR * CGFloat(dInner))

        var path = Path()

        // Corner 1: Outer Start Fillet
        let p0 = CGPoint(x: cx + (outerR - effOuterCornerR) * CGFloat(cos(s)), y: cy + (outerR - effOuterCornerR) * CGFloat(sin(s)))
        let c1 = CGPoint(x: cx + outerR * CGFloat(cos(s)), y: cy + outerR * CGFloat(sin(s)))
        let p1 = CGPoint(x: cx + outerR * CGFloat(cos(s + dOuter)), y: cy + outerR * CGFloat(sin(s + dOuter)))

        path.move(to: p0)
        path.addQuadCurve(to: p1, control: c1)

        // Outer circular arc
        let arcSteps = 18
        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (s + dOuter) + ((e - dOuter) - (s + dOuter)) * t
            path.addLine(to: CGPoint(x: cx + outerR * CGFloat(cos(a)), y: cy + outerR * CGFloat(sin(a))))
        }

        // Corner 2: Outer End Fillet
        let c2 = CGPoint(x: cx + outerR * CGFloat(cos(e)), y: cy + outerR * CGFloat(sin(e)))
        let p3 = CGPoint(x: cx + (outerR - effOuterCornerR) * CGFloat(cos(e)), y: cy + (outerR - effOuterCornerR) * CGFloat(sin(e)))
        path.addQuadCurve(to: p3, control: c2)

        // Radial edge down to inner radius
        let p4 = CGPoint(x: cx + (innerR + effInnerCornerR) * CGFloat(cos(e)), y: cy + (innerR + effInnerCornerR) * CGFloat(sin(e)))
        path.addLine(to: p4)

        // Corner 3: Inner End Fillet
        let c3 = CGPoint(x: cx + innerR * CGFloat(cos(e)), y: cy + innerR * CGFloat(sin(e)))
        let p5 = CGPoint(x: cx + innerR * CGFloat(cos(e - dInner)), y: cy + innerR * CGFloat(sin(e - dInner)))
        path.addQuadCurve(to: p5, control: c3)

        // Inner circular arc (reverse)
        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (e - dInner) + ((s + dInner) - (e - dInner)) * t
            path.addLine(to: CGPoint(x: cx + innerR * CGFloat(cos(a)), y: cy + innerR * CGFloat(sin(a))))
        }

        // Corner 4: Inner Start Fillet
        let c4 = CGPoint(x: cx + innerR * CGFloat(cos(s)), y: cy + innerR * CGFloat(sin(s)))
        let p6 = CGPoint(x: cx + (innerR + effInnerCornerR) * CGFloat(cos(s)), y: cy + (innerR + effInnerCornerR) * CGFloat(sin(s)))
        path.addQuadCurve(to: p6, control: c4)

        path.closeSubpath()
        return path
    }
}
