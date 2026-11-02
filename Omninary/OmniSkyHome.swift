import SwiftUI

/// Home in the new interface: the live pixel sky holds one random word from the learner's deck as
/// the centre of the page; a sheet below greets the learner and picks what to study next.
/// The streak and the calendar live on the Streak tab.
struct OmniSkyHomeView: View {
    @Environment(\.omniPalette) private var palette
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var weather = OmniWeather.shared
    @ObservedObject private var freezeManager = OmniStreakFreezeManager.shared
    @State private var pool: [Vocabulary] = []
    @State private var word: Vocabulary?
    /// The module picked in the sheet; none opens the Learning page itself.
    @State private var pickedModule: LearningDashboardWidget?
    /// Ground line of the buildings on screen, where the sun and moon rise and set.
    @State private var horizon: CGFloat?
    // the Home preview in Setting
    @AppStorage(OmniSkyClock.previewKey) private var previewMinutes: Int?
    @AppStorage(OmniWeather.previewKey) private var previewWeather: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                if let word {
                    wordBlock(word)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }
                Spacer(minLength: 8)
                PixelSkyline(night: palette.night, kind: weather.shownKind)
                    .frame(height: 104)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { horizon = $0 }
                    // the sheet covers the foot of the buildings
                    .padding(.bottom, -30)
                    .accessibilityHidden(true)
                todaySheet
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { PixelSkyBackground(fullPage: true, horizon: horizon) }
            .omniStatusBarBackdrop(weather: true)
            .omniTabRoot(.home)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                // a new word every time Home opens
                shuffleWord()
                Task { await load() }
            }
        }
    }

    // MARK: - Sky

    /// Dark ink on a bright day sky; white at night and under rain clouds.
    private var skyInk: Color {
        palette.night || [.drizzle, .rain, .storm].contains(weather.shownKind) ? .white : Color(hex: 0x17202E)
    }

    private var glassFill: Color { skyInk == .white ? Color.white.opacity(0.14) : Color.white.opacity(0.5) }
    private var glassLine: Color { skyInk == .white ? Color.white.opacity(0.22) : Color.white.opacity(0.7) }

    private func wordBlock(_ item: Vocabulary) -> some View {
        let text = item.vocab ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(Self.topicTitle(item).uppercased())
                .font(.omniBody(11, weight: 700))
                .tracking(1.6)
                .opacity(0.8)
            // tap the word to hear it
            Button { SpeechManager.shared.speak(word: text, ipa: item.IPA) } label: {
                Text(text)
                    .font(.omniDisplay(Self.wordSize(text), weight: 800))
                    .tracking(-1)
                    .shadow(color: skyInk == .white ? .black.opacity(0.25) : .white.opacity(0.55), radius: 0, y: 3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text), nghe phát âm")
            HStack(spacing: 8) {
                if let ipa = item.IPA, !ipa.isEmpty { Text(ipa) }
                if let form = item.word_form, !form.isEmpty {
                    Text("·").opacity(0.6)
                    Text(form)
                }
                if let cefr = item.CEFR, !cefr.isEmpty {
                    // the word card's colours: fill with its darker edge underneath
                    let card = Self.cefrColors(cefr)
                    Text(cefr)
                        .font(.omniBody(12, weight: 800))
                        .foregroundStyle(Color(hex: 0x17202E))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(card.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .background(card.edge, in: RoundedRectangle(cornerRadius: 7, style: .continuous).offset(y: 2))
                }
            }
            .font(.omniBody(14, weight: 500))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let meaning = item.V_meaning, !meaning.isEmpty {
                Text(meaning)
                    .font(.omniBody(19, weight: 700))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            Button { withAnimation(.easeInOut(duration: 0.2)) { shuffleWord() } } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(glassFill, in: Circle())
                    .overlay(Circle().stroke(glassLine, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -2)
            .padding(.top, 2)
            .accessibilityLabel("Đổi từ khác")
        }
        .foregroundStyle(skyInk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Today sheet

    private var todaySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TimelineView(.everyMinute) { timeline in
                    greeting(now: OmniSkyClock.now(timeline.date))
                }
                Spacer(minLength: 0)
                streakChip
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Self.modules, id: \.widget) { module in
                        moduleCard(module)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            studyButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(palette.background)
                .shadow(color: palette.cardShadow, radius: 14, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// "Chủ Nhật, 01/11 · Quang đãng" over "Chào buổi tối, Tân" and the version tag.
    private func greeting(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Self.dayTitle(now)) · \(weather.descriptor(night: palette.night))")
                .font(.omniBody(13, weight: 600))
                .foregroundStyle(palette.muted)
            HStack(spacing: 8) {
                Text("\(Self.greeting(now)), \(firstName)")
                    .font(.omniBody(18, weight: 800))
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if palette.extra {
                    OmniExtraChip()
                }
            }
        }
    }

    private var streakChip: some View {
        let days = freezeManager.currentStreak
        let lit = days > 0 && freezeManager.isLearnedToday
        return Button { NotificationCenter.default.post(name: .switchToStreakTab, object: nil) } label: {
            HStack(spacing: 6) {
                PixelFlameImage(flame: lit ? PixelFlame(days: days) : .unlit, height: 20)
                Text(String(days))
                    .font(.omniDisplay(18, weight: 800))
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(palette.card, in: Capsule())
            .shadow(color: palette.cardShadow, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chuỗi \(days) ngày")
    }

    private struct Module {
        let widget: LearningDashboardWidget
        let title: String
        let text: String
        /// Words after "Vào học" on the button once this module is picked.
        let short: String
        let symbol: String
        let tint: (day: UInt32, night: UInt32)
        let ink: (day: UInt32, night: UInt32)
    }

    /// The four Learning modules, in Learning's order.
    private static let modules: [Module] = [
        Module(widget: .vocabulary, title: "Học từ vựng", text: "Phiêu lưu Đảo Từ vựng", short: "từ vựng", symbol: "books.vertical.fill",
               tint: (0xE3EDFF, 0x1E3350), ink: (0x2F6FD6, 0x8CC6FF)),
        Module(widget: .grammar, title: "Học ngữ pháp", text: "Học cùng giáo sư Gram", short: "ngữ pháp", symbol: "text.book.closed.fill",
               tint: (0xDFF5E5, 0x1E3A2A), ink: (0x23893F, 0x8FE0A6)),
        Module(widget: .listening, title: "Luyện nghe", text: "Nghe chép chính tả", short: "luyện nghe", symbol: "headphones",
               tint: (0xFFF3D6, 0x3A3018), ink: (0xB8860B, 0xF2C14E)),
        Module(widget: .shadowing, title: "Shadowing", text: "Luyện âm và ngữ điệu", short: "shadowing", symbol: "waveform.and.mic",
               tint: (0xEEE6FF, 0x2A2F5E), ink: (0x6B4FE0, 0xC9B8FF))
    ]

    /// Tap to pick a module, tap again to let go of it.
    private func moduleCard(_ module: Module) -> some View {
        let night = palette.night
        let on = pickedModule == module.widget
        let tint = Color(hex: night ? module.tint.night : module.tint.day)
        let ink = Color(hex: night ? module.ink.night : module.ink.day)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button {
            if OmniSoundSettings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
            withAnimation(.easeInOut(duration: 0.15)) { pickedModule = on ? nil : module.widget }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 42, height: 42)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(.omniBody(14, weight: 800))
                        .foregroundStyle(palette.text)
                    Text(module.text)
                        .font(.omniBody(11, weight: 500))
                        .foregroundStyle(palette.muted)
                }
                .lineLimit(1)
                // each card is as wide as its own title and line, never cut short
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 74)
            .background(on ? tint : palette.card, in: shape)
            .overlay(shape.stroke(on ? ink : .clear, lineWidth: 2))
            .shadow(color: palette.cardShadow, radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Opens the picked module straight away, or the Learning page when nothing is picked.
    private var studyButton: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let picked = Self.modules.first { $0.widget == pickedModule }
        return Button {
            if let picked {
                NotificationCenter.default.post(name: .openLearningWidget, object: picked.widget.rawValue)
            } else {
                NotificationCenter.default.post(name: .returnToLearningTab, object: nil)
            }
        } label: {
            HStack(spacing: 10) {
                Text(picked.map { "Vào học \($0.short)" } ?? "Vào học ngay")
                    .font(.omniBody(18, weight: 800))
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(palette.cta, in: shape)
            .background(palette.ctaShadow, in: shape.offset(y: 5))
        }
        .buttonStyle(.plain)
        // room for the 3D edge, plus a gap above the tab bar
        .padding(.bottom, 17)
    }

    // MARK: - Data

    /// Loads the learner's deck for the random word.
    /// Someone with an empty deck still gets words, from the system topics.
    private func load() async {
        guard let userID = auth.currentUser?.id.uuidString else { return }
        var vocabs = (try? await VocabularyRepository.fetchUserVocabs(userId: userID)) ?? []
        if vocabs.isEmpty {
            vocabs = (try? await VocabularyRepository.fetchSystemVocabs(adminUserId: AppConfig.adminUserId)) ?? []
        }
        pool = vocabs.filter { !($0.vocab ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        if word == nil { shuffleWord() }
    }

    private func shuffleWord() {
        guard !pool.isEmpty else { return }
        if pool.count == 1 { word = pool[0]; return }
        var next = pool.randomElement()
        // try a few times for a different word; a deck of duplicates simply repeats
        for _ in 0..<8 where next?.vocab == word?.vocab && next?.V_meaning == word?.V_meaning {
            next = pool.randomElement()
        }
        word = next
    }

    // MARK: - Text helpers

    private var firstName: String {
        let name = auth.displayName.trimmingCharacters(in: .whitespaces)
        return name.split(separator: " ").last.map(String.init) ?? name
    }

    private static func greeting(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "Chào buổi sáng"
        case 11..<13: "Chào buổi trưa"
        case 13..<18: "Chào buổi chiều"
        case 18..<23: "Chào buổi tối"
        default: "Khuya rồi đó"
        }
    }

    /// "Chủ Nhật, 01/11"
    private static func dayTitle(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .day, .month], from: date)
        let weekday = c.weekday == 1 ? "Chủ Nhật" : "Thứ \(["Hai", "Ba", "Tư", "Năm", "Sáu", "Bảy"][(c.weekday ?? 2) - 2])"
        return String(format: "%@, %02d/%02d", weekday, c.day ?? 1, c.month ?? 1)
    }

    private static func topicTitle(_ item: Vocabulary) -> String {
        let topic = item.topics?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return topic?.isEmpty == false ? topic! : "Từ của bạn"
    }

    /// Long entries such as idioms get a smaller size so they stay on two lines, and the size
    /// shrinks further until the longest single word fits on one line, so no word is ever split.
    private static func wordSize(_ text: String) -> CGFloat {
        let base: CGFloat = text.count > 16 ? 46 : text.count > 9 ? 60 : 76
        let longest = text.split(separator: " ").map(\.count).max() ?? text.count
        // Baloo 2 ExtraBold runs about 0.56 em a letter; the word block is inset 24 pt each side
        let line = UIScreen.main.bounds.width - 48
        return min(base, (line / (CGFloat(max(longest, 1)) * 0.56)).rounded(.down))
    }

    /// Same colours as the word cards: A1 white, A2 green, B1 blue, B2 purple, C1 orange, C2 gold.
    private static func cefrColors(_ level: String) -> (fill: Color, edge: Color) {
        let pair = WordCardStyle.colors[level.uppercased()] ?? WordCardStyle.none
        return (Color(hex: pair.0), Color(hex: pair.1))
    }
}

// MARK: - Pixel skyline

/// A row of pixel buildings along the horizon, tinted from the sky's lowest band.
/// At night some windows are lit (fewer late at night).
private struct PixelSkyline: View {
    let night: Bool
    let kind: OmniWeatherKind

    /// x, width and height in sky units (the sky is 195 units wide).
    private static let buildings: [(x: CGFloat, w: CGFloat, h: CGFloat, antenna: Bool)] = [
        (-3, 27, 35, false), (22, 20, 48, true), (40, 31, 29, false), (69, 23, 42, false),
        (90, 35, 33, false), (123, 19, 51, true), (140, 29, 40, false), (167, 31, 28, false)
    ]

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 195
            let ground = size.height / unit
            let wet = [.drizzle, .rain, .storm].contains(kind)
            let base = OmniSky.bands(night: night, kind: kind, at: OmniSkyClock.now()).last ?? 0x7B8FA2
            let body = night ? Color(hex: 0x0A0E1C) : Color(hex: OmniSky.mix(base, 0x1F2A44, wet ? 0.55 : 0.45))
            let hour = Calendar.current.component(.hour, from: OmniSkyClock.now())
            let litShare = hour >= 23 || hour < 5 ? 0.28 : 0.55

            func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                let rect = CGRect(x: (x * unit).rounded(), y: (y * unit).rounded(),
                                  width: (w * unit).rounded(), height: (h * unit).rounded())
                context.fill(Path(rect), with: .color(color))
            }

            for (i, b) in Self.buildings.enumerated() {
                let top = ground - b.h
                fill(b.x, top, b.w, b.h, body)
                if b.antenna { fill(b.x + 4, top - 7, 1.5, 7, body) }
                guard night else { continue }
                var row = 0
                while top + 6 + CGFloat(row) * 7 + 3 < ground {
                    var col = 0
                    while b.x + 4 + CGFloat(col) * 7 + 3 < b.x + b.w - 2 {
                        if Self.hash(i * 31 + row * 7 + col) < litShare {
                            fill(b.x + 4 + CGFloat(col) * 7, top + 6 + CGFloat(row) * 7, 3, 3, Color(hex: 0xF3D27A))
                        }
                        col += 1
                    }
                    row += 1
                }
            }
        }
    }

    private static func hash(_ i: Int) -> Double {
        let v = sin(Double(i) * 12.9898) * 43758.5453
        return v - floor(v)
    }

}
