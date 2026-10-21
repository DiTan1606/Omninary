import Foundation

// Extra v1 learning core. Pure functions only: no UI, network or clock access,
// so every rule in docs/EXTRA_V1_DESIGN.md can be unit tested. The server
// recomputes the session aggregates from the attempt scores and skill costs
// produced here and owns the level/review decision.

enum LearningAlgorithm {
    static let version = "extra_v1"
}

enum LearningSkill: String, CaseIterable, Codable, Hashable {
    case meaning, recall, spelling, sound, context

    var title: String {
        switch self {
        case .meaning: "Nhận diện nghĩa"
        case .recall: "Gọi lại từ"
        case .spelling: "Chính tả"
        case .sound: "Âm của từ"
        case .context: "Ngữ cảnh"
        }
    }
}

extension QuestionType: CaseIterable {
    static var allCases: [QuestionType] {
        [.listenAndType, .meaningAndType, .multipleChoice, .sentenceScramble, .pronunciationExample]
    }

    init?(telemetryName: String) {
        guard let match = Self.allCases.first(where: { $0.telemetryName == telemetryName }) else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .listenAndType: "Nghe–viết"
        case .meaningAndType: "Nghĩa → viết từ"
        case .multipleChoice: "Nghĩa → chọn từ"
        case .sentenceScramble: "Sắp xếp câu"
        case .pronunciationExample: "Đọc câu ví dụ"
        }
    }

    /// Weight of the exercise score in the word's mastery score M.
    var masteryWeight: Double {
        switch self {
        case .listenAndType: 0.20
        case .meaningAndType: 0.25
        case .multipleChoice: 0.15
        case .sentenceScramble: 0.20
        case .pronunciationExample: 0.20
        }
    }

    var mainSkill: LearningSkill {
        switch self {
        case .listenAndType, .pronunciationExample: .sound
        case .meaningAndType: .recall
        case .multipleChoice: .meaning
        case .sentenceScramble: .context
        }
    }

    /// Hint ladder length; level 3 always reveals the answer.
    var maxHintLevel: Int {
        self == .pronunciationExample ? 0 : 3
    }

    /// Fee of the first hint (the second always adds 25; the third zeroes the score).
    var firstHintFee: Int { self == .listenAndType ? 50 : 25 }

    var allowsRescue: Bool { self == .listenAndType || self == .meaningAndType }

    /// Expected active answering time, in seconds, before the slowness fee starts.
    func referenceSeconds(word: String, tokenCount: Int) -> Double {
        let letters = Double(word.filter(\.isLetter).count)
        switch self {
        case .listenAndType: return 10 + 0.5 * letters
        case .meaningAndType: return 12 + 0.5 * letters
        case .multipleChoice: return 8
        case .sentenceScramble: return 3 * Double(max(tokenCount, 1))
        case .pronunciationExample: return .infinity
        }
    }
}

// MARK: - Interaction signals

enum SubmissionKind: String, Codable {
    /// Right word, right spelling.
    case correct
    /// Right word with a small spelling slip (edit distance ≤ max(1, length / 5)).
    case near
    /// A different word.
    case far
    case empty
}

struct AnswerSubmission: Codable, Equatable {
    var text: String
    var kind: SubmissionKind
    var atMs: Int
}

/// Everything observed while the learner works on one attempt of one question.
struct AttemptSignals: Codable, Equatable {
    var attemptNumber = 1
    var positionInSession = 0
    /// Questions since the learner last saw an answer card of this word; nil when never seen this session.
    var questionsSinceExposure: Int?
    var firstInteractionMs: Int?
    var activeMs = 0
    var pausedMs = 0
    var pauseCount = 0
    var submissions: [AnswerSubmission] = []
    var hintLevel = 0
    var hintOpenedMs: [Int] = []
    var gaveUp = false
    var rescueUsed = false
    var deletions = 0
    // Listening
    var autoplayed = false
    var replayCount = 0
    var playSpeeds: [Double] = []
    var firstKeyAfterAudioMs: Int?
    // Meaning → pick
    var chosenOptions: [String] = []
    var optionCount = 0
    // Scramble
    var tokenCount = 0
    var tokenMoves = 0
    var undoCount = 0
    var misplacedShare: Double?
    var correctPrefix: Int?
    // Read aloud
    var modelPlays = 0
    var recordings = 0
    var pronunciationScore: Int?
    var targetWordAccuracy: Int?
    var accuracyScore: Int?
    var fluencyScore: Int?
    var completenessScore: Int?
    var prosodyScore: Int?
    var pronunciationPassed = false

    var slowestSpeed: Double { playSpeeds.min() ?? 1 }
    var isCorrect: Bool {
        if gaveUp || hintLevel >= 3 { return false }
        return submissions.last?.kind == .correct
    }
    var wrongSubmissions: [AnswerSubmission] { submissions.filter { $0.kind != .correct } }
}

// MARK: - Scoring

enum LearningScoring {
    static let passThreshold = 50

    static func passes(_ score: Int) -> Bool { score > passThreshold }

    static func classify(answer: String, target: String) -> SubmissionKind {
        let given = LearningTextNormalizer.normalizedAnswer(answer)
        let expected = LearningTextNormalizer.normalizedAnswer(target)
        guard !given.isEmpty else { return .empty }
        if given == expected { return .correct }
        let tolerance = max(1, expected.count / 5)
        return editDistance(given, expected) <= tolerance ? .near : .far
    }

    /// Optimal string alignment distance: a swapped letter pair (recieve) counts as one slip.
    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    static func hintFee(type: QuestionType, level: Int) -> Int {
        switch level {
        case ..<1: return 0
        case 1: return type.firstHintFee
        case 2: return type.firstHintFee + 25
        default: return 100
        }
    }

    static func speedFee(slowestSpeed: Double) -> Int {
        if slowestSpeed <= 0.5 { return 10 }
        if slowestSpeed < 1 { return 5 }
        return 0
    }

    static func slownessFee(type: QuestionType, word: String, signals: AttemptSignals) -> Double {
        let reference = type.referenceSeconds(word: word, tokenCount: signals.tokenCount)
        guard reference.isFinite, reference > 0 else { return 0 }
        let ratio = Double(signals.activeMs) / 1000 / reference
        return min(15, max(0, (ratio - 1) * 10))
    }

    /// 0–100. Wrong, gave up or answer revealed → 0; otherwise 100 minus fees.
    static func attemptScore(type: QuestionType, word: String, signals: AttemptSignals) -> Int {
        if type == .pronunciationExample {
            let score = min(max(signals.pronunciationScore ?? 0, 0), 100)
            // The read-aloud pass rule stays authoritative: a failed recording never passes.
            return signals.pronunciationPassed ? max(score, passThreshold + 1) : min(score, passThreshold)
        }
        guard signals.isCorrect else { return 0 }
        var fees = Double(hintFee(type: type, level: signals.hintLevel))
        if type == .listenAndType {
            fees += Double(signals.replayCount) + Double(speedFee(slowestSpeed: signals.slowestSpeed))
        }
        if signals.rescueUsed { fees += 10 }
        fees += slownessFee(type: type, word: word, signals: signals)
        return Int(max(0, (100 - fees).rounded()))
    }

    /// Skill evidence costs of one attempt; larger means more difficulty observed.
    static func skillCosts(type: QuestionType, word: String, signals: AttemptSignals) -> [LearningSkill: Double] {
        let near = Double(signals.wrongSubmissions.filter { $0.kind == .near }.count)
        let far = Double(signals.wrongSubmissions.filter { $0.kind == .far || $0.kind == .empty }.count)
        let revealed = signals.gaveUp || signals.hintLevel >= 3
        let slowness = slownessFee(type: type, word: word, signals: signals)
        var costs: [LearningSkill: Double] = [:]

        switch type {
        case .listenAndType:
            var sound = Double(signals.replayCount) + Double(speedFee(slowestSpeed: signals.slowestSpeed))
                + Double(hintFee(type: type, level: min(signals.hintLevel, 2))) + 100 * far + slowness
            if revealed { sound = max(sound, 100) }
            costs[.sound] = sound
            if !revealed || near > 0 { costs[.spelling] = 50 * near }
        case .meaningAndType:
            var recall = Double(hintFee(type: type, level: min(signals.hintLevel, 2))) + 100 * far + slowness
            if revealed { recall = max(recall, 100) }
            costs[.recall] = recall
            if !revealed || near > 0 { costs[.spelling] = 50 * near }
        case .multipleChoice:
            let wrongPicks = Double(max(0, signals.chosenOptions.count - (signals.isCorrect ? 1 : 0)))
            var meaning = 100 * wrongPicks + Double(25 * min(signals.hintLevel, 2)) + slowness
            if revealed { meaning = max(meaning, 100) }
            costs[.meaning] = meaning
        case .sentenceScramble:
            var context = Double(25 * min(signals.hintLevel, 2)) + slowness
            if let misplaced = signals.misplacedShare, !signals.isCorrect || signals.wrongSubmissions.count > 0 {
                context += max(30, 100 * misplaced)
            }
            let excessUndo = max(0, signals.undoCount - signals.tokenCount)
            context += min(20, Double(2 * excessUndo))
            if revealed { context = max(context, 100) }
            costs[.context] = context
        case .pronunciationExample:
            let accuracy = signals.targetWordAccuracy ?? signals.pronunciationScore ?? 0
            costs[.sound] = Double(100 - min(max(accuracy, 0), 100)) + Double(signals.modelPlays)
        }
        return costs
    }

    /// Whole-process score: 100 / (1 + lost / 100).
    static func processScore(lost: Double) -> Double {
        100 / (1 + max(0, lost) / 100)
    }

    static func exerciseScore(attemptScores: [Int]) -> Double {
        processScore(lost: attemptScores.reduce(0) { $0 + Double(100 - $1) })
    }

    static func mastery(exerciseScores: [QuestionType: Double]) -> Int? {
        let weights = exerciseScores.keys.reduce(0) { $0 + $1.masteryWeight }
        guard weights > 0 else { return nil }
        let total = exerciseScores.reduce(0) { $0 + $1.key.masteryWeight * $1.value }
        return Int((total / weights).rounded())
    }
}

// MARK: - Level decision (mirrors the server function extra_v1_decide)

enum LevelDecisionKind: String, Codable {
    case jump, advance, hold

    var title: String {
        switch self {
        case .jump: "Nhảy cấp"
        case .advance: "Lên cấp"
        case .hold: "Giữ cấp, ôn bù"
        }
    }
}

struct LevelDecision: Equatable {
    let kind: LevelDecisionKind
    let reachedLevel: Int
    let storedLevel: Int
    let nextReviewDays: Int?
}

enum ExtraScheduler {
    /// Exercise types failed on the first try that force a hold, whatever M is.
    static let holdFirstAttemptFailures = 2

    /// - Parameter firstAttemptFailures: exercise types whose first (base) attempt
    ///   did not pass (score ≤ 50) in this session.
    static func decide(currentLevel: Int?, isHolding: Bool, mastery: Int, previousMastery: Int?,
                       firstAttemptFailures: Int = 0) -> LevelDecision {
        let level = max(currentLevel ?? 0, 0)
        let reached = min(isHolding ? max(level, 1) : level + 1, 10)
        let drop = max(0, (previousMastery ?? mastery) - mastery)

        // Checked before the jump: retries right after seeing the answer can
        // lift M above 60 while the word was not actually recalled.
        let mustHold = mastery < 60 || drop >= 20 || firstAttemptFailures >= holdFirstAttemptFailures
        if !mustHold && mastery >= 85 && drop <= 5 {
            let stored = min(reached + 1, 10)
            return LevelDecision(kind: .jump, reachedLevel: reached, storedLevel: stored, nextReviewDays: reviewDays(stored))
        }
        if mustHold {
            let ratio = min(0.80, max(0.15, Double(mastery) / 100 - Double(drop) / 200))
            let reference = Double(OmninaryReviewSchedule.days(for: reached - 1))
            let days = max(1, Int((reference * ratio).rounded()))
            return LevelDecision(kind: .hold, reachedLevel: reached, storedLevel: reached, nextReviewDays: reached >= 10 ? nil : days)
        }
        return LevelDecision(kind: .advance, reachedLevel: reached, storedLevel: reached, nextReviewDays: reviewDays(reached))
    }

    private static func reviewDays(_ level: Int) -> Int? {
        level >= 10 ? nil : OmninaryReviewSchedule.days(for: level)
    }
}

// MARK: - Skill profile and reinforcement

struct WordSkillProfile: Equatable {
    var skills: [LearningSkill: Double] = [:]
    var exercises: [QuestionType: Double] = [:]
    /// Spelling cost observed per exercise type in the last session (decides where spelling is trained).
    var spellingCostByType: [QuestionType: Double] = [:]
    var lastFirstAsked: [QuestionType: Date] = [:]
    var lastMastery: Int?
    var isHolding = false
    var holdAttempt = 0

    static let empty = WordSkillProfile()
}

struct Reinforcement: Equatable {
    let skill: LearningSkill
    let skillScore: Double
    let type: QuestionType
    let count: Int
}

enum ReinforcementPlanner {
    static let maxPerWord = 3

    static func plan(for profile: WordSkillProfile) -> [Reinforcement] {
        let weak = profile.skills
            .filter { $0.value < 80 }
            .sorted { $0.value < $1.value }
        var result: [Reinforcement] = []
        var budget = maxPerWord
        for (skill, score) in weak where budget > 0 {
            let count = min(score < 60 ? 2 : 1, budget)
            result.append(Reinforcement(skill: skill, skillScore: score, type: exerciseType(for: skill, profile: profile), count: count))
            budget -= count
        }
        return result
    }

    static func exerciseType(for skill: LearningSkill, profile: WordSkillProfile) -> QuestionType {
        switch skill {
        case .meaning: return .multipleChoice
        case .recall: return .meaningAndType
        case .context: return .sentenceScramble
        case .spelling:
            let listen = profile.spellingCostByType[.listenAndType] ?? 0
            let meaning = profile.spellingCostByType[.meaningAndType] ?? 0
            return listen > meaning ? .listenAndType : .meaningAndType
        case .sound:
            let listen = profile.exercises[.listenAndType] ?? 100
            let speak = profile.exercises[.pronunciationExample] ?? 100
            return speak < listen ? .pronunciationExample : .listenAndType
        }
    }

    static func reason(for reinforcements: [Reinforcement]) -> String? {
        guard !reinforcements.isEmpty else { return nil }
        return reinforcements.map {
            "\($0.skill.title) \(Int($0.skillScore.rounded())): +\($0.count) \($0.type.title.lowercased())"
        }.joined(separator: " · ")
    }
}

// MARK: - Session order

enum SessionComposer {
    /// Base set first type: the type that has gone longest without being asked first.
    /// Ties keep the order of `available`, which the builder has already shuffled.
    static func firstType(for profile: WordSkillProfile, available: [QuestionType]) -> QuestionType? {
        available.enumerated().min { lhs, rhs in
            let l = profile.lastFirstAsked[lhs.element] ?? .distantPast
            let r = profile.lastFirstAsked[rhs.element] ?? .distantPast
            if l != r { return l < r }
            return lhs.offset < rhs.offset
        }?.element
    }

    /// Interleaves per-word queues round by round, keeping two questions of the same word apart.
    static func interleave<Item>(_ queues: [[Item]], wordKey: (Item) -> String,
                                 using generator: inout some RandomNumberGenerator) -> [Item] {
        var queues = queues.filter { !$0.isEmpty }
        var result: [Item] = []
        while !queues.isEmpty {
            var round = queues.indices.shuffled(using: &generator)
            // Avoid starting a round with the word that ended the previous one.
            if let last = result.last, queues.count > 1, let first = round.first,
               let head = queues[first].first, wordKey(head) == wordKey(last) {
                round.append(round.removeFirst())
            }
            for index in round {
                result.append(queues[index].removeFirst())
            }
            queues.removeAll { $0.isEmpty }
        }
        return spreadAdjacentRepeats(result, wordKey: wordKey)
    }

    /// When one word has more questions than the rest (reinforcement), its tail
    /// would run back to back; move each repeat to the latest earlier gap
    /// between two other words.
    static func spreadAdjacentRepeats<Item>(_ items: [Item], wordKey: (Item) -> String) -> [Item] {
        var items = items
        var index = 1
        while index < items.count {
            let key = wordKey(items[index])
            guard key == wordKey(items[index - 1]) else { index += 1; continue }
            let item = items.remove(at: index)
            var target: Int?
            for position in stride(from: index - 1, through: 0, by: -1) {
                let before = position > 0 ? wordKey(items[position - 1]) : nil
                let after = wordKey(items[position])
                if before != key && after != key { target = position; break }
            }
            if let target {
                items.insert(item, at: target)
            } else {
                items.insert(item, at: index)
                index += 1
            }
        }
        return items
    }
}

// MARK: - Review list priority

struct ReviewCandidate: Identifiable, Equatable {
    let id: String
    let vocabulary: Vocabulary
    let overdueDays: Int
    let isNew: Bool
    let isHolding: Bool
    let holdAttempt: Int
    let lastMastery: Int?
    let priority: Double

    var statusText: String {
        if isNew { return "Từ mới" }
        if overdueDays > 0 { return "Quá hạn \(overdueDays) ngày" }
        return "Đến hạn hôm nay"
    }
}

enum ReviewPriority {
    static func candidates(from vocabs: [Vocabulary], profiles: [String: WordSkillProfile], now: Date) -> [ReviewCandidate] {
        var seen = Set<String>()
        return vocabs.compactMap { vocab -> ReviewCandidate? in
            guard let id = vocab.id, seen.insert(id).inserted,
                  let level = vocab.learning_level, ReviewScheduler.isDue(vocab, now: now) else { return nil }
            let profile = profiles[id] ?? .empty
            let dueDate = vocab.next_review.flatMap(parseDate) ?? now
            let overdue = max(0, Int(now.timeIntervalSince(dueDate) / 86_400))
            let interval = max(1, OmninaryReviewSchedule.days(for: level))
            let isNew = level == 0
            var priority = Double(overdue) / Double(interval)
            priority += Double(100 - (profile.lastMastery ?? 100)) / 100
            if profile.isHolding { priority += 0.5 }
            if isNew { priority += 0.3 }
            return ReviewCandidate(id: id, vocabulary: vocab, overdueDays: overdue, isNew: isNew,
                                   isHolding: profile.isHolding, holdAttempt: profile.holdAttempt,
                                   lastMastery: profile.lastMastery, priority: priority)
        }
        .sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return ($0.vocabulary.vocab ?? "") < ($1.vocabulary.vocab ?? "")
        }
    }

    static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
