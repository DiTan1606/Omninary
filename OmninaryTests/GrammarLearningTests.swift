import Foundation
import Testing
@testable import Omninary

@MainActor
struct GrammarLearningTests {
    @Test func curriculumHasSixStagesAndOnlySuppliedTitles() {
        #expect(GrammarStage.allCases.map(\.topicCount) == [19, 16, 21, 16, 21, 8])
        #expect(GrammarStage.allCases.flatMap(\.topics).count == 101)
        #expect(GrammarStage.a1.topics.prefix(4).compactMap(\.title) == [
            "To be & subject pronouns", "Object pronouns", "Nouns & plurals", "Countable & uncountable nouns"
        ])
        #expect(GrammarStage.a1.topics.dropFirst(4).allSatisfy { $0.title == nil })
        #expect(GrammarStage.allCases.dropFirst().flatMap(\.topics).allSatisfy { $0.title == nil })
    }

    @Test func completionRequiresTheoryAndSequentialDifficulties() {
        let hardOnly = GrammarTopicProgress(snapshot: snapshot(readAll: false, easy: false, medium: false, hard: true))
        #expect(hardOnly.stars == 0)
        let skippedEasy = GrammarTopicProgress(snapshot: snapshot(readAll: true, easy: false, medium: true, hard: true))
        #expect(skippedEasy.stars == 0)
        #expect(GrammarTopicProgress(snapshot: snapshot(readAll: true, easy: true, medium: false, hard: true)).stars == 1)
        #expect(GrammarTopicProgress(snapshot: snapshot(readAll: true, easy: true, medium: true, hard: false)).stars == 2)
        #expect(GrammarTopicProgress(snapshot: snapshot(readAll: true, easy: true, medium: true, hard: true)).stars == 3)
    }

    @Test func progressRestoresFromRepositoryPerAccountAndReopensAtOverview() async throws {
        let repository = InMemoryGrammarProgressRepository()
        let topic = GrammarStage.a1.topics[0]
        let first = GrammarProgressStore(userID: "first", repository: repository)
        await first.load()
        first.save(snapshot(readAll: true, easy: true, medium: true, hard: false), for: topic)
        let saved = await first.flush()
        #expect(saved)
        #expect(first.progress(for: topic).stars == 2)
        #expect(first.completedCount(in: .a1) == 1)
        let restored = GrammarProgressStore(userID: "first", repository: repository)
        await restored.load()
        #expect(restored.progress(for: topic).stars == 2)
        let other = GrammarProgressStore(userID: "other", repository: repository)
        await other.load()
        #expect(other.progress(for: topic).stars == 0)
        #expect(other.snapshot(for: topic).isEmpty)
        let privateContent = try #require(restored.snapshot(for: topic)["privateContent"] as? [String: Any])
        let state = try #require(privateContent["gramV4"] as? [String: Any])
        #expect(state["view"] as? String == "topic")
        #expect(state["deadline"] == nil)
        #expect(state["question"] == nil)
    }

    @Test func unavailableTopicsDoNotOpenAFakeLesson() async {
        let store = GrammarProgressStore(userID: "learner", repository: InMemoryGrammarProgressRepository())
        await store.load()
        #expect(store.canOpen(GrammarStage.a1.topics[0]))
        #expect(!store.canOpen(GrammarStage.a1.topics[1]))
        #expect(GrammarStage.a2.topics.allSatisfy { !store.canOpen($0) })
        store.save(["privateContent": ["gramV4": ["version": 3]]], for: GrammarStage.a1.topics[0])
        #expect(store.snapshot(for: GrammarStage.a1.topics[0]).isEmpty)
    }

    @Test func loadFailureDoesNotOverwriteCloudProgressWithAnEmptyState() async {
        let repository = InMemoryGrammarProgressRepository()
        repository.failFetch = true
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        await store.load()
        #expect(!store.hasLoaded)
        #expect(store.loadError != nil)
        store.save(snapshot(readAll: true, easy: true, medium: true, hard: false), for: GrammarStage.a1.topics[0])
        _ = await store.flush()
        #expect(repository.writes.isEmpty)
    }

    @Test func failedSaveCanBeRetriedWithoutLosingAchievements() async throws {
        let repository = InMemoryGrammarProgressRepository()
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        await store.load()
        repository.failSave = true
        store.save(snapshot(readAll: true, easy: true, medium: true, hard: false), for: GrammarStage.a1.topics[0])
        let failed = await store.flush()
        #expect(!failed)
        #expect(store.saveError != nil)
        repository.failSave = false
        let retried = await store.flush()
        #expect(retried)
        #expect(store.saveError == nil)
        let restored = GrammarProgressStore(userID: "learner", repository: repository)
        await restored.load()
        #expect(restored.progress(for: GrammarStage.a1.topics[0]).stars == 2)
    }

    @Test func editDuringAnInFlightSaveIsWrittenAfterIt() async {
        let repository = InMemoryGrammarProgressRepository()
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        await store.load()
        var gate: CheckedContinuation<Void, Never>?
        repository.onSave = { await withCheckedContinuation { gate = $0 } }
        let topic = GrammarStage.a1.topics[0]
        store.save(snapshot(readAll: true, easy: true, medium: false, hard: false), for: topic)
        let saving = Task { await store.flush() }
        while gate == nil { await Task.yield() }
        store.save(snapshot(readAll: true, easy: true, medium: true, hard: false), for: topic)
        repository.onSave = nil
        gate?.resume()
        let saved = await saving.value
        #expect(saved)
        #expect(repository.writes.count == 2)
        let restored = GrammarProgressStore(userID: "learner", repository: repository)
        await restored.load()
        #expect(restored.progress(for: topic).stars == 2)
    }

    @Test func completedAttemptIsSavedOnceAndHistoryIsPrivate() async throws {
        let repository = InMemoryGrammarProgressRepository()
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        let topic = GrammarStage.a1.topics[0]
        await store.load()
        let attempt = completedAttempt()
        let progress = snapshot(readAll: true, easy: true, medium: false, hard: false)
        let first = try await store.completeAttempt(attempt, snapshot: progress, for: topic)
        _ = try await store.completeAttempt(attempt, snapshot: progress, for: topic)
        #expect(store.progress(for: topic).stars == 1)
        let history = try await store.attempts(for: topic, offset: 0)
        let rows = try #require(history["items"] as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["score"] as? Int == 12)
        let saved = try #require(first["snapshot"] as? [String: Any])
        let contents = try #require(saved["privateContent"] as? [String: Any])
        let state = try #require(contents["gramV4"] as? [String: Any])
        #expect(state["answers"] == nil && state["question"] == nil && state["deadline"] == nil)
        let other = GrammarProgressStore(userID: "other", repository: repository)
        await other.load()
        let otherHistory = try await other.attempts(for: topic, offset: 0)
        #expect((otherHistory["items"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func failedAttemptSaveDoesNotAwardAStarAndCanRetry() async throws {
        let repository = InMemoryGrammarProgressRepository()
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        await store.load()
        repository.failSave = true
        let topic = GrammarStage.a1.topics[0]
        let attempt = completedAttempt()
        let progress = snapshot(readAll: true, easy: true, medium: false, hard: false)
        do {
            _ = try await store.completeAttempt(attempt, snapshot: progress, for: topic)
            Issue.record("A failed save should throw.")
        } catch { }
        #expect(store.progress(for: topic).stars == 0)
        repository.failSave = false
        _ = try await store.completeAttempt(attempt, snapshot: progress, for: topic)
        #expect(store.progress(for: topic).stars == 1)
        let history = try await store.attempts(for: topic, offset: 0)
        #expect((history["items"] as? [[String: Any]])?.count == 1)
    }

    private func completedAttempt() -> [String: Any] {
        ["id": UUID().uuidString, "level": "easy", "duration": 120,
         "results": (0..<16).map { index -> [String: Any] in
            ["questionID": "test-\(index)", "prompt": "Choose the form.", "stem": "I ___ a student.",
             "answer": index < 12 ? "am" : "is", "correctAnswer": "am", "correct": index < 12, "timedOut": false]
         }]
    }

    @Test func sharedRendererContainsNoBundledLessonOrAudio() throws {
        let index = try #require(GrammarLessonAssets.lessonURL(GrammarStage.a1.topics[0]))
        let root = index.deletingLastPathComponent()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("atlas.png").path))
        let portrait = try #require(GrammarLessonAssets.portrait)
        #expect(portrait.size.width >= 256)
        #expect(portrait.size.height / portrait.size.width == 1.5)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(files.allSatisfy { $0.pathExtension != "mp3" })
        let html = try String(contentsOf: index, encoding: .utf8)
        #expect(!html.contains("g-course-data"))
        #expect(!html.contains("g-island"))
        #expect(!html.contains("https://"))
        #expect(html.contains("media-src blob:"))
    }

    @Test func publishedCatalogOpensNewTopicsWithoutBundlingTheirContent() async {
        let repository = InMemoryGrammarProgressRepository()
        repository.publishedCourses.append(GrammarPublishedCourse(topic_id: "A1.2", title: "Object pronouns", title_vi: "Đại từ tân ngữ", part_ids: ["object-1"], published_version: UUID(), renderer_version: 1))
        let store = GrammarProgressStore(userID: "learner", repository: repository)
        await store.load()
        #expect(store.hasLesson(GrammarStage.a1.topics[1]))
        #expect(!store.canOpen(GrammarStage.a1.topics[1]))
        store.save(snapshot(readAll: true, easy: true, medium: true, hard: false), for: GrammarStage.a1.topics[0])
        #expect(store.canOpen(GrammarStage.a1.topics[1]))
    }

    @Test func pinnedManifestKeepsAllNarrationCuesAndInteractiveExamples() throws {
        let manifest = try manifestFixture()
        try manifest.validate(topicID: "A1.1")
        #expect(manifest.audioAssets.count == 37)
        let content = try manifest.payload()
        #expect((content["parts"] as? [[String: Any]])?.count == 27)
        #expect(content["releaseID"] as? String == manifest.versionID.uuidString.lowercased())
        #expect(content["teachingRules"] is [String: Any])
    }

    @Test func corruptedAudioIsRejectedBeforeItCanPlay() async throws {
        let manifest = try manifestFixture()
        let session = GrammarLessonSession(manifest: manifest) { _ in Data([0]) }
        do {
            _ = try await session.audio(manifest.audioAssets[0].key)
            Issue.record("Mismatched audio must not reach the lesson player.")
        } catch GrammarContentError.invalidAudio { }
        session.close()
    }

    @Test func verifiedAudioIsReusedOnlyWithinTheCurrentLessonSession() async throws {
        let fixture = try manifestFixture()
        var document = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as? [String: Any])
        var assets = try #require(document["audioAssets"] as? [[String: Any]])
        let bytes = Data("verified-memory-only-audio".utf8)
        assets[0]["sha256"] = GrammarLessonManifest.digest(bytes); assets[0]["byteCount"] = bytes.count
        document["audioAssets"] = assets
        let manifest = try JSONDecoder().decode(GrammarLessonManifest.self, from: JSONSerialization.data(withJSONObject: document))
        var downloads = 0
        let session = GrammarLessonSession(manifest: manifest) { _ in downloads += 1; return bytes }
        let key = manifest.audioAssets[0].key
        let first = try await session.audio(key)
        _ = try await session.audio(key)
        #expect(downloads == 1)
        #expect(first["version"] as? String == manifest.versionID.uuidString.lowercased())
        session.close()
        do { _ = try await session.audio(key); Issue.record("A closed session must release its audio.") }
        catch GrammarContentError.closed { }
    }

    private func manifestFixture() throws -> GrammarLessonManifest {
        let bundle = Bundle(for: GrammarFixtureBundleMarker.self)
        let url = try #require(bundle.url(forResource: "GrammarManifest", withExtension: "json", subdirectory: "Fixtures") ?? bundle.url(forResource: "GrammarManifest", withExtension: "json"))
        return try JSONDecoder().decode(GrammarLessonManifest.self, from: Data(contentsOf: url))
    }

    private func snapshot(readAll: Bool, easy: Bool, medium: Bool, hard: Bool) -> [String: Any] {
        ["privateContent": ["gramV4": [
            "version": 4, "view": "exercise", "question": 3, "deadline": 1_800_000_000_000.0,
            "progress": [
                "read": Dictionary(uniqueKeysWithValues: GrammarTopicProgress.a11PartIDs.map { ($0, readAll) }),
                "done": ["easy": easy, "medium": medium, "hard": hard]
            ]
        ]]]
    }
}

private final class GrammarFixtureBundleMarker: NSObject {}
