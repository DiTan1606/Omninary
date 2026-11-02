import SwiftUI
import CoreMotion

// MARK: - Stage background

/// Dark stage with a spotlight from above, where a word card floats.
struct OmniStageBackground: View {
    @State private var glow = false
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2A3A78), Color(hex: 0x141A38), Color(hex: 0x0A0D1F)],
                           center: UnitPoint(x: 0.5, y: 0.38), startRadius: 10, endRadius: 520)
            GeometryReader { p in
                Path { path in
                    let w = p.size.width
                    path.move(to: CGPoint(x: w * 0.38, y: -40))
                    path.addLine(to: CGPoint(x: w * 0.62, y: -40))
                    path.addLine(to: CGPoint(x: w * 1.05, y: p.size.height * 0.72))
                    path.addLine(to: CGPoint(x: -w * 0.05, y: p.size.height * 0.72))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(hex: 0xBED2FF).opacity(glow ? 0.26 : 0.18), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7)))
                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0x7896FF).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 150))
                    .frame(width: 300, height: 70)
                    .position(x: p.size.width / 2, y: p.size.height * 0.68)
            }
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { glow = true } }
    }
}

/// A full word card floating gently; `locked` hides the details until the word is downloaded.
struct OmniFloatingCard: View {
    let vocab: Vocabulary
    let mastery: Int?
    var width: CGFloat = 290
    var locked = false
    var glow: Color = Color(hex: 0x8CAAFF)
    @State private var bob = false

    var body: some View {
        let scale = width / WordCardView.fullSize.width
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color.black.opacity(bob ? 0.35 : 0.55))
                .frame(width: width * (bob ? 0.72 : 0.86), height: 22)
                .blur(radius: 10)
                .offset(y: 46)
            WordCardView(vocab: vocab, mastery: mastery, mode: .full)
                .overlay(alignment: .bottom) {
                    if locked {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 20, weight: .bold))
                            Text("Tải về để mở thẻ chi tiết").font(.omniBody(12, weight: 800))
                        }
                        .foregroundStyle(Color(hex: 0x3A3F4C))
                        .frame(maxWidth: .infinity)
                        .frame(height: WordCardView.fullSize.height * 0.4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 34)
                        .environment(\.colorScheme, .light)
                    }
                }
                .scaleEffect(scale)
                .frame(width: width, height: WordCardView.fullSize.height * scale)
                .shadow(color: glow.opacity(0.35), radius: 24)
                .offset(y: bob ? -10 : 0)
                .rotationEffect(.degrees(bob ? 1 : -1))
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true } }
    }
}

/// Filled 3D button in any colour, like the primary button.
struct OmniTintButtonStyle: ButtonStyle {
    let fill: Color
    let shadow: Color
    var text: Color = .white
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.omniDisplay(17, weight: 800))
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(shadow, in: RoundedRectangle(cornerRadius: 14, style: .continuous).offset(y: configuration.isPressed ? 1 : 4))
            .offset(y: configuration.isPressed ? 3 : 0)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

// MARK: - Card stage: swipe anywhere left/right through the set; "Xem thêm" opens progress and details

struct OmniCardStageView: View {
    @Environment(\.omniPalette) private var palette
    let title: String
    let words: [Vocabulary]
    @State var index: Int
    @ObservedObject var store: OmniExploreStore
    @Environment(\.dismiss) private var dismiss
    @State private var position: Int?
    @State private var showInfo = false
    @State private var infoDetent: PresentationDetent = .medium

    init(title: String, words: [Vocabulary], index: Int, store: OmniExploreStore) {
        self.title = title
        self.words = words
        _index = State(initialValue: index)
        _position = State(initialValue: index)
        self.store = store
    }

    private var current: Vocabulary { words[min(max(index, 0), words.count - 1)] }

    var body: some View {
        ZStack {
            OmniStageBackground()
            // A native paging scroll view: only the cards near the screen are built, and a swipe
            // anywhere on the screen turns the page.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(words.indices, id: \.self) { i in
                        let v = words[i]
                        OmniFloatingCard(vocab: store.display(v), mastery: store.mastery(v), width: 320, locked: !store.isOwned(v),
                                         glow: WordCardStyle.cefrPair(v.CEFR).1)
                            .offset(y: -24)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .onChange(of: position) { _, value in if let value { index = value } }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                pageDots.padding(.bottom, 14)
                bottom
            }
        }
        .foregroundStyle(.white)
        .omniEdgeSwipeBack { dismiss() }
        .sheet(isPresented: $showInfo, onDismiss: { infoDetent = .medium }) {
            // half screen: review status and extra details; pulled up: the learning of this word too
            ExploreWordDetail(vocab: store.display(current), profiles: store.profiles, owned: store.isOwned(current),
                              night: palette.night, compact: infoDetent != .large)
                .presentationDetents([.medium, .large], selection: $infoDetent)
                .presentationDragIndicator(.visible)
        }
        .alert("Thông báo", isPresented: $store.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.alertMessage)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng")
            Text("\(title) · \(index + 1) / \(words.count)")
                .font(.omniBody(13, weight: 700))
                .foregroundStyle(Color(hex: 0xCFD6EE))
                .lineLimit(1)
            Spacer()
            if store.isOwned(current) {
                Text("✓ Đã tải").font(.omniBody(11, weight: 800)).foregroundStyle(Color(hex: 0x8FE0A6))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color(hex: 0x34B45A).opacity(0.25), in: Capsule())
            } else {
                Text("Chưa tải").font(.omniBody(11, weight: 800)).foregroundStyle(Color(hex: 0xCFD6EE))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var pageDots: some View {
        let window = 5
        let start = max(0, min(index - window / 2, words.count - window))
        return HStack(spacing: 5) {
            ForEach(start..<min(words.count, start + window), id: \.self) { i in
                Capsule().fill(i == index ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
    }

    /// "Xem thêm · <review status>", coloured by how urgent the review is.
    private var moreButton: some View {
        let owned = store.isOwned(current)
        let (status, urgency) = WordCardStyle.status(store.display(current))
        let label = owned ? "Xem thêm · \(status)" : "Xem thêm"
        let style: OmniTintButtonStyle
        if !owned {
            style = OmniTintButtonStyle(fill: Color.white.opacity(0.14), shadow: Color.white.opacity(0.06))
        } else if urgency == 2 {
            style = OmniTintButtonStyle(fill: Color(hex: 0xE0453A), shadow: Color(hex: 0xA8282A))
        } else if urgency == 1 {
            style = OmniTintButtonStyle(fill: Color(hex: 0xF08A24), shadow: Color(hex: 0xC25E0E))
        } else {
            style = OmniTintButtonStyle(fill: palette.cta, shadow: palette.ctaShadow)
        }
        return Button { showInfo = true } label: { Text(label) }
            .buttonStyle(style)
            .accessibilityIdentifier("explore-card-more")
    }

    private var bottom: some View {
        VStack(spacing: 10) {
            if !store.isOwned(current) {
                Button {
                    Task { await store.download([current], topicId: current.topic_id) }
                } label: {
                    Text(store.downloading.contains(current.catalog_id ?? "") ? "Đang tải..." : "Tải về và bắt đầu học")
                }
                .buttonStyle(OmniPrimaryButtonStyle())
                .disabled(!store.downloading.isEmpty)
            }
            moreButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Swipe from the left edge to go back

private struct OmniEdgeSwipeBack: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            // a thin strip along the left edge, so the pages in the middle still swipe freely
            Color.clear
                .frame(width: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.width > 70 && abs(value.translation.height) < 120 { action() }
                        }
                )
                .ignoresSafeArea()
        }
    }
}

extension View {
    /// Swiping right from the left edge of the screen calls `action` (dismiss a full-screen page).
    func omniEdgeSwipeBack(_ action: @escaping () -> Void) -> some View { modifier(OmniEdgeSwipeBack(action: action)) }
}

// MARK: - Code entry for a physical card

struct OmniCardCodeSheet: View {
    let onOpen: (Vocabulary) -> Void
    @State private var code = ""
    @State private var error: String?
    @State private var isChecking = false
    @FocusState private var focused: Bool
    private let length = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image("CardBack").resizable()
                    .frame(width: 56, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .rotationEffect(.degrees(-6))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nhập mã thẻ").font(.omniDisplay(24, weight: 800))
                    Text("Mã \(length) ký tự in ở góc dưới thẻ giấy Omninary").font(.omniBody(12.5, weight: 500)).foregroundStyle(Color(hex: 0x5B6779))
                }
            }
            .padding(.top, 24)

            ZStack {
                TextField("", text: $code)
                    .focused($focused)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    // the field only takes input; the boxes show it
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .opacity(0.02)
                    .onChange(of: code) { _, value in
                        let clean = String(value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(length))
                        if clean != value { code = clean }
                        error = nil
                    }
                    .accessibilityLabel("Mã thẻ")
                HStack(spacing: 12) {
                    ForEach(0..<length, id: \.self) { i in box(i) }
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 26)


            Button { Task { await open() } } label: { Text(isChecking ? "Đang mở..." : "Mở thẻ") }
                .buttonStyle(OmniPrimaryButtonStyle())
                .disabled(code.count < length || isChecking)
                .padding(.top, 26)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.omniBody(12, weight: 700))
                    .foregroundStyle(Color(hex: 0xA8282A))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFDECEA), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 14)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .foregroundStyle(Color(hex: 0x17202E))
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        // just tall enough for the card back, the four boxes and the button; a little more when an error shows
        .presentationDetents([.height(error == nil ? 345 : 405)])
    }

    private func box(_ i: Int) -> some View {
        let chars = Array(code)
        let active = focused && i == min(chars.count, length - 1) && chars.count < length
        let filled = i < chars.count
        return Text(filled ? String(chars[i]) : "")
            .font(OmniFonts.font(.silkscreen, 700, size: 28))
            .frame(width: 58, height: 68)
            .background(Color(hex: 0xF3F6FB), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(error != nil ? Color(hex: 0xD0453B) : (filled || active ? Color(hex: 0x2F6FD6) : Color(hex: 0xD5DBE6)), lineWidth: 2))
    }

    private func open() async {
        isChecking = true
        defer { isChecking = false }
        do {
            guard let id = try await VocabularyRepository.redeemCardCode(code),
                  let vocab = try await VocabularyRepository.fetchCatalogVocab(id: id) else {
                error = "Mã không đúng, kiểm tra lại các ký tự nhé"
                if OmniSoundSettings.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                return
            }
            onOpen(vocab)
        } catch {
            self.error = "Không mở được thẻ: \(error.localizedDescription)"
        }
    }
}

// MARK: - Opening a card: shake, CEFR glow, flip to the front, badge pops, then download

struct OmniCardRevealView: View {
    let vocab: Vocabulary
    @ObservedObject var store: OmniExploreStore
    @Environment(\.dismiss) private var dismiss
    @State private var angle: Double = 0
    @State private var shake: Double = 0
    @State private var glow = false
    @State private var rays: Double = 0
    @State private var badge = false
    @State private var done = false
    @State private var showStage = false
    @State private var tilt: CGSize = .zero
    @State private var dragging = false
    @StateObject private var motion = OmniCardMotion()

    private var cefrColors: (Color, Color) { WordCardStyle.cefrPair(vocab.CEFR) }
    /// The front faces the learner between a quarter and three quarters of each full turn.
    private var showsFront: Bool {
        let a = angle.truncatingRemainder(dividingBy: 360)
        return a >= 90 && a < 270
    }
    private let cardWidth: CGFloat = 250

    var body: some View {
        let (c1, c2) = cefrColors
        let scale = cardWidth / WordCardView.fullSize.width
        let cardHeight = WordCardView.fullSize.height * scale
        ZStack {
            OmniStageBackground()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Đóng")
                    Text(vocab.card_no.map { "Thẻ mới · #\($0)" } ?? "Thẻ mới")
                        .font(.omniBody(13, weight: 700)).foregroundStyle(Color(hex: 0xCFD6EE))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [c2.opacity(0.9), c2.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 190))
                        .frame(width: 380, height: 380)
                        .opacity(glow ? 1 : 0)
                    // light rays turning behind the card
                    ForEach(0..<14, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient(colors: [c1.opacity(0.55), .clear], startPoint: .center, endPoint: .top))
                            .frame(width: 14, height: 300)
                            .offset(y: -150)
                            .rotationEffect(.degrees(Double(i) * (360.0 / 14) + rays))
                    }
                    .opacity(glow ? 0.8 : 0)
                    .scaleEffect(glow ? 1 : 0.4)

                    ZStack {
                        // back face
                        Image("CardBack").resizable()
                            .frame(width: cardWidth, height: cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .opacity(showsFront ? 0 : 1)
                        // front face, pre-flipped so it reads correctly after the turn; opening a card always
                        // shows its CEFR colours, the grey unlearned look only starts in the learner's set
                        WordCardView(vocab: store.display(vocab), mastery: store.mastery(vocab), mode: .full, rarity: true)
                            .scaleEffect(scale)
                            .frame(width: cardWidth, height: cardHeight)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                            .opacity(showsFront ? 1 : 0)
                    }
                    .shadow(color: c2.opacity(glow ? 0.8 : 0), radius: 30)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(Double(tilt.width + motion.roll * 40) / 6), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(Double(-tilt.height - motion.pitch * 40) / 6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .rotationEffect(.degrees(shake))
                    .scaleEffect(done ? (dragging ? 1.04 : 1) : (angle > 0 ? 1.06 : 0.92))
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                guard done else { return }
                                dragging = true
                                tilt = CGSize(width: max(-90, min(90, value.translation.width)), height: max(-90, min(90, value.translation.height)))
                            }
                            .onEnded { _ in
                                dragging = false
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { tilt = .zero }
                            }
                    )
                    .onTapGesture(count: 2) {
                        guard done else { return }
                        if OmniSoundSettings.hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { angle += 180 }
                    }

                    Text(vocab.CEFR?.uppercased() ?? "")
                        .font(.omniDisplay(20, weight: 800))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(c2, in: Capsule())
                        .overlay(Capsule().stroke(.white, lineWidth: 3))
                        .shadow(color: c1, radius: 12)
                        .scaleEffect(badge ? 1 : 0.2)
                        .opacity(badge ? 1 : 0)
                        .offset(y: -cardHeight / 2 - 34)
                }
                .frame(height: cardHeight + 90)
                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    if done {
                        Text("Bạn vừa mở thẻ \(vocab.vocab ?? "")!").font(.omniDisplay(22, weight: 800))
                        if store.isOwned(vocab) {
                            Text("Từ này đã có trong bộ từ của bạn").font(.omniBody(12, weight: 500)).foregroundStyle(Color(hex: 0xCFD6EE))
                            Button { showStage = true } label: { Text("Xem thẻ") }
                                .buttonStyle(OmniPrimaryButtonStyle())
                        } else {
                            Button {
                                Task { if await store.download([vocab], topicId: vocab.topic_id) { showStage = true } }
                            } label: { Text(store.downloading.isEmpty ? "Tải về và bắt đầu học" : "Đang tải...") }
                                .buttonStyle(OmniPrimaryButtonStyle())
                                .disabled(!store.downloading.isEmpty)
                        }
                    }
                }
                .frame(height: 130)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .task { await play() }
        .omniEdgeSwipeBack { dismiss() }
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .fullScreenCover(isPresented: $showStage) {
            OmniCardStageView(title: "Thẻ của bạn", words: [vocab], index: 0, store: store)
        }
        .alert("Thông báo", isPresented: $store.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.alertMessage)
        }
    }

    private func play() async {
        let haptics = OmniSoundSettings.hapticsEnabled
        try? await Task.sleep(for: .milliseconds(500))
        // the face-down card trembles for a while, growing stronger, before it turns over
        for burst in 0..<4 {
            let amp = 2.0 + Double(burst) * 1.5
            for step in [-amp, amp, -amp, amp, 0] {
                withAnimation(.easeInOut(duration: 0.07)) { shake = step }
                if haptics { UIImpactFeedbackGenerator(style: burst < 2 ? .light : .medium).impactOccurred() }
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .milliseconds(burst < 3 ? 220 : 120))
        }
        withAnimation(.easeOut(duration: 0.5)) { glow = true }
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { rays = 360 }
        try? await Task.sleep(for: .milliseconds(450))
        if haptics { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { angle = 180 }
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { badge = true }
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.easeInOut(duration: 0.4)) { done = true }
    }
}

// MARK: - Device tilt for the opened card


/// Gentle roll and pitch of the phone, so the opened card leans as the learner tilts it.
@MainActor
final class OmniCardMotion: ObservableObject {
    @Published private(set) var roll: CGFloat = 0
    @Published private(set) var pitch: CGFloat = 0
    private let manager = CMMotionManager()
    private var base: (roll: Double, pitch: Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.attitude else { return }
            // measured from how the phone was held when the card opened
            let base = self.base ?? (a.roll, a.pitch)
            self.base = base
            self.roll = CGFloat(max(-0.5, min(0.5, a.roll - base.roll)))
            self.pitch = CGFloat(max(-0.5, min(0.5, a.pitch - base.pitch)))
        }
    }

    func stop() { manager.stopDeviceMotionUpdates(); base = nil }
}
