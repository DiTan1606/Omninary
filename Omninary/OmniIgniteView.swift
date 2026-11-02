import SwiftUI

/// Full-screen moment after the day's first lesson: the grey flame trembles, bursts into a pillar of
/// fire with a flash and a shake, and settles lit while the streak rolls from the old count to the new
/// one. Every part is driven by the seconds since the screen opened.
struct OmniIgniteView: View {
    let previousDays: Int
    let newDays: Int
    var onContinue: () -> Void

    @Environment(\.omniPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// When the flame catches.
    private static let catchTime = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            // with Reduce Motion the screen opens on its finished state
            content(reduceMotion ? 6 : timeline.date.timeIntervalSince(start))
        }
        .onAppear { start = Date() }
        .task { await playHaptics() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chuỗi \(newDays) ngày")
    }

    private func content(_ t: Double) -> some View {
        let night = palette.night
        let shake = Self.shake(t)
        return ZStack {
            palette.background.ignoresSafeArea()
            warmth(night)
                .opacity(Self.ramp(t, Self.catchTime, 2.1))
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 24)
                flameStage(t, night: night)
                    .frame(width: 200, height: 248)
                number(t, night: night)
                    .padding(.top, 14)
                VStack(spacing: 4) {
                    Text("ngày streak!")
                        .font(.omniDisplay(30, weight: 800))
                        .foregroundStyle(ink(night))
                    Text("Lửa hôm nay đã cháy. Hẹn bạn ngày mai nha!")
                        .font(.omniBody(15, weight: 600))
                        .foregroundStyle(palette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .modifier(Arrive(t: t, at: 2.3))
                Spacer(minLength: 20)
                week(t, night: night)
                    .padding(.horizontal, 24)
                    .modifier(Arrive(t: t, at: 2.5))
                continueButton
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .modifier(Arrive(t: t, at: 2.9))
                    .allowsHitTesting(t > 2.9)
            }
            .offset(x: shake.width, y: shake.height)
            // the flash as the fire catches
            Color(hex: 0xFFF6D6)
                .opacity(t < Self.catchTime ? 0 : 0.85 * (1 - Self.ramp(t, Self.catchTime, 1.45)))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Flame

    private func flameStage(_ t: Double, night: Bool) -> some View {
        let c = Self.catchTime
        let anchor = UnitPoint(x: 0.5, y: 0.92)
        return ZStack(alignment: .top) {
            // heat gathering under the flame, then flaring
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: 0xFF8A3D).opacity(0.75), Color(hex: 0xFF8A3D).opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 110))
                .frame(width: 220, height: 120)
                .scaleEffect(Self.kf(t, [(0, 0.4), (0.88, 1), (0.99, 1.6), (1.6, 1.3)]))
                .opacity(Self.kf(t, [(0, 0), (0.88, 0.9), (0.99, 1), (1.6, 0.55)]))
                .offset(y: 180)
            rays(t)
                .offset(y: 150)
            Circle()
                .stroke(Color(hex: 0xFFD43B), lineWidth: 6)
                .frame(width: 40, height: 40)
                .scaleEffect(t < c ? 0.4 : 0.4 + 8.6 * Self.ramp(t, c, c + 0.8, ease: false))
                .opacity(t < c ? 0 : 0.95 * (1 - Self.ramp(t, c, c + 0.8, ease: false)))
                .offset(y: 160)
            // the pillar of fire: three flames far bigger than the real one, rising away
            ForEach(Self.blazes.indices, id: \.self) { i in
                let b = Self.blazes[i]
                let p = (t - c + 0.02 * Double(i)) / 1.3
                let rise = Self.kf(p, [(0, 0), (0.14, 1), (1, 1.2)])
                OmniFlameShape(part: .outline)
                    .fill(Color(hex: b.color))
                    .frame(width: 200, height: 240)
                    .scaleEffect(x: 0.4 + (b.sx - 0.4) * rise, y: 0.4 + (b.sy - 0.4) * rise, anchor: anchor)
                    .offset(y: -30 * Self.ramp(p, 0.14, 1))
                    .opacity(p <= 0 ? 0 : b.opacity * Self.kf(p, [(0, 0), (0.14, 1), (0.55, 0.6), (1, 0)]))
            }
            // the grey flame trembles, squashes and gives way
            OmniFlameDrawing(lit: false, night: night)
                .frame(width: 200, height: 240)
                .rotationEffect(.degrees(Self.kf(t, [(0, 0), (0.095, -3), (0.19, 3), (0.285, -4), (0.38, 4), (0.475, -5),
                                                     (0.57, 5), (0.665, -4), (0.81, 0)])), anchor: anchor)
                .scaleEffect(x: Self.kf(t, [(0, 1), (0.475, 1.05), (0.665, 1.1), (0.81, 1.15), (0.95, 0.6)]),
                             y: Self.kf(t, [(0, 1), (0.475, 0.95), (0.665, 0.86), (0.81, 0.8), (0.95, 0.4)]), anchor: anchor)
                .opacity(Self.kf(t, [(0, 1), (0.81, 1), (0.95, 0)]))
            // the lit flame shoots up and falls back to its size
            let h = t - c
            OmniFlameDrawing(lit: true, night: night)
                .frame(width: 200, height: 240)
                .scaleEffect(x: Self.kf(h, [(0, 0.3), (0.23, 1.7), (0.49, 1.45), (0.8, 1.15), (1.1, 0.92), (1.37, 1.06), (1.63, 0.98), (1.9, 1)]),
                             y: Self.kf(h, [(0, 0.3), (0.23, 2.4), (0.49, 1.8), (0.8, 1.25), (1.1, 1.02), (1.37, 0.97), (1.63, 1.02), (1.9, 1)]),
                             anchor: anchor)
                .opacity(h <= 0 ? 0 : Self.kf(h, [(0, 0), (0.23, 1)]))
            sparks(t)
            fire(t)
        }
        .frame(width: 200, height: 248, alignment: .top)
    }

    private func rays(_ t: Double) -> some View {
        let p = Self.ramp(t, Self.catchTime, Self.catchTime + 2.4, ease: false)
        return ZStack {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFD43B).opacity(0.55), Color(hex: 0xFFD43B).opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 150)
                    .offset(y: -135)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
        }
        .rotationEffect(.degrees(-20 + 45 * p))
        .scaleEffect(0.6 + 0.4 * p)
        .opacity(t < Self.catchTime ? 0 : Self.kf(p, [(0, 0), (0.25, 1), (1, 0.35)]))
    }

    private func sparks(_ t: Double) -> some View {
        ZStack {
            ForEach(Self.sparkDots) { dot in
                Particle(dot: dot.at(t))
            }
        }
        .frame(width: 200)
    }

    /// Embers rising from the fire, round and round, once it has caught.
    private func fire(_ t: Double) -> some View {
        ZStack {
            ForEach(Self.embers) { ember in
                Particle(dot: ember.at(t))
            }
        }
        .frame(width: 200)
    }

    // MARK: - Number, week and button

    private func number(_ t: Double, night: Bool) -> some View {
        let out = Self.ramp(t, 1.7, 2.15)
        let rise = Self.kf(t, [(1.8, 1.1), (2.2, -0.06), (2.5, 0)])
        return ZStack {
            Text(String(previousDays))
                .foregroundStyle(Color(hex: night ? 0x5E6888 : 0xB9C0CB))
                .offset(y: -112 * out)
                .opacity(1 - out)
            Text(String(newDays))
                .foregroundStyle(ink(night))
                .shadow(color: Color(hex: 0xFF9628).opacity(night ? 0.55 : 0.35), radius: 14)
                .offset(y: 112 * rise)
                .opacity(Self.ramp(t, 1.8, 2.0))
        }
        .font(.omniDisplay(108, weight: 800))
        .monospacedDigit()
        .frame(height: 112)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func week(_ t: Double, night: Bool) -> some View {
        let calendar = StreakClock.calendar
        let today = (calendar.component(.weekday, from: Date()) + 5) % 7
        let labels = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"]
        let lit = Color(hex: 0xFF8A3D)
        let empty = Color(hex: night ? 0x2B3457 : 0xE3E9F2)
        return HStack {
            ForEach(0..<7, id: \.self) { i in
                // the streak runs back from today without a gap
                let learned = i < today && today - i < newDays
                let isToday = i == today
                let on = learned || (isToday && t >= 2.7)
                VStack(spacing: 6) {
                    Text(labels[i])
                        .font(.omniBody(11, weight: 700))
                        .foregroundStyle(palette.muted)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white.opacity(on ? 1 : 0))
                        .frame(width: 34, height: 34)
                        .background(on ? lit : empty, in: Circle())
                        .overlay {
                            if isToday { Circle().stroke(lit.opacity(night ? 0.45 : 0.35), lineWidth: 3).padding(-3) }
                        }
                        .scaleEffect(isToday ? Self.kf(t, [(2.7, 0.6), (3.0, 1.25), (3.2, 1)]) : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: palette.cardShadow, radius: 8, y: 4)
    }

    private var continueButton: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button(action: onContinue) {
            Text("Tiếp tục")
                .font(.omniBody(18, weight: 800))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(palette.cta, in: shape)
                .background(palette.ctaShadow, in: shape.offset(y: 5))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 5)
    }

    // MARK: - Colours and timing

    private func ink(_ night: Bool) -> Color { Color(hex: night ? 0xFFB547 : 0xF2711C) }

    @ViewBuilder
    private func warmth(_ night: Bool) -> some View {
        if night {
            RadialGradient(colors: [Color(hex: 0xFF8A3D).opacity(0.3), .clear], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 320)
        } else {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xFFF6E8), Color(hex: 0xFFF1DD)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0xFFBE5A).opacity(0.45), .clear], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 320)
            }
        }
    }

    private static let fireColors: [UInt32] = [0xFFD43B, 0xFF6A3D, 0xFFE38A, 0xFF4B5C, 0xFF8A2A]

    /// The burst of sparks as the fire catches: each flies out once along its own direction.
    private static let sparkDots: [Spark] = (0..<14).map { i in
        let degrees = -90 + (Double(i) - 6.5) * 24 + (i % 2 == 0 ? -6 : 8)
        let sizes: [Double] = [7, 5, 6, 4]
        return Spark(id: i, angle: degrees * .pi / 180, reach: 120 + Double(i % 3) * 34,
                     delay: 0.95 + Double(i % 5) * 0.03, size: sizes[i % 4], color: fireColors[i % 4])
    }

    private static let embers: [Ember] = (0..<34).map { i in
        func r(_ k: Int) -> Double { noise(i * 7 + k) }
        return Ember(id: i, delay: 0.92 + 1.4 * r(1), period: 0.9 + 0.7 * r(2), size: 5 + 9 * r(3),
                     color: fireColors[Int(r(4) * 5) % 5], startX: -50 + 100 * r(5),
                     driftX: -70 + 140 * r(6), rise: 180 + 160 * r(7))
    }
    private static let blazes: [(color: UInt32, opacity: Double, sx: Double, sy: Double)] = [
        (0xFF4B5C, 0.55, 2.6, 3.2), (0xFF8A2A, 0.7, 2.1, 2.7), (0xFFD43B, 0.8, 1.6, 2.1)
    ]

    /// A short hard shake as the fire catches.
    private static func shake(_ t: Double) -> CGSize {
        let p = (t - catchTime) / 0.5
        guard p > 0, p < 1 else { return .zero }
        let x = kf(p, [(0, 0), (0.1, -7), (0.2, 6), (0.3, -6), (0.4, 5), (0.55, -3), (0.7, 2), (0.85, -1), (1, 0)])
        let y = kf(p, [(0, 0), (0.1, 4), (0.2, -5), (0.3, -3), (0.4, 5), (0.55, 2), (0.7, -2), (0.85, 1), (1, 0)])
        return CGSize(width: x, height: y)
    }

    /// 0 before `a`, 1 after `b`, eased in between.
    private static func ramp(_ t: Double, _ a: Double, _ b: Double, ease: Bool = true) -> Double {
        let x = min(1, max(0, (t - a) / (b - a)))
        return ease ? x * x * (3 - 2 * x) : x
    }

    /// Value at `t` along keyframes of (time, value), eased between neighbours and held at both ends.
    private static func kf(_ t: Double, _ frames: [(Double, Double)]) -> Double {
        guard let first = frames.first, let last = frames.last else { return 0 }
        if t <= first.0 { return first.1 }
        if t >= last.0 { return last.1 }
        for (a, b) in zip(frames, frames.dropFirst()) where t <= b.0 {
            return a.1 + (b.1 - a.1) * ramp(t, a.0, b.0)
        }
        return last.1
    }

    /// A steady pseudo-random number in 0..<1 for each seed.
    private static func noise(_ seed: Int) -> Double {
        let v = sin(Double(seed) * 12.9898) * 43758.5453
        return v - floor(v)
    }

    private func playHaptics() async {
        guard OmniSoundSettings.hapticsEnabled, !reduceMotion else { return }
        try? await Task.sleep(for: .milliseconds(900))
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        try? await Task.sleep(for: .milliseconds(900))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Where one spark or ember is at a moment: offset from the top centre of the flame box.
private struct ParticleState {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var scale: Double
    var opacity: Double
    var color: UInt32
}

private struct Particle: View {
    let dot: ParticleState
    var body: some View {
        Capsule()
            .fill(Color(hex: dot.color))
            .frame(width: dot.width, height: dot.height)
            .scaleEffect(dot.scale)
            .offset(x: dot.x, y: dot.y)
            .opacity(dot.opacity)
    }
}

private struct Spark: Identifiable {
    let id: Int
    let angle: Double
    let reach: Double
    let delay: Double
    let size: Double
    let color: UInt32

    func at(_ t: Double) -> ParticleState {
        let x = min(1, max(0, (t - delay) / 1.1))
        let p = x * x * (3 - 2 * x)
        let distance = reach * p
        return ParticleState(x: cos(angle) * distance, y: 170 + sin(angle) * distance, width: size, height: size,
                             scale: 1 - 0.7 * p, opacity: t < delay ? 0 : 1 - p, color: color)
    }
}

private struct Ember: Identifiable {
    let id: Int
    let delay: Double
    let period: Double
    let size: Double
    let color: UInt32
    let startX: Double
    let driftX: Double
    let rise: Double

    func at(_ t: Double) -> ParticleState {
        guard t >= delay else {
            return ParticleState(x: 0, y: 0, width: size, height: size, scale: 1, opacity: 0, color: color)
        }
        let local = (t - delay).truncatingRemainder(dividingBy: period) / period
        let opacity = local < 0.12 ? local / 0.12 : 1 - (local - 0.12) / 0.88
        return ParticleState(x: startX + driftX * local, y: 200 - rise * local, width: size, height: size * 1.3,
                             scale: 1 - 0.8 * local, opacity: opacity, color: color)
    }
}

/// Fades and lifts a part of the screen into place at a given second.
private struct Arrive: ViewModifier {
    let t: Double
    let at: Double
    func body(content: Content) -> some View {
        let p = min(1, max(0, (t - at) / 0.5))
        content
            .opacity(p)
            .offset(y: 14 * (1 - p))
    }
}

// MARK: - Showing it from anywhere

/// Shows the lighting in a window of its own above everything else, so it can play over a lesson,
/// the island or any other full screen, wherever the day's first lesson ends.
@MainActor
final class OmniIgniteCenter {
    static let shared = OmniIgniteCenter()
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?

    /// Plays the lighting the day's first lesson queued, if there is one; `then` runs after Tiếp tục.
    func showPending(then: (() -> Void)? = nil) {
        guard window == nil, let request = StreakActionPresenter.shared.consumeLearning() else { return }
        show(previousDays: request.previousDays, newDays: request.newDays, then: then)
    }

    func show(previousDays: Int, newDays: Int, then: (() -> Void)? = nil) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard window == nil,
              let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        let isExtra = AppInterfaceMode(rawValue: UserDefaults.standard.string(forKey: "development_interface_mode") ?? "") == .extraordinary
        let screen = OmniIgniteView(previousDays: previousDays, newDays: newDays) { [weak self] in
            self?.close()
            then?()
        }
        .modifier(OmniV2Root(isExtra: isExtra))
        let host = UIHostingController(rootView: AnyView(screen))
        host.view.backgroundColor = .clear
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.rootViewController = host
        overlay.alpha = 0
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        overlay.makeKeyAndVisible()
        UIView.animate(withDuration: 0.25) { overlay.alpha = 1 }
        window = overlay
    }

    private func close() {
        guard let overlay = window else { return }
        UIView.animate(withDuration: 0.25, animations: { overlay.alpha = 0 }) { _ in
            overlay.isHidden = true
            self.window = nil
            self.previousKeyWindow?.makeKey()
        }
    }
}
