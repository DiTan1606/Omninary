import SwiftUI
import Supabase

struct VocabularyLocationSnapshot: Codable {
    struct Membership: Codable {
        let vocab_id: String
        let topic_id: String
    }
    let vocab_ids: [String]
    let memberships: [Membership]
}

extension VocabularyRepository {
    private struct LocationParams: Encodable {
        let p_vocab_ids: [String]
        let p_source_topic_id: String
        let p_destination_topic_id: String?
        let p_action: String
    }
    private struct UndoParams: Encodable { let p_snapshot: VocabularyLocationSnapshot }
    private struct DeleteWorkspaceParams: Encodable { let p_vocab_ids: [String] }

    static func ensureVocabularyRoot() async throws -> String {
        try await supabase.rpc("ensure_vocabulary_root").execute().value
    }
    static func changeLocation(_ ids: [String], from source: String, to destination: String?, action: String) async throws -> VocabularyLocationSnapshot {
        try await supabase.rpc("change_vocabulary_location", params: LocationParams(
            p_vocab_ids: Array(Set(ids)).sorted(), p_source_topic_id: source,
            p_destination_topic_id: destination, p_action: action
        )).execute().value
    }
    static func restoreLocations(_ snapshot: VocabularyLocationSnapshot) async throws {
        try await supabase.rpc("restore_vocabulary_locations", params: UndoParams(p_snapshot: snapshot)).execute()
    }
    static func deleteFromWorkspace(_ ids: [String]) async throws {
        try await supabase.rpc("delete_vocabulary_from_workspace", params: DeleteWorkspaceParams(p_vocab_ids: ids)).execute()
    }
}

struct VocabularyFileEntry: Identifiable {
    let vocabulary: Vocabulary
    var id: String { vocabulary.vocabularyIdentity }
    var catalogIDs: [String] { vocabulary.catalog_id.map { [$0] } ?? [] }
    var title: String { vocabulary.vocab ?? "Từ vựng" }
    var subtitle: String { vocabulary.V_meaning ?? vocabulary.E_meaning ?? "Chưa có mô tả" }

    static func entries(from vocabularies: [Vocabulary], topicID: String) -> [VocabularyFileEntry] {
        Vocabulary.sortedItems(vocabularies.filter { $0.collectionTopics.contains { $0.id == topicID } })
            .map { VocabularyFileEntry(vocabulary: $0) }
    }
}

@MainActor
final class VocabularyWorkspaceStore: ObservableObject {
    @Published var meanings: [Vocabulary] = []
    @Published var privateTopics: [UserTopic] = []
    @Published var submissions: [TopicContribution] = []
    @Published var rootID: String?
    @Published var isBusy = false
    @Published var error: String?
    @Published var undoSnapshot: VocabularyLocationSnapshot?
    @Published var notice: String?

    var folders: [UserTopic] {
        var all = Dictionary(uniqueKeysWithValues: privateTopics.map { ($0.id, $0) })
        for meaning in meanings {
            for topic in meaning.collectionTopics { all[topic.id] = topic }
        }
        return all.values.filter { $0.id != rootID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var rootTopic: UserTopic? { privateTopics.first { $0.id == rootID } }
    var destinations: [UserTopic] {
        privateTopics.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func load() async {
        guard let userID = AuthManager.shared.currentUser?.id.uuidString else {
            error = "Vui lòng đăng nhập để mở kho từ vựng."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            rootID = try await VocabularyRepository.ensureVocabularyRoot()
            async let vocab = VocabularyRepository.fetchUserVocabs(userId: userID, ordered: true)
            async let topics = VocabularyRepository.fetchUserPrivateTopics(userId: userID)
            async let reviews = ContributionRepository.fetchUserTopicSubmissions()
            (meanings, privateTopics, submissions) = try await (vocab, topics, reviews)
        } catch { self.error = "Không tải được kho từ vựng: \(error.localizedDescription)" }
    }
    func change(_ ids: [String], from source: String, to destination: String? = nil, action: String) async {
        guard !isBusy else { return }
        isBusy = true
        do {
            undoSnapshot = try await VocabularyRepository.changeLocation(ids, from: source, to: destination, action: action)
            notice = action == "add" ? "Đã thêm vào bộ từ khác." : "Đã cập nhật vị trí các từ."
            await load()
        } catch { self.error = error.localizedDescription }
        isBusy = false
    }
    func undo() async {
        guard let undoSnapshot, !isBusy else { return }
        isBusy = true
        do {
            try await VocabularyRepository.restoreLocations(undoSnapshot)
            self.undoSnapshot = nil
            notice = nil
            await load()
        } catch { self.error = error.localizedDescription }
        isBusy = false
    }
    func delete(_ ids: [String]) async {
        guard !isBusy else { return }
        isBusy = true
        do {
            try await VocabularyRepository.deleteFromWorkspace(ids)
            undoSnapshot = nil
            notice = "Đã xoá khỏi kho học."
            await load()
        } catch { self.error = error.localizedDescription }
        isBusy = false
    }
    func deleteFolder(_ topic: UserTopic) async {
        guard topic.id != rootID, !isBusy else { return }
        isBusy = true
        do {
            try await VocabularyRepository.deletePrivateTopic(topic)
            undoSnapshot = nil
            notice = "Đã xoá bộ từ. Tiến độ học được giữ nguyên."
            await load()
        } catch { self.error = error.localizedDescription }
        isBusy = false
    }
}
