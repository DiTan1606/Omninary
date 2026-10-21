import Foundation

/// Builds an Extra v1 / Ditan session from the words the learner picked.
/// Base set: one question of every exercise type per word. Extra adds
/// reinforcement questions for weak skills; nothing is ever removed.
struct AdaptiveSessionPlan {
    let tasks: [LearningTask]
    let selectedGroups: [[Vocabulary]]
    /// Why each word got its reinforcement questions, keyed by vocabulary ID.
    let reasons: [String: String]
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
