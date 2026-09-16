import Foundation

enum QuestionType: Equatable {
    case listenAndType
    case meaningAndType
    case multipleChoice
    case sentenceScramble
    case pronunciationExample
}

struct LearningTask: Identifiable {
    let id = UUID()
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
