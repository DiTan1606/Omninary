import SwiftUI

// MARK: - Clock Display Mode
enum ChronoClockDisplayMode: Equatable {
    case liveVietnamTime
    case staticTime(hour: Int = 14, minute: Int = 6, second: Int = 27)
}

// MARK: - Living Chrono Omnicon View (C2 Supreme Tier)
/// Biểu tượng Omnicon C2 Master Chrono (Cỗ Máy Thời Gian Hoàng Kim / Imperial Gold Chrono):
/// - Trạng thái bình thường (`isAwakened == false`): Bản động trực tiếp, 3 kim giờ–phút–giây và các bánh răng
///   cơ khí chuyển động mượt mà đúng theo thời gian thực tại Việt Nam (GMT+7, 60–120 FPS ProMotion).
/// - Trạng thái thức tỉnh (`isAwakened == true`): Bánh răng và kim đồng hồ tăng tốc vũ bão (tỉ lệ t^3.8),
///   rung lắc chấn động rồi nổ tung (BÙM): loé sáng rực rỡ, sóng xung kích tỏa ra, 6 phiến văng tức thì trong 90ms
///   rồi trôi bồng bềnh lơ lửng ngoài vũ trụ; cỗ máy đồng hồ ở tâm vẫn kiên định quay nhanh ở tốc độ ánh sáng!
/// - Khi thả tay ra: Tua ngược thời gian, các mảnh vỡ đàn hồi hút về vị trí ban đầu và kim đồng hồ giảm tốc
///   trở về đúng giờ Việt Nam hiện tại.
struct LivingChronoOmniconView: View {
    var isAwakened: Bool = false
    var mode: ChronoClockDisplayMode = .liveVietnamTime
    var size: CGFloat = 70
    var cornerRadius: CGFloat = 18

    // Trạng thái vật lý nội tại phục vụ chuyển động gia tốc & nổ tung
    @State private var awakenStartTimestamp: Double? = nil
    @State private var releaseStartTimestamp: Double? = nil
    @State private var warpRatio: Double = 0.0
    @State private var isExploded: Bool = false
    @State private var accumulatedExtraAngle: Double = 0.0
    @State private var lastAnimationTimestamp: Double? = nil

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ChronoCanvasView(
                time: now,
                size: size,
                isAwakened: isAwakened,
                mode: mode,
                awakenStartTime: awakenStartTimestamp,
                releaseStartTime: releaseStartTimestamp
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onChange(of: isAwakened) { _, awakened in
            let currentNow = Date().timeIntervalSinceReferenceDate
            if awakened {
                awakenStartTimestamp = currentNow
                releaseStartTimestamp = nil
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            } else {
                releaseStartTimestamp = currentNow
                awakenStartTimestamp = nil
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
}

// MARK: - Chrono Canvas Engine (120 FPS High Performance)
private struct ChronoCanvasView: View {
    let time: Double
    let size: CGFloat
    let isAwakened: Bool
    let mode: ChronoClockDisplayMode
    let awakenStartTime: Double?
    let releaseStartTime: Double?

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2.0
            let cy = h / 2.0
            let scale = w / 400.0 // Base reference coordinate system is 400x400

            // 1. Tính toán trạng thái gia tốc (Warp) và Nổ Tung (Supernova)
            var currentWarpRatio: Double = 0.0
            var exploded = false
            var floatTime: Double = 0.0

            if isAwakened, let start = awakenStartTime {
                let pressElapsed = max(0.0, time - start)
                currentWarpRatio = min(1.0, pressElapsed / 1.25)
                if pressElapsed >= 1.25 {
                    exploded = true
                    floatTime = pressElapsed - 1.25
                }
            }

            // Xử lý tua ngược (Rewind) khi người dùng thả tay
            var rewindProgress: Double = 1.0 // 1.0 = bình thường, < 1.0 = đang hồi vị
            if !isAwakened, let releaseStart = releaseStartTime {
                let releaseElapsed = max(0.0, time - releaseStart)
                if releaseElapsed < 0.45 {
                    rewindProgress = releaseElapsed / 0.45
                }
            }

            // 2. Chấn động màn hình khi đang sạc gia tốc
            var shakeX: CGFloat = 0
            var shakeY: CGFloat = 0
            if isAwakened && currentWarpRatio > 0.35 && !exploded {
                let shakeMagnitude = 2.4 * scale * CGFloat(currentWarpRatio)
                shakeX = CGFloat(sin(time * 65.0)) * shakeMagnitude
                shakeY = CGFloat(cos(time * 58.0)) * shakeMagnitude
            }

            // 3. Bầu trời đêm đầy sao vũ trụ (Deep Cosmic Starfield)
            drawCosmicStarrySky(context: &context, w: w, h: h, cx: cx, cy: cy, scale: scale, time: time)

            // 4. Quầng hào quang Nebula ở tâm
            drawCentralNebula(context: &context, cx: cx, cy: cy, scale: scale, time: time)

            // 5. Tính toán góc quay của bộ 3 kim đồng hồ
            let (hourAngle, minAngle, secAngle, gearMainAngle, gearSubAngle) = computeClockAngles(
                nowTime: time,
                warpRatio: currentWarpRatio,
                isExploded: exploded,
                mode: mode
            )

            // 6. VẼ 6 MẢNH CHỮ O (Piece 1 LỘ MÁY • Pieces 2, 3, 4, 5, 6 KÍN VÀNG GOLD 18K)
            drawPiecesLayer(
                context: &context,
                cx: cx + shakeX,
                cy: cy + shakeY,
                scale: scale,
                time: time,
                isExploded: exploded,
                floatTime: floatTime,
                rewindProgress: rewindProgress,
                gearMainAngle: gearMainAngle,
                gearSubAngle: gearSubAngle
            )

            // 7. HIỆU ỨNG SÓNG NỔ XUNG KÍCH VÀNG TỪ TÂM (Radial Blast Shockwave)
            if exploded && floatTime < 1.2 {
                drawShockwaveBlast(context: &context, cx: cx, cy: cy, scale: scale, floatTime: floatTime)
            }

            // 8. CỖ MÁY ĐỒNG HỒ Ở TÂM (Vẫn ở giữa và quay liên tục ở tốc độ cực cao)
            drawCenterClockUnit(
                context: &context,
                cx: cx,
                cy: cy,
                scale: scale,
                time: time,
                isExploded: exploded,
                hourAngle: hourAngle,
                minAngle: minAngle,
                secAngle: secAngle,
                gearMainAngle: gearMainAngle,
                gearSubAngle: gearSubAngle
            )

            // 9. ÁNH CHỚP LOÉ SÁNG (Lingering Flash Overlay)
            if exploded && floatTime < 0.65 {
                let flashAlpha = 0.88 * (1.0 - (floatTime / 0.65))
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: w, height: h)),
                    with: .color(Color(red: 1.0, green: 0.96, blue: 0.82).opacity(flashAlpha))
                )
            }
        }
    }

    // MARK: - 1. Deep Space Starry Sky
    private func drawCosmicStarrySky(context: inout GraphicsContext, w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        // Nền đen vũ trụ sâu thẳm
        context.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .color(Color(red: 2/255.0, green: 6/255.0, blue: 23/255.0))
        )

        // Các ngôi sao lấp lánh cố định vị trí theo giả số
        let starCount = 42
        for i in 0..<starCount {
            let pseudoRandom1 = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
            let pseudoRandom2 = cos(Double(i) * 39.346 + 11.135) * 24634.6345
            let sx = CGFloat(pseudoRandom1 - floor(pseudoRandom1)) * w
            let sy = CGFloat(pseudoRandom2 - floor(pseudoRandom2)) * h
            let baseR = CGFloat(0.8 + (pseudoRandom1 - floor(pseudoRandom1)) * 1.5) * scale

            let twinkleSpeed = 1.2 + (pseudoRandom2 - floor(pseudoRandom2)) * 2.0
            let twinklePhase = time * twinkleSpeed + Double(i) * 0.8
            let alpha = 0.35 + 0.65 * sin(twinklePhase)

            let starRect = CGRect(x: sx - baseR, y: sy - baseR, width: baseR * 2, height: baseR * 2)
            context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(max(0.1, alpha))))

            // Tia phát sáng 4 hướng cho các ngôi sao sáng
            if baseR > 1.6 * scale && alpha > 0.75 {
                let spikeLen = 3.5 * scale
                var spikePath = Path()
                spikePath.move(to: CGPoint(x: sx - spikeLen, y: sy))
                spikePath.addLine(to: CGPoint(x: sx + spikeLen, y: sy))
                spikePath.move(to: CGPoint(x: sx, y: sy - spikeLen))
                spikePath.addLine(to: CGPoint(x: sx, y: sy + spikeLen))
                context.stroke(spikePath, with: .color(Color(red: 1.0, green: 0.95, blue: 0.7).opacity(alpha * 0.8)), lineWidth: 0.8 * scale)
            }
        }
    }

    // MARK: - 2. Central Cosmic Nebula
    private func drawCentralNebula(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        let pulse = 1.0 + 0.05 * sin(time * 2.0)
        let nebulaR = 150.0 * scale * pulse
        let rect = CGRect(x: cx - nebulaR, y: cy - nebulaR, width: nebulaR * 2, height: nebulaR * 2)
        let grad = Gradient(colors: [
            Color(red: 251/255.0, green: 191/255.0, blue: 36/255.0).opacity(0.22),
            Color(red: 180/255.0, green: 83/255.0, blue: 9/255.0).opacity(0.08),
            Color.clear
        ])
        context.fill(Path(ellipseIn: rect), with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 10 * scale, endRadius: nebulaR))
    }

    // MARK: - 3. Clock Angles Calculation
    private func computeClockAngles(nowTime: Double, warpRatio: Double, isExploded: Bool, mode: ChronoClockDisplayMode) -> (Double, Double, Double, Double, Double) {
        var baseHourAngle: Double = 63.225
        var baseMinAngle: Double = 38.7
        var baseSecAngle: Double = 162.0

        if mode == .liveVietnamTime {
            var calendar = Calendar(identifier: .gregorian)
            if let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh") {
                calendar.timeZone = tz
            }
            let date = Date(timeIntervalSinceReferenceDate: nowTime)
            let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let h = comps.hour ?? 14
            let m = comps.minute ?? 6
            let s = comps.second ?? 27
            let ns = comps.nanosecond ?? 0

            let totalSec = Double(s) + Double(ns) / 1_000_000_000.0
            let totalMin = Double(m) + totalSec / 60.0
            let totalHour = Double(h % 12) + totalMin / 60.0

            baseHourAngle = totalHour * 30.0
            baseMinAngle = totalMin * 6.0
            baseSecAngle = totalSec * 6.0
        }

        // Gia tốc góc khi nhấn giữ hoặc khi nổ tung
        var extraMultiplier: Double = 0.0
        if isExploded {
            extraMultiplier = 1200.0
        } else if warpRatio > 0.0 {
            extraMultiplier = pow(warpRatio, 3.8) * 1100.0
        }

        let speedBoost = extraMultiplier * nowTime * 6.0
        let hourAngle = baseHourAngle + speedBoost * (1.0 / 720.0) * 360.0
        let minAngle = baseMinAngle + speedBoost * (1.0 / 60.0) * 360.0
        let secAngle = baseSecAngle + speedBoost * 360.0

        // Góc quay của bánh răng cơ khí (kéo trực tiếp các kim)
        let gearSpeed = 1.0 + extraMultiplier * 0.8
        let gearMainAngle = nowTime * 32.0 * gearSpeed
        let gearSubAngle = -nowTime * 48.0 * gearSpeed

        return (hourAngle, minAngle, secAngle, gearMainAngle, gearSubAngle)
    }

    // MARK: - 4. Draw 6 Pieces of Letter O
    private struct BlastOffset {
        let blastDist: CGFloat // Khoảng cách văng ra từ tâm mảnh
        let rot: Double        // Góc nghiêng tự nhiên
        let scale: CGFloat     // Tỉ lệ thu gọn quanh tâm mảnh để lơ lửng gọn gàng trong khung hình
    }

    private let pieceBlasts: [BlastOffset] = [
        BlastOffset(blastDist: 28.0, rot: -10.0, scale: 0.78), // Piece 1 (Lộ máy lớn nhất)
        BlastOffset(blastDist: 34.0, rot: 12.0, scale: 0.76),  // Piece 2 (Đỉnh trên)
        BlastOffset(blastDist: 36.0, rot: 15.0, scale: 0.76),  // Piece 3 (Chéo trên phải)
        BlastOffset(blastDist: 36.0, rot: -12.0, scale: 0.76), // Piece 4 (Mạn phải trên)
        BlastOffset(blastDist: 34.0, rot: 10.0, scale: 0.76),  // Piece 5 (Mạn phải dưới)
        BlastOffset(blastDist: 30.0, rot: -12.0, scale: 0.78)  // Piece 6 (Đáy dưới)
    ]

    private func drawPiecesLayer(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        isExploded: Bool,
        floatTime: Double,
        rewindProgress: Double,
        gearMainAngle: Double,
        gearSubAngle: Double
    ) {
        let outerR = 145.0 * scale
        let innerR = 80.0 * scale
        let cornerR = 9.5 * scale
        let rMid = (outerR + innerR) / 2.0 // 112.5 * scale

        let piecesDeg: [(Double, Double)] = [
            (146.0, 260.0), // Piece 1 (Thân trái lớn nhất)
            (268.0, 280.0), // Piece 2 (Đỉnh trên)
            (288.0, 305.0), // Piece 3 (Chéo trên phải)
            (313.0, 350.0), // Piece 4 (Mạn phải trên)
            (5.0, 48.0),    // Piece 5 (Mạn phải dưới)
            (58.0, 133.0)   // Piece 6 (Đáy dưới)
        ]

        for (idx, pDeg) in piecesDeg.enumerated() {
            let blast = pieceBlasts[idx]

            // Góc tâm của từng phiến
            let midDeg = (pDeg.0 + pDeg.1) / 2.0
            let midRad = midDeg * .pi / 180.0

            // Tọa độ tâm của chính phiến đó
            let pcx = cx + rMid * CGFloat(cos(midRad))
            let pcy = cy + rMid * CGFloat(sin(midRad))

            // Vector dịch chuyển văng nổ ra ngoài theo góc hướng tâm
            let blastDx = blast.blastDist * scale * CGFloat(cos(midRad))
            let blastDy = blast.blastDist * scale * CGFloat(sin(midRad))

            var tx: CGFloat = 0
            var ty: CGFloat = 0
            var trot: Double = 0
            var tscale: CGFloat = 1.0

            if isExploded {
                if floatTime < 0.09 {
                    // Văng ra tức thì trong 90ms với lực giật cực đại (cubic ease-out)
                    let burstT = floatTime / 0.09
                    let burstEase = CGFloat(1.0 - pow(1.0 - burstT, 3.0))
                    tx = blastDx * burstEase
                    ty = blastDy * burstEase
                    trot = blast.rot * Double(burstEase)
                    tscale = 1.0 + (blast.scale - 1.0) * burstEase
                } else {
                    // Trôi bồng bềnh lơ lửng ngoài vũ trụ theo quỹ đạo sóng điều hòa zero-G
                    let driftX = CGFloat(sin(floatTime * 1.5 + Double(idx) * 1.3)) * 3.5 * scale
                    let driftY = CGFloat(cos(floatTime * 1.3 + Double(idx) * 1.6)) * 3.5 * scale
                    let driftRot = sin(floatTime * 1.0 + Double(idx) * 0.9) * 4.0

                    tx = blastDx + driftX
                    ty = blastDy + driftY
                    trot = blast.rot + driftRot
                    tscale = blast.scale
                }
            } else if rewindProgress < 1.0 {
                // Đang hồi vị về vị trí cũ bằng đường cong lò xo
                let t = rewindProgress
                let spring = CGFloat(1.0 - exp(-6.0 * t) * cos(6.0 * t))
                let prevTx = blastDx
                let prevTy = blastDy
                let prevRot = blast.rot
                let prevScale = blast.scale

                tx = prevTx * (1.0 - spring)
                ty = prevTy * (1.0 - spring)
                trot = prevRot * Double(1.0 - spring)
                tscale = prevScale + (1.0 - prevScale) * spring
            }

            context.drawLayer { ctx in
                // Chuyển hệ tọa độ đến TÂM CỦA CHÍNH MẢNH ĐÓ để xoay và thu phóng giữ trọn vẹn trong khung vuông
                ctx.translateBy(x: pcx + tx, y: pcy + ty)
                ctx.rotate(by: Angle(degrees: trot))
                ctx.scaleBy(x: tscale, y: tscale)
                ctx.translateBy(x: -pcx, y: -pcy)

                let piecePath = roundedPiecePath(cx: cx, cy: cy, outerR: outerR, innerR: innerR, cornerR: cornerR, startDeg: pDeg.0, endDeg: pDeg.1)

                // LAYER 1: Bóng đổ 3D
                ctx.drawLayer { shadowCtx in
                    shadowCtx.translateBy(x: 0, y: 5.0 * scale)
                    shadowCtx.fill(piecePath, with: .color(Color.black.opacity(0.48)))
                }

                // LAYER 2: Viền vát 3D cạnh dưới (Bevel lip màu nâu sẫm hoàng gia)
                ctx.drawLayer { lipCtx in
                    lipCtx.translateBy(x: 0, y: 2.5 * scale)
                    lipCtx.fill(piecePath, with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)))
                }

                if idx == 0 {
                    // PIECE 1: LỘ MÁY (OPENWORKED SKELETON)
                    drawOpenworkedPiece1(
                        context: &ctx,
                        path: piecePath,
                        cx: cx,
                        cy: cy,
                        scale: scale,
                        time: time,
                        gearMainAngle: gearMainAngle,
                        gearSubAngle: gearSubAngle
                    )
                } else {
                    // PIECES 2, 3, 4, 5, 6: KÍN MÀU VÀNG GOLD 18K
                    drawSolidGoldPiece(
                        context: &ctx,
                        path: piecePath,
                        cx: cx,
                        cy: cy,
                        outerR: outerR,
                        scale: scale,
                        startDeg: pDeg.0,
                        endDeg: pDeg.1
                    )
                }
            }
        }
    }

    // MARK: - 4a. Piece 1: Openworked Skeleton Mechanical Cavity
    private func drawOpenworkedPiece1(
        context: inout GraphicsContext,
        path: Path,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        gearMainAngle: Double,
        gearSubAngle: Double
    ) {
        // Nền khoang máy màu tối
        context.fill(path, with: .color(Color(red: 18/255.0, green: 18/255.0, blue: 24/255.0)))

        // Giới hạn trong khuôn phiến 1
        context.drawLayer { clipCtx in
            clipCtx.clip(to: path)

            // Cầu máy cong kim loại phay xước (Mechanical Bridge)
            var bridgePath = Path()
            bridgePath.move(to: CGPoint(x: cx + (68 - 200) * scale, y: cy + (250 - 200) * scale))
            bridgePath.addQuadCurve(to: CGPoint(x: cx + (120 - 200) * scale, y: cy + (130 - 200) * scale), control: CGPoint(x: cx + (82 - 200) * scale, y: cy + (180 - 200) * scale))
            bridgePath.addLine(to: CGPoint(x: cx + (175 - 200) * scale, y: cy + (75 - 200) * scale))
            bridgePath.addLine(to: CGPoint(x: cx + (182 - 200) * scale, y: cy + (110 - 200) * scale))
            bridgePath.addQuadCurve(to: CGPoint(x: cx + (128 - 200) * scale, y: cy + (245 - 200) * scale), control: CGPoint(x: cx + (125 - 200) * scale, y: cy + (190 - 200) * scale))
            bridgePath.closeSubpath()

            clipCtx.fill(bridgePath, with: .color(Color(red: 38/255.0, green: 36/255.0, blue: 48/255.0)))
            clipCtx.stroke(bridgePath, with: .color(Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0)), lineWidth: 2.2 * scale)

            // Ốc vít thép xanh nung (Blued Screws)
            drawBluedScrew(context: &clipCtx, x: cx + (78 - 200) * scale, y: cy + (235 - 200) * scale, scale: scale)
            drawBluedScrew(context: &clipCtx, x: cx + (162 - 200) * scale, y: cy + (98 - 200) * scale, scale: scale)

            // Bánh răng truyền động lớn (10 răng, bán kính 35) tại (110, 195)
            drawGear(
                context: &clipCtx,
                gx: cx + (110 - 200) * scale,
                gy: cy + (195 - 200) * scale,
                rOut: 35 * scale,
                rIn: 27 * scale,
                teeth: 10,
                color: Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),
                strokeColor: Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0),
                scale: scale,
                angleDeg: gearMainAngle,
                hubType: .ruby
            )

            // Bánh răng trung gian ăn khớp (7 răng, bán kính 22) tại (142, 142)
            drawGear(
                context: &clipCtx,
                gx: cx + (142 - 200) * scale,
                gy: cy + (142 - 200) * scale,
                rOut: 22 * scale,
                rIn: 16 * scale,
                teeth: 7,
                color: Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0),
                strokeColor: Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0),
                scale: scale,
                angleDeg: gearSubAngle,
                hubType: .screw
            )
        }

        // Viền vàng kép bao quanh Phiến 1
        let goldGrad = Gradient(colors: [
            Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0),
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0),
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),
            Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0)
        ])
        context.stroke(path, with: .linearGradient(goldGrad, startPoint: CGPoint(x: cx - 145 * scale, y: cy - 145 * scale), endPoint: CGPoint(x: cx + 145 * scale, y: cy + 145 * scale)), lineWidth: 3.2 * scale)
        context.stroke(path, with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 1.4 * scale)
    }

    // MARK: - 4b. Pieces 2-6: Solid Imperial Gold 18K
    private func drawSolidGoldPiece(
        context: inout GraphicsContext,
        path: Path,
        cx: CGFloat,
        cy: CGFloat,
        outerR: CGFloat,
        scale: CGFloat,
        startDeg: Double,
        endDeg: Double
    ) {
        // Gradient Vàng Gold 18K hoàng gia
        let solidGoldGrad = Gradient(colors: [
            Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0), // #fffbeb
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0), // #fef08a
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),  // #f59e0b
            Color(red: 180/255.0, green: 83/255.0, blue: 9/255.0),    // #b45309
            Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0)    // #78350f
        ])

        context.fill(
            path,
            with: .linearGradient(
                solidGoldGrad,
                startPoint: CGPoint(x: cx - outerR, y: cy - outerR),
                endPoint: CGPoint(x: cx + outerR, y: cy + outerR)
            )
        )

        // Viền cạnh nổi khối màu nâu đậm
        context.stroke(path, with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 1.8 * scale)

        // Vệt sáng ánh gương bóng cong dọc theo mép ngoài
        let midAng = (startDeg + endDeg) / 2.0 * .pi / 180.0
        let s = startDeg * .pi / 180.0
        let e = endDeg * .pi / 180.0
        let glossR = outerR - 5.0 * scale
        var glossPath = Path()
        let steps = 14
        for i in 0...steps {
            let a = (s + 0.05) + ((e - 0.05) - (s + 0.05)) * (Double(i) / Double(steps))
            let pt = CGPoint(x: cx + glossR * CGFloat(cos(a)), y: cy + glossR * CGFloat(sin(a)))
            if i == 0 { glossPath.move(to: pt) } else { glossPath.addLine(to: pt) }
        }
        context.stroke(glossPath, with: .color(Color.white.opacity(0.72)), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round))

        // Đinh tán vàng kim hoàng gia
        let pinR = outerR - 10.0 * scale
        let pinX = cx + pinR * CGFloat(cos(midAng))
        let pinY = cy + pinR * CGFloat(sin(midAng))
        let pinRect = CGRect(x: pinX - 3.4 * scale, y: pinY - 3.4 * scale, width: 6.8 * scale, height: 6.8 * scale)
        context.fill(Path(ellipseIn: pinRect), with: .color(Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0)))
        context.stroke(Path(ellipseIn: pinRect), with: .color(Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0)), lineWidth: 1.0 * scale)
    }

    // MARK: - 5. Shockwave Golden Blast
    private func drawShockwaveBlast(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, floatTime: Double) {
        let maxR = 150.0 * scale
        let blastR = min(maxR, 20.0 * scale + CGFloat(floatTime * 220.0) * scale)
        let blastAlpha = max(0.0, 0.95 - (floatTime / 1.2))

        let rect = CGRect(x: cx - blastR, y: cy - blastR, width: blastR * 2, height: blastR * 2)
        let grad = Gradient(colors: [
            Color.white.opacity(blastAlpha * 0.9),
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0).opacity(blastAlpha * 0.8),
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0).opacity(blastAlpha * 0.5),
            Color(red: 180/255.0, green: 83/255.0, blue: 9/255.0).opacity(blastAlpha * 0.2),
            Color.clear
        ])
        context.fill(Path(ellipseIn: rect), with: .radialGradient(grad, center: CGPoint(x: cx, y: cy), startRadius: 5 * scale, endRadius: blastR))
    }

    // MARK: - 6. Central Clock Unit
    private func drawCenterClockUnit(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        time: Double,
        isExploded: Bool,
        hourAngle: Double,
        minAngle: Double,
        secAngle: Double,
        gearMainAngle: Double,
        gearSubAngle: Double
    ) {
        let bezelR = 74.0 * scale * (isExploded ? 1.08 : 1.0)
        let apertureR = 50.0 * scale * (isExploded ? 1.08 : 1.0)

        // Bóng đổ vành đồng hồ
        context.fill(
            Path(ellipseIn: CGRect(x: cx - bezelR, y: cy - bezelR + 4 * scale, width: bezelR * 2, height: bezelR * 2)),
            with: .color(Color.black.opacity(0.55))
        )

        // Vành Bezel Vàng Gold 18K
        let bezelGrad = Gradient(colors: [
            Color(red: 255/255.0, green: 251/255.0, blue: 235/255.0),
            Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0),
            Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),
            Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0)
        ])
        let bezelRect = CGRect(x: cx - bezelR, y: cy - bezelR, width: bezelR * 2, height: bezelR * 2)
        context.fill(Path(ellipseIn: bezelRect), with: .linearGradient(bezelGrad, startPoint: CGPoint(x: cx - bezelR, y: cy - bezelR), endPoint: CGPoint(x: cx + bezelR, y: cy + bezelR)))
        context.stroke(Path(ellipseIn: bezelRect), with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 2.4 * scale)

        // Viền ánh gương phản chiếu bên trong vành bezel
        let innerBezelR = bezelR - 3.0 * scale
        context.stroke(Path(ellipseIn: CGRect(x: cx - innerBezelR, y: cy - innerBezelR, width: innerBezelR * 2, height: innerBezelR * 2)), with: .color(Color.white.opacity(0.65)), lineWidth: 1.2 * scale)

        // Khoang máy lộ cơ trong tâm đồng hồ
        let apertureRect = CGRect(x: cx - apertureR, y: cy - apertureR, width: apertureR * 2, height: apertureR * 2)
        context.fill(Path(ellipseIn: apertureRect), with: .color(Color(red: 18/255.0, green: 18/255.0, blue: 24/255.0)))
        context.stroke(Path(ellipseIn: apertureRect), with: .color(Color(red: 180/255.0, green: 83/255.0, blue: 9/255.0)), lineWidth: 2.0 * scale)

        // Bánh răng trung tâm kéo trực tiếp các kim
        drawGear(
            context: &context,
            gx: cx + (182 - 200) * scale,
            gy: cy + (214 - 200) * scale,
            rOut: 22 * scale,
            rIn: 16 * scale,
            teeth: 8,
            color: Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0),
            strokeColor: Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0),
            scale: scale,
            angleDeg: gearMainAngle,
            hubType: .ruby
        )

        drawGear(
            context: &context,
            gx: cx + (218 - 200) * scale,
            gy: cy + (186 - 200) * scale,
            rOut: 17 * scale,
            rIn: 12 * scale,
            teeth: 6,
            color: Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0),
            strokeColor: Color(red: 120/255.0, green: 53/255.0, blue: 15/255.0),
            scale: scale,
            angleDeg: gearSubAngle,
            hubType: .screw
        )

        // 12 Vạch số chỉ giờ tinh tế
        for i in 0..<12 {
            let a = Double(i * 30) * .pi / 180.0
            let isMajor = (i % 3 == 0)
            let r1 = (isMajor ? 58.0 : 63.0) * scale
            let r2 = 68.0 * scale
            let x1 = cx + CGFloat(sin(a)) * r1
            let y1 = cy - CGFloat(cos(a)) * r1
            let x2 = cx + CGFloat(sin(a)) * r2
            let y2 = cy - CGFloat(cos(a)) * r2

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x1, y: y1))
            tickPath.addLine(to: CGPoint(x: x2, y: y2))
            let tickColor = isMajor ? Color(red: 253/255.0, green: 230/255.0, blue: 138/255.0) : Color(red: 217/255.0, green: 119/255.0, blue: 6/255.0)
            context.stroke(tickPath, with: .color(tickColor), style: StrokeStyle(lineWidth: (isMajor ? 2.5 : 1.3) * scale, lineCap: .round))
        }

        // BỘ 3 KIM ĐỒNG HỒ
        // 1. Kim Giờ: Lưỡi kiếm Dauphine Vàng 18K
        drawDauphineHand(context: &context, cx: cx, cy: cy, scale: scale, angleDeg: hourAngle, length: 58 * scale, width: 7.0 * scale, isMinute: false)

        // 2. Kim Phút: Lưỡi kiếm Dauphine Vàng 18K thanh dài
        drawDauphineHand(context: &context, cx: cx, cy: cy, scale: scale, angleDeg: minAngle, length: 78 * scale, width: 5.5 * scale, isMinute: true)

        // 3. KIM GIÂY: MŨI TÊN ĐỎ RỰC NỔI BẬT (Bold Neon Red Arrow)
        drawBoldSecondHand(context: &context, cx: cx, cy: cy, scale: scale, angleDeg: secAngle)

        // Trục kim đồng hồ đính Ngọc Ruby đỏ rực lấp lánh
        let capR = 8.0 * scale
        let capRect = CGRect(x: cx - capR, y: cy - capR, width: capR * 2, height: capR * 2)
        context.fill(Path(ellipseIn: capRect), with: .color(Color(red: 253/255.0, green: 230/255.0, blue: 138/255.0)))
        context.stroke(Path(ellipseIn: capRect), with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 2.0 * scale)

        let rubyR = capR * 0.56
        let rubyRect = CGRect(x: cx - rubyR, y: cy - rubyR, width: rubyR * 2, height: rubyR * 2)
        context.fill(Path(ellipseIn: rubyRect), with: .color(Color(red: 239/255.0, green: 68/255.0, blue: 68/255.0)))

        let dotR = 1.6 * scale
        let dotRect = CGRect(x: cx - rubyR * 0.45, y: cy - rubyR * 0.45, width: dotR * 2, height: dotR * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(.white))
    }

    // MARK: - 7. Hand Helpers
    private func drawDauphineHand(
        context: inout GraphicsContext,
        cx: CGFloat,
        cy: CGFloat,
        scale: CGFloat,
        angleDeg: Double,
        length: CGFloat,
        width: CGFloat,
        isMinute: Bool
    ) {
        let rad = angleDeg * .pi / 180.0
        let cosA = CGFloat(cos(rad))
        let sinA = CGFloat(sin(rad))

        func rot(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: cx + px * cosA - py * sinA, y: cy + px * sinA + py * cosA)
        }

        let tail: CGFloat = isMinute ? 10.0 * scale : 8.0 * scale
        let shoulderW = width
        let tipW = width * 0.5
        let bodyLen = length * 0.8

        // Mặt trái vát sáng
        var leftPath = Path()
        leftPath.move(to: rot(0, tail))
        leftPath.addLine(to: rot(-shoulderW, 0))
        leftPath.addLine(to: rot(-tipW, -bodyLen))
        leftPath.addLine(to: rot(0, -length))
        leftPath.closeSubpath()

        // Mặt phải vát tối
        var rightPath = Path()
        rightPath.move(to: rot(0, tail))
        rightPath.addLine(to: rot(0, -length))
        rightPath.addLine(to: rot(tipW, -bodyLen))
        rightPath.addLine(to: rot(shoulderW, 0))
        rightPath.closeSubpath()

        // Bóng đổ nhẹ
        var shadowPath = Path()
        shadowPath.addPath(leftPath)
        shadowPath.addPath(rightPath)
        context.drawLayer { sCtx in
            sCtx.translateBy(x: 2.0 * scale, y: 3.0 * scale)
            sCtx.fill(shadowPath, with: .color(Color.black.opacity(0.4)))
        }

        let lightColor = isMinute ? Color(red: 255/255.0, green: 248/255.0, blue: 175/255.0) : Color(red: 255/255.0, green: 240/255.0, blue: 150/255.0)
        let darkColor = isMinute ? Color(red: 225/255.0, green: 130/255.0, blue: 10/255.0) : Color(red: 217/255.0, green: 119/255.0, blue: 6/255.0)

        context.fill(leftPath, with: .color(lightColor))
        context.stroke(leftPath, with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 1.0 * scale)

        context.fill(rightPath, with: .color(darkColor))
        context.stroke(rightPath, with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 1.0 * scale)

        // Sống lưng phản chiếu ánh sáng trắng
        var ridgePath = Path()
        ridgePath.move(to: rot(0, 0))
        ridgePath.addLine(to: rot(0, -length + 3 * scale))
        context.stroke(ridgePath, with: .color(Color.white.opacity(0.92)), lineWidth: 1.2 * scale)
    }

    private func drawBoldSecondHand(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, angleDeg: Double) {
        let rad = angleDeg * .pi / 180.0
        let cosA = CGFloat(cos(rad))
        let sinA = CGFloat(sin(rad))

        func rot(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: cx + px * cosA - py * sinA, y: cy + px * sinA + py * cosA)
        }

        let length = 82.0 * scale
        let tail = 22.0 * scale

        // Bóng đổ kim giây
        var shadowLine = Path()
        shadowLine.move(to: rot(0, tail))
        shadowLine.addLine(to: rot(0, -length + 8 * scale))
        context.drawLayer { sCtx in
            sCtx.translateBy(x: 2.0 * scale, y: 3.0 * scale)
            sCtx.stroke(shadowLine, with: .color(Color.black.opacity(0.45)), style: StrokeStyle(lineWidth: 4.5 * scale, lineCap: .round))
        }

        // Quầng sáng đỏ Ruby xung quanh thân kim
        var glowLine = Path()
        glowLine.move(to: rot(0, tail))
        glowLine.addLine(to: rot(0, -length + 8 * scale))
        context.stroke(glowLine, with: .color(Color(red: 1.0, green: 0.0, blue: 0.33).opacity(0.45)), style: StrokeStyle(lineWidth: 8.0 * scale, lineCap: .round))

        // Thân kim giây màu đỏ neon rực rỡ
        context.stroke(glowLine, with: .color(Color(red: 1.0, green: 0.0, blue: 0.33)), style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round))

        // Quả đối trọng Vầng Thái Dương ở đuôi kim
        let sunCenter = rot(0, tail - 5.0 * scale)
        let sunR = 5.5 * scale
        let sunRect = CGRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR, width: sunR * 2, height: sunR * 2)
        context.fill(Path(ellipseIn: sunRect), with: .color(Color(red: 254/255.0, green: 240/255.0, blue: 138/255.0)))
        context.stroke(Path(ellipseIn: sunRect), with: .color(Color(red: 69/255.0, green: 26/255.0, blue: 3/255.0)), lineWidth: 1.6 * scale)

        // Đầu mũi tên đỏ rực (Bold Arrowhead)
        var arrowPath = Path()
        arrowPath.move(to: rot(-5.5 * scale, -length + 16.0 * scale))
        arrowPath.addLine(to: rot(0, -length))
        arrowPath.addLine(to: rot(5.5 * scale, -length + 16.0 * scale))
        arrowPath.addLine(to: rot(0, -length + 11.0 * scale))
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(Color(red: 1.0, green: 0.0, blue: 0.33)))
        context.stroke(arrowPath, with: .color(.white), lineWidth: 1.4 * scale)

        // Chấm tròn trắng ở đầu mũi tên
        let dotCenter = rot(0, -length + 9.0 * scale)
        let dotR = 2.0 * scale
        let dotRect = CGRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2)
        context.fill(Path(ellipseIn: dotRect), with: .color(.white))
    }

    // MARK: - 8. Mechanical Helpers (Gears, Screws, Piece Geometry)
    private enum GearHubType {
        case ruby
        case screw
    }

    private func drawGear(
        context: inout GraphicsContext,
        gx: CGFloat,
        gy: CGFloat,
        rOut: CGFloat,
        rIn: CGFloat,
        teeth: Int,
        color: Color,
        strokeColor: Color,
        scale: CGFloat,
        angleDeg: Double,
        hubType: GearHubType
    ) {
        let totalSteps = teeth * 4
        let radOffset = angleDeg * .pi / 180.0
        var gearPath = Path()

        for i in 0..<totalSteps {
            let a = Double(i) / Double(totalSteps) * 2.0 * .pi + radOffset
            let step = i % 4
            let r = (step == 1 || step == 2) ? rOut : rIn
            let x = gx + CGFloat(cos(a)) * r
            let y = gy + CGFloat(sin(a)) * r
            if i == 0 { gearPath.move(to: CGPoint(x: x, y: y)) } else { gearPath.addLine(to: CGPoint(x: x, y: y)) }
        }
        gearPath.closeSubpath()

        context.fill(gearPath, with: .color(color))
        context.stroke(gearPath, with: .color(strokeColor), lineWidth: 2.0 * scale)

        // Nan hoa 3 lỗ khoét tròn
        let spokeR = rIn * 0.55
        let holeR = rIn * 0.22
        if holeR > 3.0 * scale {
            for s in 0..<3 {
                let sa = Double(s) / 3.0 * 2.0 * .pi + radOffset
                let hx = gx + spokeR * CGFloat(cos(sa))
                let hy = gy + spokeR * CGFloat(sin(sa))
                let holeRect = CGRect(x: hx - holeR, y: hy - holeR, width: holeR * 2, height: holeR * 2)
                context.fill(Path(ellipseIn: holeRect), with: .color(Color(red: 2/255.0, green: 6/255.0, blue: 23/255.0)))
                context.stroke(Path(ellipseIn: holeRect), with: .color(strokeColor), lineWidth: 1.2 * scale)
            }
        }

        // Ổ trục trung tâm bánh răng
        let hubR = rIn * 0.42
        let hubRect = CGRect(x: gx - hubR, y: gy - hubR, width: hubR * 2, height: hubR * 2)

        if hubType == .ruby {
            context.fill(Path(ellipseIn: hubRect), with: .color(Color(red: 253/255.0, green: 230/255.0, blue: 138/255.0)))
            context.stroke(Path(ellipseIn: hubRect), with: .color(strokeColor), lineWidth: 1.8 * scale)

            let rCore = hubR * 0.65
            let rRect = CGRect(x: gx - rCore, y: gy - rCore, width: rCore * 2, height: rCore * 2)
            context.fill(Path(ellipseIn: rRect), with: .color(Color(red: 239/255.0, green: 68/255.0, blue: 68/255.0)))

            let sDotR = hubR * 0.22
            let sDotRect = CGRect(x: gx - hubR * 0.25 - sDotR, y: gy - hubR * 0.25 - sDotR, width: sDotR * 2, height: sDotR * 2)
            context.fill(Path(ellipseIn: sDotRect), with: .color(.white))
        } else {
            drawBluedScrew(context: &context, x: gx, y: gy, scale: scale)
        }
    }

    private func drawBluedScrew(context: inout GraphicsContext, x: CGFloat, y: CGFloat, scale: CGFloat) {
        let screwR = 4.0 * scale
        let rect = CGRect(x: x - screwR, y: y - screwR, width: screwR * 2, height: screwR * 2)
        context.fill(Path(ellipseIn: rect), with: .color(Color(red: 2/255.0, green: 132/255.0, blue: 199/255.0)))
        context.stroke(Path(ellipseIn: rect), with: .color(Color(red: 56/255.0, green: 189/255.0, blue: 248/255.0)), lineWidth: 1.2 * scale)

        var slotPath = Path()
        slotPath.move(to: CGPoint(x: x - screwR * 0.6, y: y))
        slotPath.addLine(to: CGPoint(x: x + screwR * 0.6, y: y))
        context.stroke(slotPath, with: .color(Color(red: 8/255.0, green: 47/255.0, blue: 73/255.0)), lineWidth: 1.5 * scale)
    }

    private func roundedPiecePath(cx: CGFloat, cy: CGFloat, outerR: CGFloat, innerR: CGFloat, cornerR: CGFloat, startDeg: Double, endDeg: Double) -> Path {
        let s = startDeg * .pi / 180.0
        let e = endDeg * .pi / 180.0
        let dOuter = Double(cornerR / outerR)
        let dInner = Double(cornerR / innerR)

        var path = Path()

        let p0 = CGPoint(x: cx + (outerR - cornerR) * CGFloat(cos(s)), y: cy + (outerR - cornerR) * CGFloat(sin(s)))
        let c1 = CGPoint(x: cx + outerR * CGFloat(cos(s)), y: cy + outerR * CGFloat(sin(s)))
        let p1 = CGPoint(x: cx + outerR * CGFloat(cos(s + dOuter)), y: cy + outerR * CGFloat(sin(s + dOuter)))

        path.move(to: p0)
        path.addQuadCurve(to: p1, control: c1)

        let arcSteps = 16
        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (s + dOuter) + ((e - dOuter) - (s + dOuter)) * t
            path.addLine(to: CGPoint(x: cx + outerR * CGFloat(cos(a)), y: cy + outerR * CGFloat(sin(a))))
        }

        let c2 = CGPoint(x: cx + outerR * CGFloat(cos(e)), y: cy + outerR * CGFloat(sin(e)))
        let p3 = CGPoint(x: cx + (outerR - cornerR) * CGFloat(cos(e)), y: cy + (outerR - cornerR) * CGFloat(sin(e)))
        path.addQuadCurve(to: p3, control: c2)

        let p4 = CGPoint(x: cx + (innerR + cornerR) * CGFloat(cos(e)), y: cy + (innerR + cornerR) * CGFloat(sin(e)))
        path.addLine(to: p4)

        let c3 = CGPoint(x: cx + innerR * CGFloat(cos(e)), y: cy + innerR * CGFloat(sin(e)))
        let p5 = CGPoint(x: cx + innerR * CGFloat(cos(e - dInner)), y: cy + innerR * CGFloat(sin(e - dInner)))
        path.addQuadCurve(to: p5, control: c3)

        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (e - dInner) + ((s + dInner) - (e - dInner)) * t
            path.addLine(to: CGPoint(x: cx + innerR * CGFloat(cos(a)), y: cy + innerR * CGFloat(sin(a))))
        }

        let c4 = CGPoint(x: cx + innerR * CGFloat(cos(s)), y: cy + innerR * CGFloat(sin(s)))
        let p6 = CGPoint(x: cx + (innerR + cornerR) * CGFloat(cos(s)), y: cy + (innerR + cornerR) * CGFloat(sin(s)))
        path.addQuadCurve(to: p6, control: c4)

        path.closeSubpath()
        return path
    }
}
