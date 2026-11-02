import SwiftUI

struct GrammarLearningView: View {
    @Environment(\.omniPalette) private var palette
    @StateObject private var store: GrammarProgressStore

    init() {
        let userID = AuthManager.shared.currentUser?.id.uuidString ?? "guest"
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-GrammarUITest") {
            _store = StateObject(wrappedValue: GrammarProgressStore(userID: "ui-test", repository: InMemoryGrammarProgressRepository()))
            return
        }
#endif
        _store = StateObject(wrappedValue: GrammarProgressStore(userID: userID))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(0.75, geometry.size.height / 810))
            VStack(spacing: 0) {
                GrammarHeroHeader(back: "Learning", kicker: "LỘ TRÌNH CEFR", title: "Chọn chặng học",
                                  subtitle: "Sáu bậc từ A1 đến C2", portrait: true, scale: scale)
                VStack(spacing: 10 * scale) {
                    GrammarProgressStatus(store: store)
                    ForEach(GrammarStage.allCases) { stage in
                        let open = store.isUnlocked(stage)
                        NavigationLink { GrammarStageView(stage: stage, store: store) } label: {
                            GrammarStageRow(stage: stage, done: store.completedCount(in: stage), open: open, scale: scale)
                        }
                        .buttonStyle(.plain).disabled(!open).frame(maxHeight: .infinity)
                        .accessibilityLabel("Chặng \(stage.rawValue), \(stage.title)\(open ? "" : ", đang khoá")")
                        .accessibilityIdentifier("grammar-stage-\(stage.rawValue)")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14 * scale).padding(.bottom, 12)
                .frame(maxHeight: .infinity)
            }
        }
        .background { palette.background.ignoresSafeArea() }
        .textSelection(.disabled)
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.load() }
    }
}

/// The module's one green.
enum GrammarTheme {
    static func header(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x173238 : 0x1E4549) }
    /// Buttons and filled marks.
    static func deep(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x2E6A70 : 0x1E4549) }
    /// Text and icons in the green.
    static func ink(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x88D4CE : 0x1E4549) }
    static func mint(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x6CCFC2 : 0x5FC0B4) }
    static func soft(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x1C3942 : 0xE6F4F2) }
    static func border(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x356B70 : 0x7FCFC5) }
    static func dash(_ p: OmniPalette) -> Color { Color(hex: p.night ? 0x356B70 : 0xB5DDD7) }
}

private extension View {
    /// iOS 26 fades the top of a scroll view into the page colour, which reads as a pale band under the green header.
    @ViewBuilder func grammarTopEdgeEffectHidden() -> some View {
        if #available(iOS 26.0, *) { scrollEdgeEffectHidden(true, for: .top) } else { self }
    }
}

/// Green header that runs under the status bar, with the back button on top.
private struct GrammarHeroHeader: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.omniPalette) private var palette
    let back: String
    let kicker: String
    let title: String
    let subtitle: String
    var portrait = false
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            Button { dismiss() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    Text(back).font(.omniBody(13, weight: 700))
                }
                .foregroundStyle(.white)
            }.buttonStyle(.plain).accessibilityIdentifier("grammar-back")
            HStack(alignment: .bottom, spacing: 10 * scale) {
                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text(kicker).font(.omniBody(12 * scale, weight: 700)).tracking(2)
                        .foregroundStyle(Color(hex: 0x6CCFC2))
                    Text(title).font(.omniDisplay(30 * scale)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("grammar-page-title")
                    Text(subtitle).font(.omniBody(13 * scale, weight: 600))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                if portrait { GrammarProfessorPortrait().frame(width: 78 * scale, height: 108 * scale) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                GrammarTheme.header(palette)
                Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 170, height: 170).offset(x: 50, y: -40)
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
    }
}

/// One CEFR stage, coloured like the word cards of that level; locked stages are dimmed.
private struct GrammarStageRow: View {
    @Environment(\.omniPalette) private var palette
    let stage: GrammarStage
    let done: Int
    let open: Bool
    let scale: CGFloat
    private var colors: (light: Color, dark: Color) {
        let pair = WordCardStyle.colors[stage.rawValue] ?? WordCardStyle.none
        return (Color(hex: pair.0), Color(hex: pair.1))
    }

    var body: some View {
        HStack(spacing: 14 * scale) {
            Text(stage.rawValue).font(.omniDisplay(22 * scale)).foregroundStyle(Color(hex: 0x1E3A3C))
                .frame(width: 50 * scale, height: 50 * scale)
                .background(colors.light, in: RoundedRectangle(cornerRadius: 14 * scale))
                .overlay(RoundedRectangle(cornerRadius: 14 * scale).stroke(colors.dark.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5 * scale) {
                Text(stage.title).font(.omniDisplay(18 * scale)).foregroundStyle(GrammarTheme.ink(palette))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("\(done)/\(stage.topicCount) bài đã hoàn thành")
                    .font(.omniBody(12 * scale, weight: 600)).foregroundStyle(palette.muted)
                    .lineLimit(1).minimumScaleFactor(0.85)
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.line)
                        Capsule().fill(GrammarTheme.mint(palette))
                            .frame(width: bar.size.width * CGFloat(done) / CGFloat(stage.topicCount))
                    }
                }.frame(height: 5 * scale)
            }
            Spacer(minLength: 0)
            Image(systemName: open ? "arrow.right" : "lock.fill")
                .font(.system(size: 14 * scale, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40 * scale, height: 40 * scale)
                .background(open ? GrammarTheme.deep(palette) : palette.muted.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 12 * scale))
        }
        .padding(.horizontal, 14 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(open ? GrammarTheme.soft(palette) : palette.card, in: RoundedRectangle(cornerRadius: 18 * scale))
        .overlay(RoundedRectangle(cornerRadius: 18 * scale)
            .stroke(open ? GrammarTheme.border(palette) : palette.line, lineWidth: open ? 1.2 : 1))
        .saturation(open ? 1 : 0.2)
        .opacity(open ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: 18 * scale))
    }
}

private struct GrammarStageView: View {
    let stage: GrammarStage
    @ObservedObject var store: GrammarProgressStore
    @Environment(\.omniPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GrammarHeroHeader(back: "Học ngữ pháp", kicker: "CHẶNG \(stage.rawValue)", title: stage.title,
                              subtitle: "\(store.completedCount(in: stage))/\(stage.topicCount) chủ điểm đã hoàn thành")
            GrammarProgressStatus(store: store).padding(.horizontal, 16)
            ScrollView {
                GrammarRoadmap(stage: stage, store: store).padding(.horizontal, 16).padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .grammarTopEdgeEffectHidden()
            .refreshable { await store.load(force: true) }
        }
        .background { palette.background.ignoresSafeArea() }
        .textSelection(.disabled)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The circle alternates sides; connectors travel around the outer edge of the next card.
private struct GrammarRoadmap: View {
    let stage: GrammarStage
    @ObservedObject var store: GrammarProgressStore
    @Environment(\.omniPalette) private var palette
    private let rowHeight: CGFloat = 164
    private var accent: Color { GrammarTheme.ink(palette) }
    private var mint: Color { GrammarTheme.soft(palette) }
    private var border: Color { GrammarTheme.border(palette) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let diameter = max(56, min(72, width * 0.177))
            let gap: CGFloat = width < 340 ? 20 : 28
            ZStack(alignment: .top) {
                Canvas { context, size in
                    let lineColor = GrammarTheme.dash(palette)
                    for index in 0..<stage.topicCount {
                        let reverse = index % 2 == 1
                        let y = CGFloat(index) * rowHeight + rowHeight / 2
                        let start = reverse ? size.width - 12 - diameter - 4 : 12 + diameter + 4
                        let end = reverse ? start - gap + 7 : start + gap - 7
                        var horizontal = Path()
                        horizontal.move(to: CGPoint(x: start, y: y)); horizontal.addLine(to: CGPoint(x: end, y: y))
                        context.stroke(horizontal, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: end, y: y))
                        arrow.addLines([CGPoint(x: end + (reverse ? 6 : -6), y: y - 4),
                                        CGPoint(x: end + (reverse ? 6 : -6), y: y + 4)])
                        arrow.closeSubpath()
                        context.fill(arrow, with: .color(border))
                        if index < stage.topicCount - 1 {
                            let outer: CGFloat = reverse ? 1 : size.width - 1
                            let edge: CGFloat = reverse ? 12 : size.width - 12
                            let toward: CGFloat = reverse ? 14 : -14
                            let nextY = y + rowHeight
                            var connector = Path()
                            connector.move(to: CGPoint(x: edge, y: y))
                            connector.addLine(to: CGPoint(x: outer + toward, y: y))
                            connector.addQuadCurve(to: CGPoint(x: outer, y: y + 14), control: CGPoint(x: outer, y: y))
                            connector.addLine(to: CGPoint(x: outer, y: nextY - 14))
                            connector.addQuadCurve(to: CGPoint(x: outer + toward, y: nextY), control: CGPoint(x: outer, y: nextY))
                            connector.addLine(to: CGPoint(x: edge, y: nextY))
                            context.stroke(connector, with: .color(lineColor), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                        }
                    }
                }.accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(stage.topics) { topic in
                        if store.canOpen(topic) {
                            NavigationLink { GrammarLessonView(topic: topic, store: store) } label: {
                                row(topic, diameter: diameter, gap: gap)
                            }
                            .buttonStyle(.plain).disabled(!store.hasLoaded)
                            .accessibilityIdentifier("grammar-topic-\(topic.id)")
                        } else {
                            row(topic, diameter: diameter, gap: gap)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Chủ điểm \(topic.number)\(store.title(for: topic).map { ", \($0)" } ?? ""), chưa có học liệu")
                                .accessibilityIdentifier("grammar-topic-\(topic.id)")
                        }
                    }
                }.padding(.horizontal, 12)
            }
        }.frame(height: CGFloat(stage.topicCount) * rowHeight)
    }

    private func row(_ topic: GrammarTopic, diameter: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            if topic.number % 2 == 0 { lessonCard(topic) }
            node(topic, diameter: diameter)
            if topic.number % 2 == 1 { lessonCard(topic) }
        }
        .frame(height: rowHeight).contentShape(Rectangle())
    }
    private func node(_ topic: GrammarTopic, diameter: CGFloat) -> some View {
        let progress = store.progress(for: topic)
        let open = store.canOpen(topic)
        let done = progress.stars > 0
        let waiting = topic.number > 1 && store.progress(for: GrammarTopic(stage: stage, number: topic.number - 1)).stars >= 2
        return ZStack {
            Circle().fill(done ? GrammarTheme.deep(palette) : palette.card)
            Circle().strokeBorder(done ? Color.clear : open ? accent : palette.line, lineWidth: 2)
            VStack(spacing: 3) {
                if done {
                    Image(systemName: "checkmark").font(.system(size: diameter * 0.32, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6CCFC2))
                    Text(String(repeating: "★", count: progress.stars))
                        .font(.omniBody(diameter * 0.15, weight: 700)).foregroundStyle(palette.gold)
                        .lineLimit(1).fixedSize()
                } else {
                    Text(String(format: "%02d", topic.number)).font(.omniDisplay(diameter * 0.36))
                        .monospacedDigit().lineLimit(1).fixedSize()
                    if open || waiting {
                        Text(open ? "HỌC" : "CHỜ BÀI").font(.omniBody(9, weight: 700)).lineLimit(1)
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold))
                            .padding(.top, -2).padding(.bottom, 6)
                            .accessibilityLabel("Chưa mở")
                    }
                }
            }
            .foregroundStyle(open ? accent : palette.muted.opacity(0.75))
            .frame(width: diameter - 10, height: diameter - 10)
        }
        .frame(width: diameter, height: diameter)
        .overlay { if open && !done { Circle().stroke(mint, lineWidth: 3).padding(-4) } }
    }
    private func lessonCard(_ topic: GrammarTopic) -> some View {
        let open = store.canOpen(topic)
        let done = store.progress(for: topic).stars > 0
        return VStack(alignment: .leading, spacing: 7) {
            Text(store.title(for: topic) != nil ? "TỪ LOẠI" : "CHỦ ĐIỂM \(String(format: "%02d", topic.number))")
                .font(.omniBody(10, weight: 700)).tracking(0.8)
                .foregroundStyle(GrammarTheme.ink(palette).opacity(0.7))
            Text(store.title(for: topic) ?? " ").font(.omniDisplay(21)).foregroundStyle(accent)
                .lineLimit(2).minimumScaleFactor(0.85).frame(maxWidth: .infinity, alignment: .leading)
            Text(done ? "Xem kết quả · Học lại →" : open ? "Xem thông tin bài học →" : "Chưa có học liệu")
                .font(.omniBody(10, weight: 700)).foregroundStyle(open ? accent : palette.muted)
        }
        .padding(15).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(done ? mint : palette.card, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(done ? border : palette.line, lineWidth: 1))
        .omniCardShadow(radius: 17)
        .opacity(open ? 1 : 0.65)
    }
}

struct GrammarProgressStatus: View {
    @ObservedObject var store: GrammarProgressStore
    @Environment(\.omniPalette) private var palette
    var body: some View {
        if store.isLoading && !store.hasLoaded {
            ProgressView("Đang tải tiến độ…").font(.omniBody(13)).frame(maxWidth: .infinity).padding(12)
        } else if let error = store.loadError ?? store.saveError {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.omniBody(12)).foregroundStyle(palette.text)
                Button("Thử lại") {
                    Task {
                        if !store.hasLoaded || store.loadError != nil { await store.load(force: true) }
                        else { await store.flush() }
                    }
                }.font(.omniBody(13, weight: 700)).foregroundStyle(GrammarTheme.ink(palette))
            }
            .omniCard(padding: 12, radius: 16)
            .accessibilityIdentifier("grammar-sync-error")
        }
    }
}

enum GrammarLessonAssets {
    static var root: URL? { Bundle.main.url(forResource: "GrammarLessons", withExtension: "bundle") }
    static func lessonURL(_ topic: GrammarTopic) -> URL? {
        guard let root else { return nil }
        let url = root.appendingPathComponent("runtime/index.html")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static let portrait: UIImage? = {
        guard let root, let image = UIImage(contentsOfFile: root.appendingPathComponent("runtime/atlas.png").path)?.cgImage,
              let frame = image.cropping(to: CGRect(x: 0, y: 0, width: image.width / 4, height: image.height / 4)) else { return nil }
        return UIImage(cgImage: frame)
    }()
}

struct GrammarProfessorPortrait: View {
    var body: some View {
        if let image = GrammarLessonAssets.portrait {
            Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                .accessibilityLabel("Giáo sư Gram")
        } else {
            Image(systemName: "graduationcap.fill").resizable().scaledToFit().accessibilityLabel("Học ngữ pháp")
        }
    }
}

struct GrammarLearningScene: View {
    @Environment(\.omniPalette) private var palette
    var body: some View {
        GeometryReader { proxy in
            Image("learn-grammar-\(palette.night ? "night" : "day")")
                .resizable().interpolation(.none).scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
struct GrammarIntegrationPreview: View {
    @State private var tab = UserTab.learning
    var body: some View {
        OmniV2ContentView(selectedUserTab: $tab).modifier(OmniV2Root(isExtra: false))
    }
}
#endif
