import SwiftUI

// One collectible card per word: a short landscape card and a full 63 × 88 card.

enum WordCardStyle {
    static let colors: [String: (UInt32, UInt32)] = [
        "A1": (0xf7f7f2, 0xc9c9bf), "A2": (0x8fe08f, 0x2f9e4f), "B1": (0x8cc6ff, 0x2f6fd6),
        "B2": (0xc6a6ff, 0x6b3fc9), "C1": (0xffc07a, 0xe0662a), "C2": (0xffe596, 0xc4922a)
    ]
    static let none: (UInt32, UInt32) = (0xd5d8dd, 0x8d939d)
    static func pair(_ v: Vocabulary) -> (Color, Color) {
        let p = (v.learning_level ?? 0) == 0 ? none : colors[v.CEFR?.uppercased() ?? ""] ?? colors["B1"]!
        return (Color(hex: p.0), Color(hex: p.1))
    }

    /// Short review status, and how urgent it is (0 plain, 1 due, 2 overdue).
    static func status(_ v: Vocabulary, now: Date = Date()) -> (String, Int) {
        let level = v.learning_level ?? 0
        if level == 0 { return ("Từ mới", 0) }
        guard let next = v.next_review.flatMap(ReviewDates.parse) else { return ("Chưa có lịch", 0) }
        let cal = Calendar.current, days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0
        if days < 0 { return ("Quá hạn \(-days) ngày", 2) }
        if days == 0 || next <= now { return ("Tới hạn hôm nay", 1) }
        return ("Ôn lại sau \(days) ngày", 0)
    }
}

enum ReviewDates {
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoPlain = ISO8601DateFormatter()
    static func parse(_ s: String) -> Date? {
        if let d = iso.date(from: s) ?? isoPlain.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd HH:mm:ssZZZZZ", "yyyy-MM-dd"] {
            f.dateFormat = fmt; if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

struct PixelArtView: View {
    let key: String
    var size: CGFloat = 72
    var body: some View {
        if let img = WordArt.image(key) {
            Image(decorative: img, scale: 1).resizable().interpolation(.none).frame(width: size, height: size)
        }
    }
}

struct CardStars: View {
    let count: Int
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 1) {
            if count == 0 { Text("Từ mới · chưa có sao").font(.omniBody(9.5, weight: 600)).foregroundStyle(Color(hex: 0x5b5568)) }
            ForEach(0..<min(count, 10), id: \.self) { _ in
                Image(systemName: "star.fill").font(.system(size: size * 0.8, weight: .bold)).foregroundStyle(Color(hex: 0xffcc33))
                    .shadow(color: Color(hex: 0x8a5a00), radius: 0, x: 0.5, y: 0.5)
            }
        }
    }
}

struct WordCardView: View {
    enum Mode { case summary, full }
    let vocab: Vocabulary
    var mastery: Int?
    var mode: Mode = .summary
    @State private var sweep = false

    private var level: Int { vocab.learning_level ?? 0 }
    private var art: String { WordArt.key(meaning: vocab.V_meaning, extra: vocab.EV_meaning) }

    var body: some View {
        let (c1, c2) = WordCardStyle.pair(vocab)
        Group {
            if mode == .summary { summary(c1, c2) } else { full(c1, c2) }
        }
        .padding(8)
        .background(LinearGradient(colors: [c1, c2], startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if level >= 6 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: UnitPoint(x: sweep ? 1.4 : -0.6, y: 0), endPoint: UnitPoint(x: sweep ? 1.9 : -0.1, y: 1)))
                    .blendMode(.softLight).allowsHitTesting(false)
                    .onAppear { withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { sweep = true } }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
        .environment(\.colorScheme, .light)
    }

    private func header(_ c2: Color, nameSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vocab.vocab ?? "").font(.omniPixel(nameSize)).foregroundStyle(Color(hex: 0x1d1a24)).lineLimit(2).minimumScaleFactor(0.6)
                Text([vocab.word_form, vocab.IPA].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.omniBody(10, weight: 500)).italic().foregroundStyle(Color(hex: 0x5b5568)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Text("M").font(.omniBody(9, weight: 800)).foregroundStyle(Color(hex: 0x5b5568))
                Text(mastery.map(String.init) ?? "--").font(.omniPixel(nameSize)).monospacedDigit().foregroundStyle(Color(hex: 0x1d1a24))
                Text(vocab.CEFR?.uppercased() ?? "–").font(.omniBody(10, weight: 800)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(c2, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }

    private func artBox(_ c1: Color, _ c2: Color, icon: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [c1.mix(.white, 0.3), c2.mix(.white, 0.45)], center: UnitPoint(x: 0.5, y: 0.6), startRadius: 4, endRadius: 120)
            PixelArtView(key: art, size: icon).saturation(level == 0 ? 0 : 1).opacity(level == 0 ? 0.65 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(c2, lineWidth: 3))
    }

    private func statusText(_ size: CGFloat) -> some View {
        let (text, urgency) = WordCardStyle.status(vocab)
        return Text(text).font(.omniBody(size, weight: urgency > 0 ? 800 : 600))
            .foregroundStyle(urgency == 2 ? Color(hex: 0x8a1f12) : urgency == 1 ? Color(hex: 0xc24a28) : Color(hex: 0x5b5568))
    }

    private func inner<C: View>(_ c1: Color, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(LinearGradient(colors: [c1.mix(Color(hex: 0xfffaf0), 0.7), c1.mix(Color(hex: 0xfffdf7), 0.88)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summary(_ c1: Color, _ c2: Color) -> some View {
        inner(c1) {
            HStack(alignment: .top, spacing: 9) {
                artBox(c1, c2, icon: 72).frame(width: 96, height: 104)
                VStack(alignment: .leading, spacing: 4) {
                    header(c2, nameSize: 19)
                    CardStars(count: level, size: 12)
                    Text(vocab.V_meaning ?? "").font(.omniBody(16, weight: 800)).foregroundStyle(Color(hex: 0x1d1a24)).lineLimit(2)
                    Spacer(minLength: 0)
                    statusText(11)
                }
            }
        }
    }

    private func full(_ c1: Color, _ c2: Color) -> some View {
        inner(c1) {
            VStack(alignment: .leading, spacing: 6) {
                header(c2, nameSize: 22)
                HStack { Spacer(); CardStars(count: level, size: 14) }
                artBox(c1, c2, icon: 96).frame(height: 118)
                HStack(alignment: .firstTextBaseline) {
                    Text(vocab.V_meaning ?? "").font(.omniBody(16, weight: 800)).foregroundStyle(Color(hex: 0x1d1a24)).lineLimit(2)
                    Spacer(minLength: 6)
                    statusText(10)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(LinearGradient(colors: [c2.mix(.white, 0.65), .clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 4))
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                        if let e = vocab.E_meaning, !e.isEmpty { Text(e).font(.omniBody(11.5, weight: 600)).foregroundStyle(Color(hex: 0x1d1a24)) }
                        if let ev = vocab.EV_meaning, !ev.isEmpty { Text(ev).font(.omniBody(11.5, weight: 500)).foregroundStyle(Color(hex: 0x5b5568)) }
                        if let ex = vocab.englishExample {
                            Divider()
                            Text(ex).font(.omniBody(11.5, weight: 600)).italic().foregroundStyle(Color(hex: 0x1d1a24))
                            if let vx = vocab.vietnameseExample { Text(vx).font(.omniBody(11.5, weight: 500)).foregroundStyle(Color(hex: 0x5b5568)) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
        }
        .aspectRatio(63 / 88, contentMode: .fit)
    }
}

extension Color {
    /// Blend toward another colour by `amount` (0 keeps self).
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }
}
