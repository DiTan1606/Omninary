import SwiftUI

// The look of the exercise screens (from the Học từ vựng demo): chunky cards, 3D buttons, answer
// tiles and word tokens that sit up off the page. White by day; by night the same colours as Học
// ngữ pháp (Professor Gram's lessons): navy paper and surfaces, soft tinted fills for right, near
// and wrong, and buttons edged in a deeper shade of their own colour instead of the ink outline.

struct QuizPalette {
    let dark: Bool
    private var app: OmniPalette { OmniPalette(night: dark, extra: false) }
    var ink: Color { Color(hex: 0x2a2440) }
    var text: Color { app.text }
    var muted: Color { app.muted }
    var card: Color { app.card }
    var line: Color { dark ? Color(hex: 0x2B3457) : Color(hex: 0xd5dde9) }
    var link: Color { dark ? Color(hex: 0x8ee6a4) : Color(hex: 0x2f6fd6) }
    var page: Color { app.background }
    /// Grammar's soft fill (#252c52 at night).
    var soft: Color { dark ? Color(hex: 0x252c52) : Color(hex: 0xeaf0f9) }
    /// The tray a sentence is built in, and its dashed edge.
    var tray: Color { dark ? Color(hex: 0x1b2140) : Color(hex: 0xf8fafd) }
    var trayLine: Color { dark ? Color(hex: 0x4a5482) : Color(hex: 0xc9d2df) }
    /// A word already placed in the sentence (at night, Grammar's chosen option: stage green).
    var placed: (fill: Color, edge: Color, text: Color) {
        dark ? (Color(hex: 0x233e43), Color(hex: 0x34b45a), Color(hex: 0xeef1fb)) : (Color(hex: 0xe3edff), Color(hex: 0x9cc0ff), Color(hex: 0x17202e))
    }
    var empty: Color { dark ? Color(hex: 0x252c52) : Color(hex: 0xdfe5ee) }
    var hint: Color { dark ? Color(hex: 0xe8b93a) : Color(hex: 0x8a5a00) }
    var pill: (fill: Color, edge: Color, text: Color) {
        dark ? (Color(hex: 0x252c52), Color(hex: 0x252c52), Color(hex: 0xa6afc8)) : (Color(hex: 0xefeaff), Color(hex: 0xefeaff), Color(hex: 0x5b3fc9))
    }
    /// The edge of a round 3D button: the ink outline by day, a deeper shade of its colour by night.
    func outline(_ hex: UInt32) -> Color { dark ? QuizPalette.shade(hex, 0.45) : ink }

    /// `hex` darkened by `k` (0…1).
    static func shade(_ hex: UInt32, _ k: Double) -> Color {
        let f = 1 - k
        let r = Double((hex >> 16) & 0xFF) * f, g = Double((hex >> 8) & 0xFF) * f, b = Double(hex & 0xFF) * f
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
    }

    enum Verdict { case ok, near, bad }
    /// The result panel and answer tiles: background, edge and title colour for a verdict.
    func verdict(_ v: Verdict) -> (fill: Color, edge: Color, text: Color) {
        switch (v, dark) {
        case (.ok, false): (Color(hex: 0xdff5e4), Color(hex: 0x34b45a), Color(hex: 0x1f7a37))
        case (.near, false): (Color(hex: 0xfff1d1), Color(hex: 0xf0b429), Color(hex: 0x8a5a00))
        case (.bad, false): (Color(hex: 0xffe4e1), Color(hex: 0xe8463f), Color(hex: 0xb3261e))
        case (.ok, true): (Color(hex: 0x233e43), Color(hex: 0x34b45a), Color(hex: 0x8ee6a4))
        case (.near, true): (Color(hex: 0x403621), Color(hex: 0xe8b93a), Color(hex: 0xe8b93a))
        case (.bad, true): (Color(hex: 0x482b35), Color(hex: 0xffa397), Color(hex: 0xffb4bc))
        }
    }
}

/// One answered question in a quest's progress bar.
enum QuizMark: Int { case none, ok, near, bad, current }

extension View {
    /// A rounded card on the page.
    func quizCard(_ p: QuizPalette, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20).fill(p.card))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(p.line, lineWidth: 1))
    }
}

/// A big 3D button: a gradient face with an ink outline sitting on an ink base that it presses into.
struct Quiz3DButtonStyle: ButtonStyle {
    enum Tone { case blue, green, amber, red, pink }
    var tone: Tone = .blue
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private var colors: (UInt32, UInt32, Color) {
        switch tone {
        case .blue: (0x6fa2ff, 0x2f6fd6, .white)
        case .green: (0x6fdc60, 0x2f9e3a, .white)
        case .amber: (0xffd66b, 0xf0b429, Color(hex: 0x2a2440))
        case .red: (0xff7a72, 0xe8463f, .white)
        case .pink: (0xff8fa6, 0xe8466a, .white)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let (top, bottom, text) = colors, pressed = configuration.isPressed && isEnabled
        // by day the ink outline of the demo; by night, like Grammar's buttons, a deeper shade of their own colour
        let ink = scheme == .dark ? QuizPalette.shade(bottom, 0.45) : Color(hex: 0x2a2440)
        return configuration.label
            .font(.omniDisplay(20))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink, lineWidth: scheme == .dark ? 2 : 3))
            .offset(y: pressed ? 4 : 0)
            .background(RoundedRectangle(cornerRadius: 18).fill(ink).offset(y: 5))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// A multiple-choice answer tile: thicker bottom edge, green or red once answered.
struct QuizTileStyle: ButtonStyle {
    enum State { case idle, ok, bad, dim }
    let state: State
    let palette: QuizPalette

    func makeBody(configuration: Configuration) -> some View {
        let (fill, edge, text): (Color, Color, Color) = switch state {
        case .ok: palette.verdict(.ok)
        case .bad: palette.verdict(.bad)
        case .idle, .dim: (palette.card, palette.line, palette.text)
        }
        let pressed = configuration.isPressed
        return configuration.label
            .font(.omniBody(18, weight: 800))
            .foregroundStyle(text)
            .lineLimit(2).minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 18).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(edge, lineWidth: 2))
            .offset(y: pressed ? 3 : 0)
            .background(RoundedRectangle(cornerRadius: 18).fill(edge).offset(y: 4))
            .opacity(state == .dim ? 0.45 : 1)
    }
}

/// A word token for sentence building.
struct QuizTokenStyle: ButtonStyle {
    let placed: Bool
    let palette: QuizPalette

    func makeBody(configuration: Configuration) -> some View {
        let (fill, edge, text) = placed ? palette.placed : (palette.card, palette.line, palette.text)
        return configuration.label
            .font(.omniBody(17, weight: 700))
            .foregroundStyle(text)
            .lineLimit(1).minimumScaleFactor(0.75)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(edge, lineWidth: 2))
            .offset(y: configuration.isPressed ? 2 : 0)
            .background(RoundedRectangle(cornerRadius: 14).fill(edge).offset(y: 3))
    }
}

/// The quest's questions as segments: green right, amber nearly, red wrong, light blue now.
struct QuizSegments: View {
    let marks: [QuizMark]
    let palette: QuizPalette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
                Capsule().fill(color(m)).frame(height: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Đã làm \(marks.filter { $0 != .none && $0 != .current }.count) trên \(marks.count) câu")
    }

    private func color(_ m: QuizMark) -> Color {
        switch m {
        case .ok: Color(hex: 0x34b45a)
        case .near: Color(hex: 0xf0b429)
        case .bad: Color(hex: 0xe8463f)
        case .current: Color(hex: 0x9cc0ff)
        case .none: palette.empty
        }
    }
}

/// Right answers in a row, as a little flame.
struct QuizStreak: View {
    let count: Int
    var dark = false
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0xff8a1f))
            Text("\(count)").font(.omniDisplay(15)).foregroundStyle(Color(hex: dark ? 0xffb066 : 0xe8731a))
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Color(hex: dark ? 0x403621 : 0xfff1e3), in: Capsule())
        .accessibilityElement().accessibilityLabel("\(count) câu đúng liền")
    }
}

/// A small score bar.
struct QuizScoreBar: View {
    let name: String
    let value: Int
    let palette: QuizPalette
    var nameWidth: CGFloat = 86
    var body: some View {
        HStack(spacing: 8) {
            Text(name).font(.omniBody(12.5, weight: 700)).foregroundStyle(palette.text).frame(width: nameWidth, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(palette.empty)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(hex: value >= 80 ? 0x34b45a : value >= 60 ? 0xf0b429 : 0xe8463f))
                            .frame(width: g.size.width * CGFloat(max(0, min(100, value))) / 100)
                    }
            }
            .frame(height: 8)
            Text("\(value)").font(.omniDisplay(14)).foregroundStyle(palette.text).frame(width: 30, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
        }
        .accessibilityElement().accessibilityLabel("\(name) \(value) điểm")
    }
}

/// Presses a 3D shape down into the ink base drawn under it.
struct QuizPressStyle<S: Shape>: ButtonStyle {
    let shape: S
    var depth: CGFloat = 5
    var base = Color(hex: 0x2a2440)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? depth - 1 : 0)
            .background(shape.fill(base).offset(y: depth))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A ring that grows and fades behind the microphone while recording.
struct MicPulse: View {
    @State private var on = false
    var body: some View {
        Circle()
            .stroke(Color(hex: 0x34b45a).opacity(on ? 0 : 0.5), lineWidth: on ? 2 : 14)
            .scaleEffect(on ? 1.5 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { on = true }
            }
            .accessibilityHidden(true)
    }
}
