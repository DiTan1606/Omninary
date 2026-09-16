//
//  DitanaryTests.swift
//  DitanaryTests
//
//  Created by Trần Lê Duy Tân on 24/4/26.
//

import Foundation
import Testing
@testable import Ditanary

struct DitanaryTests {

    @Test func normalizesLearningText() async throws {
        #expect(LearningTextNormalizer.normalizedWords("Hello, world!") == ["hello", "world"])
        #expect(LearningTextNormalizer.normalizedAnswer("  The quick, brown fox. ") == "the quick brown fox")
    }

    @Test func pronunciationPassingRuleRequiresStrictScoresAndNoCriticalWordError() async throws {
        let passing = AzurePronunciationAssessment(
            referenceText: "Most plants require water.",
            transcript: "Most plants require water.",
            scores: .init(pronunciation: 82, accuracy: 80, fluency: 70, completeness: 95),
            words: [
                .init(word: "Most", accuracy: 90, errorType: "None", phonemes: []),
                .init(word: "plants", accuracy: 86, errorType: "None", phonemes: [])
            ],
            shadowingProgress: nil
        )
        let mispronounced = AzurePronunciationAssessment(
            referenceText: passing.referenceText,
            transcript: passing.transcript,
            scores: .init(pronunciation: 92, accuracy: 92, fluency: 80, completeness: 100),
            words: [
                .init(word: "Most", accuracy: 90, errorType: "Mispronunciation", phonemes: [])
            ],
            shadowingProgress: nil
        )

        #expect(PronunciationPassingRule.passes(passing))
        #expect(!PronunciationPassingRule.passes(mispronounced))
        #expect(PronunciationPassingRule.failureReasons(for: mispronounced).contains("Từ “Most” cần phát âm lại"))
    }

    @Test func pronunciationPassingRuleRejectsWeakWordEvenWhenAzureDoesNotFlagAnError() async throws {
        let assessment = AzurePronunciationAssessment(
            referenceText: "Most plants require water.",
            transcript: "Most plants require water.",
            scores: .init(pronunciation: 90, accuracy: 90, fluency: 85, completeness: 100),
            words: [
                .init(word: "Most", accuracy: 90, errorType: "None", phonemes: []),
                .init(word: "plants", accuracy: 69, errorType: "None", phonemes: [])
            ],
            shadowingProgress: nil
        )

        #expect(!PronunciationPassingRule.passes(assessment))
        #expect(PronunciationPassingRule.failureReasons(for: assessment).contains("Từ “plants” cần đạt ít nhất 70 điểm"))
    }

    @Test func pronunciationPassingRuleRejectsInsertedWords() async throws {
        let assessment = AzurePronunciationAssessment(
            referenceText: "Most plants require water.",
            transcript: "Most plants really require water.",
            scores: .init(pronunciation: 92, accuracy: 92, fluency: 85, completeness: 100),
            words: [
                .init(word: "Most", accuracy: 90, errorType: "None", phonemes: []),
                .init(word: "really", accuracy: 90, errorType: "Insertion", phonemes: [])
            ],
            shadowingProgress: nil
        )

        #expect(!PronunciationPassingRule.passes(assessment))
        #expect(PronunciationPassingRule.failureReasons(for: assessment).contains("Bạn đã đọc thừa từ “really”"))
    }

    @Test func pronunciationFeedbackUsesWordAndPhonemeThresholds() async throws {
        let goodWord = AzurePronunciationAssessment.WordFeedback(
            word: "think",
            accuracy: 86,
            errorType: "None",
            phonemes: []
        )
        let improvingWord = AzurePronunciationAssessment.WordFeedback(
            word: "think",
            accuracy: 72,
            errorType: "None",
            phonemes: []
        )
        let retryWord = AzurePronunciationAssessment.WordFeedback(
            word: "think",
            accuracy: 69,
            errorType: "None",
            phonemes: []
        )
        let improvingPhoneme = AzurePronunciationAssessment.WordFeedback.PhonemeFeedback(
            phoneme: "θ",
            accuracy: 65,
            heardPhoneme: "s",
            heardScore: 100
        )

        #expect(PronunciationPassingRule.feedbackLevel(for: goodWord) == .good)
        #expect(PronunciationPassingRule.feedbackLevel(for: improvingWord) == .needsImprovement)
        #expect(PronunciationPassingRule.feedbackLevel(for: retryWord) == .retry)
        #expect(PronunciationPassingRule.feedbackLevel(for: improvingPhoneme) == .needsImprovement)
        #expect(PronunciationPassingRule.heardAs(for: improvingPhoneme) == "s")
    }

    @Test func pronunciationAssessmentDecodesHeardPhonemeAndWordTiming() throws {
        let payload = """
        {
          "referenceText": "Think with care.",
          "transcript": "Think with care.",
          "scores": {
            "pronunciation": 84,
            "accuracy": 82,
            "fluency": 80,
            "completeness": 100
          },
          "words": [
            {
              "word": "with",
              "accuracy": 68,
              "errorType": "None",
              "offsetMilliseconds": 420,
              "durationMilliseconds": 310,
              "phonemes": [
                {
                  "phoneme": "θ",
                  "accuracy": 48,
                  "heardPhoneme": "s",
                  "heardScore": 100
                }
              ]
            }
          ]
        }
        """

        let assessment = try JSONDecoder().decode(
            AzurePronunciationAssessment.self,
            from: Data(payload.utf8)
        )
        let word = try #require(assessment.words.first)
        let phoneme = try #require(word.phonemes.first)

        #expect(word.offsetMilliseconds == 420)
        #expect(word.durationMilliseconds == 310)
        #expect(phoneme.heardPhoneme == "s")
        #expect(PronunciationPassingRule.heardAs(for: phoneme) == "s")
    }

    @Test func pronunciationPassingRuleRejectsMissingWordFeedback() async throws {
        let assessment = AzurePronunciationAssessment(
            referenceText: "Most plants require water.",
            transcript: "Most plants require water.",
            scores: .init(pronunciation: 95, accuracy: 95, fluency: 95, completeness: 100),
            words: [],
            shadowingProgress: nil
        )

        #expect(!PronunciationPassingRule.passes(assessment))
    }

    @Test func shadowingPassingRuleAlsoRequiresFluency() async throws {
        let weakFluency = AzurePronunciationAssessment(
            referenceText: "I am ready to learn.",
            transcript: "I am ready to learn.",
            scores: .init(pronunciation: 90, accuracy: 90, fluency: 64, completeness: 100),
            words: [
                .init(word: "I", accuracy: 90, errorType: "None", phonemes: []),
                .init(word: "ready", accuracy: 90, errorType: "None", phonemes: [])
            ],
            shadowingProgress: nil
        )
        let passing = AzurePronunciationAssessment(
            referenceText: weakFluency.referenceText,
            transcript: weakFluency.transcript,
            scores: .init(pronunciation: 90, accuracy: 90, fluency: 65, completeness: 100),
            words: weakFluency.words,
            shadowingProgress: nil
        )

        #expect(!ShadowingPassingRule.passes(weakFluency))
        #expect(ShadowingPassingRule.failureReasons(for: weakFluency).contains("Độ trôi chảy cần từ 65 trở lên"))
        #expect(ShadowingPassingRule.passes(passing))
    }

    @Test func reviewSchedulerContinuesAfterMasterLevel() async throws {
        #expect(ReviewScheduler.nextLearningLevel(from: 0) == 1)
        #expect(ReviewScheduler.nextLearningLevel(from: 5) == 6)
        #expect(ReviewScheduler.nextLearningLevel(from: 6) == 7)
        #expect(ReviewScheduler.reviewDelayDays(for: 4) == 7)
        #expect(ReviewScheduler.reviewDelayDays(for: 5) == 15)
        #expect(ReviewScheduler.reviewDelayDays(for: 6) == 30)
        #expect(ReviewScheduler.reviewDelayDays(for: 7) == 60)
        #expect(ReviewScheduler.reviewDelayDays(for: 10) == 365)
    }

    @Test func ditandnaryReviewScheduleUsesPublishedFixedIntervals() async throws {
        #expect(DitanaryReviewSchedule.days(for: 1) == 0)
        #expect(DitanaryReviewSchedule.days(for: 2) == 1)
        #expect(DitanaryReviewSchedule.days(for: 3) == 3)
        #expect(DitanaryReviewSchedule.days(for: 4) == 7)
        #expect(DitanaryReviewSchedule.days(for: 5) == 15)
        #expect(DitanaryReviewSchedule.days(for: 6) == 30)
        #expect(DitanaryReviewSchedule.days(for: 7) == 60)
        #expect(DitanaryReviewSchedule.days(for: 8) == 120)
        #expect(DitanaryReviewSchedule.days(for: 9) == 240)
        #expect(DitanaryReviewSchedule.days(for: 10) == 365)
    }

    @Test func learningSessionBuilderAddsSentencePronunciationTasks() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let future = ISO8601DateFormatter().string(from: now.addingTimeInterval(3600))

        let due = Vocabulary(
            id: "due",
            vocab: "apple",
            V_meaning: "quả táo",
            E_example: "An apple is on the table.",
            learning_level: 2,
            next_review: past
        )
        let notDue = Vocabulary(id: "future", vocab: "banana", V_meaning: "quả chuối", learning_level: 2, next_review: future)

        let plan = LearningSessionBuilder.build(from: [due, notDue], now: now, maxWords: 5)

        #expect(plan.totalSavedWords == 2)
        #expect(plan.totalLearningWords == 2)
        #expect(plan.dueVocabsCount == 1)
        #expect(plan.selectedGroups.count == 1)
        #expect(plan.tasks.contains { $0.type == .multipleChoice })
        #expect(plan.tasks.contains {
            $0.type == .pronunciationExample && $0.pronunciationExample == "An apple is on the table."
        })
    }

    @Test func learningSessionBuilderIncludesMasterWordsInNormalReview() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let master = Vocabulary(
            id: "master",
            vocab: "orange",
            V_meaning: "quả cam",
            E_example: "I like orange juice.",
            learning_level: 6,
            next_review: past
        )

        let plan = LearningSessionBuilder.build(from: [master], now: now)

        #expect(plan.dueVocabsCount == 1)
        #expect(plan.selectedGroups.count == 1)
        #expect(plan.tasks.contains { $0.type == .pronunciationExample })
    }

    @Test func learningSessionBuilderKeepsBaseExercisesWhenExampleIsMissing() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let missingExample = Vocabulary(
            id: "missing",
            vocab: "weather",
            V_meaning: "thời tiết",
            learning_level: 2,
            next_review: past
        )

        let plan = LearningSessionBuilder.build(from: [missingExample], now: now)

        #expect(plan.dueVocabsCount == 1)
        #expect(plan.selectedGroups.count == 1)
        #expect(plan.tasks.count == 2)
        #expect(plan.tasks.allSatisfy {
            $0.type != .multipleChoice
                && $0.type != .pronunciationExample
                && $0.type != .sentenceScramble
        })
        #expect(plan.wordsWithoutExampleExercises == ["weather"])
    }

    @Test func learningSessionBuilderUsesOnlyRealMultipleChoiceOptions() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let apple = Vocabulary(
            id: "apple",
            vocab: "apple",
            V_meaning: "quả táo",
            learning_level: 1,
            next_review: past
        )
        let banana = Vocabulary(
            id: "banana",
            vocab: "banana",
            V_meaning: "quả chuối",
            learning_level: 1,
            next_review: past
        )

        let plan = LearningSessionBuilder.build(from: [apple, banana], now: now)
        let validMeanings = Set(["quả táo", "quả chuối"])
        let multipleChoiceTasks = plan.tasks.filter { $0.type == .multipleChoice }

        #expect(multipleChoiceTasks.count == 2)
        #expect(multipleChoiceTasks.allSatisfy {
            Set($0.options).isSubset(of: validMeanings)
        })
        #expect(!plan.tasks.contains {
            $0.options.contains { $0.hasPrefix("Nghĩa giả định") }
        })
    }

    @Test func learningRetryPlannerAppendsFreshTaskOnlyAfterIncorrectAnswer() async throws {
        let task = LearningTask(
            word: "apple",
            meanings: [Vocabulary(id: "apple", vocab: "apple", V_meaning: "quả táo")],
            type: .meaningAndType
        )

        let afterCorrectAnswer = LearningRetryPlanner.tasks(
            afterAnswering: task,
            isCorrect: true,
            scheduledTasks: [task]
        )
        let afterIncorrectAnswer = LearningRetryPlanner.tasks(
            afterAnswering: task,
            isCorrect: false,
            scheduledTasks: [task]
        )

        #expect(afterCorrectAnswer.count == 1)
        #expect(afterIncorrectAnswer.count == 2)
        #expect(afterIncorrectAnswer[1].id != task.id)
        #expect(afterIncorrectAnswer[1].word == task.word)
        #expect(afterIncorrectAnswer[1].type == task.type)
    }

    @Test func learningSessionBuilderLimitsDefaultSetToFiveWords() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let vocabs = (0..<6).map { index in
            Vocabulary(
                id: "word-\(index)",
                vocab: "word\(index)",
                V_meaning: "nghĩa \(index)",
                E_example: "This is word \(index).",
                learning_level: 1,
                next_review: past
            )
        }

        let plan = LearningSessionBuilder.build(from: vocabs, now: now)

        #expect(plan.dueVocabsCount == 6)
        #expect(plan.selectedGroups.count == 5)
    }

    @Test func listeningTextMaskerRevealsCorrectPrefix() async throws {
        let target = "Hi, I am Mary."

        #expect(ListeningTextMasker.maskedText(target: target, input: "") == "••, • •• ••••.")
        #expect(ListeningTextMasker.maskedText(target: target, input: "H") == "H•, • •• ••••.")
        #expect(ListeningTextMasker.maskedText(target: target, input: "Hi i") == "Hi, I •• ••••.")
    }

    @Test func listeningTextMaskerDetectsCompletionAndMistakes() async throws {
        let target = "This phenomenon is noticeable."

        #expect(ListeningTextMasker.progress(target: target, input: "this phe").hasMistake == false)
        #expect(ListeningTextMasker.progress(target: target, input: "this wrong").hasMistake == true)
        #expect(ListeningTextMasker.progress(target: target, input: "This phenomenon is noticeable").isComplete == true)
    }

    @Test func listeningSentenceScoreDeductsHintedWords() async throws {
        #expect(ListeningScoreCalculator.sentenceScore(wordCount: 5, hintedWordCount: 0) == 100)
        #expect(ListeningScoreCalculator.sentenceScore(wordCount: 5, hintedWordCount: 1) == 80)
        #expect(ListeningScoreCalculator.sentenceScore(wordCount: 5, hintedWordCount: 5) == 0)
    }

    @Test func listeningLessonPassesAtEightyPoints() async throws {
        #expect(ListeningScoreCalculator.hasPassed(score: 79.9) == false)
        #expect(ListeningScoreCalculator.hasPassed(score: 80) == true)
        #expect(ListeningScoreCalculator.hasPassed(score: 100) == true)
    }

    @Test func listeningLessonScoreWeightsSentencesEqually() async throws {
        let results = [
            ListeningSentenceResult(wordCount: 2, hintedWordCount: 0),
            ListeningSentenceResult(wordCount: 10, hintedWordCount: 5)
        ]

        #expect(ListeningScoreCalculator.lessonScore(results: results, totalSentenceCount: 2) == 75)
    }

    @Test func listeningLessonScoreLeavesUnfinishedSentencesAtZero() async throws {
        let results = [
            ListeningSentenceResult(wordCount: 4, hintedWordCount: 0),
            ListeningSentenceResult(wordCount: 4, hintedWordCount: 0)
        ]

        #expect(ListeningScoreCalculator.lessonScore(results: results, totalSentenceCount: 4) == 50)
    }

    @Test func listeningScoresKeepOneDecimalPlace() async throws {
        #expect(ListeningScoreCalculator.sentenceScore(wordCount: 3, hintedWordCount: 1) == 66.7)
        #expect(ListeningScoreCalculator.display(16.85) == "16.9")
    }

    @Test func listeningHintIdentifiesTheNextUnfinishedWord() async throws {
        let target = "Hi, I am Mary."

        #expect(ListeningTextMasker.nextHintWordIndex(target: target, input: "") == 0)
        #expect(ListeningTextMasker.nextHintWordIndex(target: target, input: "Hi I") == 2)
        #expect(ListeningTextMasker.nextHintWordIndex(target: target, input: "Hi I am Mary") == nil)
    }

    @Test func listeningWordTilesReflectTypingAndHints() async throws {
        let target = "Hi, I am Mary."
        let tiles = ListeningTextMasker.wordTiles(
            target: target,
            input: "Hi I ax",
            hintedWordIndices: [3]
        )

        #expect(tiles.count == 4)
        #expect(tiles[0].state == .correct)
        #expect(tiles[1].state == .correct)
        #expect(tiles[2].state == .wrong)
        #expect(tiles[2].displayText == "ax")
        #expect(tiles[3].state == .hinted)
        #expect(tiles[3].displayText == "Mary")
    }

}
