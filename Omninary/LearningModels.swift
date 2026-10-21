import Foundation

enum QuestionType: Equatable {
    case listenAndType
    case meaningAndType
    case multipleChoice
    case sentenceScramble
    case pronunciationExample

    var telemetryName: String {
        switch self {
        case .listenAndType: return "listen_and_type"
        case .meaningAndType: return "meaning_and_type"
        case .multipleChoice: return "multiple_choice"
        case .sentenceScramble: return "sentence_scramble"
        case .pronunciationExample: return "pronunciation_example"
        }
    }
}

struct LearningTask: Identifiable {
    let id = UUID()
    /// Keeps retries tied to the original exercise while each rendered task keeps its own ID.
    var exerciseID = UUID()
    let word: String
    let meanings: [Vocabulary]
    let type: QuestionType
    var options: [String] = []
    var correctSentence: String? = nil
    var scrambledWords: [String] = []
    var vHint: String? = nil
    var pronunciationMeaning: Vocabulary? = nil
    var pronunciationExample: String? = nil

    func freshRetryCopy() -> LearningTask {
        LearningTask(
            exerciseID: exerciseID,
            word: word,
            meanings: meanings,
            type: type,
            options: options,
            correctSentence: correctSentence,
            scrambledWords: scrambledWords,
            vHint: vHint,
            pronunciationMeaning: pronunciationMeaning,
            pronunciationExample: pronunciationExample
        )
    }
}

/// The smallest useful immutable learning record for Extra v1. It is collected
/// for Ditan too, then evaluated by the server when the session is settled.
struct LearningAttemptTelemetry: Encodable, Identifiable {
    let id: UUID
    let exercise_id: UUID
    let user_vocabulary_ids: [String]
    let task_type: String
    let attempt_number: Int
    let is_correct: Bool
    let answer_text: String?
    let response_duration_ms: Int
    let pronunciation_score: Int?
    let answered_at: String

    enum CodingKeys: String, CodingKey {
        case id = "attempt_id"
        case exercise_id
        case user_vocabulary_ids
        case task_type
        case attempt_number
        case is_correct
        case answer_text
        case response_duration_ms
        case pronunciation_score
        case answered_at
    }
}

enum LearningRetryPlanner {
    static func tasks(
        afterAnswering task: LearningTask,
        isCorrect: Bool,
        scheduledTasks: [LearningTask]
    ) -> [LearningTask] {
        guard !isCorrect else { return scheduledTasks }

        var retryTask = task.freshRetryCopy()
        if retryTask.type == .multipleChoice {
            retryTask.options.shuffle()
        }
        if retryTask.type == .sentenceScramble {
            retryTask.scrambledWords.shuffle()
        }

        return scheduledTasks + [retryTask]
    }
}

struct TaskResult: Identifiable {
    let id = UUID()
    let task: LearningTask
    let isCorrect: Bool
    let selectedOption: String?
    let answerText: String
}

struct LearningSessionPlan {
    let selectedGroups: [[Vocabulary]]
    let tasks: [LearningTask]
    let statsByLevel: [Int: Int]
    let totalLearningWords: Int
    let totalSavedWords: Int
    let dueVocabsCount: Int
    let wordsWithoutExampleExercises: [String]
}
