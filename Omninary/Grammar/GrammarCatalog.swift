import Foundation
import Combine

enum GrammarStage: String, CaseIterable, Identifiable, Codable, Hashable {
    case a1 = "A1", a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1", c2 = "C2"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a1: "Trình độ căn bản"
        case .a2: "Trình độ sơ cấp"
        case .b1: "Trình độ trung cấp"
        case .b2: "Trình độ trung cao cấp"
        case .c1: "Trình độ cao cấp"
        case .c2: "Trình độ thành thạo"
        }
    }
    var topicCount: Int {
        switch self {
        case .a1: 19
        case .a2: 16
        case .b1: 21
        case .b2: 16
        case .c1: 21
        case .c2: 8
        }
    }
    var topics: [GrammarTopic] {
        (1...topicCount).map { GrammarTopic(stage: self, number: $0) }
    }
}

struct GrammarTopic: Identifiable, Hashable {
    let stage: GrammarStage
    let number: Int
    var id: String { "\(stage.rawValue).\(number)" }
    var title: String? {
        guard stage == .a1 else { return nil }
        switch number {
        case 1: return "To be & subject pronouns"
        case 2: return "Object pronouns"
        case 3: return "Nouns & plurals"
        case 4: return "Countable & uncountable nouns"
        default: return nil
        }
    }
    var meaning: String? {
        guard stage == .a1 else { return nil }
        switch number {
        case 1: return "Động từ nối và đại từ chủ ngữ"
        case 2: return "Đại từ tân ngữ"
        case 3: return "Danh từ và số nhiều"
        case 4: return "Danh từ đếm được và không đếm được"
        default: return nil
        }
    }
}

struct GrammarTopicProgress: Codable, Equatable {
    var theoryCompleted = false
    var easyCompleted = false
    var mediumCompleted = false
    var hardCompleted = false
    var stars: Int { hardCompleted ? 3 : mediumCompleted ? 2 : easyCompleted ? 1 : 0 }

    static let a11PartIDs = (0..<2).map { "0-\($0)" }
        + (0..<4).map { "1-\($0)" } + (0..<7).map { "2-\($0)" }
        + (0..<6).map { "3-\($0)" } + (0..<8).map { "4-\($0)" }

    init() {}
    init(snapshot: [String: Any], partIDs: [String] = GrammarTopicProgress.a11PartIDs) {
        guard let privateContent = snapshot["privateContent"] as? [String: Any],
              let state = privateContent["gramV4"] as? [String: Any],
              (state["version"] as? Int) == 4,
              let progress = state["progress"] as? [String: Any] else { return }
        let read = progress["read"] as? [String: Bool] ?? [:]
        theoryCompleted = !partIDs.isEmpty && partIDs.allSatisfy { read[$0] == true }
        let done = progress["done"] as? [String: Bool] ?? [:]
        easyCompleted = theoryCompleted && done["easy"] == true
        mediumCompleted = easyCompleted && done["medium"] == true
        hardCompleted = mediumCompleted && done["hard"] == true
    }
}

@MainActor
final class GrammarProgressStore: ObservableObject {
    private struct Record {
        let snapshot: Data
    }
    @Published private(set) var courses: [String: GrammarPublishedCourse] = [:]
    @Published private var records: [String: Record] = [:]
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var loadError: String?
    @Published private(set) var saveError: String?
    private let userID: String
    private let repository: any GrammarProgressRepository
    private var pending: [String: Data] = [:]
    private var debounceTask: Task<Void, Never>?
    private var writerTask: Task<Bool, Never>?

    init(userID: String, repository: (any GrammarProgressRepository)? = nil) {
        self.userID = userID
        self.repository = repository ?? SupabaseGrammarProgressRepository()
    }

    func load(force: Bool = false) async {
        guard !isLoading, force || !hasLoaded else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        if (!pending.isEmpty || writerTask != nil), !(await flush()) { return }
        do {
            async let progressRequest = repository.fetch(userID: userID)
            async let catalogRequest = repository.courses(userID: userID)
            let (fetched, catalog) = try await (progressRequest, catalogRequest)
            courses = Dictionary(uniqueKeysWithValues: catalog.filter { $0.renderer_version == 1 && !$0.part_ids.isEmpty }.map { ($0.topic_id, $0) })
            records = fetched.reduce(into: [:]) { result, entry in
                if let record = Self.record(entry.value) { result[entry.key] = record }
            }
            hasLoaded = true
        } catch {
            loadError = "Chưa tải được tiến độ. Bạn kiểm tra kết nối rồi thử lại nhé."
        }
    }

    func progress(for topic: GrammarTopic) -> GrammarTopicProgress {
        guard let data = records[topic.id]?.snapshot,
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return GrammarTopicProgress() }
        return GrammarTopicProgress(snapshot: value, partIDs: partIDs(for: topic))
    }
    func canOpen(_ topic: GrammarTopic) -> Bool {
        guard hasLesson(topic) else { return false }
        if topic.number == 1 { return isUnlocked(topic.stage) }
        return progress(for: GrammarTopic(stage: topic.stage, number: topic.number - 1)).stars >= 2
    }
    func hasLesson(_ topic: GrammarTopic) -> Bool { courses[topic.id] != nil }
    func title(for topic: GrammarTopic) -> String? { courses[topic.id]?.title ?? topic.title }
    func meaning(for topic: GrammarTopic) -> String? { courses[topic.id]?.title_vi ?? topic.meaning }
    private func partIDs(for topic: GrammarTopic) -> [String] {
        courses[topic.id]?.part_ids ?? (topic.id == "A1.1" ? GrammarTopicProgress.a11PartIDs : [])
    }
    func loadLesson(for topic: GrammarTopic) async throws -> GrammarLessonSession {
        guard hasLoaded, hasLesson(topic) else { throw GrammarContentError.unavailable }
        let manifest = try await repository.lesson(topicID: topic.id, userID: userID)
        try manifest.validate(topicID: topic.id)
        courses[topic.id] = try manifest.summary()
        let repository = repository, userID = userID
        return GrammarLessonSession(manifest: manifest) { asset in try await repository.audio(asset, userID: userID) }
    }
    func completedCount(in stage: GrammarStage) -> Int {
        stage.topics.filter { progress(for: $0).stars >= 2 }.count
    }
    /// A1 is always open; each later stage opens once every topic of the stage before it is passed.
    func isUnlocked(_ stage: GrammarStage) -> Bool {
        guard let index = GrammarStage.allCases.firstIndex(of: stage), index > 0 else { return true }
        let previous = GrammarStage.allCases[index - 1]
        return isUnlocked(previous) && completedCount(in: previous) == previous.topicCount
    }
    func snapshot(for topic: GrammarTopic) -> [String: Any] {
        guard let data = records[topic.id]?.snapshot,
              var snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        // Unfinished quizzes never resume when a topic is reopened.
        if var contents = snapshot["privateContent"] as? [String: Any], var state = contents["gramV4"] as? [String: Any] {
            state = state.filter { ["version", "progress", "heard", "part", "level", "rate", "lessonVersion"].contains($0.key) }
            state["view"] = "topic"
            contents["gramV4"] = state
            snapshot["privateContent"] = contents
        }
        return snapshot
    }
    func save(_ incoming: [String: Any], for topic: GrammarTopic) {
        let snapshot = Self.achievementsOnly(incoming)
        guard hasLoaded, hasLesson(topic), JSONSerialization.isValidJSONObject(snapshot),
              let privateContent = snapshot["privateContent"] as? [String: Any],
              let state = privateContent["gramV4"] as? [String: Any], (state["version"] as? Int) == 4,
              let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), data.count <= 16_384,
              records[topic.id]?.snapshot != data else { return }
        let theoryWasDone = progress(for: topic).theoryCompleted
        records[topic.id] = Record(snapshot: data)
        // reading the last theory part counts as the day's learning
        if !theoryWasDone, progress(for: topic).theoryCompleted { keepStreak() }
        pending[topic.id] = data
        debounceTask?.cancel()
        // Coalesce rapid input without writing a second, stale request in parallel.
        debounceTask = Task { [self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            debounceTask = nil
            _ = await flush()
        }
    }

    @discardableResult
    func flush() async -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        if let writerTask { return await writerTask.value }
        guard !pending.isEmpty else { return saveError == nil }
        let task = Task { [self] in await writePending() }
        writerTask = task
        let result = await task.value
        writerTask = nil
        return result
    }

    private func writePending() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        while let (topicID, data) = pending.first {
            pending.removeValue(forKey: topicID)
            do {
                let saved = try await repository.save(data, topicID: topicID, userID: userID)
                // A later edit stays on screen while this earlier request completes.
                if pending[topicID] == nil, let record = Self.record(saved) { records[topicID] = record }
            } catch {
                if pending[topicID] == nil { pending[topicID] = data }
                saveError = "Chưa lưu được tiến độ. Bạn kiểm tra kết nối rồi thử lại nhé."
                return false
            }
        }
        return true
    }

    func attempts(for topic: GrammarTopic, offset: Int) async throws -> [String: Any] {
        guard hasLoaded, hasLesson(topic), (0...1_000_000).contains(offset) else { throw GrammarHistoryError.invalidResponse }
        let rows = try await repository.attempts(topicID: topic.id, userID: userID, offset: offset)
        return ["items": try rows.map { try $0.payload() }, "hasMore": rows.count == 50]
    }

    func completeAttempt(_ attempt: [String: Any], snapshot: [String: Any], for topic: GrammarTopic, lessonPartIDs: [String]? = nil) async throws -> [String: Any] {
        let cleaned = Self.achievementsOnly(snapshot)
        guard hasLoaded, hasLesson(topic), JSONSerialization.isValidJSONObject(attempt),
              let attemptData = try? JSONSerialization.data(withJSONObject: attempt), attemptData.count <= 65_536,
              let snapshotData = try? JSONSerialization.data(withJSONObject: cleaned), snapshotData.count <= 16_384,
              let id = attempt["id"] as? String, UUID(uuidString: id) != nil,
              let level = attempt["level"] as? String, ["easy", "medium", "hard"].contains(level),
              let answers = attempt["results"] as? [[String: Any]], (1...500).contains(answers.count),
              GrammarTopicProgress(snapshot: cleaned, partIDs: lessonPartIDs ?? partIDs(for: topic)).theoryCompleted else { throw GrammarHistoryError.invalidAttempt }
        guard await flush() else { throw GrammarHistoryError.unavailable }
        // The RPC and the ordinary progress writer are sequential. The database also merges achievements.
        let saved = try await repository.completeAttempt(attemptData, snapshot: snapshotData, topicID: topic.id, userID: userID)
        let savedData = try JSONEncoder().encode(saved.snapshot)
        if let record = Self.record(savedData) { records[topic.id] = record }
        saveError = nil
        // so does finishing an exercise set, at any level
        keepStreak()
        return ["attempt": try saved.attempt.payload(),
                "snapshot": try JSONSerialization.jsonObject(with: savedData)]
    }

    /// Records today's learning for the streak; the day's first one lights it on its full screen.
    /// Practice data (tests and previews) never touches the account's streak.
    private func keepStreak() {
        guard repository is SupabaseGrammarProgressRepository else { return }
        let userID = userID
        Task { @MainActor in
            let first = (try? await UserProgressRepository.recordDailyActivityAndUpdateStreak(userId: userID, sessionId: UUID())) ?? false
            if first { OmniIgniteCenter.shared.showPending() }
        }
    }

    private static func achievementsOnly(_ incoming: [String: Any]) -> [String: Any] {
        var result = incoming
        if var privateContent = result["privateContent"] as? [String: Any],
           var state = privateContent["gramV4"] as? [String: Any] {
            state = state.filter { ["version", "progress", "heard", "part", "level", "rate", "lessonVersion"].contains($0.key) }
            state["view"] = "topic"
            privateContent["gramV4"] = state
            result["privateContent"] = privateContent
        }
        return result
    }

    private static func record(_ data: Data) -> Record? {
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let canonical = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return Record(snapshot: canonical)
    }
}
