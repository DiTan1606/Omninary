import Foundation

enum LearningTextNormalizer {
    static func normalizedWords(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .punctuationCharacters)
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    static func normalizedAnswer(_ text: String) -> String {
        normalizedWords(text).joined(separator: " ")
    }

    static func sentenceScrambleWords(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "[.,!?;:]", with: "", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}

enum ReviewScheduler {
    static func nextLearningLevel(from currentLevel: Int) -> Int {
        min(currentLevel + 1, 10)
    }

    static func reviewDelayDays(for learningLevel: Int) -> Int {
        OmninaryReviewSchedule.days(for: learningLevel)
    }

    static func nextReviewDate(for learningLevel: Int, from date: Date) -> Date? {
        guard learningLevel < 10 else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: reviewDelayDays(for: learningLevel),
            to: date
        ) ?? date
    }

    static func reviewString(for learningLevel: Int, from date: Date, formatter: ISO8601DateFormatter) -> String? {
        nextReviewDate(for: learningLevel, from: date).map { formatter.string(from: $0) }
    }

    static func isDue(_ vocab: Vocabulary, now: Date) -> Bool {
        guard let level = vocab.learning_level, (0..<10).contains(level) else { return false }
        guard let nextReview = vocab.next_review else { return true }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        if let date = fractionalFormatter.date(from: nextReview) ?? fallbackFormatter.date(from: nextReview) {
            return date <= now
        }

        return true
    }
}

enum OmninaryReviewSchedule {
    static func days(for level: Int) -> Int {
        switch level {
        case ..<1: return 0
        case 1: return 1
        case 2: return 3
        case 3: return 7
        case 4: return 15
        case 5: return 30
        case 6: return 60
        case 7: return 120
        case 8: return 240
        case 9: return 365
        default: return 0 // Super has no automatic review.
        }
    }

    static let visiblePlan: [(title: String, subtitle: String)] = [
        ("New", "Đưa vào danh sách học để lên Cấp 0"),
        ("Cấp 0", "Học lần đầu ngay"),
        ("Cấp 1–5", "Ôn sau 1, 3, 7, 15, rồi 30 ngày"),
        ("Master", "Ôn sau 60, 120, 240, rồi 365 ngày"),
        ("Super", "Hoàn thành, không còn lịch ôn tự động")
    ]
}

enum LearningLevelDisplay {
    static func bucket(for level: Int) -> Int {
        level >= 10 ? 7 : min(max(level, 0), 6)
    }

    static func title(for level: Int?) -> String {
        guard let level else { return "New" }
        if level >= 10 { return "Super" }
        return level >= 6 ? "Master" : "Cấp \(level)"
    }
}

enum ReviewTimeFormatter {
    static func text(for dateStr: String?) -> String {
        guard let dateStr else { return "Ngay bây giờ" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()

        guard let date = formatter.date(from: dateStr) ?? fallbackFormatter.date(from: dateStr) else {
            return "Ngay bây giờ"
        }

        let now = Date()
        if date <= now {
            return "Hôm nay"
        }

        let diff = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: date)
        if let days = diff.day, days > 0 {
            return "sau \(days) ngày"
        }
        if let hours = diff.hour, hours > 0 {
            return "sau \(hours) giờ"
        }
        if let minutes = diff.minute, minutes > 0 {
            return "sau \(minutes) phút"
        }
        return "Ngay bây giờ"
    }
}

enum LearningSessionBuilder {
    static func build(from vocabs: [Vocabulary], now: Date = Date(), maxWords: Int = 5) -> LearningSessionPlan {
        // Collection projections may contain the same item more than once. Learning
        // and telemetry always use one entry per catalog ID.
        var seenMeaningIDs = Set<String>()
        let uniqueVocabs = vocabs.filter { vocab in
            guard let identity = vocab.catalog_id ?? vocab.user_vocabulary_id ?? vocab.id else { return true }
            return seenMeaningIDs.insert(identity).inserted
        }
        let allDistinctMeanings = Array(Set(uniqueVocabs.compactMap { $0.V_meaning?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))

        var dueMeanings: [Vocabulary] = []
        var stats = Dictionary(uniqueKeysWithValues: (0...7).map { ($0, 0) })
        var totalLearningWords = 0

        for vocab in uniqueVocabs {
            guard let level = vocab.learning_level, level >= 0 else { continue }

            totalLearningWords += 1
            stats[LearningLevelDisplay.bucket(for: level), default: 0] += 1

            if ReviewScheduler.isDue(vocab, now: now) {
                dueMeanings.append(vocab)
            }
        }

        let dueCount = dueMeanings.count
        var selectedDueMeanings = dueMeanings
        selectedDueMeanings.shuffle()
        let selectedMeanings = Array(selectedDueMeanings.prefix(maxWords))
        let selectedGroups = selectedMeanings.map { [$0] }

        let wordsWithoutExampleExercises = selectedMeanings.compactMap { meaning -> String? in
            meaning.englishExample != nil ? nil : meaning.vocab
        }
        let tasks = buildLearningTasks(from: selectedMeanings, allDistinctMeanings: allDistinctMeanings).shuffled()

        return LearningSessionPlan(
            selectedGroups: selectedGroups,
            tasks: tasks,
            statsByLevel: stats,
            totalLearningWords: totalLearningWords,
            totalSavedWords: uniqueVocabs.count,
            dueVocabsCount: dueCount,
            wordsWithoutExampleExercises: wordsWithoutExampleExercises.sorted()
        )
    }

    private static func buildLearningTasks(from meanings: [Vocabulary], allDistinctMeanings: [String]) -> [LearningTask] {
        var tasks: [LearningTask] = []

        for meaning in meanings {
            guard let word = meaning.vocab?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { continue }
            let singleMeaningGroup = [meaning]

            tasks.append(LearningTask(word: word, meanings: singleMeaningGroup, type: .listenAndType))
            tasks.append(LearningTask(word: word, meanings: singleMeaningGroup, type: .meaningAndType))

            if let correctOption = meaning.V_meaning?.trimmingCharacters(in: .whitespacesAndNewlines), !correctOption.isEmpty {
                var options = [correctOption]
                let distractors = allDistinctMeanings.filter { $0 != correctOption }.shuffled()
                options.append(contentsOf: distractors.prefix(3))

                if options.count >= 2 {
                    options.shuffle()
                    tasks.append(LearningTask(word: word, meanings: singleMeaningGroup, type: .multipleChoice, options: options))
                }
            }

            if let example = meaning.englishExample {
                let words = LearningTextNormalizer.sentenceScrambleWords(example)

                if words.count >= 3 {
                    tasks.append(LearningTask(
                        word: word,
                        meanings: singleMeaningGroup,
                        type: .sentenceScramble,
                        correctSentence: example,
                        scrambledWords: words.shuffled(),
                        vHint: meaning.vietnameseExample
                    ))
                }

                tasks.append(LearningTask(
                    word: word,
                    meanings: singleMeaningGroup,
                    type: .pronunciationExample,
                    pronunciationMeaning: meaning,
                    pronunciationExample: example
                ))
            }
        }

        return tasks
    }
}
