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

    func isNight(at date: Date = Date()) -> Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .auto:
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
    var cta: Color { extra ? Color(hex: 0x7C5CFF) : Color(hex: 0x34B45A) }
    var ctaShadow: Color { extra ? Color(hex: 0x4B32B8) : Color(hex: 0x23893F) }
    var selected: Color { extra ? Color(hex: 0x7C5CFF) : Color(hex: 0x2F6FD6) }
    var gold: Color { Color(hex: 0xE8B93A) }
    var danger: Color { Color(hex: 0xE8463F) }
    var shadow: Color { night ? .black.opacity(0.45) : Color(red: 20 / 255, green: 40 / 255, blue: 80 / 255).opacity(0.18) }
    var versionTint: Color {
        if extra { return night ? Color(hex: 0xC9B8FF) : Color(hex: 0x7C5CFF) }
        return night ? Color(hex: 0x8FE0A6) : Color(hex: 0x2F9E4F)
    }
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
    /// Pixel face for card names.
    static func omniPixel(_ size: CGFloat, weight: Int = 700) -> Font { OmniFonts.font(.pixelify, weight, size: size) }
}

// MARK: - Root modifier: decides v2, night and Extra once for the whole tree

struct OmniV2Root: ViewModifier {
    @AppStorage(OmniInterfaceVersion.storageKey) private var v2Enabled = true
    @AppStorage(OmniAppearanceMode.storageKey) private var appearanceRaw = OmniAppearanceMode.auto.rawValue
    let isExtra: Bool

    func body(content: Content) -> some View {
        TimelineView(.everyMinute) { context in
            let night = (OmniAppearanceMode(rawValue: appearanceRaw) ?? .auto).isNight(at: context.date)
            let palette = OmniPalette(night: v2Enabled && night, extra: isExtra)
            content
                .environment(\.omniV2, v2Enabled)
                .environment(\.omniNight, v2Enabled && night)
                .environment(\.omniExtra, isExtra)
                // Screens not yet redrawn still style Extra as dark, so the system stays dark for Extra.
                .preferredColorScheme(v2Enabled ? ((night || isExtra) ? .dark : .light) : (isExtra ? .dark : nil))
                .tint(v2Enabled ? palette.selected : (isExtra ? ExtraAuroraPalette.electricBlue : Color.blue))
        }
    }
}

// MARK: - Surfaces and controls

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
            .shadow(color: palette.shadow, radius: 9, y: 6)
    }
}

extension View {
    func omniCard(padding: CGFloat = 16, radius: CGFloat = 20) -> some View { modifier(OmniCardModifier(padding: padding, radius: radius)) }
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

/// Small rounded chip with a pixel icon and a number, as in the hearts and Omni chips.
struct OmniChip: View {
    @Environment(\.omniPalette) private var palette
    let icon: String
    let value: String
    var body: some View {
        HStack(spacing: 4) {
            PixelIcon(icon, size: 16)
            Text(value).font(.omniDisplay(15, weight: 800)).monospacedDigit()
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(palette.card, in: Capsule())
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
    }
}

/// Green (Extra: violet) 3D primary button.
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

// MARK: - Pixel sky behind page headers (day: clouds and hills; night: stars and moon)

struct PixelSkyBackground: View {
    @Environment(\.omniPalette) private var palette
    var body: some View {
        ZStack(alignment: .top) {
            palette.background
            Canvas(rendersAsynchronously: false) { context, size in
                let gw: CGFloat = 195, gh: CGFloat = 390, s = size.width / gw
                func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    context.fill(Path(CGRect(x: x * s, y: y * s, width: w * s + 0.5, height: h * s + 0.5)), with: .color(c))
                }
                func rnd(_ i: Double) -> Double { let v = sin(i * 12.9898) * 43758.5453; return v - floor(v) }
                if !palette.night {
                    let bands: [UInt32] = [0x7CC8FB, 0x8FD3FF, 0xA6DCFF, 0xBDE6FF, 0xD3EFFF]
                    for (i, c) in bands.enumerated() { px(0, CGFloat(i) * 56, gw, 56, Color(hex: c)) }
                    px(0, 280, gw, gh - 280, Color(hex: 0xD3EFFF))
                    for (cx, cy, w) in [(108.0, 30.0, 30.0), (150, 112, 38), (12, 150, 30), (120, 210, 36)] {
                        px(cx, cy, w, 6, .white); px(cx + 4, cy - 4, w - 12, 4, .white); px(cx + 8, cy - 8, w - 22, 4, .white); px(cx, cy + 6, w, 2, Color(hex: 0xE3F1FB))
                    }
                } else {
                    let bands: [UInt32] = [0x120D2E, 0x151036, 0x1B1442, 0x22184F, 0x2C2266]
                    for (i, c) in bands.enumerated() { px(0, CGFloat(i) * 56, gw, 56, Color(hex: c)) }
                    px(0, 280, gw, gh - 280, Color(hex: 0x2C2266))
                    for i in 0..<70 {
                        let sx = floor(rnd(Double(i)) * gw), sy = floor(rnd(Double(i + 99)) * 260)
                        px(sx, sy, 1, 1, i % 5 == 0 ? .white : Color(hex: 0xCFC6FF))
                    }
                    for j in -7...7 { for i in -7...7 where i * i + j * j <= 49 && (i + 3) * (i + 3) + (j - 2) * (j - 2) > 30 { px(114 + CGFloat(i), 28 + CGFloat(j), 1, 1, Color(hex: 0xF3E9B6)) } }
                }
            }
            .frame(height: 270)
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
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
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if v2 {
                GeometryReader { proxy in
                    let sky = palette.night ? Color(hex: 0x120D2E) : Color(hex: 0x7CC8FB)
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
    func omniStatusBarBackdrop() -> some View { modifier(OmniStatusBarBackdrop()) }
}
