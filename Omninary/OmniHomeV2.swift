import SwiftUI

// MARK: - Streak flame milestones of the new Home (one family for Ditandnary and Extraordinary)

/// Milestone for a streak length; it sets the colour of the streak number and its note.
enum PixelFlame: Int, CaseIterable {
    case unlit, ember, spark, blaze, azure, frost, legend

    init(days: Int) {
        switch days {
        case ..<1: self = .unlit
        case 1..<10: self = .ember
        case 10..<30: self = .spark
        case 30..<100: self = .blaze
        case 100..<200: self = .azure
        case 200..<300: self = .frost
        default: self = .legend
        }
    }

    /// Colour of the streak number and status line.
    func ink(night: Bool) -> Color {
        switch self {
        case .unlit: Color(hex: 0x9AA2B2)
        case .ember: Color(hex: 0xE89A12)
        case .spark: Color(hex: 0xF2711C)
        case .blaze: Color(hex: 0xE5452B)
        case .azure: night ? Color(hex: 0x5EA8FF) : Color(hex: 0x2F80E0)
        case .frost: night ? Color(hex: 0x45D0EA) : Color(hex: 0x1597B8)
        case .legend: night ? Color(hex: 0xFFC23C) : Color(hex: 0xD08A10)
        }
    }
}

/// The streak flame, drawn for Omninary: a gold rim around a body fading from pink-red to orange,
/// a small white flame at its heart and a soft gold shadow underneath, the same for every milestone
/// and still once lit. Unlit it is the same flame in grey; when it lights it pops up with a burst of
/// sparks and a glow. The name stays from the pixel art it replaced.
struct PixelFlameImage: View {
    let flame: PixelFlame
    let height: CGFloat
    @Environment(\.omniPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ignitions = 0
    @State private var sparksOut = false
    @State private var popping = false

    private var lit: Bool { flame != .unlit }
    /// Sparks and glow only where the flame is big enough to show them.
    private var large: Bool { height >= 40 }

    private static let sparkAngles: [Double] = [-150, -115, -80, -45, -10, 200]

    var body: some View {
        let night = palette.night
        ZStack {
            if lit && large {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFB13B).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: height * 0.55))
                    .frame(width: height * 1.1, height: height * 1.1)
                    .offset(y: height * 0.1)
                    .transition(.opacity)
            }
            OmniFlameDrawing(lit: lit, night: night)
            // its own box, so the wider glow behind can never stretch the drawing
            .frame(width: height * OmniFlameShape.aspect, height: height)
            .scaleEffect(popping ? 1.18 : 1, anchor: .bottom)
            if large {
                ForEach(Self.sparkAngles.indices, id: \.self) { i in
                    let angle = CGFloat(Self.sparkAngles[i]) * .pi / 180
                    let reach = height * (0.62 + 0.08 * CGFloat(i % 3))
                    Circle()
                        .fill(Color(hex: i.isMultiple(of: 2) ? 0xFFD43B : 0xFF6A3D))
                        .frame(width: height * 0.07, height: height * 0.07)
                        .offset(x: sparksOut ? cos(angle) * reach : 0, y: sparksOut ? sin(angle) * reach : height * 0.1)
                        .opacity(sparksOut ? 0 : 1)
                        .scaleEffect(sparksOut ? 0.4 : 1)
                        .opacity(ignitions > 0 ? 1 : 0)
                }
            }
        }
        .frame(width: (height * OmniFlameShape.aspect).rounded(), height: height)
        .animation(.easeInOut(duration: 0.35), value: lit)
        .onChange(of: lit) { _, now in
            guard now, !reduceMotion else { return }
            ignitions += 1
            sparksOut = false
            withAnimation(.easeOut(duration: 0.7)) { sparksOut = true }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { popping = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { popping = false }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Omninary flame with its shadow, lit (gold rim, pink-red to orange body, white heart) or grey.
struct OmniFlameDrawing: View {
    let lit: Bool
    let night: Bool

    static let fire = LinearGradient(
        stops: [.init(color: Color(hex: 0xFF4B5C), location: 0), .init(color: Color(hex: 0xFF6A3D), location: 0.5),
                .init(color: Color(hex: 0xFFA41C), location: 1)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        ZStack {
            OmniFlameShape(part: .shadow)
                .fill(Color(hex: 0xFFD43B).opacity(lit ? (night ? 0.18 : 0.35) : (night ? 0.1 : 0.2)))
            OmniFlameShape(part: .outline)
                .fill(lit ? Color(hex: 0xFFD43B) : Color(hex: night ? 0x4A5372 : 0xCDD3DC))
            OmniFlameShape(part: .body)
                .fill(lit ? AnyShapeStyle(Self.fire) : AnyShapeStyle(Color(hex: night ? 0x626C8C : 0xE3E7ED)))
            OmniFlameShape(part: .core)
                .fill(Color.white.opacity(lit ? 1 : 0.75))
        }
    }
}

/// The parts of the Omninary flame, drawn in a 100 × 120 box: three rounded tongues (a short one on
/// each side of the tall middle one) over a full round base.
struct OmniFlameShape: Shape {
    enum Part { case outline, body, core, shadow }
    let part: Part

    /// Width over height of the drawing box.
    static let aspect: CGFloat = 100 / 120

    private typealias Curve = (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)

    private static let outline: (start: CGPoint, curves: [Curve]) = (CGPoint(x: 44, y: 10), [
        (46, 5, 52, 4, 55, 9), (58, 16, 61, 25, 65, 33), (68, 30, 72, 28, 76, 27), (80, 26, 83, 29, 83, 33),
        (91, 47, 94, 63, 92, 80), (89, 104, 71, 117, 50, 117), (29, 117, 9, 104, 8, 82), (7, 66, 15, 48, 20, 38),
        (22, 34, 26, 33, 28, 36), (32, 44, 30, 54, 37, 58), (36, 44, 39, 24, 44, 10)
    ])
    private static let body: (start: CGPoint, curves: [Curve]) = (CGPoint(x: 45.3, y: 30.7), [
        (46.9, 26.8, 51.6, 26, 53.9, 29.9), (56.2, 35.4, 58.6, 42.4, 61.7, 48.6), (64, 46.3, 67.2, 44.7, 70.3, 43.9),
        (73.4, 43.2, 75.7, 45.5, 75.7, 48.6), (82, 59.5, 84.3, 72, 82.8, 85.3), (80.4, 104, 66.4, 114.1, 50, 114.1),
        (33.6, 114.1, 18, 104, 17.2, 86.8), (16.5, 74.4, 19.2, 65.2, 23.1, 57.4), (24.6, 54.3, 27.8, 53.5, 29.3, 55.9),
        (33.2, 62.1, 34.6, 65.6, 37.4, 68.4), (39, 70, 41.2, 70, 41, 67.2), (40, 55.5, 41.8, 41, 45.3, 30.7)
    ])
    private static let core: (start: CGPoint, curves: [Curve]) = (CGPoint(x: 48.1, y: 76), [
        (48.7, 74.4, 50.6, 74, 51.6, 75.6), (52.6, 77.9, 53.5, 80.8, 54.8, 83.3), (55.8, 82.4, 57, 81.7, 58.3, 81.4),
        (59.6, 81.1, 60.6, 82, 60.6, 83.3), (63.1, 87.8, 64.1, 92.9, 63.4, 98.4), (62.5, 106, 56.7, 110.2, 50, 110.2),
        (43.3, 110.2, 36.9, 106, 36.6, 99), (36.2, 93.9, 35.9, 89.7, 37.5, 86.5), (38.2, 85.2, 39.4, 84.9, 40.1, 85.9),
        (41.7, 88.4, 43.6, 91, 45.8, 92.3), (45.5, 86.8, 46.5, 80.4, 48.1, 76)
    ])

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 100, sy = rect.height / 120
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        if part == .shadow {
            path.addEllipse(in: CGRect(origin: pt(20, 112), size: CGSize(width: 60 * sx, height: 10 * sy)))
            return path
        }
        let drawing = part == .outline ? Self.outline : part == .body ? Self.body : Self.core
        path.move(to: pt(drawing.start.x, drawing.start.y))
        for c in drawing.curves {
            path.addCurve(to: pt(c.4, c.5), control1: pt(c.0, c.1), control2: pt(c.2, c.3))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Month calendar as a heatmap

/// A month where each day's colour deepens with the words learned; frozen days cyan, rescued days red.
struct OmniHeatmapCalendar: View {
    @Environment(\.omniPalette) private var palette
    let month: Date
    let wordCounts: [String: Int]
    let learnedDays: [String: Bool]
    let frozenDays: Set<String>
    let rescuedDays: Set<String>
    let today: Date
    var onSelect: (Date) -> Void

    static let dayShades: [UInt32] = [0xDBE8FC, 0xA9C8F7, 0x5E97EC, 0x2F6FD6]
    static let nightShades: [UInt32] = [0x23305A, 0x2C4F9C, 0x3F7BE0, 0x7FB2FF]
    static let frozen: UInt32 = 0x1AA7C4
    static let rescued: UInt32 = 0xD0453B

    private var calendar: Calendar {
        var c = StreakClock.calendar
        c.firstWeekday = 2
        return c
    }

    private var cells: [Date?] {
        let cal = calendar
        guard let interval = cal.dateInterval(of: .month, for: month),
              let days = cal.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in days { out.append(cal.date(byAdding: .day, value: d - 1, to: interval.start)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    var body: some View {
        let all = cells
        let rows = max(1, all.count / 7)
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { d in
                    Text(d)
                        .font(.omniBody(10.5, weight: 700))
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { proxy in
                let cellH = min(44, (proxy.size.height - CGFloat(rows - 1) * 2) / CGFloat(rows))
                VStack(spacing: 2) {
                    ForEach(0..<rows, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { c in
                                dayCell(all[r * 7 + c]).frame(height: cellH)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let key = StreakClock.dayKey(date)
            let cal = calendar
            let isToday = cal.isDate(date, inSameDayAs: today)
            let future = date > today && !isToday
            let style = cellStyle(key: key, future: future)
            Button { if !future { onSelect(date) } } label: {
                Text("\(cal.component(.day, from: date))")
                    .font(.omniBody(12, weight: isToday ? 800 : 700))
                    .foregroundStyle(style.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(style.fill)
                    .overlay {
                        if let ring = style.ring { Rectangle().strokeBorder(ring, lineWidth: 2) }
                        if isToday { Rectangle().strokeBorder(palette.text, lineWidth: 2) }
                    }
            }
            .buttonStyle(.plain)
            .disabled(future)
            .accessibilityLabel(accessibility(date: date, key: key))
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    private struct CellStyle { let fill: Color; let text: Color; let ring: Color? }

    private func cellStyle(key: String, future: Bool) -> CellStyle {
        if future { return CellStyle(fill: .clear, text: palette.night ? Color(hex: 0x5C6589) : Color(hex: 0x9AA4B5), ring: nil) }
        if rescuedDays.contains(key) { return CellStyle(fill: Color(hex: 0xFDE2DF), text: Color(hex: 0xA8282A), ring: Color(hex: Self.rescued)) }
        if frozenDays.contains(key) && learnedDays[key] != true { return CellStyle(fill: Color(hex: 0xD6F3FB), text: Color(hex: 0x127A91), ring: Color(hex: Self.frozen)) }
        let words = wordCounts[key] ?? 0
        guard words > 0 || learnedDays[key] == true else { return CellStyle(fill: .clear, text: palette.text, ring: nil) }
        let i = words < 5 ? 0 : words < 10 ? 1 : words < 20 ? 2 : 3
        let shades = palette.night ? Self.nightShades : Self.dayShades
        let text: [UInt32] = palette.night ? [0xCFD6EE, 0xFFFFFF, 0xFFFFFF, 0x0D1A3A] : [0x1D56B8, 0x17418F, 0xFFFFFF, 0xFFFFFF]
        return CellStyle(fill: Color(hex: shades[i]), text: Color(hex: text[i]), ring: nil)
    }

    private func accessibility(date: Date, key: String) -> String {
        let day = calendar.component(.day, from: date)
        if rescuedDays.contains(key) { return "Ngày \(day), đã cứu lửa" }
        if frozenDays.contains(key) && learnedDays[key] != true { return "Ngày \(day), đóng băng" }
        if let w = wordCounts[key], w > 0 { return "Ngày \(day), học \(w) từ" }
        return learnedDays[key] == true ? "Ngày \(day), đã học" : "Ngày \(day), không học"
    }
}

/// Colour strip under the calendar: none, little to many words, frozen, rescued. No text.
struct OmniHeatmapLegend: View {
    @Environment(\.omniPalette) private var palette
    var body: some View {
        let shades = palette.night ? OmniHeatmapCalendar.nightShades : OmniHeatmapCalendar.dayShades
        HStack(spacing: 0) {
            Rectangle().fill(palette.card)
                .overlay(Rectangle().strokeBorder(palette.night ? Color(hex: 0x3A4472) : Color(hex: 0xC9D2DF), lineWidth: 1))
            ForEach(shades, id: \.self) { Rectangle().fill(Color(hex: $0)) }
            Rectangle().fill(Color(hex: OmniHeatmapCalendar.frozen))
            Rectangle().fill(Color(hex: OmniHeatmapCalendar.rescued))
        }
        .frame(height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Chú thích màu: không học, ít đến nhiều từ, đóng băng, cứu lửa")
    }
}
