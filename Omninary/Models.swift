import Foundation

struct Vocabulary: Identifiable, Codable, Hashable {
    var id: String?
    var topicMemberships: [UserTopic]?
    var catalog_id: String?
    var user_vocabulary_id: String?
    var created_at: String?
    var saved_at: String?
    var topic_id: String?
    var topics: String?
    var created_by: String?
    var visibility: String?
    var vocab: String?
    var CEFR: String?
    var IPA: String?
    var word_form: String?
    var E_meaning: String?
    var EV_meaning: String?
    var V_meaning: String?
    var E_example: String?
    var V_example: String?
    var word_family: String?
    var synonymous: String?
    var antonym: String?
    var collocation: String?
    var formula: String?
    var note: String?
    var bonus: String?
    var user_id: String?
    var learning_level: Int?
    var next_review: String?
    var pronunciation_score: Int?
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case topicMemberships
        case catalog_id
        case user_vocabulary_id
        case created_at
        case saved_at
        case topic_id
        case topics
        case created_by
        case visibility
        case vocab
        case CEFR
        case IPA
        case word_form
        case E_meaning
        case EV_meaning
        case V_meaning
        case E_example
        case V_example
        case word_family
        case synonymous
        case antonym
        case collocation
        case formula
        case note
        case bonus
        case user_id
        case learning_level
        case next_review
        case pronunciation_score
    }
    
    init(id: String? = UUID().uuidString,
         topicMemberships: [UserTopic]? = nil,
         catalog_id: String? = nil,
         user_vocabulary_id: String? = nil,
         created_at: String? = nil,
         saved_at: String? = nil,
         topic_id: String? = nil,
         topics: String? = nil,
         created_by: String? = nil,
         visibility: String? = nil,
         vocab: String? = nil,
         CEFR: String? = nil,
         IPA: String? = nil,
         word_form: String? = nil,
         E_meaning: String? = nil,
         EV_meaning: String? = nil,
         V_meaning: String? = nil,
         E_example: String? = nil,
         V_example: String? = nil,
         word_family: String? = nil,
         synonymous: String? = nil,
         antonym: String? = nil,
         collocation: String? = nil,
         formula: String? = nil,
         note: String? = nil,
         bonus: String? = nil,
         user_id: String? = nil,
         learning_level: Int? = nil,
         next_review: String? = nil,
         pronunciation_score: Int? = nil) {
        self.id = id
        self.topicMemberships = topicMemberships
        self.catalog_id = catalog_id
        self.user_vocabulary_id = user_vocabulary_id
        self.created_at = created_at
        self.saved_at = saved_at
        self.topic_id = topic_id
        self.topics = topics
        self.created_by = created_by
        self.visibility = visibility
        self.vocab = vocab
        self.CEFR = CEFR
        self.IPA = IPA
        self.word_form = word_form
        self.E_meaning = E_meaning
        self.EV_meaning = EV_meaning
        self.V_meaning = V_meaning
        self.E_example = E_example
        self.V_example = V_example
        self.word_family = word_family
        self.synonymous = synonymous
        self.antonym = antonym
        self.collocation = collocation
        self.formula = formula
        self.note = note
        self.bonus = bonus
        self.user_id = user_id
        self.learning_level = learning_level
        self.next_review = next_review
        self.pronunciation_score = pronunciation_score
    }
}

extension Vocabulary {
    static func normalizedExample(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed != "...",
              trimmed != "…" else {
            return nil
        }
        return trimmed
    }

    var englishExample: String? {
        Self.normalizedExample(E_example)
    }

    var vietnameseExample: String? {
        Self.normalizedExample(V_example)
    }

    var normalizedWord: String? {
        vocab?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var downloadIdentityKey: String? {
        if let catalogId = catalog_id { return catalogId.lowercased() }
        guard let normalizedWord else { return nil }
        return [
            normalizedWord,
            normalizedText(word_form),
            normalizedText(E_meaning),
            normalizedText(EV_meaning),
            normalizedText(V_meaning)
        ].joined(separator: "|")
    }

    /// Explicit empty memberships mean uncategorized; do not revive a legacy topic.
    var collectionTopics: [UserTopic] {
        if let topicMemberships { return topicMemberships }
        guard let topic_id, let topics else { return [] }
        return [UserTopic(id: topic_id, name: topics, description: nil, visibility: nil, owner_id: nil, created_at: nil)]
    }

    /// The catalog ID identifies the learning item, never its spelling.
    var vocabularyIdentity: String { catalog_id ?? id ?? "" }

    static func sortedItems(_ vocabs: [Vocabulary]) -> [Vocabulary] {
        var seen: Set<String> = []
        return vocabs.filter { seen.insert($0.vocabularyIdentity).inserted }.sorted {
            let order = ($0.vocab ?? "").localizedStandardCompare($1.vocab ?? "")
            return order == .orderedSame ? $0.vocabularyIdentity < $1.vocabularyIdentity : order == .orderedAscending
        }
    }

    static func groupedByTopic(_ vocabs: [Vocabulary], uncategorizedName: String = "Chủ đề chung") -> [String: [Vocabulary]] {
        var result: [String: [Vocabulary]] = [:]
        for vocab in vocabs {
            let memberships = vocab.collectionTopics
            if memberships.isEmpty { result[uncategorizedName, default: []].append(vocab) }
            for topic in memberships {
                var contextual = vocab
                contextual.topic_id = topic.id
                contextual.topics = topic.name
                result[topic.name, default: []].append(contextual)
            }
        }
        return result
    }

    private func normalizedText(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}

extension Vocabulary {
    static func supplementaryValues(_ text: String?) -> [String] {
        (text ?? "").components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedSupplementaryText(_ text: String?) -> String? {
        let values = supplementaryValues(text)
        return values.isEmpty ? nil : values.joined(separator: "; ")
    }

    func validateContent() throws {
        let required: [(String, String?)] = [
            ("Từ vựng", vocab), ("Trình độ ngôn ngữ", CEFR), ("Phiên âm", IPA),
            ("Từ loại", word_form), ("Nghĩa tiếng Anh", E_meaning),
            ("Dịch nghĩa tiếng Anh", EV_meaning), ("Nghĩa tiếng Việt", V_meaning),
            ("Ví dụ tiếng Anh", Self.normalizedExample(E_example)),
            ("Ví dụ tiếng Việt", Self.normalizedExample(V_example))
        ]
        let missing = required.filter { ($0.1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0)
        if !missing.isEmpty {
            throw VocabularyContentError(message: "Vui lòng bổ sung: \(missing.joined(separator: ", ")).")
        }
        let values = required.map(\.1) + [word_family, synonymous, antonym, collocation, formula, note, bonus]
        let hasReviewAnnotation = values.contains { value in
            (value ?? "").components(separatedBy: .newlines).dropFirst().contains { line in
                (1...3).contains { priority in line.hasPrefix("(Nhận xét ưu tiên \(priority):") }
            }
        }
        if hasReviewAnnotation {
            throw VocabularyContentError(message: "Hãy xử lý và xoá nhận xét rà dữ liệu trước khi lưu từ vựng.")
        }
    }
}

struct VocabularyContentError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct UpdatePronunciationScore: Encodable {
    let pronunciation_score: Int
}
struct Profile: Identifiable, Codable {
    var id: String
    var email: String?
    var display_name: String?
    var role: String?
    var created_at: String?
}

struct ActivityLog: Identifiable, Codable {
    var id: String?
    var user_id: String?
    var date: String // YYYY-MM-DD
    var completed: Bool
}

struct UserStats: Codable {
    var user_id: String
    var streak_count: Int
    var last_learning_date: String?
    var streak_freeze_date: String? = nil
    var saved_streak_count: Int? = 0
    var streak_restore_expires_at: String? = nil
}

struct Notification: Identifiable, Codable {
    var id: String
    var user_id: String?
    var title: String
    var content: String
    var is_read: Bool
    var created_at: String?
}

struct UserTopic: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var description: String?
    var visibility: String?
    var owner_id: String?
    var created_at: String?
}

struct TopicDraftWordInput: Identifiable, Codable {
    var id: String = UUID().uuidString
    var catalogId: String?
    var word: String = ""
    var cefr: String = ""
    var ipa: String = ""
    var wordForm: String = ""
    var eMeaning: String = ""
    var evMeaning: String = ""
    var vMeaning: String = ""
    var eExample: String = ""
    var vExample: String = ""
    var wordFamily: String = ""
    var synonymous: String = ""
    var antonym: String = ""
    var collocation: String = ""
    var formula: String = ""
    var note: String = ""
    var bonus: String = ""
}

struct VocabSubmissionStatus: Identifiable {
    let id: String
    let catalogId: String
    let status: String
    let createdAt: String?
}

struct TopicContribution: Identifiable {
    let id: String
    let requesterId: String
    let topicId: String?
    let name: String
    let description: String?
    let status: String
    let createdAt: String?
    let words: [TopicDraftWordInput]
}
