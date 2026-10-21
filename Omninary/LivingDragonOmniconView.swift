import SwiftUI

// MARK: - Living Dragon Omnicon View
/// Biểu tượng Omnicon Thanh Long Thời Lý:
/// - Khi `isAwakened == false`: Hiển thị tác phẩm nghệ thuật tĩnh tinh xảo chuẩn 1024x1024, siêu tiết kiệm pin.
/// - Khi `isAwakened == true`: Chú Rồng Vàng thức tỉnh với ĐẦU RỒNG UY PHONG cân đối hoàn hảo, ĐUÔI RỒNG VUỐT THON DÀI cùng vây đuôi lửa xoắn ốc uốn lượn mềm mại như dải lụa, chân vuốt hoàng gia và thân rồng bệ vệ lướt trên/dưới 6 phiến ngọc cẩm thạch bo góc 3D. Tâm chữ O giữ trọn vầng thái dương rực rỡ lấp lánh (60-120 FPS ProMotion).
struct LivingDragonOmniconView: View {
    var isAwakened: Bool
    var size: CGFloat = 70
    var cornerRadius: CGFloat = 18

    var body: some View {
        ZStack {
            // Trạng thái tĩnh (Mặc định)
            Image("OmniMythicJadeDragon")
                .resizable()
                .scaledToFit()
                .opacity(isAwakened ? 0 : 1)

            // Trạng thái thức tỉnh (Nhấn giữ)
            if isAwakened {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    DragonCanvasView(time: time, size: size)
                }
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.28), value: isAwakened)
    }
}

// MARK: - Canvas Render Engine (High Performance 120 FPS)
private struct DragonCanvasView: View {
    let time: Double
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let cx = w / 2
            let cy = h / 2
            let scale = w / 220.0

            // 1. Bầu trời sao đêm vũ trụ (Starry Sky)
            drawStarrySky(context: &context, w: w, h: h, cx: cx, cy: cy, time: time)

            // Rồng thần thoại: 92 khớp thân dài uốn lượn thanh thoát
            let totalJoints = 92
            let headNeckJointCount = 3
            var joints: [DragonJoint] = []
            joints.reserveCapacity(totalJoints)
            for i in 0..<totalJoints {
                joints.append(getJoint(index: i, time: time, total: totalJoints, cx: cx, cy: cy, scale: scale))
            }

            // 2. PASS 1: Các đốt thân rồng, chân và đuôi lướt DƯỚI phiến ngọc (Z < 0)
            // Ba đốt sát đầu được thay bằng một cổ liền mạch ở lớp trên, để
            // vòng ngọc không cắt rời phần nối thân–đầu.
            for i in (0..<totalJoints).reversed() {
                let j = joints[i]
                if j.z < 0 && i >= headNeckJointCount {
                    drawJoint(context: &context, joint: j, index: i, total: totalJoints, scale: scale, isOver: false, time: time)
                }
            }
            if let last = joints.last, last.z < 0, joints.count > 3 {
                drawDragonTailFin(context: &context, tip: last, prev: joints[totalJoints - 4], scale: scale, isOver: false, time: time)
            }

            // 3. PASS 2: Vòng chữ O 6 mảnh Cẩm Thạch Phỉ Thúy (Tâm hoàn toàn thông thoáng cho mặt trời)
            drawJadeRing(context: &context, cx: cx, cy: cy, scale: scale, time: time)

            // 4. PASS 3: Mặt Trời Trong Tâm Rực Rỡ Hào Quang Lấp Lánh
            drawRadiantSun(context: &context, cx: cx, cy: cy, scale: scale, time: time)

            // 5. PASS 4: Các đốt thân rồng, chân và đuôi lướt TRÊN phiến ngọc (Z >= 0)
            for i in (0..<totalJoints).reversed() {
                let j = joints[i]
                if j.z >= 0 && i >= headNeckJointCount {
                    drawJoint(context: &context, joint: j, index: i, total: totalJoints, scale: scale, isOver: true, time: time)
                }
            }
            if let last = joints.last, last.z >= 0, joints.count > 3 {
                drawDragonTailFin(context: &context, tip: last, prev: joints[totalJoints - 4], scale: scale, isOver: true, time: time)
            }

            // Cổ được vẽ từ thân lùi vào đúng gốc đầu, không có cổ bù kéo ra
            // phía trước đầu rồng.
            drawContinuousNeck(context: &context, joints: joints, jointCount: headNeckJointCount, scale: scale)

            // 6. PASS 5: Đầu rồng thời Lý uy phong (Tỉ lệ chuẩn, cân đối với thân)
            if joints.count > 2 {
                drawLyHead(context: &context, joints: joints, cx: cx, cy: cy, scale: scale, time: time)
            }
        }
    }

    // MARK: - Joint Struct & Physics
    struct DragonJoint {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat
        var prog: CGFloat
        var theta: CGFloat
    }

    private func getJoint(index: Int, time: Double, total: Int, cx: CGFloat, cy: CGFloat, scale: CGFloat) -> DragonJoint {
        let prog = CGFloat(index) / CGFloat(total)
        // Tốc độ bay chậm rãi, uy nghi, trầm hùng
        let speed = 0.66
        let theta = (time * speed) - (Double(index) * 0.044)

        // Quỹ đạo uốn lượn dập dềnh ra vào các mảnh ngọc. Chuyển tiếp đầu–thân
        // và thân–đuôi phải liên tục; đổi bán kính đột ngột sẽ làm một đốt bị
        // hất lệch khỏi đốt kế bên.
        let headBlendRaw = min(max(prog / 0.16, 0), 1)
        let headBlend = headBlendRaw * headBlendRaw * (3 - 2 * headBlendRaw)
        let tailBlendRaw = min(max((prog - 0.74) / 0.26, 0), 1)
        let tailBlend = tailBlendRaw * tailBlendRaw * (3 - 2 * tailBlendRaw)
        let rMid = (62.0 + (1.0 - headBlend) * 6.0 + tailBlend * 3.0) * scale
        let rAmp = 21.0 * scale
        let rWave = sin(theta * 2.2 + time * 0.4) * Double(rAmp)
        let r = CGFloat(Double(rMid) + rWave)

        // Sóng uốn lượn ngang thân:
        let wave = CGFloat(sin(time * 4.2 - Double(index) * 0.22)) * (6.0 * (1.0 - prog * 0.35)) * scale

        let x = cx + CGFloat(cos(theta)) * r - CGFloat(sin(theta)) * wave
        let y = cy + CGFloat(sin(theta)) * r + CGFloat(cos(theta)) * wave

        // 3D Z-Depth: Đan xen rõ rệt Lên / Xuống các phiến ngọc
        let z = CGFloat(sin(theta * 2.2 + time * 0.4 + 0.3))

        return DragonJoint(x: x, y: y, z: z, prog: prog, theta: CGFloat(theta))
    }

    // MARK: - 1. Starry Sky
    private func drawStarrySky(context: inout GraphicsContext, w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat, time: Double) {
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let skyGrad = Gradient(colors: [
            Color(red: 0.04, green: 0.06, blue: 0.14),
            Color(red: 0.02, green: 0.03, blue: 0.08),
            Color(red: 0.01, green: 0.01, blue: 0.04)
        ])
        context.fill(Path(rect), with: .radialGradient(skyGrad, center: CGPoint(x: cx, y: cy), startRadius: 10, endRadius: w * 0.75))

        let starCoords: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (0.12, 0.15, 1.3, 0.0), (0.28, 0.10, 0.9, 1.2), (0.82, 0.14, 1.6, 2.4),
            (0.91, 0.25, 1.0, 0.5), (0.10, 0.42, 1.2, 1.8), (0.92, 0.62, 1.4, 3.1),
            (0.14, 0.78, 1.1, 2.0), (0.22, 0.89, 1.5, 0.7), (0.81, 0.87, 1.3, 1.5),
            (0.88, 0.76, 0.9, 2.8), (0.16, 0.93, 1.1, 0.3), (0.75, 0.11, 1.4, 1.9),
            (0.08, 0.65, 0.9, 2.2), (0.94, 0.43, 1.2, 0.9), (0.35, 0.22, 0.8, 1.4)
        ]

        for star in starCoords {
            let sx = star.0 * w
            let sy = star.1 * h
            let r = star.2
            let phase = star.3
            let twinkle = 0.45 + 0.55 * sin(time * 3.2 + phase)

            let starRect = CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(twinkle)))

            if r > 1.2 {
                var hPath = Path()
                hPath.move(to: CGPoint(x: sx - 4, y: sy))
                hPath.addLine(to: CGPoint(x: sx + 4, y: sy))
                hPath.move(to: CGPoint(x: sx, y: sy - 4))
                hPath.addLine(to: CGPoint(x: sx, y: sy + 4))
                context.stroke(hPath, with: .color(Color.white.opacity(twinkle * 0.75)), lineWidth: 0.8)
            }
        }
    }

    // MARK: - 2. Jade Ring (6 pieces with 3D bevel, rounded corners & vibrant emerald jade)
    private func drawJadeRing(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        let outerR = 74.0 * scale
        let innerR = 41.0 * scale
        let cornerR = 5.0 * scale

        // 6 Authentic Pieces of the Omninary O (Clockwise screen angles in degrees):
        let piecesDeg: [(Double, Double)] = [
            (146.0, 260.0), // Piece 1 (Thân trái lớn nhất)
            (268.0, 280.0), // Piece 6 (Mảnh nhỏ trên cùng)
            (288.0, 305.0), // Piece 5 (Mảnh chéo góc trên)
            (313.0, 350.0), // Piece 4 (Mảnh góc trên bên phải)
            (5.0, 48.0),    // Piece 3 (Mảnh góc dưới bên phải)
            (58.0, 133.0)   // Piece 2 (Mảnh đáy bên dưới)
        ]

        // Màu ngọc cẩm thạch phỉ thúy tươi sáng, quý phái (#29C473 chuẩn bản tĩnh)
        let jadeGradient = Gradient(colors: [
            Color(red: 48/255.0, green: 222/255.0, blue: 132/255.0),
            Color(red: 38/255.0, green: 196/255.0, blue: 114/255.0),
            Color(red: 28/255.0, green: 168/255.0, blue: 96/255.0)
        ])

        for (pIdx, p) in piecesDeg.enumerated() {
            let path = roundedJadePiecePath(cx: cx, cy: cy, outerR: outerR, innerR: innerR, cornerR: cornerR, startDeg: p.0, endDeg: p.1)

            // LAYER 1: Bóng đổ nổi khối 3D (Drop shadow làm phiến ngọc nổi bồng bềnh)
            context.drawLayer { ctx in
                ctx.translateBy(x: 0, y: 5.0 * scale)
                ctx.fill(path, with: .color(Color.black.opacity(0.48)))
            }

            // LAYER 2: Viền vát 3D cạnh dưới (Bevel bottom lip - màu xanh sẫm tạo độ dày phiến ngọc)
            context.drawLayer { ctx in
                ctx.translateBy(x: 0, y: 2.2 * scale)
                ctx.fill(path, with: .color(Color(red: 25/255.0, green: 135/255.0, blue: 78/255.0)))
            }

            // LAYER 3: Mặt ngọc chính (Vibrant Mint Emerald)
            context.fill(
                path,
                with: .linearGradient(
                    jadeGradient,
                    startPoint: CGPoint(x: cx - outerR, y: cy - outerR),
                    endPoint: CGPoint(x: cx + outerR, y: cy + outerR)
                )
            )

            // LAYER 4: Ánh sáng phản chiếu gờ trên (Top-left rim light bắt sáng lóng lánh)
            context.stroke(
                path,
                with: .color(Color(red: 175/255.0, green: 252/255.0, blue: 215/255.0).opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round, lineJoin: .round)
            )

            // LAYER 5: Đường chỉ vàng kim hoàng gia viền quanh bo góc
            context.stroke(
                path,
                with: .color(Color(red: 1.0, green: 0.90, blue: 0.45).opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round, lineJoin: .round)
            )

            // LAYER 6: Đinh tán sao vàng ở các góc phiến ngọc (đặc trưng bản tĩnh)
            if pIdx == 0 || pIdx == 3 || pIdx == 4 {
                let pinAng = p.1 * .pi / 180.0
                let pinX = cx + CGFloat(cos(pinAng)) * (outerR - 6 * scale)
                let pinY = cy + CGFloat(sin(pinAng)) * (outerR - 6 * scale)
                drawGoldPin(context: &context, x: pinX, y: pinY, scale: scale, time: time)
            }
        }
    }

    // Helper: Vẽ phiến ngọc với 4 góc bo tròn mềm mại (Tâm O luôn thông thoáng tuyệt đối)
    private func roundedJadePiecePath(cx: CGFloat, cy: CGFloat, outerR: CGFloat, innerR: CGFloat, cornerR: CGFloat, startDeg: Double, endDeg: Double) -> Path {
        let s = startDeg * .pi / 180.0
        let e = endDeg * .pi / 180.0
        let dOuter = Double(cornerR / outerR)
        let dInner = Double(cornerR / innerR)

        var path = Path()

        // 1. Điểm đầu trên cạnh hướng tâm gần góc ngoài
        let p0 = CGPoint(x: cx + (outerR - cornerR) * CGFloat(cos(s)), y: cy + (outerR - cornerR) * CGFloat(sin(s)))
        let c1 = CGPoint(x: cx + outerR * CGFloat(cos(s)), y: cy + outerR * CGFloat(sin(s)))
        let p1 = CGPoint(x: cx + outerR * CGFloat(cos(s + dOuter)), y: cy + outerR * CGFloat(sin(s + dOuter)))

        path.move(to: p0)
        // Góc bo 1: Ngoài - Bắt đầu
        path.addQuadCurve(to: p1, control: c1)

        // 2. Cung ngoài: nội suy góc tăng dần từ (s + dOuter) đến (e - dOuter)
        let arcSteps = 16
        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (s + dOuter) + ((e - dOuter) - (s + dOuter)) * t
            path.addLine(to: CGPoint(x: cx + outerR * CGFloat(cos(a)), y: cy + outerR * CGFloat(sin(a))))
        }

        // 3. Góc bo 2: Ngoài - Kết thúc
        let c2 = CGPoint(x: cx + outerR * CGFloat(cos(e)), y: cy + outerR * CGFloat(sin(e)))
        let p3 = CGPoint(x: cx + (outerR - cornerR) * CGFloat(cos(e)), y: cy + (outerR - cornerR) * CGFloat(sin(e)))
        path.addQuadCurve(to: p3, control: c2)

        // 4. Cạnh hướng tâm đi vào
        let p4 = CGPoint(x: cx + (innerR + cornerR) * CGFloat(cos(e)), y: cy + (innerR + cornerR) * CGFloat(sin(e)))
        path.addLine(to: p4)

        // 5. Góc bo 3: Trong - Kết thúc
        let c3 = CGPoint(x: cx + innerR * CGFloat(cos(e)), y: cy + innerR * CGFloat(sin(e)))
        let p5 = CGPoint(x: cx + innerR * CGFloat(cos(e - dInner)), y: cy + innerR * CGFloat(sin(e - dInner)))
        path.addQuadCurve(to: p5, control: c3)

        // 6. Cung trong: nội suy góc giảm dần từ (e - dInner) xuống (s + dInner)
        // Đảm bảo TUYỆT ĐỐI không bao giờ quét qua tâm
        for i in 1...arcSteps {
            let t = Double(i) / Double(arcSteps)
            let a = (e - dInner) + ((s + dInner) - (e - dInner)) * t
            path.addLine(to: CGPoint(x: cx + innerR * CGFloat(cos(a)), y: cy + innerR * CGFloat(sin(a))))
        }

        // 7. Góc bo 4: Trong - Bắt đầu
        let c4 = CGPoint(x: cx + innerR * CGFloat(cos(s)), y: cy + innerR * CGFloat(sin(s)))
        let p6 = CGPoint(x: cx + (innerR + cornerR) * CGFloat(cos(s)), y: cy + (innerR + cornerR) * CGFloat(sin(s)))
        path.addQuadCurve(to: p6, control: c4)

        path.closeSubpath()
        return path
    }

    // Helper: Đinh tán sao vàng
    private func drawGoldPin(context: inout GraphicsContext, x: CGFloat, y: CGFloat, scale: CGFloat, time: Double) {
        let pinR = 3.2 * scale
        let pinRect = CGRect(x: x - pinR, y: y - pinR, width: pinR * 2, height: pinR * 2)
        context.fill(Path(ellipseIn: pinRect), with: .color(Color(red: 1.0, green: 0.88, blue: 0.25)))

        var rayPath = Path()
        rayPath.move(to: CGPoint(x: x, y: y))
        rayPath.addLine(to: CGPoint(x: x + 6 * scale, y: y - 5 * scale))
        rayPath.move(to: CGPoint(x: x, y: y))
        rayPath.addLine(to: CGPoint(x: x + 8 * scale, y: y - 2 * scale))
        rayPath.move(to: CGPoint(x: x, y: y))
        rayPath.addLine(to: CGPoint(x: x + 7 * scale, y: y + 3 * scale))
        context.stroke(rayPath, with: .color(Color(red: 1.0, green: 0.95, blue: 0.65).opacity(0.8)), lineWidth: 0.8 * scale)
    }

    // MARK: - 3. Radiant Sun (Lấp lánh, phát sáng hào quang rực rỡ ở tâm chữ O)
    private func drawRadiantSun(context: inout GraphicsContext, cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        let pulse = 1.0 + 0.12 * sin(time * 3.8)
        let coreR = 14.0 * scale

        // 1. Quầng hào quang tỏa sáng rộng lớn (Vibrant Solar Corona)
        let auraR = 48.0 * scale * pulse
        let auraRect = CGRect(x: cx - auraR, y: cy - auraR, width: auraR * 2, height: auraR * 2)
        let auraGrad = Gradient(colors: [
            Color(red: 1.0, green: 0.72, blue: 0.18).opacity(0.55),
            Color(red: 1.0, green: 0.50, blue: 0.10).opacity(0.25),
            Color(red: 1.0, green: 0.35, blue: 0.05).opacity(0.08),
            Color.clear
        ])
        context.fill(Path(ellipseIn: auraRect), with: .radialGradient(auraGrad, center: CGPoint(x: cx, y: cy), startRadius: 4 * scale, endRadius: auraR))

        // 2. 32 Tia sáng mặt trời lấp lánh (16 tia chính + 16 tia phụ nhấp nháy đa sắc)
        for i in 0..<32 {
            let isPrimary = (i % 2 == 0)
            let ang = Double(i) * (.pi * 2.0 / 32.0) + time * 0.14
            let sparkle = 0.75 + 0.25 * sin(time * 6.5 + Double(i) * 0.8)
            let rayLen = (isPrimary ? (35.0 * pulse) : (22.0 * pulse)) * scale * sparkle
            let w = isPrimary ? 0.045 : 0.025

            let x1 = cx + CGFloat(cos(ang - w)) * 8 * scale
            let y1 = cy + CGFloat(sin(ang - w)) * 8 * scale
            let x2 = cx + CGFloat(cos(ang)) * rayLen
            let y2 = cy + CGFloat(sin(ang)) * rayLen
            let x3 = cx + CGFloat(cos(ang + w)) * 8 * scale
            let y3 = cy + CGFloat(sin(ang + w)) * 8 * scale

            var rayPath = Path()
            rayPath.move(to: CGPoint(x: x1, y: y1))
            rayPath.addLine(to: CGPoint(x: x2, y: y2))
            rayPath.addLine(to: CGPoint(x: x3, y: y3))
            rayPath.closeSubpath()

            let rayColor = isPrimary ? Color(red: 1.0, green: 0.90, blue: 0.45) : Color(red: 1.0, green: 0.98, blue: 0.75)
            context.fill(rayPath, with: .color(rayColor.opacity(0.85 * sparkle)))
        }

        // 3. Đĩa mặt trời hoàng kim
        let outerDiscR = coreR * 1.2
        let outerDiscRect = CGRect(x: cx - outerDiscR, y: cy - outerDiscR, width: outerDiscR * 2, height: outerDiscR * 2)
        context.fill(Path(ellipseIn: outerDiscRect), with: .color(Color(red: 1.0, green: 0.60, blue: 0.12)))

        let coreRect = CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)
        context.fill(Path(ellipseIn: coreRect), with: .color(Color(red: 1.0, green: 0.78, blue: 0.20)))

        // 4. Lõi thái dương trắng chói lòa
        let whiteCore = coreR * 0.55
        let whiteRect = CGRect(x: cx - whiteCore, y: cy - whiteCore, width: whiteCore * 2, height: whiteCore * 2)
        context.fill(Path(ellipseIn: whiteRect), with: .color(Color(red: 1.0, green: 1.0, blue: 0.96)))

        // 5. Ngôi sao 4 cánh lấp lánh ở tâm (Diamond Flare Sparkle)
        let flareLen = 18.0 * scale * (1.0 + 0.25 * sin(time * 5.0))
        let flareW = 2.0 * scale
        var flarePath = Path()
        flarePath.move(to: CGPoint(x: cx, y: cy - flareLen))
        flarePath.addLine(to: CGPoint(x: cx + flareW, y: cy))
        flarePath.addLine(to: CGPoint(x: cx, y: cy + flareLen))
        flarePath.addLine(to: CGPoint(x: cx - flareW, y: cy))
        flarePath.closeSubpath()
        flarePath.move(to: CGPoint(x: cx - flareLen, y: cy))
        flarePath.addLine(to: CGPoint(x: cx, y: cy - flareW))
        flarePath.addLine(to: CGPoint(x: cx + flareLen, y: cy))
        flarePath.addLine(to: CGPoint(x: cx, y: cy + flareW))
        flarePath.closeSubpath()
        context.fill(flarePath, with: .color(Color.white.opacity(0.9)))
    }

    // MARK: - 4. Dragon Joint, Claws & Tail
    private func drawJoint(context: inout GraphicsContext, joint: DragonJoint, index: Int, total: Int, scale: CGFloat, isOver: Bool, time: Double) {
        let prog = joint.prog

        // Thân rồng dày dặn, vuốt thon dài mềm mại dần về đuôi.
        // Bán kính phải biến thiên liên tục để cổ không tạo một nấc phình/gãy.
        let bodyR: CGFloat
        let neckBase: CGFloat = 7.8 // bán kính gốc cổ khớp với nửa đáy của hàm rồng
        let middleR = 5.8 - prog * 0.9
        if prog < 0.18 {
            let rawT = min(max(prog / 0.18, 0), 1)
            let t = rawT * rawT * (3 - 2 * rawT)
            bodyR = (neckBase * (1.0 - t) + middleR * t) * scale
        } else if prog > 0.74 {
            let tailP = (prog - 0.74) / 0.26
            let t = tailP * tailP * (3 - 2 * tailP)
            let tailBaseR = 5.8 - 0.74 * 0.9
            bodyR = max(1.4 * scale, (tailBaseR * (1.0 - t) + 1.4 * t) * scale)
        } else {
            bodyR = middleR * scale
        }

        let rect = CGRect(x: joint.x - bodyR, y: joint.y - bodyR, width: bodyR * 2, height: bodyR * 2)

        // Khối thân vàng 3D hình trụ (Cylindrical Gold Shading - sạch bong không bóng đen)
        let goldGrad = Gradient(colors: [
            Color(red: 1.0, green: 0.96, blue: 0.72),
            Color(red: 0.99, green: 0.82, blue: 0.20),
            Color(red: 0.78, green: 0.50, blue: 0.08)
        ])
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                goldGrad,
                center: CGPoint(x: joint.x - bodyR * 0.3, y: joint.y - bodyR * 0.3),
                startRadius: 0,
                endRadius: bodyR * 1.15
            )
        )

        // CHÂN RỒNG & MÓNG VUỐT HOÀNG GIA (Dragon Claws)
        // Chân trước tại khớp 16, Chân sau tại khớp 48
        if index == 16 {
            drawDragonLegAndClaws(context: &context, joint: joint, isRight: true, scale: scale, isOver: isOver, time: time)
            drawDragonLegAndClaws(context: &context, joint: joint, isRight: false, scale: scale, isOver: isOver, time: time)
        } else if index == 48 {
            drawDragonLegAndClaws(context: &context, joint: joint, isRight: true, scale: scale, isOver: isOver, time: time)
            drawDragonLegAndClaws(context: &context, joint: joint, isRight: false, scale: scale, isOver: isOver, time: time)
        }

        // Vây lưng rồng dập dềnh
        if index > 6 && index < total - 12 && index % 4 == 0 {
            let finLen = bodyR * 2.2
            let ang = Double(joint.theta) + .pi / 2.0
            var finPath = Path()
            finPath.move(to: CGPoint(x: joint.x, y: joint.y))
            finPath.addLine(to: CGPoint(x: joint.x + CGFloat(cos(ang)) * finLen, y: joint.y + CGFloat(sin(ang)) * finLen))
            finPath.addLine(to: CGPoint(x: joint.x + CGFloat(cos(ang + 0.3)) * (finLen * 0.5), y: joint.y + CGFloat(sin(ang + 0.3)) * (finLen * 0.5)))
            finPath.closeSubpath()
            context.fill(finPath, with: .color(Color(red: 1.0, green: 0.90, blue: 0.45).opacity(0.85)))
        }
    }

    // MARK: - Continuous Neck
    /// Thay ba khớp đầu bằng một ống cổ có tiếp tuyến liên tục để phần nối với đầu rồng luôn mềm mại.
    private func drawContinuousNeck(context: inout GraphicsContext, joints: [DragonJoint], jointCount: Int, scale: CGFloat) {
        guard joints.count > jointCount, jointCount >= 2 else { return }

        let base = joints[jointCount]
        let control1 = joints[jointCount - 1]
        let control2 = joints[1]
        let headRoot = joints[0]
        let neckR = 7.8 * scale
        let goldGradient = Gradient(colors: [
            Color(red: 0.78, green: 0.50, blue: 0.08),
            Color(red: 0.99, green: 0.82, blue: 0.20),
            Color(red: 1.0, green: 0.96, blue: 0.72)
        ])

        var neckPath = Path()
        neckPath.move(to: CGPoint(x: base.x, y: base.y))
        neckPath.addCurve(
            to: CGPoint(x: headRoot.x, y: headRoot.y),
            control1: CGPoint(x: control1.x, y: control1.y),
            control2: CGPoint(x: control2.x, y: control2.y)
        )

        context.stroke(
            neckPath,
            with: .linearGradient(
                goldGradient,
                startPoint: CGPoint(x: base.x, y: base.y),
                endPoint: CGPoint(x: headRoot.x, y: headRoot.y)
            ),
            style: StrokeStyle(lineWidth: neckR * 2.0, lineCap: .round, lineJoin: .round)
        )
    }

    // Helper: Vẽ vây đuôi lửa xoắn ốc thời Lý mềm mại ở chóp đuôi
    private func drawDragonTailFin(context: inout GraphicsContext, tip: DragonJoint, prev: DragonJoint, scale: CGFloat, isOver: Bool, time: Double) {
        let dx = tip.x - prev.x
        let dy = tip.y - prev.y
        let tailAngle = atan2(dy, dx)

        context.drawLayer { ctx in
            ctx.translateBy(x: tip.x, y: tip.y)
            ctx.rotate(by: .radians(Double(tailAngle)))

            // Dải lụa lửa trung tâm (Central flame ribbon)
            let sway = CGFloat(sin(time * 5.2)) * 3.5 * scale
            var f1 = Path()
            f1.move(to: CGPoint(x: 0, y: 0))
            f1.addCurve(
                to: CGPoint(x: 28 * scale, y: -8 * scale + sway),
                control1: CGPoint(x: 10 * scale, y: -16 * scale + sway * 0.7),
                control2: CGPoint(x: 20 * scale, y: 2 * scale)
            )
            ctx.stroke(f1, with: .color(Color(red: 1.0, green: 0.90, blue: 0.40)), style: StrokeStyle(lineWidth: 2.6 * scale, lineCap: .round))

            // Dải lửa trên (Upper flame tendril)
            var f2 = Path()
            f2.move(to: CGPoint(x: -2 * scale, y: -2 * scale))
            f2.addQuadCurve(to: CGPoint(x: 22 * scale, y: -20 * scale + sway * 1.2), control: CGPoint(x: 8 * scale, y: -20 * scale))
            ctx.stroke(f2, with: .color(Color(red: 1.0, green: 0.82, blue: 0.25)), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            // Dải lửa dưới (Lower flame tendril)
            var f3 = Path()
            f3.move(to: CGPoint(x: -2 * scale, y: 2 * scale))
            f3.addQuadCurve(to: CGPoint(x: 24 * scale, y: 12 * scale - sway * 1.2), control: CGPoint(x: 10 * scale, y: 14 * scale))
            ctx.stroke(f3, with: .color(Color(red: 1.0, green: 0.82, blue: 0.25)), style: StrokeStyle(lineWidth: 2.0 * scale, lineCap: .round))

            // Vòng xoắn ốc chóp đuôi đặc trưng thời Lý (Signature Lý spiral fin)
            var spiral = Path()
            spiral.move(to: CGPoint(x: 18 * scale, y: -8 * scale + sway))
            spiral.addCurve(
                to: CGPoint(x: 34 * scale, y: -4 * scale + sway),
                control1: CGPoint(x: 24 * scale, y: -16 * scale + sway),
                control2: CGPoint(x: 36 * scale, y: -12 * scale + sway)
            )
            ctx.stroke(spiral, with: .color(Color(red: 1.0, green: 0.95, blue: 0.65)), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
        }
    }

    // Helper: Vẽ chân rồng vươn ra với 4 móng vuốt cong mềm mại (sạch bong không bóng đen)
    private func drawDragonLegAndClaws(context: inout GraphicsContext, joint: DragonJoint, isRight: Bool, scale: CGFloat, isOver: Bool, time: Double) {
        let legAngle = Double(joint.theta) + (isRight ? (.pi * 0.55) : (-.pi * 0.55))
        let legLen = 17.0 * scale

        let x0 = joint.x
        let y0 = joint.y

        // Đầu gối chân rồng
        let xKnee = x0 + CGFloat(cos(legAngle)) * (legLen * 0.6)
        let yKnee = y0 + CGFloat(sin(legAngle)) * (legLen * 0.6)

        // Bàn chân rồng
        let xFoot = x0 + CGFloat(cos(legAngle + (isRight ? 0.25 : -0.25))) * legLen
        let yFoot = y0 + CGFloat(sin(legAngle + (isRight ? 0.25 : -0.25))) * legLen

        // Bắp chân & Cẳng chân
        var legPath = Path()
        legPath.move(to: CGPoint(x: x0, y: y0))
        legPath.addLine(to: CGPoint(x: xKnee, y: yKnee))
        legPath.addLine(to: CGPoint(x: xFoot, y: yFoot))
        context.stroke(legPath, with: .color(Color(red: 0.95, green: 0.78, blue: 0.18)), style: StrokeStyle(lineWidth: 3.2 * scale, lineCap: .round, lineJoin: .round))

        // Cựa lửa ở đầu gối
        var spur = Path()
        spur.move(to: CGPoint(x: xKnee, y: yKnee))
        spur.addLine(to: CGPoint(x: xKnee + CGFloat(cos(legAngle - 0.5)) * 6 * scale, y: yKnee + CGFloat(sin(legAngle - 0.5)) * 6 * scale))
        context.stroke(spur, with: .color(Color(red: 1.0, green: 0.90, blue: 0.40)), lineWidth: 1.5 * scale)

        // 4 Móng vuốt cong hoàng gia thời Lý (spreading claw talons)
        for clawIdx in 0..<4 {
            let clawSpread = (Double(clawIdx) - 1.5) * 0.32 + (isRight ? 0.25 : -0.25)
            let cAng = legAngle + clawSpread
            let cLen = 11.5 * scale

            let xTip = xFoot + CGFloat(cos(cAng)) * cLen
            let yTip = yFoot + CGFloat(sin(cAng)) * cLen
            let xCtrl = xFoot + CGFloat(cos(cAng + 0.15)) * (cLen * 0.5)
            let yCtrl = yFoot + CGFloat(sin(cAng + 0.15)) * (cLen * 0.5)

            var claw = Path()
            claw.move(to: CGPoint(x: xFoot, y: yFoot))
            claw.addQuadCurve(to: CGPoint(x: xTip, y: yTip), control: CGPoint(x: xCtrl, y: yCtrl))
            context.stroke(claw, with: .color(Color(red: 1.0, green: 0.92, blue: 0.50)), style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
        }
    }

    // MARK: - 5. ĐẦU RỒNG THỜI LÝ UY PHONG (Cân đối, tinh xảo, thu nhỏ 1 xíu xiu)
    private func drawLyHead(context: inout GraphicsContext, joints: [DragonJoint], cx: CGFloat, cy: CGFloat, scale: CGFloat, time: Double) {
        guard joints.count > 2 else { return }

        let h0 = joints[0]
        let h1 = joints[1]
        let h2 = joints[2]

        // Lấy tiếp tuyến trung bình của ba đốt đầu thay vì chỉ dựa vào một
        // cặp khớp. Hướng đầu vì thế không bị giật hoặc gãy khi sóng thân đổi pha.
        let tangentX = h0.x - h2.x
        let tangentY = h0.y - h2.y
        let fallbackX = h0.x - h1.x
        let fallbackY = h0.y - h1.y
        let flightAngle = atan2(
            abs(tangentX) + abs(tangentY) > 0.001 ? tangentY : fallbackY,
            abs(tangentX) + abs(tangentY) > 0.001 ? tangentX : fallbackX
        )

        // Hệ số thu nhỏ vừa vặn (hs = 0.82) giúp đầu rồng gọn gàng, cân xứng với thân
        let hs: CGFloat = 0.82 * scale

        context.drawLayer { ctx in
            ctx.translateBy(x: h0.x, y: h0.y)
            ctx.rotate(by: .radians(Double(flightAngle)))

            // 1. Bờm rồng cuồn cuộn 3 tầng xuôi theo chiều gió
            var mane1 = Path()
            mane1.move(to: CGPoint(x: -6 * hs, y: 0))
            mane1.addQuadCurve(to: CGPoint(x: -34 * hs, y: -10 * hs), control: CGPoint(x: -18 * hs, y: -16 * hs))
            ctx.stroke(mane1, with: .color(Color(red: 0.90, green: 0.55, blue: 0.08)), lineWidth: 3.0 * hs)

            var mane2 = Path()
            mane2.move(to: CGPoint(x: -6 * hs, y: 3 * hs))
            mane2.addQuadCurve(to: CGPoint(x: -34 * hs, y: 10 * hs), control: CGPoint(x: -18 * hs, y: 16 * hs))
            ctx.stroke(mane2, with: .color(Color(red: 0.90, green: 0.55, blue: 0.08)), lineWidth: 3.0 * hs)

            var mane3 = Path()
            mane3.move(to: CGPoint(x: -4 * hs, y: 0))
            mane3.addQuadCurve(to: CGPoint(x: -28 * hs, y: 0), control: CGPoint(x: -15 * hs, y: -7 * hs))
            ctx.stroke(mane3, with: .color(Color(red: 1.0, green: 0.75, blue: 0.18)), lineWidth: 1.8 * hs)

            // 2. Sừng gạc hoàng kim (Golden Antlers)
            var horn1 = Path()
            horn1.move(to: CGPoint(x: 2 * hs, y: -7 * hs))
            horn1.addLine(to: CGPoint(x: -15 * hs, y: -24 * hs))
            horn1.addLine(to: CGPoint(x: -28 * hs, y: -32 * hs))
            horn1.move(to: CGPoint(x: -15 * hs, y: -24 * hs))
            horn1.addLine(to: CGPoint(x: -13 * hs, y: -35 * hs))
            ctx.stroke(horn1, with: .color(Color(red: 1.0, green: 0.88, blue: 0.35)), style: StrokeStyle(lineWidth: 2.2 * hs, lineCap: .round, lineJoin: .round))

            // 3. Mào lửa thời Lý đa tầng uy dũng (Flame Crest on snout)
            var crest = Path()
            crest.move(to: CGPoint(x: 5 * hs, y: -5 * hs))
            crest.addLine(to: CGPoint(x: 11 * hs, y: -20 * hs))
            crest.addLine(to: CGPoint(x: 17 * hs, y: -11 * hs))
            crest.addLine(to: CGPoint(x: 24 * hs, y: -23 * hs))
            crest.addLine(to: CGPoint(x: 27 * hs, y: -7 * hs))
            crest.closeSubpath()
            let crestGrad = Gradient(colors: [
                Color(red: 1.0, green: 0.92, blue: 0.48),
                Color(red: 1.0, green: 0.72, blue: 0.18),
                Color(red: 0.90, green: 0.48, blue: 0.08)
            ])
            ctx.fill(crest, with: .linearGradient(crestGrad, startPoint: CGPoint(x: 15 * hs, y: -23 * hs), endPoint: CGPoint(x: 15 * hs, y: -5 * hs)))
            ctx.stroke(crest, with: .color(Color(red: 1.0, green: 0.95, blue: 0.65)), lineWidth: 1.0 * hs)

            // 4. Hàm trên vươn dài vểnh nhẹ (Upper Jaw)
            var upperJaw = Path()
            upperJaw.move(to: CGPoint(x: -7 * hs, y: -6 * hs))
            upperJaw.addLine(to: CGPoint(x: 28 * hs, y: -7 * hs))
            upperJaw.addLine(to: CGPoint(x: 22 * hs, y: -2 * hs))
            upperJaw.addLine(to: CGPoint(x: -7 * hs, y: -2 * hs))
            upperJaw.closeSubpath()
            let jawGrad = Gradient(colors: [
                Color(red: 1.0, green: 0.90, blue: 0.40),
                Color(red: 0.99, green: 0.78, blue: 0.16),
                Color(red: 0.85, green: 0.55, blue: 0.08)
            ])
            ctx.fill(upperJaw, with: .linearGradient(jawGrad, startPoint: CGPoint(x: 10 * hs, y: -6 * hs), endPoint: CGPoint(x: 10 * hs, y: 2 * hs)))
            ctx.stroke(upperJaw, with: .color(Color(red: 0.78, green: 0.50, blue: 0.06)), lineWidth: 1.2 * hs)

            // 5. Hàm dưới há to mở rộng gầm uy phong (Wide Roaring Lower Jaw)
            var lowerJaw = Path()
            lowerJaw.move(to: CGPoint(x: -7 * hs, y: 3 * hs))
            lowerJaw.addLine(to: CGPoint(x: 24 * hs, y: 16 * hs))
            lowerJaw.addLine(to: CGPoint(x: 17 * hs, y: 21 * hs))
            lowerJaw.addLine(to: CGPoint(x: -7 * hs, y: 9 * hs))
            lowerJaw.closeSubpath()
            ctx.fill(lowerJaw, with: .linearGradient(jawGrad, startPoint: CGPoint(x: 10 * hs, y: 3 * hs), endPoint: CGPoint(x: 10 * hs, y: 21 * hs)))
            ctx.stroke(lowerJaw, with: .color(Color(red: 0.78, green: 0.50, blue: 0.06)), lineWidth: 1.2 * hs)

            // 6. Khoang miệng / Họng
            var throat = Path()
            throat.move(to: CGPoint(x: -6 * hs, y: -2 * hs))
            throat.addLine(to: CGPoint(x: 6 * hs, y: -2 * hs))
            throat.addLine(to: CGPoint(x: 10 * hs, y: 2 * hs))
            throat.addLine(to: CGPoint(x: 6 * hs, y: 7 * hs))
            throat.addLine(to: CGPoint(x: -6 * hs, y: 7 * hs))
            throat.closeSubpath()
            ctx.fill(throat, with: .color(Color(red: 180/255.0, green: 30/255.0, blue: 25/255.0)))

            // 7. Răng nanh sắc nhọn trắng muốt
            var teeth = Path()
            // Răng hàm trên mọc xuống
            for tx in [9, 13, 17, 21, 24] {
                teeth.move(to: CGPoint(x: CGFloat(tx) * hs, y: -2 * hs))
                teeth.addLine(to: CGPoint(x: (CGFloat(tx) + 1.8) * hs, y: 2.5 * hs))
                teeth.addLine(to: CGPoint(x: (CGFloat(tx) + 3.0) * hs, y: -2 * hs))
            }
            // Răng hàm dưới mọc lên
            for tx in [8, 12, 16, 20] {
                let tProg = CGFloat(tx - 8) / 16.0
                let baseY = (3.0 + tProg * 11.0) * hs
                teeth.move(to: CGPoint(x: CGFloat(tx) * hs, y: baseY))
                teeth.addLine(to: CGPoint(x: (CGFloat(tx) + 1.8) * hs, y: baseY - 4.5 * hs))
                teeth.addLine(to: CGPoint(x: (CGFloat(tx) + 3.0) * hs, y: baseY))
            }
            ctx.fill(teeth, with: .color(Color.white))

            // 8. Mắt ngọc Ruby to tròn, sáng rực (Luminous Ruby Eye)
            let eyeCenter = CGPoint(x: 6.5 * hs, y: -4.5 * hs)
            let eyeR = 3.8 * hs
            let eyeRect = CGRect(x: eyeCenter.x - eyeR, y: eyeCenter.y - eyeR, width: eyeR * 2, height: eyeR * 2)
            ctx.fill(Path(ellipseIn: eyeRect), with: .color(Color(red: 0.95, green: 0.05, blue: 0.18)))

            let eyeGlare = CGRect(x: eyeCenter.x + 0.8 * hs, y: eyeCenter.y - 1.6 * hs, width: 1.5 * hs, height: 1.5 * hs)
            ctx.fill(Path(ellipseIn: eyeGlare), with: .color(Color.white))

            var brow = Path()
            brow.move(to: CGPoint(x: eyeCenter.x - eyeR - 1 * hs, y: eyeCenter.y - eyeR))
            brow.addQuadCurve(to: CGPoint(x: eyeCenter.x + eyeR + 2 * hs, y: eyeCenter.y - eyeR + 1 * hs), control: CGPoint(x: eyeCenter.x, y: eyeCenter.y - eyeR - 2.5 * hs))
            ctx.stroke(brow, with: .color(Color(red: 1.0, green: 0.92, blue: 0.45)), lineWidth: 1.8 * hs)

            // 9. Đôi Râu Rồng Vàng Uy Nghi vươn dài (Flowing Golden Whiskers)
            let wSway = CGFloat(sin(time * 6.5)) * 5.0 * scale
            var w1 = Path()
            w1.move(to: CGPoint(x: 24 * hs, y: -3 * hs))
            w1.addCurve(
                to: CGPoint(x: 56 * scale, y: -15 * scale + wSway * 1.5),
                control1: CGPoint(x: 35 * scale, y: -17 * scale + wSway),
                control2: CGPoint(x: 46 * scale, y: -7 * scale)
            )
            ctx.stroke(w1, with: .color(Color(red: 1.0, green: 0.95, blue: 0.65)), lineWidth: 1.6 * scale)

            var w2 = Path()
            w2.move(to: CGPoint(x: 24 * hs, y: 3 * hs))
            w2.addCurve(
                to: CGPoint(x: 56 * scale, y: 16 * scale - wSway * 1.5),
                control1: CGPoint(x: 35 * scale, y: 17 * scale - wSway),
                control2: CGPoint(x: 46 * scale, y: 8 * scale)
            )
            ctx.stroke(w2, with: .color(Color(red: 1.0, green: 0.95, blue: 0.65)), lineWidth: 1.6 * scale)
        }
    }
}
