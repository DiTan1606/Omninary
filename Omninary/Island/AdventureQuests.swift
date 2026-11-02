import Foundation

// One Phiêu lưu run: the planned quests, then the retries five questions at a time,
// and the copy kept on disk so the learner can leave and come back.

enum AdventureQuests {
    static let size = 5

    /// Words in one adventure: always 5 on Ditan; Extra picks 3 to 7 in Setting.
    static let wordCountKey = "adventure_word_count"
    static func wordCount(isExtra: Bool) -> Int {
        guard isExtra else { return 5 }
        let saved = UserDefaults.standard.integer(forKey: wordCountKey)
        return saved == 0 ? 5 : min(7, max(3, saved))
    }

    /// Question index at which each quest ends. Planned quests first; the questions added
    /// after them (answers to retry) make further quests of at most `size`.
    static func ends(planned: [Int], total: Int) -> [Int] {
        var ends: [Int] = []
        var end = 0
        for count in planned where count > 0 && end < total {
            end = min(total, end + count)
            ends.append(end)
        }
        while end < total {
            end = min(total, end + size)
            ends.append(end)
        }
        return ends
    }

    /// Quests finished once `answered` questions are done.
    static func done(answered: Int, ends: [Int]) -> Int { ends.filter { $0 <= answered }.count }

    /// Questions of the quest that starts at `start`, given the session's current length.
    static func range(startingAt start: Int, ends: [Int]) -> Range<Int>? {
        guard let end = ends.first(where: { $0 > start }) else { return nil }
        return start..<end
    }
}

/// What a learning session needs to pick up exactly where an adventure left it.
struct LearningQuestProgress: Codable {
    var tasks: [LearningTask]
    var answered: Int
    var attempts: [LearningAttemptTelemetry]
    var attemptNumbers: [UUID: Int]
    var correctAnswers: Int
    var exposures: [String: Int]
    var startedAt: Date
}

/// An unfinished adventure, saved after every quest.
struct AdventureSave: Codable {
    let userID: String
    let sessionID: UUID
    let region: String
    let stage: Int
    let words: [Vocabulary]
    let planned: [Int]
    let reasons: [String: String]
    var progress: LearningQuestProgress?
}

enum AdventureStore {
    private static let key = "adventure_in_progress"

    static func load(userID: String?) -> AdventureSave? {
        guard let userID, let data = UserDefaults.standard.data(forKey: key),
              let save = try? JSONDecoder().decode(AdventureSave.self, from: data), save.userID == userID else { return nil }
        return save
    }

    static func save(_ save: AdventureSave) {
        guard let data = try? JSONEncoder().encode(save) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
