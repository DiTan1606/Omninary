import Foundation
import Supabase

/// The learner's island and adventure progress as the server keeps them.
struct IslandServerState: Decodable, Equatable {
    var open_regions: [String]
    var buildings: [String: String]
    var progress: [String: Int]
    var omni_points: Int?
    var learned_words: Int
    var earned: Int?
    var already_paid: Bool?
    /// The map being conquered (index 0…59, 60 when all are collected) and its words so far.
    var conquest: AdventureConquest?
    // Returned by adventure_complete: where the map stood before this adventure.
    var map_before: Int?
    var words_before: Int?
    var gained: Int?
    var collected: Int?

    var layout: IslandLayout { IslandLayout(openRegions: Set(open_regions), buildings: buildings) }
}

struct AdventureConquest: Decodable, Equatable {
    let map: Int
    let words: Int
}

enum IslandRepository {
    private struct BuildParams: Encodable { let p_lot_key: String; let p_building: String }
    private struct RegionParams: Encodable { let p_region: String }
    private struct CompleteParams: Encodable { let p_session_id: UUID; let p_words: Int; let p_quests: Int }
    private struct NoParams: Encodable {}

    static func fetchState() async throws -> IslandServerState {
        try await supabase.rpc("get_island_state", params: NoParams()).execute().value
    }
    static func build(lot: String, building: String) async throws -> IslandServerState {
        try await supabase.rpc("island_build", params: BuildParams(p_lot_key: lot, p_building: building)).execute().value
    }
    static func openRegion(_ id: String) async throws -> IslandServerState {
        try await supabase.rpc("island_open_region", params: RegionParams(p_region: id)).execute().value
    }
    /// Pays a finished adventure and adds its words to the map being conquered.
    static func complete(sessionID: UUID, words: Int, quests: Int) async throws -> IslandServerState {
        try await supabase.rpc("adventure_complete", params: CompleteParams(p_session_id: sessionID, p_words: words, p_quests: quests)).execute().value
    }

    /// The message the database raised, or a general one.
    static func message(_ error: Error) -> String {
        if let e = error as? PostgrestError { return e.message }
        return error.localizedDescription
    }
}

/// History rows that explain each word's schedule in Nhà nghiên cứu.
struct WordMasteryHistory: Decodable, Identifiable {
    var id: String { "\(session_id)-\(user_vocabulary_id)" }
    let session_id: UUID
    let user_vocabulary_id: String
    let mode: String?
    let level_before: Int?
    let stored_level: Int?
    let mastery: Int?
    let previous_mastery: Int?
    let decision: String?
    let next_review: String?
    let skill_scores: [String: Double]?
    let first_attempt_failures: Int?
    let created_at: String?
}

enum WordHistoryRepository {
    static func fetch(userId: String) async throws -> [WordMasteryHistory] {
        try await supabase.from("learning_word_mastery")
            .select("session_id,user_vocabulary_id,mode,level_before,stored_level,mastery,previous_mastery,decision,next_review,skill_scores,first_attempt_failures,created_at")
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .limit(5000)
            .execute().value
    }

    /// The history of one word only.
    static func fetch(userId: String, userVocabularyId: String) async throws -> [WordMasteryHistory] {
        try await supabase.from("learning_word_mastery")
            .select("session_id,user_vocabulary_id,mode,level_before,stored_level,mastery,previous_mastery,decision,next_review,skill_scores,first_attempt_failures,created_at")
            .eq("user_id", value: userId)
            .eq("user_vocabulary_id", value: userVocabularyId)
            .order("created_at", ascending: true)
            .execute().value
    }
}
