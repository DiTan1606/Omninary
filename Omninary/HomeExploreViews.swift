import SwiftUI

struct VocabularyExploreView: View {
    let topics: [String]
    let groupedVocabs: [String: [Vocabulary]]
    let downloadedKeysByTopic: [String: Set<String>]
    @Binding var isDownloading: Bool
    let downloadTopic: ([Vocabulary], String) -> Void

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var body: some View {
        List {
            if topics.isEmpty {
                ContentUnavailableView(
                    "Chưa có chủ đề",
                    systemImage: "books.vertical",
                    description: Text("Các chủ đề từ vựng sẽ xuất hiện tại đây.")
                )
                .foregroundStyle(isExtra ? .white : .primary)
            } else {
                Section {
                    ForEach(Array(topics.enumerated()), id: \.element) { index, topic in
                        let isBottom = (index == topics.count - 1)
                        topicRow(topic: topic)
                            .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                            .listRowSeparator(isBottom ? .hidden : .visible, edges: .bottom)
                            .listRowSeparator(.hidden, edges: .top)
                            .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                    }
                } header: {
                    Text("Chủ đề từ vựng")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(isExtra ? Color.white.opacity(0.8) : .secondary)
                }
                .listSectionSeparator(.hidden, edges: .all)
            }
        }
        .scrollContentBackground(isExtra ? .hidden : .automatic)
        .background {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle("Khám phá Từ vựng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func topicRow(topic: String) -> some View {
        let topicVocabs = groupedVocabs[topic] ?? []
        let downloadedKeys = downloadedKeysByTopic[topicVocabs.first?.topic_id ?? ""] ?? []
        let missingVocabs = topicVocabs.filter { vocab in
            guard let key = vocab.downloadIdentityKey else { return false }
            return !downloadedKeys.contains(key)
        }
        let hasDownloadedSome = !downloadedKeys.isEmpty
        let isFullyDownloaded = hasDownloadedSome && missingVocabs.isEmpty
        let needsUpdate = hasDownloadedSome && !missingVocabs.isEmpty
        let wordCount = Vocabulary.sortedItems(topicVocabs).count

        NavigationLink {
            TopicPreviewView(
                topicName: topic,
                vocabs: topicVocabs,
                missingVocabs: missingVocabs,
                isFullyDownloaded: isFullyDownloaded,
                needsUpdate: needsUpdate,
                onDownload: { downloadTopic(missingVocabs, topic) },
                isDownloading: $isDownloading
            )
        } label: {
            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isExtra ? ExtraAuroraPalette.violet.opacity(0.2) : Color.blue.opacity(0.12))
                        .frame(width: 50, height: 50)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic)
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(isExtra ? Color.white : Color.primary)
                    Text("\(wordCount) từ")
                        .font(.caption)
                        .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                }
                Spacer()
                downloadStatus(isFullyDownloaded: isFullyDownloaded, needsUpdate: needsUpdate, missingCount: missingVocabs.count)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func downloadStatus(isFullyDownloaded: Bool, needsUpdate: Bool, missingCount: Int) -> some View {
        if isFullyDownloaded {
            Text("Đã tải")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppSemanticColor.success)
        } else if needsUpdate {
            Text("+\(missingCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppSemanticColor.attention)
        } else {
            Text("Mới")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isExtra ? ExtraAuroraPalette.electricBlue : Color(red: 0.0, green: 0.48, blue: 1.0))
        }
    }
}

struct ListeningExploreView: View {
    let catalog: [ListeningSeriesCatalogItem]
    let downloadedLessonIds: Set<String>
    let refreshLibrary: () -> Void

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var body: some View {
        List {
            if catalog.isEmpty {
                ContentUnavailableView(
                    "Chưa có bài luyện nghe",
                    systemImage: "headphones",
                    description: Text("Các bài luyện nghe sẽ xuất hiện tại đây.")
                )
                .foregroundStyle(isExtra ? .white : .primary)
            } else {
                Section {
                    ForEach(Array(catalog.enumerated()), id: \.element.id) { index, item in
                        let isBottom = (index == catalog.count - 1)
                        NavigationLink {
                            ListeningSeriesPreviewView(
                                catalogItem: item,
                                downloadedLessonIds: downloadedLessonIds,
                                onLibraryChanged: refreshLibrary
                            )
                        } label: {
                            ListeningSystemSeriesRow(
                                catalogItem: item,
                                downloadedLessonIds: downloadedLessonIds,
                                showChevron: false
                            )
                        }
                        .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                        .listRowSeparator(isBottom ? .hidden : .visible, edges: .bottom)
                        .listRowSeparator(.hidden, edges: .top)
                        .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                    }
                } header: {
                    Text("Bài luyện nghe")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(isExtra ? Color.white.opacity(0.8) : .secondary)
                }
                .listSectionSeparator(.hidden, edges: .all)
            }
        }
        .scrollContentBackground(isExtra ? .hidden : .automatic)
        .background {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle("Khám phá Bài luyện nghe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct DailyLearningStatsPlaceholderView: View {
    let date: Date

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var body: some View {
        Group {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle("Thống kê ngày")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
