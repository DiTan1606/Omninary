import Foundation

/// Builds an Extra v1 / Ditan session from the words the learner picked.
/// Base set: one question of every exercise type per word. Extra adds
/// reinforcement questions for weak skills; nothing is ever removed.
struct AdaptiveSessionPlan {
    let tasks: [LearningTask]
    let selectedGroups: [[Vocabulary]]
    /// Why each word got its reinforcement questions, keyed by vocabulary ID.
    let reasons: [String: String]
    /// Adventure only: how many questions each planned quest holds, in order.
    var questSizes: [Int] = []
}

enum AdaptiveSessionBuilder {
    static func build(
        selected: [Vocabulary],
        distractorPool: [Vocabulary],
        profiles: [String: WordSkillProfile],
        isExtra: Bool
    ) -> AdaptiveSessionPlan {
        var generator = SystemRandomNumberGenerator()
        return build(selected: selected, distractorPool: distractorPool, profiles: profiles,
                     isExtra: isExtra, using: &generator)
    }

    static func build(
        selected: [Vocabulary],
        distractorPool: [Vocabulary],
        profiles: [String: WordSkillProfile],
        isExtra: Bool,
        using generator: inout some RandomNumberGenerator
    ) -> AdaptiveSessionPlan {
        var queues: [[LearningTask]] = []
        var reasons: [String: String] = [:]

        for vocab in selected {
            guard let word = vocab.vocab?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { continue }
            let id = vocab.id ?? word
            let profile = profiles[id] ?? .empty
            let available = QuestionType.allCases.filter { canBuild($0, for: vocab) }
            guard !available.isEmpty else { continue }

            var base = available.compactMap {
                makeTask(type: $0, vocab: vocab, word: word, pool: distractorPool, using: &generator)
            }
            base.shuffle(using: &generator)
            if let first = SessionComposer.firstType(for: profile, available: base.map(\.type)),
               let index = base.firstIndex(where: { $0.type == first }) {
                base.insert(base.remove(at: index), at: 0)
            }

            var extras: [LearningTask] = []
            if isExtra {
                let plan = ReinforcementPlanner.plan(for: profile).filter { available.contains($0.type) }
                for item in plan {
                    for _ in 0..<item.count {
                        guard var task = makeTask(type: item.type, vocab: vocab, word: word,
                                                  pool: distractorPool, using: &generator) else { continue }
                        task.reinforcedSkill = item.skill
                        extras.append(task)
                    }
                }
                reasons[id] = ReinforcementPlanner.reason(for: plan)
            }
            // Reinforcement goes after the base set so it lands in later rounds.
            queues.append(base + extras)
        }

        let tasks = SessionComposer.interleave(queues, wordKey: { $0.vocabularyID ?? $0.word }, using: &generator)
        return AdaptiveSessionPlan(tasks: tasks, selectedGroups: selected.map { [$0] }, reasons: reasons)
    }

    private struct AdventureEntry { let vocab: Vocabulary; let word: String; let id: String; let available: [QuestionType] }

    /// Order in which a word meets the exercise types: recognise, hear, recall, use, say.
    static let adventureTypes: [QuestionType] = [.multipleChoice, .listenAndType, .meaningAndType, .sentenceScramble, .pronunciationExample]

    static func buildAdventure(
        selected: [Vocabulary],
        distractorPool: [Vocabulary],
        profiles: [String: WordSkillProfile],
        isExtra: Bool
    ) -> AdaptiveSessionPlan {
        var generator = SystemRandomNumberGenerator()
        return buildAdventure(selected: selected, distractorPool: distractorPool, profiles: profiles,
                              isExtra: isExtra, using: &generator)
    }

    /// An adventure: one quest per round, each word once per round with one exercise type,
    /// so every word meets every type across the rounds. Rotating the word order by two each
    /// round keeps two questions of the same word at least two questions apart (five words).
    /// New words start with multiple choice. Extra's reinforcement comes first, as its own quests.
    static func buildAdventure(
        selected: [Vocabulary],
        distractorPool: [Vocabulary],
        profiles: [String: WordSkillProfile],
        isExtra: Bool,
        using generator: inout some RandomNumberGenerator
    ) -> AdaptiveSessionPlan {
        var entries: [AdventureEntry] = []
        for vocab in selected {
            guard let word = vocab.vocab?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { continue }
            let available = adventureTypes.filter { canBuild($0, for: vocab) }
            guard !available.isEmpty else { continue }
            entries.append(AdventureEntry(vocab: vocab, word: word, id: vocab.id ?? word, available: available))
        }
        // New words take the first rows so their first question is multiple choice.
        entries = entries.filter { ($0.vocab.learning_level ?? 0) == 0 } + entries.filter { ($0.vocab.learning_level ?? 0) != 0 }

        var reasons: [String: String] = [:]
        var extraQueues: [[LearningTask]] = []
        var rows: [[LearningTask]] = []
        for (row, entry) in entries.enumerated() {
            let isNew = (entry.vocab.learning_level ?? 0) == 0
            let start = isNew ? 0 : row % adventureTypes.count
            let order = (0..<adventureTypes.count).map { adventureTypes[(start + $0) % adventureTypes.count] }
                .filter { entry.available.contains($0) }
            rows.append(order.compactMap {
                makeTask(type: $0, vocab: entry.vocab, word: entry.word, pool: distractorPool, using: &generator)
            })
            guard isExtra else { continue }
            let profile = profiles[entry.id] ?? .empty
            let plan = ReinforcementPlanner.plan(for: profile).filter { entry.available.contains($0.type) }
            var extras: [LearningTask] = []
            for item in plan {
                for _ in 0..<item.count {
                    guard var task = makeTask(type: item.type, vocab: entry.vocab, word: entry.word,
                                              pool: distractorPool, using: &generator) else { continue }
                    task.reinforcedSkill = item.skill
                    extras.append(task)
                }
            }
            extraQueues.append(extras)
            reasons[entry.id] = ReinforcementPlanner.reason(for: plan)
        }

        var tasks: [LearningTask] = []
        var sizes: [Int] = []
        let extras = SessionComposer.interleave(extraQueues, wordKey: { $0.vocabularyID ?? $0.word }, using: &generator)
        for start in stride(from: 0, to: extras.count, by: AdventureQuests.size) {
            let chunk = extras[start..<min(start + AdventureQuests.size, extras.count)]
            tasks += chunk; sizes.append(chunk.count)
        }
        let rounds = rows.map(\.count).max() ?? 0
        for round in 0..<rounds {
            let n = rows.count
            let quest = (0..<n).compactMap { position -> LearningTask? in
                let row = (position + 2 * round) % n
                return round < rows[row].count ? rows[row][round] : nil
            }
            guard !quest.isEmpty else { continue }
            tasks += quest; sizes.append(quest.count)
        }
        return AdaptiveSessionPlan(tasks: tasks, selectedGroups: entries.map { [$0.vocab] }, reasons: reasons, questSizes: sizes)
    }

    static func canBuild(_ type: QuestionType, for vocab: Vocabulary) -> Bool {
        switch type {
        case .listenAndType, .meaningAndType, .multipleChoice:
            return !(vocab.vocab ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .sentenceScramble:
            return LearningTextNormalizer.sentenceScrambleWords(vocab.englishExample ?? "").count >= 3
        case .pronunciationExample:
            return vocab.englishExample != nil
        }
    }

    static func blankedExample(_ sentence: String?, word: String) -> String? {
        guard let sentence else { return nil }
        let ranges = VocabularyExampleHighlight.ranges(in: sentence, target: word)
        guard !ranges.isEmpty else { return nil }
        var result = sentence
        for range in ranges.reversed() {
            result.replaceSubrange(range, with: "_______")
        }
        return result
    }

    private static func makeTask(
        type: QuestionType, vocab: Vocabulary, word: String, pool: [Vocabulary],
        using generator: inout some RandomNumberGenerator
    ) -> LearningTask? {
        var task = LearningTask(word: word, meanings: [vocab], type: type)
        task.blankedExample = blankedExample(vocab.englishExample, word: word)
        switch type {
        case .listenAndType, .meaningAndType:
            break
        case .multipleChoice:
            let options = wordOptions(for: vocab, word: word, pool: pool, using: &generator)
            guard options.count >= 2 else { return nil }
            task.options = options
        case .sentenceScramble:
            guard let example = vocab.englishExample else { return nil }
            task.correctSentence = example
            task.scrambledWords = LearningTextNormalizer.sentenceScrambleWords(example).shuffled(using: &generator)
            task.vHint = vocab.vietnameseExample
        case .pronunciationExample:
            guard let example = vocab.englishExample else { return nil }
            task.pronunciationMeaning = vocab
            task.pronunciationExample = example
        }
        return task
    }

    /// Four English words: the answer plus distractors, same word form first.
    static func wordOptions(
        for vocab: Vocabulary, word: String, pool: [Vocabulary],
        using generator: inout some RandomNumberGenerator
    ) -> [String] {
        let target = word.lowercased()
        var seen: Set<String> = [target]
        var sameForm: [String] = []
        var others: [String] = []
        let form = (vocab.word_form ?? "").lowercased().split(separator: "-").first.map { $0.trimmingCharacters(in: .whitespaces) }
        for candidate in pool.shuffled(using: &generator) {
            guard let text = candidate.vocab?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  seen.insert(text.lowercased()).inserted else { continue }
            let candidateForm = (candidate.word_form ?? "").lowercased().split(separator: "-").first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if candidateForm == form { sameForm.append(text) } else { others.append(text) }
        }
        let distractors = Array((sameForm + others).prefix(3))
        return ([word] + distractors).shuffled(using: &generator)
    }
}
