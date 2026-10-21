#if DEBUG
import SwiftUI

/// Local fixtures for checking presentation without signing in or modifying learning data.
struct InterfacePolishPreview: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var isDownloading = false
    private var isExtra: Bool { (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme }
    private let month = StreakClock.parseDay("2026-10-18")!
    private let words = [
        Vocabulary(catalog_id: "preview-apple", vocab: "apple", CEFR: "A1", IPA: "/ˈæp.əl/", word_form: "noun", V_meaning: "Quả táo"),
        Vocabulary(catalog_id: "preview-adapt", vocab: "adapt", CEFR: "B2", IPA: "/əˈdæpt/", word_form: "verb", V_meaning: "Thích nghi")
    ]
    private var listeningSample: ListeningSeriesCatalogItem {
        let series = ListeningSeries(id: "preview-series", slug: nil, title: "Bài nghe mẫu", vi_title: nil, description: nil, is_published: true, created_at: nil)
        let lesson = ListeningLesson(id: "preview-lesson", series_id: series.id, slug: nil, source_id: nil, title: "A day at school", vi_title: "Một ngày ở trường", cefr: "A1", description: nil, is_published: true, created_at: nil)
        return ListeningSeriesCatalogItem(series: series, lessons: [lesson])
    }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(spacing: AppSpacing.cardGap) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Lịch học tập").font(.headline)
                            CustomMonthCalendar(month: month,
                                activityLogs: ["2026-10-15": true],
                                frozenDates: ["2026-10-16"], rescuedDates: ["2026-10-17"],
                                isExtra: isExtra) { _ in }
                        }
                        .padding(AppSpacing.card)
                        .appSurface(.card, isExtra: isExtra)
                        NavigationLink("Xem bộ từ mẫu") {
                            TopicPreviewView(topicName: "Bộ từ mẫu", vocabs: words,
                                missingVocabs: [words[0]], isFullyDownloaded: false,
                                needsUpdate: true, onDownload: {}, isDownloading: $isDownloading)
                        }
                        .buttonStyle(.borderedProminent)
                        NavigationLink("Xem seri mẫu") {
                            ListeningSeriesPreviewView(catalogItem: listeningSample, downloadedLessonIds: [], onLibraryChanged: {})
                        }
                    }
                    .padding(18)
                }
                .background {
                    if isExtra { AuroraBackdrop() }
                    else { Color(UIColor.systemGroupedBackground).ignoresSafeArea() }
                }
                .navigationTitle("Kiểm tra giao diện")
            }
            .tabItem { Label("Trang chủ", systemImage: "house") }
            LibraryView().tabItem { Label("Thư viện", systemImage: "books.vertical") }
            LearningView().tabItem { Label("Học tập", systemImage: "graduationcap") }
        }
        .preferredColorScheme(isExtra ? .dark : nil)
    }
}
#endif
