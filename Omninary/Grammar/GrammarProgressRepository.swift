import Foundation
import Supabase

@MainActor
protocol GrammarProgressRepository {
    func fetch(userID: String) async throws -> [String: Data]
    func courses(userID: String) async throws -> [GrammarPublishedCourse]
    func lesson(topicID: String, userID: String) async throws -> GrammarLessonManifest
    func audio(_ asset: GrammarAudioAsset, userID: String) async throws -> Data
    func save(_ snapshot: Data, topicID: String, userID: String) async throws -> Data
    func attempts(topicID: String, userID: String, offset: Int) async throws -> [GrammarAttempt]
    func completeAttempt(_ attempt: Data, snapshot: Data, topicID: String, userID: String) async throws -> GrammarAttemptCompletion
}

@MainActor
struct SupabaseGrammarProgressRepository: GrammarProgressRepository {
    private struct ProgressRow: Codable {
        let user_id: UUID
        let topic_id: String
        let snapshot: AnyJSON
    }
    private struct SnapshotRow: Decodable {
        let topic_id: String
        let snapshot: AnyJSON
    }
    private let contentTransport = GrammarContentTransport()
    func courses(userID: String) async throws -> [GrammarPublishedCourse] { try await contentTransport.courses(userID: userID) }
    func lesson(topicID: String, userID: String) async throws -> GrammarLessonManifest { try await contentTransport.lesson(topicID: topicID, userID: userID) }
    func audio(_ asset: GrammarAudioAsset, userID: String) async throws -> Data { try await contentTransport.audio(asset, userID: userID) }
    private enum AccessError: Error { case signInRequired }

    func fetch(userID: String) async throws -> [String: Data] {
        guard UUID(uuidString: userID) != nil else { throw AccessError.signInRequired }
        let rows: [SnapshotRow] = try await supabase
            .from("user_grammar_progress")
            .select("topic_id,snapshot")
            .eq("user_id", value: userID)
            .execute().value
        return try Dictionary(uniqueKeysWithValues: rows.map { ($0.topic_id, try JSONEncoder().encode($0.snapshot)) })
    }

    func save(_ snapshot: Data, topicID: String, userID: String) async throws -> Data {
        guard let id = UUID(uuidString: userID) else { throw AccessError.signInRequired }
        let row = ProgressRow(user_id: id, topic_id: topicID, snapshot: try JSONDecoder().decode(AnyJSON.self, from: snapshot))
        let saved: SnapshotRow = try await supabase
            .from("user_grammar_progress")
            .upsert(row, onConflict: "user_id,topic_id")
            .select("topic_id,snapshot").single()
            .execute().value
        return try JSONEncoder().encode(saved.snapshot)
    }
    func attempts(topicID: String, userID: String, offset: Int) async throws -> [GrammarAttempt] {
        guard UUID(uuidString: userID) != nil else { throw AccessError.signInRequired }
        return try await supabase.from("user_grammar_attempts")
            .select("id,topic_id,level,completed_at,duration_seconds,score,answers,lesson_version_id")
            .eq("user_id", value: userID).eq("topic_id", value: topicID)
            .order("completed_at", ascending: false).order("id", ascending: false)
            .range(from: offset, to: offset + 49).execute().value
    }

    func completeAttempt(_ attempt: Data, snapshot: Data, topicID: String, userID: String) async throws -> GrammarAttemptCompletion {
        guard let id = UUID(uuidString: userID) else { throw AccessError.signInRequired }
        struct Parameters: Encodable {
            let p_user_id: UUID
            let p_topic_id: String
            let p_attempt: AnyJSON
            let p_snapshot: AnyJSON
        }
        let parameters = Parameters(p_user_id: id, p_topic_id: topicID,
                                    p_attempt: try JSONDecoder().decode(AnyJSON.self, from: attempt),
                                    p_snapshot: try JSONDecoder().decode(AnyJSON.self, from: snapshot))
        return try await supabase.rpc("complete_grammar_attempt", params: parameters).execute().value
    }

}

#if DEBUG
/// Tests exercise the real screens without reading or changing an account's cloud data.
@MainActor
final class InMemoryGrammarProgressRepository: GrammarProgressRepository {
    var records: [String: [String: Data]] = [:]
    var failFetch = false
    var failSave = false
    var onSave: (() async -> Void)?
    private(set) var writes: [Data] = []
    var publishedCourses = [GrammarPublishedCourse(topic_id: "A1.1", title: "To be & subject pronouns", title_vi: "Động từ nối và đại từ chủ ngữ", part_ids: GrammarTopicProgress.a11PartIDs, published_version: UUID(), renderer_version: 1)]
    var lessonFixture: GrammarLessonManifest?
    var audioFixtures: [String: Data] = [:]
    func courses(userID: String) async throws -> [GrammarPublishedCourse] {
        if failFetch { throw Failure.connection }; return publishedCourses
    }
    func lesson(topicID: String, userID: String) async throws -> GrammarLessonManifest {
        guard !failFetch, let lessonFixture else { throw Failure.connection }; return lessonFixture
    }
    func audio(_ asset: GrammarAudioAsset, userID: String) async throws -> Data {
        guard !failFetch, let data = audioFixtures[asset.key] else { throw Failure.connection }; return data
    }
    private enum Failure: Error { case connection }
    func fetch(userID: String) async throws -> [String: Data] {
        if failFetch { throw Failure.connection }
        return records[userID] ?? [:]
    }
    func save(_ snapshot: Data, topicID: String, userID: String) async throws -> Data {
        if let onSave { await onSave() }
        if failSave { throw Failure.connection }
        records[userID, default: [:]][topicID] = snapshot
        writes.append(snapshot)
        return snapshot
    }
    private var history: [String: [GrammarAttempt]] = [:]
    func attempts(topicID: String, userID: String, offset: Int) async throws -> [GrammarAttempt] {
        if failFetch { throw Failure.connection }
        return Array((history[userID] ?? []).filter { $0.topic_id == topicID }.dropFirst(offset).prefix(50))
    }
    func completeAttempt(_ attempt: Data, snapshot: Data, topicID: String, userID: String) async throws -> GrammarAttemptCompletion {
        if failSave { throw Failure.connection }
        struct Input: Decodable { let id: UUID; let level: String; let duration: Int; let results: [GrammarAttempt.Answer] }
        let input = try JSONDecoder().decode(Input.self, from: attempt)
        guard (1...500).contains(input.results.count) else { throw GrammarHistoryError.invalidAttempt }
        let record = history[userID]?.first(where: { $0.id == input.id }) ?? GrammarAttempt(
            id: input.id, topic_id: topicID, level: input.level,
            completed_at: ISODate.string(), duration_seconds: input.duration,
            score: input.results.filter { $0.correct && !$0.timedOut }.count, answers: input.results)
        records[userID, default: [:]][topicID] = snapshot
        if !(history[userID] ?? []).contains(where: { $0.id == record.id }) { history[userID, default: []].insert(record, at: 0) }
        return GrammarAttemptCompletion(attempt: record, snapshot: try JSONDecoder().decode(AnyJSON.self, from: snapshot))
    }

}
#endif
