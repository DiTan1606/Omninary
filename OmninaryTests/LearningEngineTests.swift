import Foundation
import Testing
@testable import Omninary

/// Deterministic generator so session composition can be asserted.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct LearningEngineTests {
    // MARK: Attempt score

    @Test func correctFirstTryScoresFullMarks() {
        var signals = AttemptSignals()
        signals.submissions = [AnswerSubmission(text: "afford", kind: .correct, atMs: 3_000)]
        signals.activeMs = 3_000
        #expect(LearningScoring.attemptScore(type: .meaningAndType, word: "afford", signals: signals) == 100)
    }

    @Test func listeningFeesFollowTheAgreedConvention() {
        var signals = AttemptSignals()
        signals.submissions = [AnswerSubmission(text: "lay off", kind: .correct, atMs: 5_000)]
        signals.activeMs = 5_000
        signals.replayCount = 3
        signals.playSpeeds = [1, 1, 0.75, 0.5]
        // 100 − 3 replays − 10 slowest speed = 87
        #expect(LearningScoring.attemptScore(type: .listenAndType, word: "lay off", signals: signals) == 87)

        signals.hintLevel = 1
        // −50 for the English definition hint
        #expect(LearningScoring.attemptScore(type: .listenAndType, word: "lay off", signals: signals) == 37)

        signals.hintLevel = 3
        #expect(LearningScoring.attemptScore(type: .listenAndType, word: "lay off", signals: signals) == 0)
    }

    @Test func rescueCostsTenPoints() {
        var signals = AttemptSignals()
        signals.submissions = [
            AnswerSubmission(text: "recieve", kind: .near, atMs: 2_000),
            AnswerSubmission(text: "receive", kind: .correct, atMs: 4_000)
        ]
        signals.rescueUsed = true
        signals.activeMs = 4_000
        #expect(LearningScoring.attemptScore(type: .meaningAndType, word: "receive", signals: signals) == 90)
    }

    @Test func wrongOrGiveUpScoresZeroAndMustRetry() {
        var signals = AttemptSignals()
        signals.submissions = [AnswerSubmission(text: "table", kind: .far, atMs: 2_000)]
        let score = LearningScoring.attemptScore(type: .multipleChoice, word: "chair", signals: signals)
        #expect(score == 0)
        #expect(!LearningScoring.passes(score))
        #expect(!LearningScoring.passes(50))
        #expect(LearningScoring.passes(51))
    }

    @Test func slownessFeeIsCapped() {
        var signals = AttemptSignals()
        signals.submissions = [AnswerSubmission(text: "chair", kind: .correct, atMs: 60_000)]
        signals.activeMs = 120_000
        // 8 s reference, far slower → capped at 15
        #expect(LearningScoring.attemptScore(type: .multipleChoice, word: "chair", signals: signals) == 85)
    }

    @Test func classifiesNearAndFarMisses() {
        #expect(LearningScoring.classify(answer: "Receive ", target: "receive") == .correct)
        #expect(LearningScoring.classify(answer: "recieve", target: "receive") == .near)
        #expect(LearningScoring.classify(answer: "deceive", target: "receive") == .near)
        #expect(LearningScoring.classify(answer: "table", target: "receive") == .far)
        #expect(LearningScoring.classify(answer: "  ", target: "receive") == .empty)
    }

    // MARK: Whole-process exercise score and mastery

    @Test func exerciseScoreCountsTheWholeProcess() {
        #expect(LearningScoring.exerciseScore(attemptScores: [100]) == 100)
        #expect(abs(LearningScoring.exerciseScore(attemptScores: [50, 100]) - 66.67) < 0.01)
        #expect(LearningScoring.exerciseScore(attemptScores: [50, 50, 100]) == 50)
        #expect(LearningScoring.exerciseScore(attemptScores: [0, 0, 0, 100]) == 25)
    }

    @Test func masteryUsesAgreedWeights() {
        let all: [QuestionType: Double] = [
            .listenAndType: 50, .meaningAndType: 100, .multipleChoice: 100,
            .sentenceScramble: 100, .pronunciationExample: 100
        ]
        // 0.2 × 50 + 0.8 × 100 = 90
        #expect(LearningScoring.mastery(exerciseScores: all) == 90)
        #expect(LearningScoring.mastery(exerciseScores: [:]) == nil)
    }

    // MARK: Skill evidence

    @Test func nearMissesBlameSpellingFarMissesBlameSound() {
        var near = AttemptSignals()
        near.submissions = [AnswerSubmission(text: "recieve", kind: .near, atMs: 1),
                            AnswerSubmission(text: "receive", kind: .correct, atMs: 2)]
        let nearCosts = LearningScoring.skillCosts(type: .listenAndType, word: "receive", signals: near)
        #expect(nearCosts[.spelling] == 50)
        #expect(nearCosts[.sound] == 0)

        var far = AttemptSignals()
        far.submissions = [AnswerSubmission(text: "believe", kind: .far, atMs: 1)]
        let farCosts = LearningScoring.skillCosts(type: .listenAndType, word: "receive", signals: far)
        #expect(farCosts[.sound] == 100)
        #expect(farCosts[.spelling] == 0)
    }

    @Test func recallAndSpellingAreSeparatedInMeaningToWrite() {
        var signals = AttemptSignals()
        signals.hintLevel = 2
        signals.submissions = [AnswerSubmission(text: "afford", kind: .correct, atMs: 1)]
        let costs = LearningScoring.skillCosts(type: .meaningAndType, word: "afford", signals: signals)
        #expect(costs[.recall] == 50)
        #expect(costs[.spelling] == 0)
    }

    // MARK: Level decision

    @Test func strongReviewJumpsALevel() {
        let decision = ExtraScheduler.decide(currentLevel: 0, isHolding: false, mastery: 95, previousMastery: nil)
        #expect(decision.kind == .jump)
        #expect(decision.reachedLevel == 1)
        #expect(decision.storedLevel == 2)
        #expect(decision.nextReviewDays == 3)
    }

    @Test func averageReviewFollowsTheFixedSchedule() {
        let decision = ExtraScheduler.decide(currentLevel: 2, isHolding: false, mastery: 75, previousMastery: 72)
        #expect(decision == LevelDecision(kind: .advance, reachedLevel: 3, storedLevel: 3, nextReviewDays: 7))
    }

    @Test func forgettingHoldsTheLevelWithASoonerReview() {
        // Level 3, 4th review after 7 days, mastery 80 → 45: hold level 4, review after 2 days.
        let decision = ExtraScheduler.decide(currentLevel: 3, isHolding: false, mastery: 45, previousMastery: 80)
        #expect(decision == LevelDecision(kind: .hold, reachedLevel: 4, storedLevel: 4, nextReviewDays: 2))

        // While holding, the next review stays at level 4 (4.2) and never demotes.
        let retry = ExtraScheduler.decide(currentLevel: 4, isHolding: true, mastery: 72, previousMastery: 45)
        #expect(retry == LevelDecision(kind: .advance, reachedLevel: 4, storedLevel: 4, nextReviewDays: 15))
    }

    @Test func highScoreAfterADropDoesNotJump() {
        let decision = ExtraScheduler.decide(currentLevel: 4, isHolding: false, mastery: 86, previousMastery: 98)
        #expect(decision.kind == .advance)
    }

    // MARK: Reinforcement

    @Test func weakSkillsGetReinforcementNeverRemoval() {
        var profile = WordSkillProfile()
        profile.skills = [.sound: 48, .spelling: 72, .meaning: 95]
        profile.exercises = [.listenAndType: 50, .pronunciationExample: 80]
        profile.spellingCostByType = [.meaningAndType: 100, .listenAndType: 0]
        let plan = ReinforcementPlanner.plan(for: profile)
        #expect(plan == [
            Reinforcement(skill: .sound, skillScore: 48, type: .listenAndType, count: 2),
            Reinforcement(skill: .spelling, skillScore: 72, type: .meaningAndType, count: 1)
        ])
    }

    @Test func sessionKeepsOneOfEveryTypeAndAddsReinforcement() {
        let words = (1...3).map { index in
            Vocabulary(id: "w\(index)", vocab: "word\(index)", word_form: "noun",
                       E_meaning: "meaning \(index)", EV_meaning: "nghĩa \(index)", V_meaning: "nghĩa \(index)",
                       E_example: "This is word\(index) in a sentence.", V_example: "Câu ví dụ.",
                       learning_level: 1)
        }
        var profile = WordSkillProfile()
        profile.skills = [.context: 40]
        var generator = SeededGenerator(state: 7)

        let ditan = AdaptiveSessionBuilder.build(selected: words, distractorPool: words,
                                                 profiles: ["w1": profile], isExtra: false, using: &generator)
        #expect(ditan.tasks.count == 15)

        let extra = AdaptiveSessionBuilder.build(selected: words, distractorPool: words,
                                                 profiles: ["w1": profile], isExtra: true, using: &generator)
        #expect(extra.tasks.count == 17)
        #expect(extra.tasks.filter { $0.reinforcedSkill == .context }.count == 2)
        for word in words {
            let types = Set(extra.tasks.filter { $0.vocabularyID == word.id }.map(\.type))
            #expect(types.count == 5)
        }
        // Interleaved: the same word never appears twice in a row.
        for (lhs, rhs) in zip(extra.tasks, extra.tasks.dropFirst()) {
            #expect(lhs.vocabularyID != rhs.vocabularyID || extra.tasks.allSatisfy { $0.vocabularyID == lhs.vocabularyID })
        }
    }

    @Test func listeningContextBlanksTheWord() {
        #expect(AdaptiveSessionBuilder.blankedExample("They laid off 200 workers.", word: "lay off")
                == "They _______ 200 workers.")
    }

    // MARK: Review priority

    @Test func overdueAndWeakWordsComeFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let formatter = ISO8601DateFormatter()
        let overdue = Vocabulary(id: "late", vocab: "late", learning_level: 2,
                                 next_review: formatter.string(from: now.addingTimeInterval(-6 * 86_400)))
        let today = Vocabulary(id: "today", vocab: "today", learning_level: 2,
                               next_review: formatter.string(from: now.addingTimeInterval(-60)))
        let future = Vocabulary(id: "future", vocab: "future", learning_level: 2,
                                next_review: formatter.string(from: now.addingTimeInterval(86_400)))
        let candidates = ReviewPriority.candidates(from: [today, future, overdue], profiles: [:], now: now)
        #expect(candidates.map(\.id) == ["late", "today"])
        #expect(candidates.first?.statusText == "Quá hạn 6 ngày")
        #expect(candidates.last?.statusText == "Đến hạn hôm nay")
    }
}
