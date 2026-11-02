import SwiftUI
import CoreText

// MARK: - New interface (v2): modern chrome, pixel imagery, day/night by the real clock

/// Turns the new interface on or off so the old and new screens can be compared side by side.
enum OmniInterfaceVersion {
    static let storageKey = "ui_v2_enabled"
}

/// Light or dark: follows the clock by default (6:00 to 18:00 is day), or stays fixed.
enum OmniAppearanceMode: String, CaseIterable, Identifiable {
    case auto, light, dark
    static let storageKey = "appearance_mode"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Tự động"
        case .light: "Luôn sáng"
        case .dark: "Luôn tối"
        }
    }

    /// Automatic follows the real sun at the learner's place (Open-Meteo `is_day`); before the first
    /// weather fetch, or with the weather sky turned off, it falls back to the clock (6:00 to 18:00 is day).
    func isNight(at date: Date = Date(), isDay: Bool? = nil) -> Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .auto:
            if let isDay { return !isDay }
            let hour = Calendar.current.component(.hour, from: date)
            return hour < 6 || hour >= 18
        }
    }
}

private struct OmniV2Key: EnvironmentKey { static let defaultValue = false }
private struct OmniNightKey: EnvironmentKey { static let defaultValue = false }
private struct OmniExtraKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when the new interface is on.
    var omniV2: Bool { get { self[OmniV2Key.self] } set { self[OmniV2Key.self] = newValue } }
    /// True when the new interface is showing its night palette.
    var omniNight: Bool { get { self[OmniNightKey.self] } set { self[OmniNightKey.self] = newValue } }
    /// True when the learner is on Extraordinary.
    var omniExtra: Bool { get { self[OmniExtraKey.self] } set { self[OmniExtraKey.self] = newValue } }
    var omniPalette: OmniPalette { OmniPalette(night: omniNight, extra: omniExtra) }
}

// MARK: - Palette

struct OmniPalette {
    let night: Bool
    let extra: Bool

    var background: Color { night ? Color(hex: 0x10142A) : Color(hex: 0xEEF3FB) }
    var card: Color { night ? Color(hex: 0x1B2140) : .white }
    var line: Color { night ? Color(hex: 0x2B3457) : Color(hex: 0xE3E9F2) }
    var panel: Color { night ? Color(hex: 0x252C52) : Color(hex: 0xEEF3FB) }
    var text: Color { night ? Color(hex: 0xEEF1FB) : Color(hex: 0x17202E) }
    var muted: Color { night ? Color(hex: 0xA6AFC8) : Color(hex: 0x5B6779) }
    var cta: Color { Color(hex: 0x34B45A) }
    var ctaShadow: Color { Color(hex: 0x23893F) }
    var selected: Color { Color(hex: 0x2F6FD6) }
    var gold: Color { Color(hex: 0xE8B93A) }
    var shadow: Color { night ? .black.opacity(0.45) : Color(red: 20 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18) }
    var cardShadow: Color { night ? .black.opacity(0.26) : Color(hex: 0x142850).opacity(0.10) }
    var versionTint: Color { night ? Color(hex: 0x8FE0A6) : Color(hex: 0x2F9E4F) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Fonts

/// Registers the bundled fonts once and maps family + weight to the PostScript name.
enum OmniFonts {
    enum Family: String { case baloo = "Baloo2", vietnam = "BeVietnamPro", pixelify = "PixelifySans", silkscreen = "Silkscreen" }

    private static var names: [String: String] = [:]
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            guard let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(font, &error)
            if let name = font.postScriptName as String? { names[url.deletingPathExtension().lastPathComponent] = name }
        }
    }

    static func font(_ family: Family, _ weight: Int, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        register()
        let available: [Int]
        switch family {
        case .baloo: available = [600, 700, 800]
        case .vietnam: available = [400, 500, 600, 700, 800]
        case .pixelify: available = [500, 700]
        case .silkscreen: available = [400, 700]
        }
        let pick = available.min(by: { abs($0 - weight) < abs($1 - weight) }) ?? available[0]
        guard let name = names["\(family.rawValue)-\(pick)"] else { return .system(size: size, weight: .bold, design: .rounded) }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension Font {
    /// Rounded display face for numbers and headings.
    static func omniDisplay(_ size: CGFloat, weight: Int = 800) -> Font { OmniFonts.font(.baloo, weight, size: size, relativeTo: .title) }
    /// Body face for running text.
    static func omniBody(_ size: CGFloat, weight: Int = 500) -> Font { OmniFonts.font(.vietnam, weight, size: size) }
}

// MARK: - Root modifier: decides v2, night and Extra once for the whole tree

struct OmniV2Root: ViewModifier {
    @AppStorage(OmniInterfaceVersion.storageKey) private var v2Enabled = true
    @AppStorage(OmniAppearanceMode.storageKey) private var appearanceRaw = OmniAppearanceMode.auto.rawValue
    @ObservedObject private var weather = OmniWeather.shared
    // read here so a Home preview set in Setting redraws the whole tree
    @AppStorage(OmniSkyClock.previewKey) private var previewMinutes: Int?
    @AppStorage(OmniWeather.previewKey) private var previewWeather: String?
    let isExtra: Bool

    func body(content: Content) -> some View {
        TimelineView(.everyMinute) { context in
            // a previewed time decides day and night by the clock alone
            let isDay = weather.isEnabled && previewMinutes == nil ? weather.isDay : nil
            let night = (OmniAppearanceMode(rawValue: appearanceRaw) ?? .auto).isNight(at: OmniSkyClock.now(context.date), isDay: isDay)
            let palette = OmniPalette(night: v2Enabled && night, extra: isExtra)
            content
                .environment(\.omniV2, v2Enabled)
                .environment(\.omniNight, v2Enabled && night)
                .environment(\.omniExtra, isExtra)
                .preferredColorScheme(v2Enabled ? (night ? .dark : .light) : nil)
                .tint(v2Enabled ? palette.selected : (isExtra ? ExtraAuroraPalette.electricBlue : Color.blue))
        }
    }
}

// MARK: - Surfaces and controls

/// A single soft shadow beneath the card silhouette, independent of its text and artwork.
struct OmniCardShadowModifier: ViewModifier {
    @Environment(\.omniPalette) private var palette
    var radius: CGFloat
    var enabled = true

    func body(content: Content) -> some View {
        content.background {
            if enabled {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(palette.cardShadow)
                    .blur(radius: 4)
                    .offset(y: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct OmniCardModifier: ViewModifier {
    @Environment(\.omniPalette) private var palette
    var padding: CGFloat = 16
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(palette.line, lineWidth: 1))
            .omniCardShadow(radius: radius)
    }
}

extension View {
    func omniCardShadow(radius: CGFloat = 20, enabled: Bool = true) -> some View { modifier(OmniCardShadowModifier(radius: radius, enabled: enabled)) }
    func omniCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View { modifier(OmniCardModifier(padding: padding, radius: radius)) }
}

/// Title of a tab's first page. It sits in the middle of the second colour band of the static sky
/// and leaves the first card to start just inside the third band, on every phone size.
/// The parent stack uses spacing 12 and no top padding.
struct OmniPageTitle: View {
    @Environment(\.omniPalette) private var palette
    let text: String
    init(_ text: String) { self.text = text }

    /// Height of one sky band in points (same maths as the static sky painter: 280 units, 6 bands).
    private static var band: CGFloat {
        let unit = UIScreen.main.bounds.width / 195
        return (280 * 0.75 / 6).rounded(.up) * unit
    }
    private static var safeTop: CGFloat {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets.top ?? 59
    }

    var body: some View {
        let height: CGFloat = 38
        let titleTop = band(1.5) - height / 2 + 6
        let cardTop = band(2) + 12
        Text(text)
            .font(.omniDisplay(36, weight: 800))
            .foregroundStyle(palette.night ? Color.white : Color(hex: 0x17202E))
            .frame(height: height)
            .padding(.leading, 4)
            .padding(.top, max(8, titleTop - Self.safeTop))
            .padding(.bottom, max(8, cardTop - titleTop - height - 12))
            .accessibilityAddTraits(.isHeader)
    }

    private func band(_ n: CGFloat) -> CGFloat { Self.band * n }
}

/// Uppercase section label, as in "CHUỖI HỌC TẬP".
struct OmniSectionLabel: View {
    @Environment(\.omniPalette) private var palette
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.omniBody(12.5, weight: 800))
            .tracking(0.8)
            .foregroundStyle(palette.muted)
    }
}

/// Green 3D primary button.
struct OmniPrimaryButtonStyle: ButtonStyle {
    @Environment(\.omniPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.omniDisplay(17, weight: 800))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(palette.cta, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(palette.ctaShadow, in: RoundedRectangle(cornerRadius: 14, style: .continuous).offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Extra marks: the app keeps its colours, Extra shows through a chip and a thin gradient edge

enum OmniExtraStyle {
    static let violet = Color(hex: 0x7C5CFF)
    static let ink = Color(hex: 0x17202E)
    /// Navy of the night pixel Omnicon, for Extraordinary sales cards.
    static let navy = Color(hex: 0x1F2550)
    /// Edge of the cards that only Extra learners have.
    static let edge = LinearGradient(colors: [violet, Color(hex: 0x2F6FD6), Color(hex: 0xE8B93A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let chipEdge = LinearGradient(colors: [violet, Color(hex: 0xE8B93A)], startPoint: .leading, endPoint: .trailing)
}

/// Dark "EXTRA" chip with a gold star; a light streak crosses it every few seconds.
struct OmniExtraChip: View {
    var large = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine = false

    var body: some View {
        HStack(spacing: large ? 5 : 4) {
            Image(systemName: "sparkle")
                .font(.system(size: large ? 11 : 9, weight: .black))
                .foregroundStyle(Color(hex: 0xE8B93A))
            Text("EXTRA")
                .font(.omniBody(large ? 11 : 10, weight: 800))
                .kerning(large ? 1.6 : 1.4)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, large ? 10 : 8)
        .frame(height: large ? 24 : 20)
        .background(OmniExtraStyle.ink, in: Capsule())
        .overlay {
            GeometryReader { proxy in
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 0.4)
                    .rotationEffect(.degrees(10))
                    .offset(x: shine ? proxy.size.width * 1.3 : -proxy.size.width * 0.6)
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
        }
        .overlay(Capsule().strokeBorder(OmniExtraStyle.chipEdge, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Extra")
        .task {
            guard !reduceMotion else { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            while !Task.isCancelled {
                withTransaction(reset) { shine = false }
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeInOut(duration: 1.6)) { shine = true }
                try? await Task.sleep(for: .seconds(3.15))
            }
        }
    }
}

extension View {
    /// Thin violet → blue → gold edge for a card that belongs to Extra.
    func omniExtraEdge(radius: CGFloat, lineWidth: CGFloat = 1.5) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(OmniExtraStyle.edge, lineWidth: lineWidth))
    }
}

// MARK: - Pixel icons (12 × 12 hand-drawn), shared with the demo

struct PixelIcon: View {
    let name: String
    let size: CGFloat
    init(_ name: String, size: CGFloat = 24) { self.name = name; self.size = size }

    private static let palette: [Character: Color] = [
        "k": Color(hex: 0x2B2238), "w": .white, "r": Color(hex: 0xE0453A), "R": Color(hex: 0xA8282A), "o": Color(hex: 0xF08A24),
        "y": Color(hex: 0xF4C542), "B": Color(hex: 0x2F6FD6), "l": Color(hex: 0x8CCDF7), "g": Color(hex: 0x58B84A), "G": Color(hex: 0x2F7D3A),
        "c": Color(hex: 0xFFF4D6), "b": Color(hex: 0x8A5A2B), "m": Color(hex: 0x9AA2B2), "p": Color(hex: 0x9A5FD6), "P": Color(hex: 0x5B2D91), "h": Color(hex: 0xC98A4B)
    ]

    static let art: [String: [String]] = [
        "home": [".....kk.....", "....krrk....", "...krrrrk...", "..krrrrrrk..", ".krrrrrrrrk.", "kkcccccccckk", ".kcccccccck.", ".kcBBcbbcck.", ".kcBBcbbcck.", ".kccccbbcck.", ".kkkkkkkkkk.", "............"],
        "book": ["............", ".kkkk..kkkk.", "kwwwwkkwwwwk", "kwBBwkkwBBwk", "kwwwwkkwwwwk", "kwBBwkkwBBwk", "kwwwwkkwwwwk", "kwBwwkkwwBwk", "kwwwwkkwwwwk", ".kkkkbbkkkk.", ".....bb.....", "............"],
        "omni": ["....kkkk....", "..kkBBBBkk..", ".kBBllllBBk.", ".kBl....lBk.", "kBl......lBk", "kBl..yy..lBk", "kBl..yy..lBk", "kBl......lBk", ".kBl....lBk.", ".kBBllllBBk.", "..kkBBBBkk..", "....kkkk...."],
        "gear": [".....kk.....", "..k.kmmk.k..", ".kmkmmmmkmk.", "..kmmmmmmk..", ".kmmmkkmmmk.", "kmmmk..kmmmk", "kmmmk..kmmmk", ".kmmmkkmmmk.", "..kmmmmmmk..", ".kmkmmmmkmk.", "..k.kmmk.k..", ".....kk....."],
        "flame": [".....r......", "....rr......", "....ror..r..", "...roor.rr..", "..rooorroor.", "..roooyyoor.", ".rooyyyyyor.", ".royyywyyor.", ".royywwyyor.", ".rooyyyyoor.", "..rroooorr..", "....rrrr...."],
        "flameB": [".....l......", "....ll......", "....lBl..l..", "...lBBl.ll..", "..lBBBllBBl.", "..lBBBwwBBl.", ".lBBwwwwwBl.", ".lBwwwwwwBl.", ".lBwwwwwwBl.", ".lBBwwwwBBl.", "..llBBBBll..", "....llll...."],
        "heart": ["............", ".rrr...rrr..", "rwwrr.rrrrr.", "rwrrrrrrrrr.", "rrrrrrrrrRr.", "rrrrrrrrRRr.", ".rrrrrrrRr..", "..rrrrrRr...", "...rrrRr....", "....rRr.....", ".....r......", "............"],
        "coin": ["...kkkkkk...", "..kyyyyyyk..", ".kyywwyyyyk.", "kyywyyyyyyok", "kyywyyyyyyok", "kyyyyyyyyyok", "kyyyyyyyyyok", "kyyyyyyyyook", ".kyyyyyyyok.", "..kyoooook..", "...kkkkkk...", "............"],
        "cal": ["..k....k....", ".kkkkkkkkkk.", ".krrrrrrrrk.", ".kkkkkkkkkk.", ".kwwwwwwwwk.", ".kwkwkwkwwk.", ".kwwwwwwwwk.", ".kwkwkwrwwk.", ".kwwwwwwwwk.", ".kwkwkwkwwk.", ".kkkkkkkkkk.", "............"],
        "head": ["...kkkkkk...", "..k......k..", ".k........k.", ".k........k.", "k..........k", "kk........kk", "kBk......kBk", "kBBk....kBBk", "kBBk....kBBk", "kBk......kBk", ".k........k.", "............"],
        "bell": [".....kk.....", "....kyyk....", "...kyyyyk...", "...kyyyyk...", "..kyyyyyyk..", "..kyyyyyyk..", ".kyyyyyyyyk.", "kkkkkkkkkkkk", ".....kk.....", "............"],
        "snow": ["....l.....", ".l..l..l..", "..l.l.l...", "...lBl....", "lllBwBlll.", "...lBl....", "..l.l.l...", ".l..l..l..", "....l.....", ".........."],
        "music": ["......kkkk..", "......kppk..", "......k..k..", "......k..k..", "......k..k..", "...kkkk.kk..", "..kpppk.....", "..kpppk.....", "...kkk......"],
        "spark": [".....y......", ".....y......", "....yyy.....", "yyyyywyyyyy.", "....yyy.....", ".....y......", ".....y......"],
        "door": ["..........", "..kkkkkk..", "..kbbbbk..", "..kbhbbk..", "..kbbbbk..", "..kbbbyk..", "..kbbbbk..", "..kbbbbk..", "..kkkkkk..", ".........."],
        "back": ["............", "....kk......", "...kwk......", "..kwwkkkkkk.", ".kwwwwwwwwk.", "..kwwkkkkkk.", "...kwk......", "....kk......", "............"],
        "mic": ["....kkkk....", "...kmmmmk...", "...kmwmmk...", "...kmmmmk...", "...kmmmmk...", ".k.kmmmmk.k.", ".k..kkkk..k.", "..k......k..", "...kkkkkk...", ".....kk.....", "...kkkkkk...", "............"],
        "headphones": ["................", ".....BBBBBB.....", "...BBllllllBB...", "..Bll......llB..", ".Bl..........lB.", ".Bl..........lB.", "Bl............lB", "Bl............lB", "BBBB........BBBB", "BcoB........BcoB", "BooB........BooB", "BooB........BooB", "BooB........BooB", "BBBB........BBBB"],
        "compass": ["....kkkk....", "..kkwwwwkk..", ".kwwwrrwwwk.", ".kwwwrrwwwk.", "kwwwrrrrwwwk", "kwwwwkkwwwwk", "kwwwwkkwwwwk", "kwwwBBBBwwwk", ".kwwwBBwwwk.", ".kwwwBBwwwk.", "..kkwwwwkk..", "....kkkk...."],
        "check": ["..........k", ".........kk", "........kk.", "k......kk..", "kk....kk...", ".kk..kk....", "..kkkk.....", "...kk......"]
    ]

    var body: some View {
        let rows = Self.art[name] ?? []
        let w = rows.map(\.count).max() ?? 1, h = max(rows.count, 1)
        Canvas(rendersAsynchronously: false) { context, canvas in
            let cell = min(canvas.width / CGFloat(w), canvas.height / CGFloat(h))
            let ox = (canvas.width - cell * CGFloat(w)) / 2, oy = (canvas.height - cell * CGFloat(h)) / 2
            for (j, row) in rows.enumerated() {
                for (i, ch) in row.enumerated() {
                    guard let color = Self.palette[ch] else { continue }
                    context.fill(Path(CGRect(x: ox + CGFloat(i) * cell, y: oy + CGFloat(j) * cell, width: cell + 0.3, height: cell + 0.3)), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Sky clock

/// The time the sky and Home show. Setting's Home preview card can pin it to a chosen time of day
/// (minutes after midnight); without that it is the real time.
enum OmniSkyClock {
    static let previewKey = "sky_time_preview"
    static var previewMinutes: Int? { UserDefaults.standard.object(forKey: previewKey) as? Int }
    static func now(_ real: Date = Date()) -> Date {
        guard let m = previewMinutes else { return real }
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: real) ?? real
    }
}

// MARK: - Pixel sky behind page headers (day: clouds and hills; night: stars and moon)

/// Sky colours for each weather; the first band is also the status bar backdrop.
enum OmniSky {
    static func bands(night: Bool, kind: OmniWeatherKind) -> [UInt32] {
        if night {
            switch kind {
            case .clear, .partlyCloudy: return [0x0A0F24, 0x0D1430, 0x10193A, 0x141F46, 0x182652, 0x1C2C5C]
            case .cloudy, .fog: return [0x111729, 0x151C33, 0x19223D, 0x1E2948, 0x243053, 0x2A375C]
            default: return [0x0F1424, 0x12182B, 0x161D33, 0x1B233C, 0x212A45, 0x27304D]
            }
        }
        switch kind {
        case .clear: return [0x4FB0F2, 0x66BCF7, 0x7CC8FB, 0x97D4FD, 0xB4E1FE, 0xD3EFFF]
        case .partlyCloudy: return [0x6ABDF6, 0x7CC8FB, 0x8FD3FF, 0xA6DCFF, 0xBDE6FF, 0xD3EFFF]
        case .cloudy: return [0x8FA9C0, 0x9DB4C8, 0xAEC1D2, 0xBFCEDC, 0xCFDBE6, 0xDDE6EE]
        case .fog: return [0xB9C5D0, 0xC4CFD8, 0xCFD8E0, 0xD9E0E7, 0xE3E8ED, 0xECF0F3]
        case .snow: return [0xA9BCCE, 0xB7C8D8, 0xC6D4E1, 0xD4DFE9, 0xE2EAF1, 0xEEF3F8]
        default: return [0x5F7387, 0x6C8094, 0x7B8FA2, 0x8D9FB0, 0xA0B0BF, 0xB4C2CE]
        }
    }
    static func top(night: Bool, kind: OmniWeatherKind) -> Color { Color(hex: bands(night: night, kind: kind)[0]) }

    /// Home's sky: the weather colours, warmed by the hour. A clear or partly cloudy sky takes the
    /// colours of the time of day (dawn, midday, golden afternoon, twilight, deep night); a grey sky
    /// keeps its weather colours with a little of the dawn or dusk glow; rain and snow stay as they are.
    static func bands(night: Bool, kind: OmniWeatherKind, at date: Date) -> [UInt32] {
        let weather = bands(night: night, kind: kind)
        guard let timed = timeBands(night: night, at: date) else { return weather }
        switch kind {
        case .clear, .partlyCloudy: return timed
        case .cloudy, .fog: return zip(weather, timed).map { mix($0, $1, 0.3) }
        default: return weather
        }
    }

    /// Colours for the hours that differ from the plain day and night skies; nil for midday and deep night.
    private static func timeBands(night: Bool, at date: Date) -> [UInt32]? {
        let hour = Calendar.current.component(.hour, from: date)
        if night {
            // twilight from sunset until 8 pm
            return (17..<20).contains(hour) ? [0x2C2F66, 0x4B3F82, 0x7A4E8C, 0xB85E86, 0xE5806C, 0xF4AE68] : nil
        }
        if hour < 9 { return [0x6FA8DE, 0x8DBBE6, 0xB3CDEB, 0xE9C6B8, 0xF5B596, 0xFAD3A0] }
        if hour >= 16 { return [0x5B9BD8, 0x7DB0E0, 0xA7C4E3, 0xE3C7A8, 0xF2B27C, 0xF7C98A] }
        return nil
    }

    /// The six colour stops spread into `count` thin bands, each a step between its neighbours.
    static func smooth(_ stops: [UInt32], count: Int) -> [UInt32] {
        guard stops.count > 1, count > 1 else { return stops }
        return (0..<count).map { i in
            let p = Double(i) / Double(count - 1) * Double(stops.count - 1)
            let k = min(Int(p), stops.count - 2)
            return mix(stops[k], stops[k + 1], p - Double(k))
        }
    }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

/// Pixel sky behind the new pages. `fullPage` paints the whole screen with live weather
/// (sun rays, drifting clouds, rain, snow, fog, stars and moon); otherwise a header band that fades out.
struct PixelSkyBackground: View {
    @Environment(\.omniPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var weather = OmniWeather.shared
    var fullPage = false
    /// Home only: the ground line of its buildings, in points from the top of the screen.
    /// The sun and moon rise and set behind it.
    var horizon: CGFloat? = nil

    var body: some View {
        let kind = fullPage ? weather.shownKind : .partlyCloudy
        ZStack(alignment: .top) {
            palette.background
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !fullPage)) { tl in
                let t = reduceMotion || !fullPage ? 0 : tl.date.timeIntervalSinceReferenceDate
                Canvas(rendersAsynchronously: false) { context, size in
                    PixelSkyPainter(context: context, size: size, night: palette.night, kind: kind, t: t, fullPage: fullPage,
                                    cloudCover: fullPage ? weather.shownCloudCover : 30, windFactor: fullPage ? weather.cloudSpeedFactor : 1,
                                    date: OmniSkyClock.now(tl.date), horizon: horizon).paint()
                }
            }
            .frame(height: fullPage ? nil : 270)
            .mask(LinearGradient(colors: fullPage ? [.black, .black] : [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
        .onAppear { if fullPage { weather.refreshIfNeeded() } }
    }
}

private struct PixelSkyPainter {
    let context: GraphicsContext
    let size: CGSize
    let night: Bool
    let kind: OmniWeatherKind
    let t: Double
    let fullPage: Bool
    var cloudCover = 30
    var windFactor = 1.0
    var date = Date()
    var horizon: CGFloat? = nil

    private var s: CGFloat { size.width / 195 }
    private var gh: CGFloat { size.height / s }
    /// Sun, moon and lightning sit in the top-right corner of the open sky above the Home title.
    /// Low enough that the status bar backdrop never cuts off the top of the sun or moon.
    static let skyBody = CGPoint(x: 159, y: 42)

    /// Where the sun or moon sits on Home: an arc over the right half that starts and ends behind the
    /// buildings (the sun from 6:00 to 18:00, the moon from 18:00 to 6:00), highest at noon and midnight.
    /// `lift` runs from 0 on the horizon to 1 at the top of the arc.
    private var bodySpot: (point: CGPoint, lift: Double) {
        guard fullPage, let horizon else { return (Self.skyBody, 1) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double((c.hour ?? 12) * 60 + (c.minute ?? 0))
        let since = night ? (minutes >= 720 ? minutes - 1080 : minutes + 360) : minutes - 360
        let p = min(1, max(0, since / 720))
        let lift = sin(Double.pi * p)
        // at the lowest the whole disc is under the roofline of the shortest building
        let low = horizon / s - 20
        let y = low - (low - Self.skyBody.y) * CGFloat(lift)
        return (CGPoint(x: 175 - 70 * CGFloat(p), y: y), lift)
    }
    private func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
        // Snap both edges to whole points so neighbouring pixels share an edge and leave no hairline seams.
        let x0 = (x * s).rounded(), y0 = (y * s).rounded()
        let x1 = ((x + w) * s).rounded(), y1 = ((y + h) * s).rounded()
        context.fill(Path(CGRect(x: x0, y: y0, width: max(1, x1 - x0), height: max(1, y1 - y0))), with: .color(c))
    }
    private func rnd(_ i: Double) -> Double { let v = sin(i * 12.9898) * 43758.5453; return v - floor(v) }

    func paint() {
        // Home's full sky follows the hour too, in many thin steps; header skies keep six bands.
        let bands = fullPage ? OmniSky.smooth(OmniSky.bands(night: night, kind: kind, at: date), count: 16)
                             : OmniSky.bands(night: night, kind: kind)
        let skyH = fullPage ? gh : 280
        let bandH = (skyH * 0.75 / CGFloat(bands.count)).rounded(.up)
        for (i, c) in bands.enumerated() { px(0, CGFloat(i) * bandH, 195, bandH + 1, Color(hex: c)) }
        px(0, CGFloat(bands.count) * bandH, 195, max(0, skyH - CGFloat(bands.count) * bandH), Color(hex: bands.last!))
        let wet = [.drizzle, .rain, .storm].contains(kind)
        if night {
            let starCount = fullPage ? (kind == .clear ? 170 : kind == .partlyCloudy ? 110 : wet || kind == .cloudy ? 25 : 60) : 70
            let starH = fullPage ? skyH * 0.85 : 260
            for i in 0..<starCount {
                let sx = floor(rnd(Double(i)) * 195), sy = floor(rnd(Double(i + 99)) * starH)
                let tw = fullPage ? 0.5 + 0.5 * sin(t * (1.2 + rnd(Double(i + 7)) * 2) + Double(i)) : 1
                let big = i % 9 == 0
                let col = (i % 5 == 0 ? Color.white : Color(hex: 0xC8D6FF)).opacity(0.35 + 0.65 * tw)
                px(sx, sy, 1, 1, col)
                if big && tw > 0.75 { px(sx - 1, sy, 3, 1, col.opacity(0.6)); px(sx, sy - 1, 1, 3, col.opacity(0.6)) }
            }
            if !wet { if fullPage { moon(bodySpot.point.x, bodySpot.point.y, 10) } else { moon(150, 44, 7) } }
            if fullPage && kind == .clear { shootingStar() }
        } else if fullPage && (kind == .clear || kind == .partlyCloudy) {
            // low in the sky it is a big orange-red sun without rays, as at sunrise and sunset
            let spot = bodySpot
            sun(spot.point.x, spot.point.y, kind == .clear && spot.lift >= 0.4, warm: spot.lift < 0.4)
        }
        clouds(skyH)
        if kind == .fog { fog(skyH) }
        if wet { rain(skyH, heavy: kind != .drizzle) }
        if kind == .storm { lightning(bolt: fullPage) }
        if kind == .snow { snow(skyH) }
    }

    /// Lunar phase as a fraction of the synodic month (0 new, 0.5 full), snapped to 8 phases.
    static func moonPhase(at date: Date = Date()) -> Double {
        let synodic = 29.530588853
        let knownNew = Date(timeIntervalSince1970: 947_182_440) // 6 Jan 2000 18:14 UTC
        var age = date.timeIntervalSince(knownNew) / 86_400
        age = age.truncatingRemainder(dividingBy: synodic)
        if age < 0 { age += synodic }
        return (age / synodic * 8).rounded().truncatingRemainder(dividingBy: 8) / 8
    }

    private func moon(_ cx: CGFloat, _ cy: CGFloat, _ r: Int) {
        let f = Self.moonPhase()
        let k = cos(2 * Double.pi * f)
        let rr = Double(r) + 0.5
        for j in -r...r { for i in -r...r where i * i + j * j <= r * r {
            let edge = (1 - pow(Double(j) / rr, 2)).squareRoot() * rr
            let x = Double(i)
            let lit = f <= 0.5 ? x > k * edge - 0.5 : x < -k * edge + 0.5
            px(cx + CGFloat(i), cy + CGFloat(j), 1, 1, lit ? Color(hex: 0xF3E9B6) : Color(hex: 0x2A3765, opacity: 0.55))
        } }
        // soft halo
        context.fill(Path(ellipseIn: CGRect(x: (cx - CGFloat(r) * 2.2) * s, y: (cy - CGFloat(r) * 2.2) * s, width: CGFloat(r) * 4.4 * s, height: CGFloat(r) * 4.4 * s)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xF3E9B6).opacity(0.18), .clear]), center: CGPoint(x: cx * s, y: cy * s), startRadius: 0, endRadius: CGFloat(r) * 2.2 * s))
    }

    private func shootingStar() {
        let period = 9.0, phase = t.truncatingRemainder(dividingBy: period)
        guard phase < 0.9 else { return }
        let k = floor(t / period), f = phase / 0.9
        let x0 = 40 + rnd(k) * 110, y0 = 10 + rnd(k + 3) * 60
        for j in 0..<10 { let d = Double(j) * 2.2, a = (1 - Double(j) / 10) * (1 - f)
            px(x0 + f * 70 - d, y0 + f * 35 - d * 0.5, 1, 1, Color.white.opacity(a)) }
    }

    private func sun(_ cx: CGFloat, _ cy: CGFloat, _ rays: Bool, warm: Bool = false) {
        let pulse = rays && fullPage ? (sin(t * 2) > 0 ? 1.0 : 0.0) : 0
        let glow = Gradient(colors: [Color(hex: warm ? 0xFF8A4C : 0xFFF2A8).opacity(warm ? 0.6 : 0.55), .clear])
        let halo: CGFloat = warm ? 44 : 34
        context.fill(Path(ellipseIn: CGRect(x: (cx - halo) * s, y: (cy - halo) * s, width: halo * 2 * s, height: halo * 2 * s)), with: .radialGradient(glow, center: CGPoint(x: cx * s, y: cy * s), startRadius: 0, endRadius: halo * s))
        let r = warm ? 11 : 9
        let (rim, fill, shine): (UInt32, UInt32, UInt32) = warm ? (0xE0532F, 0xF5803A, 0xFFC27A) : (0xF7B731, 0xFFD94A, 0xFFF6C8)
        for j in -r...r { for i in -r...r where i * i + j * j <= r * r {
            let edge = i * i + j * j > (r - 1) * (r - 1)
            px(cx + CGFloat(i), cy + CGFloat(j), 1, 1, Color(hex: edge ? rim : (i + j < -6 ? shine : fill)))
        } }
        guard rays else { return }
        let len: CGFloat = 4 + CGFloat(pulse) * 2
        for (dx, dy) in [(0.0, -1.0), (0, 1), (-1, 0), (1, 0)] { px(cx + CGFloat(dx) * 12 - (dx == 0 ? 0.5 : (dx < 0 ? len : 0)), cy + CGFloat(dy) * 12 - (dy == 0 ? 0.5 : (dy < 0 ? len : 0)), dx == 0 ? 1 : len, dy == 0 ? 1 : len, Color(hex: 0xFFD94A)) }
        for (dx, dy) in [(1.0, 1.0), (1, -1), (-1, 1), (-1, -1)] { for k in 0..<Int(len / 1.5) { px(cx + CGFloat(dx) * (10 + CGFloat(k)), cy + CGFloat(dy) * (10 + CGFloat(k)), 1, 1, Color(hex: 0xFFD94A)) } }
    }

    private func cloudShape(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ c: Color, _ shade: Color) {
        px(x, y, w, 6, c); px(x + 4, y - 4, w - 12, 4, c); px(x + 8, y - 8, max(4, w - 22), 4, c); px(x, y + 6, w, 2, shade)
    }

    private func clouds(_ skyH: CGFloat) {
        // Four levels from the real cloud cover: almost clear, a few, many, overcast.
        let count: Int
        if fullPage {
            count = cloudCover <= 10 ? 1 : cloudCover <= 40 ? 4 : cloudCover <= 80 ? 8 : 14
        } else {
            count = [.cloudy, .fog].contains(kind) ? 6 : 5
        }
        let wet = [.drizzle, .rain, .storm].contains(kind)
        let c: Color, sh: Color
        if night { c = Color(hex: wet || kind == .cloudy ? 0x343E62 : 0x26335E); sh = Color(hex: 0x1C2647) }
        else if wet { c = Color(hex: 0x8C99A6); sh = Color(hex: 0x6E7B88) }
        else if kind == .cloudy || kind == .snow { c = Color(hex: 0xEEF2F6); sh = Color(hex: 0xC9D3DD) }
        else { c = .white; sh = Color(hex: 0xE3F1FB) }
        // the static sky of the inner tabs: one cloud at the top, one on the right beside the title
        let fixed: [(CGFloat, CGFloat, CGFloat)] = [(100, 30, 30), (158, 58, 32), (150, 112, 38), (12, 150, 30), (120, 210, 36)]
        for i in 0..<count {
            let base: (CGFloat, CGFloat, CGFloat) = !fullPage && i < fixed.count ? fixed[i]
                : (CGFloat(rnd(Double(i) + 0.3)) * 230, 18 + CGFloat(rnd(Double(i) + 5.1)) * (skyH * (wet || kind == .cloudy ? 0.55 : 0.8)), 26 + CGFloat(rnd(Double(i) + 9.7)) * 24)
            let speed = fullPage ? (1.2 + rnd(Double(i) + 2.2) * 2.4) * windFactor : 0
            let x = (base.0 + CGFloat(t * speed)).truncatingRemainder(dividingBy: 260) - 40
            cloudShape(x, base.1, base.2, c, sh)
        }
    }

    private func rain(_ skyH: CGFloat, heavy: Bool) {
        let n = heavy ? 170 : 80, col = night ? Color(hex: 0xB4C6EE) : Color(hex: 0xF4F9FF)
        for i in 0..<n {
            let speed = 110 + rnd(Double(i) + 4) * 60
            let y = (CGFloat(rnd(Double(i) + 1.5)) * skyH + CGFloat(t * speed)).truncatingRemainder(dividingBy: skyH + 10) - 5
            let x = (CGFloat(rnd(Double(i))) * 220 - y * 0.18).truncatingRemainder(dividingBy: 215)
            px(x < 0 ? x + 215 : x, y, 1, heavy ? 7 : 4, col.opacity(night ? 0.8 : 0.92))
        }
    }

    private static let bolt = ["......YYYY", ".....YYYY.", ".....YYY..", "....YYWY..", "....YWY...", "...YWY....",
                               "...YWYYYYY", "..YWWYYYY.", "....YWYY..", "....YYY...", "....YWY...", "...YYY....",
                               "...YY.....", "..YY......", "..Y......."]

    private func lightning(bolt: Bool) {
        let period = 7.0, phase = t.truncatingRemainder(dividingBy: period)
        let flash = phase < 0.12 || (phase > 0.22 && phase < 0.3)
        if bolt {
            // a pixel bolt where the sun and moon sit, brightest while the sky flashes
            let ox = Self.skyBody.x - 8, oy = Self.skyBody.y - 6, cell: CGFloat = 1.6
            for (j, row) in Self.bolt.enumerated() {
                for (i, ch) in row.enumerated() where ch != "." {
                    let c = ch == "W" ? Color(hex: 0xFFF8D6) : Color(hex: flash ? 0xFFE27A : 0xFFCE3A)
                    px(ox + CGFloat(i) * cell, oy + CGFloat(j) * cell, cell, cell, c)
                }
            }
        }
        if flash {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.white.opacity(night ? 0.18 : 0.28)))
        }
    }

    private func snow(_ skyH: CGFloat) {
        for i in 0..<90 {
            let y = (CGFloat(rnd(Double(i) + 1.5)) * skyH + CGFloat(t * (14 + rnd(Double(i)) * 10))).truncatingRemainder(dividingBy: skyH)
            let x = CGFloat(rnd(Double(i))) * 195 + CGFloat(sin(t + Double(i)) * 3)
            px(x, y, i % 4 == 0 ? 2 : 1, i % 4 == 0 ? 2 : 1, .white.opacity(0.85))
        }
    }

    private func fog(_ skyH: CGFloat) {
        for k in 0..<6 {
            let y = skyH * (0.15 + 0.13 * CGFloat(k)), x = CGFloat(sin(t * 0.15 + Double(k)) * 20)
            px(x - 20, y, 240, 10, Color.white.opacity(night ? 0.06 : 0.28))
        }
    }
}

// MARK: - Sound and vibration preferences

enum OmniSoundSettings {
    static let musicKey = "sound_music_enabled"
    static let effectsKey = "sound_effects_enabled"
    static let hapticsKey = "haptics_enabled"

    private static func flag(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    static var musicEnabled: Bool { flag(musicKey) }
    static var effectsEnabled: Bool { flag(effectsKey) }
    static var hapticsEnabled: Bool { flag(hapticsKey) }
}

// MARK: - Sky band behind the status bar so scrolled content does not run under the clock

struct OmniStatusBarBackdrop: ViewModifier {
    @Environment(\.omniV2) private var v2
    @Environment(\.omniPalette) private var palette
    @ObservedObject private var weather = OmniWeather.shared
    var useWeather = false
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if v2 {
                GeometryReader { proxy in
                    let sky = useWeather ? Color(hex: OmniSky.bands(night: palette.night, kind: weather.shownKind, at: OmniSkyClock.now())[0]) : (palette.night ? Color(hex: 0x120D2E) : Color(hex: 0x7CC8FB))
                    LinearGradient(stops: [.init(color: sky, location: 0), .init(color: sky, location: 0.7), .init(color: sky.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: proxy.safeAreaInsets.top + 14)
                        .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func omniStatusBarBackdrop(weather: Bool = false) -> some View { modifier(OmniStatusBarBackdrop(useWeather: weather)) }
}
