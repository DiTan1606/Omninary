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
        currentLevel + 1
    }

    static func reviewDelayDays(for learningLevel: Int) -> Int {
        DitanaryReviewSchedule.days(for: learningLevel)
    }

    static func nextReviewDate(for learningLevel: Int, from date: Date) -> Date {
        Calendar.current.date(
            byAdding: .day,
            value: reviewDelayDays(for: learningLevel),
            to: date
        ) ?? date
    }

    static func reviewString(for learningLevel: Int, from date: Date, formatter: ISO8601DateFormatter) -> String {
        formatter.string(from: nextReviewDate(for: learningLevel, from: date))
    }

    static func isDue(_ vocab: Vocabulary, now: Date) -> Bool {
        guard let level = vocab.learning_level, level > 0 else { return false }
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

enum DitanaryReviewSchedule {
    static func days(for level: Int) -> Int {
        switch level {
        case ..<1: return 0
        case 1: return 0
        case 2: return 1
        case 3: return 3
        case 4: return 7
        case 5: return 15
        case 6: return 30
        case 7: return 60
        case 8: return 120
        case 9: return 240
        default: return 365
        }
    }

    static let visiblePlan: [(title: String, subtitle: String)] = [
        ("Cấp 0", "Mới tải về, bấm đưa từ này vào học để lên Cấp 1"),
        ("Cấp 1 -> 2", "Ôn lại trong ngày"),
        ("Cấp 2 -> 3", "Ôn lại sau 1 ngày"),
        ("Cấp 3 -> 4", "Ôn lại sau 3 ngày"),
        ("Cấp 4 -> 5", "Ôn lại sau 7 ngày"),
        ("Cấp 5 -> 6", "Ôn lại sau 15 ngày"),
        ("Cấp 6+", "Master, tiếp tục ôn sau 30, 60, 120, 240, rồi 365 ngày")
    ]
}

enum LearningLevelDisplay {
    static func bucket(for level: Int) -> Int {
        level >= 6 ? 6 : max(level, 0)
    }

    static func title(for level: Int) -> String {
        level >= 6 ? "Master" : "Cấp \(level)"
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
        let allGrouped = Dictionary(grouping: vocabs, by: {
            $0.vocab?.trimmingCharacters(in: .whitespaces).lowercased() ?? "unknown"
        })

        let allJoinedMeanings = Array(Set(allGrouped.values.compactMap { group -> String? in
            let meanings = group.compactMap { $0.V_meaning }.filter { !$0.isEmpty }
            return meanings.isEmpty ? nil : meanings.joined(separator: " / ")
        }))

        var dueGroups: [[Vocabulary]] = []
        var stats = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0]
        var totalLearningWords = 0

        for group in allGrouped.values {
            let isLearning = group.contains { ($0.learning_level ?? 0) > 0 }
            guard isLearning else { continue }

            totalLearningWords += 1
            let level = group.first(where: { ($0.learning_level ?? 0) > 0 })?.learning_level ?? 1
            stats[LearningLevelDisplay.bucket(for: level), default: 0] += 1

            let isDue = group.contains { ReviewScheduler.isDue($0, now: now) }
            if isDue {
                dueGroups.append(group)
            }
        }

        let dueCount = dueGroups.count
        var selectedDueGroups = dueGroups
        selectedDueGroups.shuffle()
        let selectedGroups = Array(selectedDueGroups.prefix(maxWords))
        let wordsWithoutExampleExercises = selectedGroups.compactMap { group -> String? in
            group.contains(where: { $0.englishExample != nil }) ? nil : group.first?.vocab
        }
        let tasks = buildLearningTasks(from: selectedGroups, allJoinedMeanings: allJoinedMeanings).shuffled()

        return LearningSessionPlan(
            selectedGroups: selectedGroups,
            tasks: tasks,
            statsByLevel: stats,
            totalLearningWords: totalLearningWords,
            totalSavedWords: allGrouped.count,
            dueVocabsCount: dueCount,
            wordsWithoutExampleExercises: wordsWithoutExampleExercises.sorted()
        )
    }

    private static func buildLearningTasks(from groups: [[Vocabulary]], allJoinedMeanings: [String]) -> [LearningTask] {
        var tasks: [LearningTask] = []

        for group in groups {
            guard let word = group.first?.vocab else { continue }

            tasks.append(LearningTask(word: word, meanings: group, type: .listenAndType))
            tasks.append(LearningTask(word: word, meanings: group, type: .meaningAndType))

            let correctMeaning = group.compactMap { $0.V_meaning }.filter { !$0.isEmpty }.joined(separator: " / ")
            let correctOption = correctMeaning.isEmpty ? "Không có nghĩa" : correctMeaning
            var options = [correctOption]
            let distractors = allJoinedMeanings.filter { $0 != correctOption }.shuffled()
            options.append(contentsOf: distractors.prefix(3))

            while options.count < 4 {
                options.append("Nghĩa giả định \(UUID().uuidString.prefix(4))")
            }

            options.shuffle()
            tasks.append(LearningTask(word: word, meanings: group, type: .multipleChoice, options: options))

            for meaning in group {
                if let example = meaning.englishExample {
                    let words = LearningTextNormalizer.sentenceScrambleWords(example)

                    if words.count >= 3 {
                        tasks.append(LearningTask(
                            word: word,
                            meanings: group,
                            type: .sentenceScramble,
                            correctSentence: example,
                            scrambledWords: words.shuffled(),
                            vHint: meaning.vietnameseExample
                        ))
                    }

                    tasks.append(LearningTask(
                        word: word,
                        meanings: group,
                        type: .pronunciationExample,
                        pronunciationMeaning: meaning,
                        pronunciationExample: example
                    ))
                }
            }
        }

        return tasks
    }
}
