import Foundation

struct ListeningSeries: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let slug: String?
    let title: String
    let vi_title: String?
    let description: String?
    let is_published: Bool?
    let created_at: String?
}

struct ListeningLesson: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let series_id: String?
    let slug: String?
    let source_id: String?
    let title: String
    let vi_title: String?
    let cefr: String?
    let description: String?
    let is_published: Bool?
    let created_at: String?
}

struct ListeningSeriesCatalogItem: Identifiable, Hashable, Sendable {
    let series: ListeningSeries
    let lessons: [ListeningLesson]

    var id: String { series.id }
}

struct ListeningLessonSummary: Identifiable, Hashable, Sendable {
    let lesson: ListeningLesson
    let segmentCount: Int
    let durationSeconds: Double

    var id: String { lesson.id }
}

struct ListeningSegment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let lesson_id: String
    let order_index: Int
    let english_text: String
    let vietnamese_text: String?
    let ipa: String?
    let audio_path: String?
    let duration_seconds: Double?
    let word_count: Int?
    let created_at: String?
}

struct ListeningProgress: Codable, Sendable {
    let user_id: String
    let segment_id: String
    let status: String?
    let attempts: Int?
    let latest_score: Double?
    let best_score: Double?
    let hinted_word_count: Int?
    let hinted_word_indexes: [Int]?
    let word_count: Int?
    let completed_at: String?
    let updated_at: String?
}

struct ShadowingProgress: Codable, Sendable {
    let user_id: String
    let segment_id: String
    let status: String?
    let attempts: Int?
    let latest_score: Double?
    let best_score: Double?
    let accuracy_score: Double?
    let fluency_score: Double?
    let completeness_score: Double?
    let passed_at: String?
    let updated_at: String?

    var isPassed: Bool {
        status == "passed"
    }
}

struct ListeningSentenceResult: Equatable, Sendable {
    let wordCount: Int
    let hintedWordCount: Int
    let hintedWordIndices: Set<Int>

    init(
        wordCount: Int,
        hintedWordCount: Int,
        hintedWordIndices: Set<Int> = []
    ) {
        self.wordCount = wordCount
        self.hintedWordCount = hintedWordCount
        self.hintedWordIndices = hintedWordIndices
    }

    var score: Double {
        ListeningScoreCalculator.sentenceScore(
            wordCount: wordCount,
            hintedWordCount: hintedWordCount
        )
    }
}

struct UserListeningLesson: Codable, Hashable, Sendable {
    let user_id: String
    let lesson_id: String
    let is_in_learning: Bool?
    let downloaded_at: String?
    let learning_started_at: String?
    let completed_at: String?
    let latest_score: Double?
    let best_score: Double?
    let is_in_shadowing: Bool?
    let shadowing_started_at: String?
    let shadowing_completed_at: String?
    let shadowing_latest_score: Double?
    let shadowing_best_score: Double?
    let listening_lessons: ListeningLesson?

    var isInLearning: Bool {
        is_in_learning ?? false
    }

    var isInShadowing: Bool {
        is_in_shadowing ?? false
    }
}

struct ListeningLibraryItem: Identifiable, Hashable, Sendable {
    let entry: UserListeningLesson
    let lesson: ListeningLesson
    let segmentCount: Int
    let completedSegmentCount: Int
    let shadowingPassedSegmentCount: Int

    var id: String { lesson.id }

    var isInLearning: Bool {
        entry.isInLearning
    }

    var isCompleted: Bool {
        entry.completed_at != nil
    }

    var completionFraction: Double {
        guard segmentCount > 0 else { return 0 }
        return Double(completedSegmentCount) / Double(segmentCount)
    }

    var isInShadowing: Bool {
        entry.isInShadowing
    }

    var isShadowingCompleted: Bool {
        segmentCount > 0 && shadowingPassedSegmentCount >= segmentCount
    }

    var shadowingCompletionFraction: Double {
        guard segmentCount > 0 else { return 0 }
        return Double(shadowingPassedSegmentCount) / Double(segmentCount)
    }
}

struct ListeningSeriesLibraryItem: Identifiable, Hashable, Sendable {
    let series: ListeningSeries
    let lessons: [ListeningLibraryItem]

    var id: String { series.id }

    var completedLessonCount: Int {
        lessons.filter(\.isCompleted).count
    }

    var learningLessonCount: Int {
        lessons.filter(\.isInLearning).count
    }

    var shadowingLessonCount: Int {
        lessons.filter(\.isInShadowing).count
    }
}

struct UserListeningLessonInsert: Encodable {
    let user_id: String
    let lesson_id: String
}

struct RemoveListeningLessonFromLibraryParams: Encodable {
    let p_lesson_id: String
}

struct UserListeningLessonLearningUpdate: Encodable {
    let is_in_learning: Bool
    let learning_started_at: String
}

struct UserListeningLessonShadowingUpdate: Encodable {
    let is_in_shadowing: Bool
    let shadowing_started_at: String
}

struct RecordListeningSegmentCompletionParams: Encodable {
    let p_segment_id: String
    let p_hinted_word_indexes: [Int]
}

struct ListeningLessonIdParams: Encodable {
    let p_lesson_id: String
}
