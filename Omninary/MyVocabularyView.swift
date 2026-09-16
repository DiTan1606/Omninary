import SwiftUI

struct MyVocabularyView: View {
    @State private var vocabs: [Vocabulary] = []
    @State private var privateTopics: [UserTopic] = []
    @State private var topicSubmissions: [TopicContribution] = []
    @State private var isLoading = false
    @State private var showingCreateTopic = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    private var topicItems: [MyVocabularyTopicItem] {
        var itemsById: [String: MyVocabularyTopicItem] = [:]

        for vocab in vocabs {
            let topicName = vocab.topics?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = topicName?.isEmpty == false ? topicName! : "Chưa phân loại"
            let key = vocab.topic_id ?? "uncategorized-\(name)"
            var item = itemsById[key] ?? MyVocabularyTopicItem(id: key, name: name, topic: nil, vocabs: [], submission: nil)
            item.vocabs.append(vocab)
            itemsById[key] = item
        }

        for topic in privateTopics {
            var item = itemsById[topic.id] ?? MyVocabularyTopicItem(id: topic.id, name: topic.name, topic: topic, vocabs: [], submission: nil)
            item.topic = topic
            item.name = topic.name
            itemsById[topic.id] = item
        }

        let latestSubmissionByTopic = Dictionary(
            grouping: topicSubmissions.compactMap { submission -> TopicContribution? in
                submission.topicId == nil ? nil : submission
            },
            by: { $0.topicId ?? "" }
        ).mapValues { submissions in
            submissions.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }.first
        }

        for (topicId, submission) in latestSubmissionByTopic {
            guard var item = itemsById[topicId], let submission else { continue }
            item.submission = submission
            itemsById[topicId] = item
        }

        return itemsById.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if isLoading && topicItems.isEmpty {
                ProgressView("Đang tải dữ liệu...")
            } else if topicItems.isEmpty {
                VStack {
                    Text("Chưa có bộ từ nào.")
                        .foregroundColor(.secondary)
                    Text("Hãy tải bộ từ ở Trang chủ hoặc tạo topic riêng để học theo sở thích.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
            } else {
                List {
                    if !topicItems.isEmpty {
                        Section("Bộ từ của tôi") {
                            ForEach(topicItems) { item in
                                NavigationLink {
                                    TopicDetailView(
                                        topic: item.name,
                                        topicInfo: item.topic,
                                        topicSubmission: item.submission,
                                        vocabs: item.vocabs,
                                        onRefresh: {
                                            Task { await fetchVocabs() }
                                        }
                                    )
                                } label: {
                                    MyVocabularyTopicRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await fetchVocabs()
        }
        .navigationTitle("My Vocabulary")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateTopic = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .task {
            await fetchVocabs()
        }
        .alert("Thông báo", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingCreateTopic) {
            PrivateTopicCreateView(onComplete: {
                Task { await fetchVocabs() }
            })
        }
    }
    
    @MainActor
    private func fetchVocabs() async {
        guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
            vocabs = []
            privateTopics = []
            topicSubmissions = []
            isLoading = false
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let fetchedVocabs = VocabularyRepository.fetchUserVocabs(userId: userId, ordered: true)
            async let fetchedPrivateTopics = VocabularyRepository.fetchUserPrivateTopics(userId: userId)
            async let fetchedSubmissions = ContributionRepository.fetchUserTopicSubmissions()
            let result = try await (fetchedVocabs, fetchedPrivateTopics, fetchedSubmissions)

            vocabs = result.0
            privateTopics = result.1
            topicSubmissions = result.2
        } catch {
            alertMessage = "Không tải được My Vocabulary: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

private struct MyVocabularyTopicItem: Identifiable {
    let id: String
    var name: String
    var topic: UserTopic?
    var vocabs: [Vocabulary]
    var submission: TopicContribution?
}

private struct MyVocabularyTopicRow: View {
    let item: MyVocabularyTopicItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.headline)

                    if item.topic?.visibility == "private" {
                        Text("Riêng tư")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.12))
                            .cornerRadius(4)
                    }

                    if let status = item.submission?.status {
                        statusBadge(status)
                    }
                }

                Text("\(uniqueWordCount) từ")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var uniqueWordCount: Int {
        Set(item.vocabs.compactMap { $0.vocab?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        if status == "pending" {
            Text("Chờ duyệt")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)
        } else if status == "rejected" {
            Text("Không duyệt")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12))
                .cornerRadius(4)
        }
    }
}

private struct PrivateTopicCreateView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic riêng") {
                    TextField("Tên topic", text: $name)
                    TextField("Mô tả ngắn", text: $description)
                }

                Section {
                    Text("Topic riêng chỉ có bạn thấy. Bạn có thể thêm từ và học ngay, khi thấy đủ hay thì gửi admin duyệt để chia sẻ lên hệ thống.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tạo topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tạo") {
                        Task { await createTopic() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Đang tạo...")
                        .padding()
                        .background(Color(.systemBackground).opacity(0.85))
                        .cornerRadius(10)
                }
            }
            .alert("Thông báo", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("Đã tạo") {
                        onComplete()
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func createTopic() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await VocabularyRepository.createPrivateTopic(name: name, description: description)
            alertMessage = "Đã tạo topic riêng. Bạn có thể vào topic này để thêm từ và học ngay."
            showingAlert = true
        } catch {
            alertMessage = "Tạo topic thất bại: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}
