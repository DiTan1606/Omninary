import SwiftUI

struct VocabularyExploreView: View {
    let topics: [String]
    let groupedVocabs: [String: [Vocabulary]]
    let downloadedKeysByTopic: [String: Set<String>]
    @Binding var isDownloading: Bool
    let downloadTopic: ([Vocabulary], String) -> Void

    var body: some View {
        List {
            if topics.isEmpty {
                ContentUnavailableView(
                    "Chưa có chủ đề",
                    systemImage: "books.vertical",
                    description: Text("Các chủ đề từ vựng sẽ xuất hiện tại đây.")
                )
            } else {
                Section("Chủ đề từ vựng") {
                    ForEach(topics, id: \.self) { topic in
                        topicRow(topic: topic)
                    }
                }
            }
        }
        .navigationTitle("Khám phá Từ vựng")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func topicRow(topic: String) -> some View {
        let topicVocabs = groupedVocabs[topic] ?? []
        let downloadedKeys = downloadedKeysByTopic[topic] ?? []
        let missingVocabs = topicVocabs.filter { vocab in
            guard let key = vocab.downloadIdentityKey else { return false }
            return !downloadedKeys.contains(key)
        }
        let hasDownloadedSome = !downloadedKeys.isEmpty
        let isFullyDownloaded = hasDownloadedSome && missingVocabs.isEmpty
        let needsUpdate = hasDownloadedSome && !missingVocabs.isEmpty
        let wordCount = Set(topicVocabs.compactMap { $0.vocab?.trimmingCharacters(in: .whitespaces).lowercased() }).count

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
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(topic)
                        .font(.headline)
                    Text("\(wordCount) từ vựng")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                downloadStatus(isFullyDownloaded: isFullyDownloaded, needsUpdate: needsUpdate, missingCount: missingVocabs.count)
            }
        }
    }

    @ViewBuilder
    private func downloadStatus(isFullyDownloaded: Bool, needsUpdate: Bool, missingCount: Int) -> some View {
        if isFullyDownloaded {
            Text("Đã tải")
                .foregroundStyle(.green)
        } else if needsUpdate {
            Text("+\(missingCount)")
                .foregroundStyle(.orange)
        } else {
            Text("Mới")
                .foregroundStyle(.blue)
        }
    }
}

struct ListeningExploreView: View {
    let catalog: [ListeningSeriesCatalogItem]
    let downloadedLessonIds: Set<String>
    let refreshLibrary: () -> Void

    var body: some View {
        List {
            if catalog.isEmpty {
                ContentUnavailableView(
                    "Chưa có bài luyện nghe",
                    systemImage: "headphones",
                    description: Text("Các bài luyện nghe sẽ xuất hiện tại đây.")
                )
            } else {
                Section("Bài luyện nghe") {
                    ForEach(catalog) { item in
                        NavigationLink {
                            ListeningSeriesPreviewView(
                                catalogItem: item,
                                downloadedLessonIds: downloadedLessonIds,
                                onLibraryChanged: refreshLibrary
                            )
                        } label: {
                            ListeningSystemSeriesRow(
                                catalogItem: item,
                                downloadedLessonIds: downloadedLessonIds
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Khám phá Bài luyện nghe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DailyLearningStatsPlaceholderView: View {
    let date: Date

    var body: some View {
        Color(UIColor.systemGroupedBackground)
            .ignoresSafeArea()
            .navigationTitle("Thống kê ngày")
            .navigationBarTitleDisplayMode(.inline)
    }
}
