import SwiftUI

// One collectible card per word: a short landscape card and a full 63 × 88 card.

enum WordCardStyle {
    static let colors: [String: (UInt32, UInt32)] = [
        "A1": (0xf7f7f2, 0xc9c9bf), "A2": (0x8fe08f, 0x2f9e4f), "B1": (0x8cc6ff, 0x2f6fd6),
        "B2": (0xc6a6ff, 0x6b3fc9), "C1": (0xffc07a, 0xe0662a), "C2": (0xffe596, 0xc4922a)
    ]
    static let none: (UInt32, UInt32) = (0xd5d8dd, 0x8d939d)
    /// `rarity` shows the CEFR colours even before the word is learned (opening a printed card).
    static func pair(_ v: Vocabulary, rarity: Bool = false) -> (Color, Color) {
        let p = (v.learning_level ?? 0) == 0 && !rarity ? none : colors[v.CEFR?.uppercased() ?? ""] ?? colors["B1"]!
        return (Color(hex: p.0), Color(hex: p.1))
    }

    /// Short review status, and how urgent it is (0 plain, 1 due, 2 overdue).
    static func status(_ v: Vocabulary, now: Date = Date()) -> (String, Int) {
        let level = v.learning_level ?? 0
        if level == 0 { return ("Từ mới", 0) }
        guard let next = v.next_review.flatMap(ReviewDates.parse) else { return ("Chưa có lịch", 0) }
        let cal = Calendar.current, days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0
        if days < 0 { return ("Quá hạn \(-days) ngày", 2) }
        if days == 0 || next <= now { return ("Đến hạn ôn tập", 1) }
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
    /// The printed card size: 63 × 88 mm at 300 pt wide.
    static let fullSize = CGSize(width: 300, height: 300 * 88 / 63)

    let vocab: Vocabulary
    var mastery: Int?
    var mode: Mode = .summary
    /// Show the CEFR colours of a word not learned yet, as when a printed card is opened.
    var rarity = false
    /// Tapping the card reads the word aloud, wherever the card is shown.
    var speaksOnTap = true
    @State private var sweep = false

    private var level: Int { vocab.learning_level ?? 0 }
    private var grey: Bool { level == 0 && !rarity }
    private static let ink = Color(hex: 0x1d1a24), muted = Color(hex: 0x5b5568)

    var body: some View {
        let (c1, c2) = WordCardStyle.pair(vocab, rarity: rarity)
        Group {
            if mode == .summary { summary(c1, c2) } else { full(c1, c2) }
        }
        // thick coloured border, as on the printed card (about 3 mm of a 63 mm card)
        .padding(mode == .full ? 14 : 11)
        .background(LinearGradient(colors: [c1, c2], startPoint: UnitPoint(x: 0.1, y: 0), endPoint: UnitPoint(x: 0.9, y: 1)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if level >= 6 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: UnitPoint(x: sweep ? 1.4 : -0.6, y: 0), endPoint: UnitPoint(x: sweep ? 1.9 : -0.1, y: 1)))
                    .blendMode(.softLight).allowsHitTesting(false)
                    .onAppear { withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) { sweep = true } }
            }
        }
        .frame(width: mode == .full ? Self.fullSize.width : nil, height: mode == .full ? Self.fullSize.height : nil)
        .omniCardShadow(radius: 16)
        .environment(\.colorScheme, .light)
        // Only the full card reads aloud: a tap anywhere reads the word, a tap on the English example
        // reads the sentence (the example's own tap wins over this one). The gesture is switched off
        // on summary cards, so a summary card inside a button opens its word with a single tap.
        .gesture(TapGesture().onEnded {
            SpeechManager.shared.speak(word: vocab.vocab ?? "", ipa: vocab.IPA)
        }, including: speaksOnTap && mode == .full ? .all : .subviews)
    }

    /// The headword: a rounded display face with a hard one-pixel shadow, easier to read than a pixel font.
    private func word(_ size: CGFloat) -> some View {
        Text(vocab.vocab ?? "")
            .font(OmniFonts.font(.baloo, 800, size: size))
            .foregroundStyle(Self.ink)
            .shadow(color: .white.opacity(0.9), radius: 0, x: 1, y: 1)
            .lineLimit(1).minimumScaleFactor(0.45)
            .accessibilityIdentifier("word-card-word")
    }

    private var formAndIPA: String {
        [vocab.word_form, vocab.IPA].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private func masteryBadge(_ c2: Color, numberSize: CGFloat) -> some View {
        HStack(spacing: 5) {
            Text("M").font(.omniBody(9, weight: 800)).foregroundStyle(Self.muted)
            Text(mastery.map(String.init) ?? "--").font(OmniFonts.font(.silkscreen, 700, size: numberSize)).monospacedDigit().foregroundStyle(Self.ink)
            Text(vocab.CEFR?.uppercased() ?? "–").font(.omniBody(10, weight: 800)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(c2, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
                .accessibilityLabel("Cấp độ \(vocab.CEFR ?? "")")
        }
    }

    private func artBox(_ c1: Color, _ c2: Color, icon: CGFloat) -> some View {
        ZStack {
            RadialGradient(colors: [c1.mix(.white, 0.3), c2.mix(.white, 0.45)], center: UnitPoint(x: 0.5, y: 0.6), startRadius: 4, endRadius: 120)
            WordPictureView(vocab: vocab, size: icon).saturation(grey ? 0 : 1).opacity(grey ? 0.65 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(c2, lineWidth: 3))
    }

    /// Review status on the summary card: "Từ mới", "Đến hạn ôn tập" (orange), "Quá hạn … ngày" (red).
    private func statusText(_ size: CGFloat) -> some View {
        let (text, urgency) = WordCardStyle.status(vocab)
        return Text(text).font(.omniBody(size, weight: urgency > 0 ? 800 : 600))
            .foregroundStyle(urgency == 2 ? Color(hex: 0x8a1f12) : urgency == 1 ? Color(hex: 0xc24a28) : Self.muted)
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
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            word(20)
                            Text(formAndIPA).font(.omniBody(10, weight: 500)).italic().foregroundStyle(Self.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        masteryBadge(c2, numberSize: 15)
                    }
                    CardStars(count: level, size: 12)
                    Text(vocab.V_meaning ?? "").font(.omniBody(16, weight: 800)).foregroundStyle(Self.ink).lineLimit(2).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    statusText(11)
                }
            }
        }
    }

    private func full(_ c1: Color, _ c2: Color) -> some View {
        inner(c1) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    word(24)
                    Spacer(minLength: 4)
                    masteryBadge(c2, numberSize: 17)
                }
                HStack(spacing: 4) {
                    Text(formAndIPA).font(.omniBody(10.5, weight: 500)).italic().foregroundStyle(Self.muted).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    CardStars(count: level, size: 12)
                }
                artBox(c1, c2, icon: 84).frame(height: 98)
                // the whole row is the meaning; the review status lives in the word page, not on the card
                Text(vocab.V_meaning ?? "")
                    .font(.omniBody(18, weight: 800)).foregroundStyle(Self.ink)
                    .lineLimit(2).minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("word-card-meaning")
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(LinearGradient(colors: [c2.mix(.white, 0.65), .clear], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 4))
                ViewThatFits(in: .vertical) {
                    ForEach([11.5, 11, 10.5, 10, 9.5, 9, 8.5, 8], id: \.self) { size in details(CGFloat(size), highlight: WordCardStyle.cefrPair(vocab.CEFR).1) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                footer
            }
        }
    }

    /// English definition, its translation and the example pair, at the largest size that fits the space left.
    /// English meaning and example in bold (the word itself in the CEFR colour), Vietnamese in italics,
    /// as on the printed card.
    private func details(_ size: CGFloat, highlight: Color) -> some View {
        VStack(alignment: .leading, spacing: size * 0.35) {
            Rectangle().fill(Self.muted.opacity(0.18)).frame(height: 1)
            if let e = Vocabulary.normalizedExample(vocab.E_meaning) {
                Text(e).font(.omniBody(size, weight: 700)).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let ev = Vocabulary.normalizedExample(vocab.EV_meaning) {
                Text(ev).font(.omniBody(size, weight: 500)).italic().foregroundStyle(Self.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let ex = vocab.englishExample {
                Rectangle().fill(Self.muted.opacity(0.18)).frame(height: 1)
                Text(highlighted(ex, size: size, color: highlight)).font(.omniBody(size, weight: 700)).foregroundStyle(Self.ink).fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard speaksOnTap else { return }
                        SpeechManager.shared.speak(example: ex, targetWord: vocab.vocab ?? "", ipa: vocab.IPA)
                    }
                if let vx = vocab.vietnameseExample {
                    Text(vx).font(.omniBody(size, weight: 500)).italic().foregroundStyle(Self.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlighted(_ sentence: String, size: CGFloat, color: Color) -> AttributedString {
        var result = AttributedString(sentence)
        for range in VocabularyExampleHighlight.ranges(in: sentence, target: vocab.vocab ?? "") {
            if let r = Range(range, in: result) {
                result[r].font = .omniBody(size, weight: 800)
                result[r].foregroundColor = color
            }
        }
        return result
    }

    @ViewBuilder
    private var footer: some View {
        if let number = vocab.card_no {
            HStack(alignment: .bottom, spacing: 6) {
                Text("OMNINARY").font(OmniFonts.font(.silkscreen, 400, size: 8)).foregroundStyle(Self.muted.opacity(0.7))
                Spacer(minLength: 4)
                Text("#\(number)").font(.omniBody(12, weight: 800)).monospacedDigit().foregroundStyle(Self.ink)
                    .accessibilityLabel("Thẻ số \(number)")
            }
        }
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
