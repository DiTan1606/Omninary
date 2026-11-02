import SwiftUI
import WebKit
import AVFoundation

struct GrammarLessonView: View {
    let topic: GrammarTopic
    @ObservedObject var store: GrammarProgressStore
    @Environment(\.omniPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OmniSoundSettings.effectsKey) private var effectsEnabled = true
    @State private var content: GrammarLessonSession?
    @State private var ready = false
    @State private var failure: String?
    @State private var reloadID = UUID()
    @State private var closing = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if let url = GrammarLessonAssets.lessonURL(topic), let content {
                GrammarLessonWebView(topic: topic, url: url, store: store, content: content, palette: palette,
                                     isActive: scenePhase == .active, effectsEnabled: effectsEnabled,
                                     onReady: { ready = true }, onFailure: { failure = $0 }, onExit: { closeLesson() })
                    .id(reloadID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("grammar-lesson-web")
            }
            if !ready && failure == nil {
                ProgressView("Đang tải bài học…")
                    .font(.omniBody(14)).padding(24)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 20))
            }
            if let failure { errorContent(failure) }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: reloadID) {
            do {
                guard GrammarLessonAssets.lessonURL(topic) != nil else { throw GrammarContentError.invalidContent }
                let loaded = try await store.loadLesson(for: topic)
                if Task.isCancelled { loaded.close(); return }
                content = loaded
            } catch {
                if !Task.isCancelled { failure = (error as? GrammarContentError)?.errorDescription ?? "Chưa tải được bài học. Bạn kiểm tra kết nối rồi thử lại nhé." }
            }
        }
        .onDisappear { content?.close() }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.saveError != nil {
                GrammarProgressStatus(store: store).padding(8).background(palette.background)
            } else if closing {
                ProgressView("Đang lưu tiến độ…").font(.omniBody(13)).padding(12).frame(maxWidth: .infinity).background(palette.card)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await store.flush() } }
        }
        .onAppear {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        }
    }

    private func closeLesson() {
        guard !closing else { return }
        closing = true
        Task {
            if await store.flush() { dismiss() }
            closing = false
        }
    }

    private func errorContent(_ text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(palette.muted)
            Text(text).font(.omniBody(15)).multilineTextAlignment(.center).foregroundStyle(palette.text)
            if failure != nil {
                Button("Mở lại bài học") { content?.close(); content = nil; failure = nil; ready = false; reloadID = UUID() }
                    .buttonStyle(OmniPrimaryButtonStyle())
            }
            Button("Về lộ trình") { closeLesson() }.font(.omniBody(14, weight: 700))
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.background)
    }
}

private struct GrammarLessonWebView: UIViewRepresentable {
    let topic: GrammarTopic
    let url: URL
    let store: GrammarProgressStore
    let content: GrammarLessonSession
    let palette: OmniPalette
    let isActive: Bool
    let effectsEnabled: Bool
    let onReady: () -> Void
    let onFailure: (String) -> Void
    let onExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(topic: topic, root: url.deletingLastPathComponent(), store: store, content: content,
                    onReady: onReady, onFailure: onFailure, onExit: onExit)
    }
    func makeUIView(context: Context) -> UIView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isTextInteractionEnabled = false
        let controller = configuration.userContentController
        let theme = Self.theme(palette)
        let lessonData = (try? content.manifest.payload()) ?? [:]
        let initial = "window.gramCourseData=\(Self.json(lessonData));window.gramInitialState=\(Self.json(store.snapshot(for: topic)));window.gramInitialTheme=\(Self.json(theme));window.gramEffectsEnabled=\(effectsEnabled ? "true" : "false");"
        controller.addUserScript(WKUserScript(source: initial, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(context.coordinator, name: "grammar")
        controller.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "grammarHistory")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(palette.background)
        view.scrollView.backgroundColor = UIColor(palette.background)
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = false
        view.isFindInteractionEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.bounces = false
        view.scrollView.bouncesZoom = false
        view.scrollView.minimumZoomScale = 1
        view.scrollView.maximumZoomScale = 1
        view.scrollView.pinchGestureRecognizer?.isEnabled = false
        view.scrollView.isScrollEnabled = false
        view.scrollView.delegate = context.coordinator
        view.navigationDelegate = context.coordinator
        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgeSwipe(_:)))
        edgeSwipe.edges = .left
        edgeSwipe.delegate = context.coordinator
        context.coordinator.webView = view
        context.coordinator.themeJSON = Self.json(theme)
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        // The web view sits in a host so the edge swipe can slide it off the page behind it.
        let host = UIView()
        host.clipsToBounds = true
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(view)
        host.addGestureRecognizer(edgeSwipe)
        return host
    }
    func updateUIView(_ host: UIView, context: Context) {
        guard let view = context.coordinator.webView else { return }
        view.overrideUserInterfaceStyle = palette.night ? .dark : .light
        view.backgroundColor = UIColor(palette.background)
        view.scrollView.backgroundColor = UIColor(palette.background)
        let theme = Self.json(Self.theme(palette))
        if context.coordinator.themeJSON != theme {
            context.coordinator.themeJSON = theme
            view.evaluateJavaScript("window.gramNative?.setTheme(\(theme))", completionHandler: nil)
        }
        view.evaluateJavaScript("window.gramNative?.setEffectsEnabled(\(effectsEnabled ? "true" : "false"))", completionHandler: nil)
        if !isActive && context.coordinator.wasActive { context.coordinator.pause() }
        context.coordinator.wasActive = isActive
    }
    static func dismantleUIView(_ host: UIView, coordinator: Coordinator) {
        guard let view = coordinator.webView else { return }
        view.endEditing(true)
        coordinator.content.close()
        view.evaluateJavaScript("window.gramLeave?.()", completionHandler: nil)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "grammar")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "grammarHistory", contentWorld: .page)
        view.navigationDelegate = nil
        view.scrollView.delegate = nil
        if OmniEdgeSwipe.innerBackView === view { OmniEdgeSwipe.innerBackView = nil }
    }

    private static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private static func css(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgba(\(Int((r * 255).rounded())),\(Int((g * 255).rounded())),\(Int((b * 255).rounded())),\(a))"
    }
    private static func theme(_ p: OmniPalette) -> [String: Any] {
        ["night": p.night, "colors": [
            "paper": css(p.background), "surface": css(p.card), "ink": css(p.text),
            "muted": css(p.muted), "line": css(p.line), "green": css(GrammarTheme.deep(p)),
            "on-green": css(.white), "soft": css(p.panel), "gold": css(p.gold),
            "gold-soft": css(p.night ? Color(hex: 0x403621) : Color(hex: 0xFFF3D0)),
            "coral": css(p.night ? Color(hex: 0xFFB293) : Color(hex: 0xAD502F)),
            "red-soft": css(p.night ? Color(hex: 0x4B3028) : Color(hex: 0xFFF0E8)),
            "stage": css(GrammarTheme.soft(p)),
            "shadow": css(p.shadow), "card-shadow": css(p.cardShadow)
        ]]
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let topic: GrammarTopic
        let root: URL
        let store: GrammarProgressStore
        let content: GrammarLessonSession
        let onReady: () -> Void
        let onFailure: (String) -> Void
        let onExit: () -> Void
        weak var webView: WKWebView?
        var themeJSON = "{}"
        var wasActive = true
        private var currentScreen = "topic"

        init(topic: GrammarTopic, root: URL, store: GrammarProgressStore, content: GrammarLessonSession,
             onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void, onExit: @escaping () -> Void) {
            self.topic = topic; self.root = root; self.store = store; self.content = content
            self.onReady = onReady; self.onFailure = onFailure; self.onExit = onExit
        }
        func pause() { webView?.evaluateJavaScript("window.gramPause?.()", completionHandler: nil) }
        private func isLocal(_ url: URL) -> Bool {
            url.isFileURL && url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let url = webView?.url, isLocal(url),
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "screen":
                let screen = body["screen"] as? String
                currentScreen = screen ?? "topic"
                // Inside theory, exercises, history… the edge swipe returns to the topic page, not the stage.
                OmniEdgeSwipe.innerBackView = currentScreen == "topic" ? nil : webView
                rememberScreen(currentScreen)
                if currentScreen != "exercise" { webView?.endEditing(true) }
                webView?.scrollView.isScrollEnabled = screen == "history" || screen == "result"
                webView?.configuration.preferences.isTextInteractionEnabled = screen == "exercise"
                webView?.scrollView.pinchGestureRecognizer?.isEnabled = false
            case "focus-answer":
                guard wasActive, currentScreen == "exercise", let key = body["key"] as? String,
                      !key.isEmpty, key.count <= 160 else { return }
                let payload = GrammarLessonWebView.json(["key": key])
                // A public, client-initiated focus request presents the software keyboard.
                webView?.evaluateJavaScript("window.gramFocusAnswer?.(\(payload))", completionHandler: nil)
            case "ready": onReady()
            case "failure":
#if DEBUG
                print("Gram web error:", body["detail"] ?? "Unknown")
#endif
                onFailure("Bài học tạm dừng. Bạn thử mở lại nhé.")
            case "progress":
                if let snapshot = body["payload"] as? [String: Any] { store.save(snapshot, for: topic) }
            case "exit": pause(); onExit()
            default: break
            }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            // WebKit can pan a focused field even with user scrolling disabled.
            // Fixed lesson pages already fit above the keyboard; keep their header anchored.
            guard !scrollView.isScrollEnabled,
                  abs(scrollView.contentOffset.x) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 else { return }
            scrollView.setContentOffset(.zero, animated: false)
        }
        /// Last look of each inner screen and where its back arrow leads, so the swipe can show
        /// the page underneath while it drags, like a navigation pop.
        private var screenshots: [String: UIImage] = [:]
        private var backTarget = "topic"
        private var backdrop: UIView?
        private var sliding = false

        private func rememberScreen(_ screen: String) {
            webView?.evaluateJavaScript("document.querySelector('.g-toolbar .g-icon-btn')?.dataset.action") { [weak self] value, _ in
                if let target = value as? String { self?.backTarget = target }
            }
            // Wait for the screen's entrance animation before taking its picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.currentScreen == screen, !self.sliding, let webView = self.webView else { return }
                webView.takeSnapshot(with: nil) { [weak self] image, _ in
                    if let image { self?.screenshots[screen] = image }
                }
            }
        }

        @objc func edgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard let webView, let host = webView.superview else { return }
            let width = max(host.bounds.width, 1)
            let x = min(max(gesture.translation(in: host).x, 0), width)
            switch gesture.state {
            case .began:
                sliding = true
                let under = UIImageView(image: screenshots[backTarget])
                under.backgroundColor = webView.backgroundColor
                under.contentMode = .scaleAspectFill
                under.frame = host.bounds
                let dim = UIView(frame: under.bounds)
                dim.backgroundColor = UIColor.black.withAlphaComponent(0.08)
                dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                under.addSubview(dim)
                host.insertSubview(under, belowSubview: webView)
                backdrop = under
                webView.layer.shadowColor = UIColor.black.cgColor
                webView.layer.shadowOpacity = 0.18
                webView.layer.shadowRadius = 10
                webView.layer.shadowOffset = CGSize(width: -3, height: 0)
                webView.layer.shadowPath = UIBezierPath(rect: webView.bounds).cgPath
                webView.endEditing(true)
                slide(to: 0, width: width)
            case .changed:
                slide(to: x, width: width)
            case .ended, .cancelled, .failed:
                let commit = gesture.state == .ended && (x > width * 0.35 || gesture.velocity(in: host).x > 600)
                UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.slide(to: commit ? width : 0, width: width)
                } completion: { _ in
                    guard commit else { self.finishSlide(); return }
                    // The same back arrow the toolbar shows, so leaving a quiz keeps its usual cleanup.
                    webView.evaluateJavaScript("document.querySelector('.g-toolbar .g-icon-btn')?.click()") { _, _ in
                        // Let the new screen paint before the web view slides back in place.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.finishSlide() }
                    }
                }
            default: break
            }
        }
        private func slide(to x: CGFloat, width: CGFloat) {
            webView?.transform = CGAffineTransform(translationX: x, y: 0)
            backdrop?.transform = CGAffineTransform(translationX: (x - width) * 0.3, y: 0)
            backdrop?.subviews.first?.alpha = 1 - x / width
        }
        private func finishSlide() {
            webView?.transform = .identity
            webView?.layer.shadowOpacity = 0
            backdrop?.removeFromSuperview()
            backdrop = nil
            sliding = false
            rememberScreen(currentScreen)
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            currentScreen != "topic" && !sliding
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            scrollView.pinchGestureRecognizer?.isEnabled = false
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame, let url = webView?.url, isLocal(url),
                  let body = message.body as? [String: Any], let type = body["type"] as? String else {
                replyHandler(nil, "Chưa nhận được yêu cầu hợp lệ."); return
            }
            switch type {
            case "load":
                guard let offset = body["offset"] as? Int, (0...1_000_000).contains(offset) else {
                    replyHandler(nil, "Chưa nhận được trang lịch sử."); return
                }
                Task { @MainActor in
                    do { replyHandler(try await store.attempts(for: topic, offset: offset), nil) }
                    catch { replyHandler(nil, "Chưa tải được lịch sử. Bạn thử lại nhé.") }
                }
            case "audio":
                guard let key = body["key"] as? String, key.count <= 80,
                      let version = body["version"] as? String, UUID(uuidString: version) == content.manifest.versionID else {
                    replyHandler(nil, "Tệp lời giảng chưa khớp bài học."); return
                }
                Task { @MainActor in
                    do { replyHandler(try await content.audio(key), nil) }
                    catch { replyHandler(nil, "Chưa tải được lời giảng. Bạn thử nghe lại nhé.") }
                }
            case "complete":
                guard let attempt = body["attempt"] as? [String: Any],
                      let version = attempt["lessonVersion"] as? String, UUID(uuidString: version) == content.manifest.versionID, let snapshot = body["snapshot"] as? [String: Any] else {
                    replyHandler(nil, "Kết quả chưa đầy đủ để lưu."); return
                }
                guard let level = attempt["level"] as? String,
                      let results = attempt["results"] as? [[String: Any]],
                      let course = try? content.manifest.courseObject(),
                      let banks = course["exercises"] as? [String: [[String: Any]]],
                      let bank = banks[level], results.count == bank.count else {
                    replyHandler(nil, "Kết quả chưa đủ số câu của bài học."); return
                }
                Task { @MainActor in
                    do { replyHandler(try await store.completeAttempt(attempt, snapshot: snapshot, for: topic, lessonPartIDs: try content.manifest.summary().part_ids), nil) }
                    catch { replyHandler(nil, "Chưa lưu được kết quả. Bạn kiểm tra kết nối rồi thử lại nhé.") }
                }
            default: replyHandler(nil, "Yêu cầu chưa được hỗ trợ.")
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, isLocal(url) else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.gramNative?.setTheme(\(themeJSON))", completionHandler: nil)
            onReady()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onFailure("Chưa mở được bài học. Bạn thử lại nhé.") }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onFailure("Bài học tạm dừng. Bạn thử mở lại nhé.") }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onFailure("Bài học tạm dừng. Bạn thử mở lại nhé.")
        }
    }
}
