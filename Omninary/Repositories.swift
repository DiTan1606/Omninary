import Foundation
import Supabase

enum VocabularyRepository {
    private struct CreateMeaningParams: Encodable {
        let p_vocab: VocabCatalogInsert
        let p_topic_id: String?
        let p_as_system: Bool
    }
    private struct SaveToTopicParams: Encodable {
        let p_vocab_ids: [String]
        let p_topic_id: String?
    }
    private struct TopicMembershipRow: Codable {
        let topics: UserTopic?
        let topic_id: String?
    }
    private struct StartLearningParams: Encodable {
        let p_user_vocabulary_ids: [String]
    }

    private struct CompleteLearningSessionParams: Encodable {
        let p_session_id: UUID
        let p_user_vocabulary_ids: [String]
        let p_correct_answers: Int
        let p_attempts: [LearningAttemptTelemetry]
        let p_started_at: String
    }

    struct StartLearningResult: Decodable {
        let success: Bool
        let started_count: Int
    }

    private struct TopicRow: Codable {
        let id: String
        let name: String
        let description: String?
        let visibility: String?
        let owner_id: String?
        let created_at: String?
    }

    private struct TopicInsert: Encodable {
        let id: String
        let name: String
        let description: String?
        let visibility: String
        let owner_id: String?
    }

    private struct VocabCatalogRow: Codable {
        let id: String
        let created_at: String?
        let topic_id: String?
        let topic_vocab: [TopicMembershipRow]?
        let created_by: String?
        let visibility: String?
        let word: String?
        let cefr: String?
        let ipa: String?
        let word_form: String?
        let e_meaning: String?
        let ev_meaning: String?
        let v_meaning: String?
        let e_example: String?
        let v_example: String?
        let word_family: String?
        let synonymous: String?
        let antonym: String?
        let collocation: String?
        let formula: String?
        let note: String?
        let bonus: String?
        let topics: TopicRow?
    }

    private struct UserVocabularyRow: Codable {
        let id: String
        let user_id: String?
        let vocab_id: String?
        let learning_level: Int?
        let next_review: String?
        let pronunciation_score: Int?
        let saved_at: String?
        let vocab_catalog: VocabCatalogRow?
        let user_topic_vocab: [TopicMembershipRow]?
    }

    private struct VocabCatalogInsert: Encodable {
        let id: String
        let topic_id: String?
        let created_by: String?
        let visibility: String
        let word: String
        let cefr: String?
        let ipa: String?
        let word_form: String?
        let e_meaning: String?
        let ev_meaning: String?
        let v_meaning: String?
        let e_example: String?
        let v_example: String?
        let word_family: String?
        let synonymous: String?
        let antonym: String?
        let collocation: String?
        let formula: String?
        let note: String?
        let bonus: String?
    }

    private struct VocabCatalogUpdate: Encodable {
        let word: String
        let cefr: String?
        let ipa: String?
        let word_form: String?
        let e_meaning: String?
        let ev_meaning: String?
        let v_meaning: String?
        let e_example: String?
        let v_example: String?
        let word_family: String?
        let synonymous: String?
        let antonym: String?
        let collocation: String?
        let formula: String?
        let note: String?
        let bonus: String?
    }

    private struct UserVocabularyInsert: Encodable {
        let id: String
        let user_id: String
        let vocab_id: String
        let learning_level: Int?
        let next_review: String?
        let pronunciation_score: Int?
    }

    private struct UserVocabularyDeleteLookup: Decodable {
        let vocab_id: String?
        let vocab_catalog: VocabCatalogRow?
    }

    private struct TopicSubmissionLookup: Decodable {
        let id: String
    }

    static func fetchUserVocabs(userId: String, ordered: Bool = false) async throws -> [Vocabulary] {
        let selectColumns = """
        id,user_id,vocab_id,learning_level,next_review,pronunciation_score,saved_at,user_topic_vocab(topic_id,topics(id,name,description,visibility,owner_id,created_at)),
        vocab_catalog(id,created_at,topic_id,topic_vocab(topics(id,name,description,visibility,owner_id,created_at)),created_by,visibility,word,cefr,ipa,word_form,e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,collocation,formula,note,bonus,topics!vocab_catalog_topic_id_fkey(id,name))
        """

        if ordered {
            let rows: [UserVocabularyRow] = try await supabase
                .from("user_vocabulary")
                .select(selectColumns)
                .eq("user_id", value: userId)
                .order("saved_at", ascending: false)
                .execute()
                .value

            return rows.compactMap(mapUserVocabulary)
        }

        let rows: [UserVocabularyRow] = try await supabase
            .from("user_vocabulary")
            .select(selectColumns)
            .eq("user_id", value: userId)
            .execute()
            .value

        return rows.compactMap(mapUserVocabulary)
    }

    static func fetchSystemVocabs(adminUserId: String) async throws -> [Vocabulary] {
        let rows: [VocabCatalogRow] = try await supabase
            .from("vocab_catalog")
            .select("id,created_at,topic_id,topic_vocab(topics(id,name,description,visibility,owner_id,created_at)),created_by,visibility,word,cefr,ipa,word_form,e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,collocation,formula,note,bonus,topics!vocab_catalog_topic_id_fkey(id,name)")
            .eq("visibility", value: "system")
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map { row in
            var vocab = mapCatalog(row)
            vocab.topicMemberships = (vocab.topicMemberships ?? []).filter { $0.visibility == "system" }
            return vocab
        }
    }

    static func insert(_ vocabs: [Vocabulary], intoTopicId: String? = nil) async throws {
        let ids = Array(Set(vocabs.compactMap { $0.catalog_id ?? $0.id })).sorted()
        guard !ids.isEmpty else { return }
        try await saveMeanings(ids, toTopic: intoTopicId ?? vocabs.first?.topic_id)
    }

    static func saveMeanings(_ catalogIds: [String], toTopic topicId: String?) async throws {
        try await supabase.rpc("save_vocabulary_to_topic", params: SaveToTopicParams(
            p_vocab_ids: Array(Set(catalogIds)).sorted(), p_topic_id: topicId
        )).execute()
    }

    static func removeMeanings(_ catalogIds: [String], fromTopic topicId: String) async throws {
        try await supabase.rpc("remove_vocabulary_from_topic", params: SaveToTopicParams(
            p_vocab_ids: Array(Set(catalogIds)).sorted(), p_topic_id: topicId
        )).execute()
    }

    static func searchAvailableMeanings(word: String) async throws -> [Vocabulary] {
        let rows: [VocabCatalogRow] = try await supabase.from("vocab_catalog")
            .select("id,word,word_form,e_meaning,v_meaning,cefr,ipa,visibility,topic_id,created_by")
            .ilike("word", pattern: word.trimmingCharacters(in: .whitespacesAndNewlines))
            .order("word").limit(50).execute().value
        return rows.map(mapCatalog)
    }

    static func insert(_ vocab: Vocabulary, asSystem: Bool = false, preferredTopicId: String? = nil) async throws {
        try vocab.validateContent()
        guard let userId = await AuthManager.shared.currentUser?.id.uuidString else { return }
        let catalogId = vocab.catalog_id ?? vocab.id ?? UUID().uuidString
        let resolvedTopicId: String?
        if let preferredTopicId {
            resolvedTopicId = preferredTopicId
        } else {
            resolvedTopicId = try await topicId(for: vocab.topics, allowCreate: asSystem)
        }

        try await supabase.rpc("create_vocabulary_item", params: CreateMeaningParams(
            p_vocab: makeCatalogInsert(from: vocab, id: catalogId, topicId: resolvedTopicId, userId: userId, asSystem: asSystem),
            p_topic_id: resolvedTopicId,
            p_as_system: asSystem
        )).execute()
    }

    static func update(_ vocab: Vocabulary) async throws {
        try vocab.validateContent()
        guard let catalogId = vocab.catalog_id ?? (vocab.user_vocabulary_id == nil ? vocab.id : nil) else { return }
        try await supabase
            .from("vocab_catalog")
            .update(makeCatalogUpdate(from: vocab))
            .eq("id", value: catalogId)
            .execute()
    }

    static func delete(id: String) async throws {
        let userRows: [UserVocabularyDeleteLookup] = try await supabase
            .from("user_vocabulary")
            .select("vocab_id,vocab_catalog(id,visibility)")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        if let userRow = userRows.first {
            try await supabase
                .from("user_vocabulary")
                .delete()
                .eq("id", value: id)
                .execute()

            if userRow.vocab_catalog?.visibility == "private",
               let catalogId = userRow.vocab_id {
                try await supabase
                    .from("vocab_catalog")
                    .delete()
                    .eq("id", value: catalogId)
                    .execute()
            }
            return
        }

        guard await AuthManager.shared.isAdmin else {
            throw NSError(
                domain: "Omninary",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy từ trong thư viện của bạn."]
            )
        }

        try await supabase
            .from("vocab_catalog")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func startLearning(userVocabularyIds: [String]) async throws -> StartLearningResult {
        try await supabase
            .rpc(
                "start_vocabulary_learning",
                params: StartLearningParams(p_user_vocabulary_ids: userVocabularyIds)
            )
            .execute()
            .value
    }

    static func completeLearningSession(
        sessionId: UUID,
        userVocabularyIds: [String],
        correctAnswers: Int,
        attempts: [LearningAttemptTelemetry],
        startedAt: String
    ) async throws -> VocabularyLearningSettlementResult {
        try await supabase
            .rpc(
                "complete_vocabulary_learning_session_extra_v1",
                params: CompleteLearningSessionParams(
                    p_session_id: sessionId,
                    p_user_vocabulary_ids: userVocabularyIds,
                    p_correct_answers: correctAnswers,
                    p_attempts: attempts,
                    p_started_at: startedAt
                )
            )
            .execute()
            .value
    }

    static func updatePronunciationScore(id: String, score: Int) async throws {
        try await supabase
            .from("user_vocabulary")
            .update(UpdatePronunciationScore(pronunciation_score: score))
            .eq("id", value: id)
            .execute()
    }

    static func createPrivateTopic(name: String, description: String?) async throws -> UserTopic {
        guard let userId = await AuthManager.shared.currentUser?.id.uuidString.lowercased() else {
            throw NSError(domain: "Omninary", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa đăng nhập."])
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Tên topic không được để trống."])
        }
        guard trimmedName.lowercased() != "Bộ từ gốc".lowercased() else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bộ từ gốc là vị trí gốc của kho từ vựng. Hãy chọn tên khác cho bộ từ mới."])
        }

        let row = TopicInsert(
            id: UUID().uuidString,
            name: trimmedName,
            description: nilIfEmpty(description),
            visibility: "private",
            owner_id: userId
        )

        let inserted: [UserTopic] = try await supabase
            .from("topics")
            .insert(row)
            .select("id,name,description,visibility,owner_id,created_at")
            .execute()
            .value

        guard let topic = inserted.first else {
            throw NSError(domain: "Omninary", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không tạo được topic."])
        }

        return topic
    }

    static func fetchUserPrivateTopics(userId: String) async throws -> [UserTopic] {
        try await supabase
            .from("topics")
            .select("id,name,description,visibility,owner_id,created_at")
            .eq("owner_id", value: userId)
            .eq("visibility", value: "private")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func deletePrivateTopic(_ topic: UserTopic) async throws {
        guard let userId = await AuthManager.shared.currentUser?.id.uuidString.lowercased() else {
            throw NSError(domain: "Omninary", code: 401, userInfo: [NSLocalizedDescriptionKey: "Chưa đăng nhập."])
        }

        guard topic.visibility == "private" else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Chỉ có thể xoá topic riêng."])
        }

        if let ownerId = topic.owner_id?.lowercased(), ownerId != userId {
            throw NSError(domain: "Omninary", code: 403, userInfo: [NSLocalizedDescriptionKey: "Bạn không có quyền xoá topic này."])
        }

        let pendingSubmissions: [TopicSubmissionLookup] = try await supabase
            .from("topic_submissions")
            .select("id")
            .eq("requester_id", value: userId)
            .eq("topic_id", value: topic.id)
            .eq("status", value: "pending")
            .limit(1)
            .execute()
            .value

        guard pendingSubmissions.isEmpty else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Topic đang chờ duyệt, chưa thể xoá."])
        }

        try await supabase
            .from("topic_submissions")
            .delete()
            .eq("requester_id", value: userId)
            .eq("topic_id", value: topic.id)
            .eq("status", value: "rejected")
            .execute()

        try await supabase
            .from("topics")
            .delete()
            .eq("id", value: topic.id)
            .eq("owner_id", value: userId)
            .eq("visibility", value: "private")
            .execute()
    }

    private static func topicId(for topicName: String?, allowCreate: Bool) async throws -> String? {
        let name = topicName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }

        var query = supabase.from("topics").select("id,name")
            .eq("name", value: name)
            .eq("visibility", value: allowCreate ? "system" : "private")
        if !allowCreate {
            guard let ownerId = await AuthManager.shared.currentUser?.id.uuidString else { return nil }
            query = query.eq("owner_id", value: ownerId)
        }
        let existing: [TopicRow] = try await query.limit(1).execute().value

        if let topic = existing.first {
            return topic.id
        }

        guard allowCreate else { return nil }

        let topic = TopicInsert(id: UUID().uuidString, name: name, description: nil, visibility: "system", owner_id: nil)
        try await supabase
            .from("topics")
            .insert(topic)
            .execute()

        return topic.id
    }

    private static func makeCatalogInsert(from vocab: Vocabulary, id: String, topicId: String?, userId: String, asSystem: Bool) -> VocabCatalogInsert {
        VocabCatalogInsert(
            id: id,
            topic_id: topicId,
            created_by: userId,
            visibility: asSystem ? "system" : "private",
            word: normalizedRequiredWord(vocab.vocab),
            cefr: nilIfEmpty(vocab.CEFR),
            ipa: nilIfEmpty(vocab.IPA),
            word_form: nilIfEmpty(vocab.word_form),
            e_meaning: nilIfEmpty(vocab.E_meaning),
            ev_meaning: nilIfEmpty(vocab.EV_meaning),
            v_meaning: nilIfEmpty(vocab.V_meaning),
            e_example: Vocabulary.normalizedExample(vocab.E_example),
            v_example: Vocabulary.normalizedExample(vocab.V_example),
            word_family: Vocabulary.normalizedSupplementaryText(vocab.word_family),
            synonymous: Vocabulary.normalizedSupplementaryText(vocab.synonymous),
            antonym: Vocabulary.normalizedSupplementaryText(vocab.antonym),
            collocation: Vocabulary.normalizedSupplementaryText(vocab.collocation),
            formula: Vocabulary.normalizedSupplementaryText(vocab.formula),
            note: Vocabulary.normalizedSupplementaryText(vocab.note),
            bonus: Vocabulary.normalizedSupplementaryText(vocab.bonus)
        )
    }

    private static func makeCatalogUpdate(from vocab: Vocabulary) -> VocabCatalogUpdate {
        VocabCatalogUpdate(
            word: normalizedRequiredWord(vocab.vocab),
            cefr: nilIfEmpty(vocab.CEFR),
            ipa: nilIfEmpty(vocab.IPA),
            word_form: nilIfEmpty(vocab.word_form),
            e_meaning: nilIfEmpty(vocab.E_meaning),
            ev_meaning: nilIfEmpty(vocab.EV_meaning),
            v_meaning: nilIfEmpty(vocab.V_meaning),
            e_example: Vocabulary.normalizedExample(vocab.E_example),
            v_example: Vocabulary.normalizedExample(vocab.V_example),
            word_family: Vocabulary.normalizedSupplementaryText(vocab.word_family),
            synonymous: Vocabulary.normalizedSupplementaryText(vocab.synonymous),
            antonym: Vocabulary.normalizedSupplementaryText(vocab.antonym),
            collocation: Vocabulary.normalizedSupplementaryText(vocab.collocation),
            formula: Vocabulary.normalizedSupplementaryText(vocab.formula),
            note: Vocabulary.normalizedSupplementaryText(vocab.note),
            bonus: Vocabulary.normalizedSupplementaryText(vocab.bonus)
        )
    }

    private static func mapCatalog(_ row: VocabCatalogRow) -> Vocabulary {
        Vocabulary(
            id: row.id,
            topicMemberships: row.topic_vocab?.compactMap(\.topics),
            catalog_id: row.id,
            created_at: row.created_at,
            topic_id: row.topic_id,
            topics: row.topics?.name,
            created_by: row.created_by,
            visibility: row.visibility,
            vocab: row.word,
            CEFR: row.cefr,
            IPA: row.ipa,
            word_form: row.word_form,
            E_meaning: row.e_meaning,
            EV_meaning: row.ev_meaning,
            V_meaning: row.v_meaning,
            E_example: row.e_example,
            V_example: row.v_example,
            word_family: row.word_family,
            synonymous: row.synonymous,
            antonym: row.antonym,
            collocation: row.collocation,
            formula: row.formula,
            note: row.note,
            bonus: row.bonus,
            user_id: row.created_by,
            learning_level: nil
        )
    }

    private static func mapUserVocabulary(_ row: UserVocabularyRow) -> Vocabulary? {
        guard let catalog = row.vocab_catalog else { return nil }
        let vocabulary = Vocabulary(
            id: row.id,
            topicMemberships: row.user_topic_vocab?.compactMap(\.topics),
            catalog_id: catalog.id,
            user_vocabulary_id: row.id,
            created_at: catalog.created_at,
            saved_at: row.saved_at,
            topic_id: catalog.topic_id,
            topics: catalog.topics?.name,
            created_by: catalog.created_by,
            visibility: catalog.visibility,
            vocab: catalog.word,
            CEFR: catalog.cefr,
            IPA: catalog.ipa,
            word_form: catalog.word_form,
            E_meaning: catalog.e_meaning,
            EV_meaning: catalog.ev_meaning,
            V_meaning: catalog.v_meaning,
            E_example: catalog.e_example,
            V_example: catalog.v_example,
            word_family: catalog.word_family,
            synonymous: catalog.synonymous,
            antonym: catalog.antonym,
            collocation: catalog.collocation,
            formula: catalog.formula,
            note: catalog.note,
            bonus: catalog.bonus,
            user_id: row.user_id,
            learning_level: row.learning_level,
            next_review: row.next_review,
            pronunciation_score: row.pronunciation_score
        )
        return vocabulary
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedRequiredWord(_ value: String?) -> String {
        nilIfEmpty(value) ?? "Untitled"
    }
}

enum ContributionRepository {
    private struct VocabSubmissionInsert: Encodable {
        let id: String
        let requester_id: String
        let catalog_id: String
        let topic_id: String?
        let status: String
    }

    private struct VocabSubmissionRow: Decodable {
        let id: String
        let requester_id: String
        let catalog_id: String?
        let status: String
        let created_at: String?
    }

    private struct TopicSubmissionInsert: Encodable {
        let id: String
        let requester_id: String
        let topic_id: String?
        let name: String
        let description: String?
        let status: String
    }

    private struct TopicSubmissionWordInsert: Encodable {
        let id: String
        let submission_id: String
        let catalog_id: String?
        let word: String
        let cefr: String?
        let ipa: String?
        let word_form: String?
        let e_meaning: String?
        let ev_meaning: String?
        let v_meaning: String?
        let e_example: String?
        let v_example: String?
        let word_family: String?
        let synonymous: String?
        let antonym: String?
        let collocation: String?
        let formula: String?
        let note: String?
        let bonus: String?
    }

    private struct TopicSubmissionWordRow: Decodable {
        let id: String
        let catalog_id: String?
        let word: String
        let cefr: String?
        let ipa: String?
        let word_form: String?
        let e_meaning: String?
        let ev_meaning: String?
        let v_meaning: String?
        let e_example: String?
        let v_example: String?
        let word_family: String?
        let synonymous: String?
        let antonym: String?
        let collocation: String?
        let formula: String?
        let note: String?
        let bonus: String?
    }

    private struct TopicSubmissionRow: Decodable {
        let id: String
        let requester_id: String
        let topic_id: String?
        let name: String
        let description: String?
        let status: String
        let created_at: String?
        let topic_submission_words: [TopicSubmissionWordRow]?
    }

    static func submitVocabulary(_ vocab: Vocabulary) async throws {
        guard let userId = await AuthManager.shared.currentUser?.id.uuidString,
              let catalogId = vocab.catalog_id ?? vocab.id else { return }

        let submission = VocabSubmissionInsert(
            id: UUID().uuidString,
            requester_id: userId,
            catalog_id: catalogId,
            topic_id: vocab.topic_id,
            status: "pending"
        )

        try await supabase
            .from("vocab_submissions")
            .insert(submission)
            .execute()
    }

    static func fetchUserVocabularySubmissionStatuses() async throws -> [VocabSubmissionStatus] {
        let rows: [VocabSubmissionRow] = try await supabase
            .from("vocab_submissions")
            .select("id,requester_id,catalog_id,status,created_at")
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.compactMap { row in
            guard let catalogId = row.catalog_id else { return nil }
            return VocabSubmissionStatus(
                id: row.id,
                catalogId: catalogId,
                status: row.status,
                createdAt: row.created_at
            )
        }
    }

    static func submitPrivateTopicForReview(topic: UserTopic, vocabs: [Vocabulary]) async throws {
        guard let userId = await AuthManager.shared.currentUser?.id.uuidString else { return }

        let validVocabs = vocabs.filter {
            ($0.catalog_id ?? $0.id) != nil &&
            !($0.vocab ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !validVocabs.isEmpty else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Topic cần có ít nhất một từ để gửi duyệt."])
        }
        let submissionId = UUID().uuidString
        let submission = TopicSubmissionInsert(
            id: submissionId,
            requester_id: userId,
            topic_id: topic.id,
            name: topic.name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: nilIfEmpty(topic.description),
            status: "pending"
        )

        try await supabase
            .from("topic_submissions")
            .insert(submission)
            .execute()

        let wordRows = validVocabs.compactMap { vocab -> TopicSubmissionWordInsert? in
            guard let catalogId = vocab.catalog_id ?? vocab.id else { return nil }
            return TopicSubmissionWordInsert(
                id: UUID().uuidString,
                submission_id: submissionId,
                catalog_id: catalogId,
                word: normalizedRequiredWord(vocab.vocab),
                cefr: nilIfEmpty(vocab.CEFR),
                ipa: nilIfEmpty(vocab.IPA),
                word_form: nilIfEmpty(vocab.word_form),
                e_meaning: nilIfEmpty(vocab.E_meaning),
                ev_meaning: nilIfEmpty(vocab.EV_meaning),
                v_meaning: nilIfEmpty(vocab.V_meaning),
                e_example: Vocabulary.normalizedExample(vocab.E_example),
                v_example: Vocabulary.normalizedExample(vocab.V_example),
                word_family: Vocabulary.normalizedSupplementaryText(vocab.word_family),
                synonymous: Vocabulary.normalizedSupplementaryText(vocab.synonymous),
                antonym: Vocabulary.normalizedSupplementaryText(vocab.antonym),
                collocation: Vocabulary.normalizedSupplementaryText(vocab.collocation),
                formula: Vocabulary.normalizedSupplementaryText(vocab.formula),
                note: Vocabulary.normalizedSupplementaryText(vocab.note),
                bonus: Vocabulary.normalizedSupplementaryText(vocab.bonus)
            )
        }

        try await supabase
            .from("topic_submission_words")
            .insert(wordRows)
            .execute()
    }

    static func fetchUserTopicSubmissions() async throws -> [TopicContribution] {
        let rows: [TopicSubmissionRow] = try await supabase
            .from("topic_submissions")
            .select("""
            id,requester_id,topic_id,name,description,status,created_at,
            topic_submission_words(id,catalog_id,word,cefr,ipa,word_form,e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,collocation,formula,note,bonus)
            """)
            .neq("status", value: "approved")
            .order("created_at", ascending: false)
            .execute()
            .value

        return rows.map { row in
            TopicContribution(
                id: row.id,
                requesterId: row.requester_id,
                topicId: row.topic_id,
                name: row.name,
                description: row.description,
                status: row.status,
                createdAt: row.created_at,
                words: (row.topic_submission_words ?? []).map(mapDraftWord)
            )
        }
    }


    private static func mapDraftWord(_ row: TopicSubmissionWordRow) -> TopicDraftWordInput {
        TopicDraftWordInput(
            id: row.id,
            catalogId: row.catalog_id,
            word: row.word,
            cefr: row.cefr ?? "",
            ipa: row.ipa ?? "",
            wordForm: row.word_form ?? "",
            eMeaning: row.e_meaning ?? "",
            evMeaning: row.ev_meaning ?? "",
            vMeaning: row.v_meaning ?? "",
            eExample: row.e_example ?? "",
            vExample: row.v_example ?? "",
            wordFamily: row.word_family ?? "",
            synonymous: row.synonymous ?? "",
            antonym: row.antonym ?? "",
            collocation: row.collocation ?? "",
            formula: row.formula ?? "",
            note: row.note ?? "",
            bonus: row.bonus ?? ""
        )
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func normalizedRequiredWord(_ value: String?) -> String {
        nilIfEmpty(value) ?? "Untitled"
    }

}

enum UserProgressRepository {
    private struct DailyActivityParams: Encodable { let p_session_id: UUID }
    typealias DailyActivityResult = StreakStateResult

    struct StreakStateResult: Decodable {
        let streak_count: Int
        let saved_streak_count: Int
        let last_learning_date: String?
        let streak_freeze_date: String?
        let streak_restore_expires_at: String?
        var streak_protected_through: String? = nil
        var streak_freeze_used_at: String? = nil
        var streak_freeze_requires_learning: Bool? = nil
        var streak_restored_on: String? = nil
        var is_extra: Bool? = nil
        var is_first_learning_today: Bool? = nil
        var previous_streak_count: Int? = nil
        var was_frozen_today: Bool? = nil
    }

    static func fetchStats(userId: String) async throws -> [UserStats] {
        try await supabase
            .from("user_stats")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    static func resetStreak(userId: String) async throws {
        _ = try await refreshStreakState()
    }

    static func refreshStreakState() async throws -> StreakStateResult {
        try await supabase.rpc("refresh_streak_state", params: OmniRewardRepository.EmptyParams()).execute().value
    }

    static func fetchCompletedActivityLogs(userId: String) async throws -> [ActivityLog] {
        try await supabase
            .from("activity_logs")
            .select()
            .eq("user_id", value: userId)
            .eq("completed", value: true)
            .execute()
            .value
    }

    /// Kích hoạt Mùa đông không lạnh: Lưu ngày đóng băng lên Supabase
    static func activateStreakFreeze(userId: String, date: String) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Đóng băng chuỗi phải dùng giao dịch use_omni_item."])
    }

    /// Hủy ngày đóng băng trên Supabase (khi người dùng đã học vào ngày đó)
    static func clearStreakFreeze(userId: String) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Trạng thái chuỗi được cập nhật khi ghi nhận hoạt động."])
    }

    /// Cập nhật chuỗi lưu dự phòng lên Supabase
    static func updateSavedStreak(userId: String, savedStreak: Int) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Chuỗi lưu dự phòng do máy chủ tính toán."])
    }

    /// Khôi phục chuỗi bằng Người giữ lửa: đưa streak_count và saved_streak_count về mốc khôi phục
    static func restoreStreak(userId: String, streakToRestore: Int) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Khôi phục chuỗi phải dùng giao dịch use_omni_item."])
    }

    @discardableResult
    static func recordDailyActivityAndUpdateStreak(userId: String, sessionId: UUID) async throws -> Bool {
        let result: StreakStateResult = try await supabase
            .rpc("record_daily_activity", params: DailyActivityParams(p_session_id: sessionId)).execute().value
        return await MainActor.run {
            let manager = OmniStreakFreezeManager.shared
            manager.applyRemoteState(result)
            let first = result.is_first_learning_today == true
            if first {
                StreakActionPresenter.shared.enqueue(.learning,
                    previousDays: result.previous_streak_count ?? max(0, result.streak_count - 1),
                    newDays: result.streak_count, wasFrozen: result.was_frozen_today == true,
                    date: StreakClock.parseDay(result.last_learning_date) ?? Date())
            }
            if result.is_extra == true {
                NotificationManager.shared.schedulePotentialStreakRestoreAlert(afterLearningOn: Date())
            } else {
                NotificationManager.shared.cancelPotentialStreakRestoreAlert()
            }
            return first
        }
    }

}

enum NotificationRepository {
    static func fetchUnreadCount(userId: String) async throws -> Int {
        try await supabase
            .from("notifications")
            .select("*", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("is_read", value: false)
            .execute()
            .count ?? 0
    }

    static func fetchUserNotifications(userId: String) async throws -> [Notification] {
        try await supabase
            .from("notifications")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func insert(_ notification: Notification) async throws {
        try await supabase
            .from("notifications")
            .insert(notification)
            .execute()
    }

    static func markAsRead(id: String) async throws {
        try await supabase
            .from("notifications")
            .update(["is_read": true])
            .eq("id", value: id)
            .execute()
    }

    static func delete(id: String) async throws {
        try await supabase
            .from("notifications")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}

enum ProfileRepository {
    static func fetchRole(userId: String) async throws -> String? {
        struct RoleData: Decodable { let role: String? }
        let fetched: [RoleData] = try await supabase
            .from("profiles")
            .select("role")
            .eq("id", value: userId)
            .execute()
            .value

        return fetched.first?.role
    }

    static func updateDisplayName(userId: String, name: String) async throws {
        try await supabase
            .from("profiles")
            .update(["display_name": name] as [String: String])
            .eq("id", value: userId)
            .execute()
    }

}

// MARK: - Omni Reward Models & Repository
struct OmniProfileData: Decodable {
    let omni_points: Int?
    let equipped_omni_icon: String?
    let unlocked_omni_icons: [String]?
    let double_points_until: String?
    let extraordinary_trial_until: String?
    let learning_hearts_remaining: Int?
    let learning_hearts_reset_date: String?
}

struct RedeemOmniIconResult: Decodable {
    let success: Bool
    let message: String?
    let new_points: Int?
}

struct OmniActionResult: Decodable {
    let success: Bool
    let message: String?
    let new_points: Int?
    let unlocked_omni_icons: [String]?
    let equipped_omni_icon: String?
    let remaining_hearts: Int?
    let double_points_until: String?
    let extraordinary_trial_until: String?
    let streak_count: Int?
    let saved_streak_count: Int?
    let streak_freeze_date: String?
    let streak_restore_expires_at: String?
    let earned_points: Int?
    var last_learning_date: String? = nil
    var streak_protected_through: String? = nil
    var streak_freeze_used_at: String? = nil
    var streak_freeze_requires_learning: Bool? = nil
    var streak_restored_on: String? = nil
    var previous_streak_count: Int? = nil
    var was_frozen_today: Bool? = nil

    var streak_rescued_date: String? = nil

}

struct LearningAccessState: Decodable {
    let success: Bool
    let is_extra: Bool
    let remaining_hearts: Int
    let reset_date: String?
    let reset_at: String?
}

struct VocabularyLearningSettlementResult: Decodable {
    let success: Bool
    let already_completed: Bool
    let earned_points: Int
    let new_points: Int
    let remaining_hearts: Int
    let reset_date: String?
    let reset_at: String?
    let is_extra: Bool
    let streak_count: Int
    let saved_streak_count: Int?
    let streak_freeze_date: String?
    let streak_restore_expires_at: String?
    let is_first_learning_today: Bool?
    var last_learning_date: String? = nil
    var streak_protected_through: String? = nil
    var streak_freeze_used_at: String? = nil
    var streak_freeze_requires_learning: Bool? = nil
    var streak_restored_on: String? = nil
    var previous_streak_count: Int? = nil
    var was_frozen_today: Bool? = nil

}

enum OmniRewardRepository {
    struct RedeemParams: Encodable {
        let icon_id: String
    }

    struct ItemParams: Encodable { let item_id: String }
    struct DurationParams: Encodable { let days: Int }
    struct DevelopmentPointsParams: Encodable { let points: Int }
    struct EmptyParams: Encodable {}

    /// Lấy toàn bộ thông tin Điểm Omni, icon đang trang bị, icon đã mở khóa và thời hạn vật phẩm từ Supabase
    static func fetchOmniProfile(userId: String) async throws -> OmniProfileData? {
        do {
            let fetched: [OmniProfileData] = try await supabase
                .from("profiles")
                .select("omni_points, equipped_omni_icon, unlocked_omni_icons, double_points_until, extraordinary_trial_until, learning_hearts_remaining, learning_hearts_reset_date")
                .eq("id", value: userId)
                .execute()
                .value
            return fetched.first
        } catch {
            // Fallback 1: nếu cột extraordinary_trial_until chưa được tạo trên Supabase
            struct IntermediateOmniProfileData: Decodable {
                let omni_points: Int?
                let equipped_omni_icon: String?
                let unlocked_omni_icons: [String]?
                let double_points_until: String?
            }
            if let fetched: [IntermediateOmniProfileData] = try? await supabase
                .from("profiles")
                .select("omni_points, equipped_omni_icon, unlocked_omni_icons, double_points_until")
                .eq("id", value: userId)
                .execute()
                .value,
               let first = fetched.first {
                return OmniProfileData(
                    omni_points: first.omni_points,
                    equipped_omni_icon: first.equipped_omni_icon,
                    unlocked_omni_icons: first.unlocked_omni_icons,
                    double_points_until: first.double_points_until,
                    extraordinary_trial_until: nil,
                    learning_hearts_remaining: nil,
                    learning_hearts_reset_date: nil
                )
            }

            // Fallback 2: nếu cả cột double_points_until cũng chưa được tạo trên Supabase
            struct LegacyOmniProfileData: Decodable {
                let omni_points: Int?
                let equipped_omni_icon: String?
                let unlocked_omni_icons: [String]?
            }
            let fallback: [LegacyOmniProfileData] = try await supabase
                .from("profiles")
                .select("omni_points, equipped_omni_icon, unlocked_omni_icons")
                .eq("id", value: userId)
                .execute()
                .value
            if let first = fallback.first {
                return OmniProfileData(
                    omni_points: first.omni_points,
                    equipped_omni_icon: first.equipped_omni_icon,
                    unlocked_omni_icons: first.unlocked_omni_icons,
                    double_points_until: nil,
                    extraordinary_trial_until: nil,
                    learning_hearts_remaining: nil,
                    learning_hearts_reset_date: nil
                )
            }
            return nil
        }
    }

    /// Cập nhật biểu tượng Omnicon đang trang bị lên Supabase
    static func updateEquippedIcon(userId: String, iconId: String) async throws {
        let params = RedeemParams(icon_id: iconId)
        let _: OmniActionResult = try await supabase
            .rpc("equip_omni_icon", params: params)
            .execute()
            .value
    }

    /// Cập nhật danh sách Omnicon đã mở khóa lên Supabase
    static func updateUnlockedIcons(userId: String, iconIds: [String]) async throws {
        let _: OmniActionResult = try await supabase
            .rpc("unlock_streak_omni_icons", params: EmptyParams())
            .execute()
            .value
    }

    /// Cập nhật thời điểm hết hạn Gấp đôi Canxi lên Supabase
    static func updateDoublePointsUntil(userId: String, until: Date?) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Gấp đôi điểm phải được kích hoạt bằng giao dịch use_omni_item."])
    }

    /// Cập nhật thời điểm hết hạn Trải nghiệm phi thường lên Supabase
    static func updateExtraordinaryTrialUntil(userId: String, until: Date?) async throws {
        throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Quyền Extraordinary phải được kích hoạt bằng giao dịch máy chủ."])
    }

    /// Cộng điểm Omni (sau bài học hoặc nạp tiền) qua hàm RPC trên Supabase
    static func addOmniPoints(userId: String, pointsToAdd: Int) async throws -> Int {
        guard pointsToAdd > 0 else {
            throw NSError(domain: "Omninary", code: 400, userInfo: [NSLocalizedDescriptionKey: "Không thể thay đổi số dư trực tiếp."])
        }
        let result: OmniActionResult = try await supabase
            .rpc("grant_development_omni_points", params: DevelopmentPointsParams(points: pointsToAdd))
            .execute()
            .value
        return result.new_points ?? 0
    }

    /// Đổi Omnicon bằng điểm Omni qua hàm RPC trên Supabase
    static func redeemOmniIcon(userId: String, iconId: String, cost: Int) async throws -> RedeemOmniIconResult {
        let params = RedeemParams(icon_id: iconId)
        let result: RedeemOmniIconResult = try await supabase
            .rpc("redeem_omni_icon", params: params)
            .execute()
            .value
        return result
    }

    static func useOmniItem(_ itemId: String) async throws -> OmniActionResult {
        try await supabase.rpc("use_omni_item", params: ItemParams(item_id: itemId)).execute().value
    }

    static func activateExtraordinaryAccess(days: Int) async throws -> OmniActionResult {
        try await supabase.rpc("activate_extraordinary_access", params: DurationParams(days: days)).execute().value
    }

    static func fetchLearningAccessState() async throws -> LearningAccessState {
        try await supabase
            .rpc("get_learning_access_state", params: EmptyParams())
            .execute()
            .value
    }

    static func unlockStreakIcons() async throws -> OmniActionResult {
        try await supabase.rpc("unlock_streak_omni_icons", params: EmptyParams()).execute().value
    }

    /// Đồng bộ từ Supabase về bộ nhớ đệm máy (UserDefaults / AppStorage)
    @discardableResult
    @MainActor
    static func syncServerToLocal(userId: String) async -> Bool {
        do {
            _ = await OmniIconCatalog.shared.refresh()
            _ = await OmniItemCatalog.shared.refresh()
            if let profile = try await fetchOmniProfile(userId: userId) {
                if let pts = profile.omni_points {
                    UserDefaults.standard.set(pts, forKey: "omni_reward_points")
                }
                let localEquipped = UserDefaults.standard.string(forKey: "equipped_omni_icon_id")
                if let localEquipped = localEquipped,
                   localEquipped == "omni_mythic_imperial_chrono",
                   profile.equipped_omni_icon != "omni_mythic_imperial_chrono" {
                    Task {
                        try? await updateEquippedIcon(userId: userId, iconId: localEquipped)
                    }
                } else if let icon = profile.equipped_omni_icon, !icon.isEmpty {
                    UserDefaults.standard.set(icon, forKey: "equipped_omni_icon_id")
                }

                if let unlocked = profile.unlocked_omni_icons, !unlocked.isEmpty {
                    var merged = Set(unlocked)
                    let localRaw = UserDefaults.standard.string(forKey: "unlocked_omni_icon_ids") ?? ""
                    for item in localRaw.split(separator: ",").map(String.init) where !item.isEmpty {
                        merged.insert(item)
                    }
                    if localEquipped == "omni_mythic_imperial_chrono" {
                        merged.insert("omni_mythic_imperial_chrono")
                    }
                    UserDefaults.standard.set(Array(merged).joined(separator: ","), forKey: "unlocked_omni_icon_ids")
                }
                OmniLearningHeartManager.shared.syncFromRemote(
                    remainingHearts: profile.learning_hearts_remaining,
                    resetDate: profile.learning_hearts_reset_date
                )
                OmniDoublePointsManager.shared.syncFromRemote(untilDateString: profile.double_points_until)
                OmniExtraordinaryManager.shared.syncFromRemote(untilDateString: profile.extraordinary_trial_until)
                return true
            }
            return false
        } catch {
            print("Đồng bộ Omni profile từ Supabase thất bại: \(error)")
            return false
        }
    }
}
