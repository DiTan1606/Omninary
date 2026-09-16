import Foundation

enum ListeningRepositoryError: LocalizedError {
    case missingAudioPath

    var errorDescription: String? {
        switch self {
        case .missingAudioPath:
            return "Câu này chưa có file audio."
        }
    }
}

enum ListeningRepository {
    private static let audioBucket = "listening-audio"
    private static let userLessonSelect = """
    user_id,lesson_id,is_in_learning,downloaded_at,learning_started_at,completed_at,latest_score,best_score,
    is_in_shadowing,shadowing_started_at,shadowing_completed_at,shadowing_latest_score,shadowing_best_score,
    listening_lessons(id,series_id,slug,source_id,title,vi_title,cefr,description,is_published,created_at)
    """

    static func fetchPublishedSeries() async throws -> [ListeningSeries] {
        try await supabase
            .from("listening_series")
            .select()
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchLessons() async throws -> [ListeningLesson] {
        try await supabase
            .from("listening_lessons")
            .select()
            .eq("is_published", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func fetchSeriesCatalog() async throws -> [ListeningSeriesCatalogItem] {
        async let seriesRequest = fetchPublishedSeries()
        async let lessonsRequest = fetchLessons()

        let (series, lessons) = try await (seriesRequest, lessonsRequest)
        let lessonsBySeriesId = Dictionary(grouping: lessons.compactMap { lesson -> ListeningLesson? in
            guard lesson.series_id != nil else { return nil }
            return lesson
        }) { $0.series_id ?? "" }

        return series.compactMap { series in
            let seriesLessons = lessonsBySeriesId[series.id] ?? []
            guard !seriesLessons.isEmpty else { return nil }
            return ListeningSeriesCatalogItem(series: series, lessons: seriesLessons)
        }
    }

    static func fetchSegments(lessonId: String) async throws -> [ListeningSegment] {
        try await supabase
            .from("listening_segments")
            .select()
            .eq("lesson_id", value: lessonId)
            .order("order_index", ascending: true)
            .execute()
            .value
    }

    static func fetchLessonSummaries(for lessons: [ListeningLesson]) async throws -> [ListeningLessonSummary] {
        let lessonOrder = Dictionary(uniqueKeysWithValues: lessons.enumerated().map { ($1.id, $0) })

        return try await withThrowingTaskGroup(of: ListeningLessonSummary.self) { group in
            for lesson in lessons {
                group.addTask {
                    let segments = try await fetchSegments(lessonId: lesson.id)
                    return ListeningLessonSummary(
                        lesson: lesson,
                        segmentCount: segments.count,
                        durationSeconds: segments.reduce(0) { $0 + ($1.duration_seconds ?? 0) }
                    )
                }
            }

            var summaries: [ListeningLessonSummary] = []
            for try await summary in group {
                summaries.append(summary)
            }

            return summaries.sorted {
                (lessonOrder[$0.lesson.id] ?? .max) < (lessonOrder[$1.lesson.id] ?? .max)
            }
        }
    }

    static func fetchUserLessonEntries(userId: String) async throws -> [UserListeningLesson] {
        try await supabase
            .from("user_listening_lessons")
            .select(userLessonSelect)
            .eq("user_id", value: userId)
            .order("downloaded_at", ascending: false)
            .execute()
            .value
    }

    static func fetchUserLessonEntry(userId: String, lessonId: String) async throws -> UserListeningLesson? {
        let entries: [UserListeningLesson] = try await supabase
            .from("user_listening_lessons")
            .select("user_id,lesson_id,is_in_learning,downloaded_at,learning_started_at,completed_at,latest_score,best_score,is_in_shadowing,shadowing_started_at,shadowing_completed_at,shadowing_latest_score,shadowing_best_score")
            .eq("user_id", value: userId)
            .eq("lesson_id", value: lessonId)
            .limit(1)
            .execute()
            .value

        return entries.first
    }

    static func fetchLibraryItems(userId: String) async throws -> [ListeningLibraryItem] {
        async let entriesRequest = fetchUserLessonEntries(userId: userId)
        async let completedSegmentIdsRequest = fetchCompletedSegmentIds(userId: userId)
        async let passedShadowingSegmentIdsRequest = fetchPassedShadowingSegmentIds(userId: userId)

        let (entries, completedSegmentIds, passedShadowingSegmentIds) = try await (
            entriesRequest,
            completedSegmentIdsRequest,
            passedShadowingSegmentIdsRequest
        )

        return try await withThrowingTaskGroup(of: ListeningLibraryItem?.self) { group in
            for entry in entries {
                group.addTask {
                    guard let lesson = entry.listening_lessons else { return nil }
                    let segments = try await fetchSegments(lessonId: lesson.id)
                    let completedCount = segments.filter { completedSegmentIds.contains($0.id) }.count
                    return ListeningLibraryItem(
                        entry: entry,
                        lesson: lesson,
                        segmentCount: segments.count,
                        completedSegmentCount: completedCount,
                        shadowingPassedSegmentCount: segments.filter { passedShadowingSegmentIds.contains($0.id) }.count
                    )
                }
            }

            var items: [ListeningLibraryItem] = []
            for try await item in group {
                if let item {
                    items.append(item)
                }
            }

            return items.sorted {
                ($0.entry.downloaded_at ?? "") > ($1.entry.downloaded_at ?? "")
            }
        }
    }

    static func fetchLibrarySeriesItems(userId: String) async throws -> [ListeningSeriesLibraryItem] {
        async let libraryItemsRequest = fetchLibraryItems(userId: userId)
        async let seriesRequest = fetchPublishedSeries()

        let (libraryItems, series) = try await (libraryItemsRequest, seriesRequest)
        let seriesById = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let itemsBySeriesId = Dictionary(grouping: libraryItems.compactMap { item -> ListeningLibraryItem? in
            guard item.lesson.series_id != nil else { return nil }
            return item
        }) { $0.lesson.series_id ?? "" }

        return itemsBySeriesId.compactMap { seriesId, items in
            guard let series = seriesById[seriesId] else { return nil }
            return ListeningSeriesLibraryItem(series: series, lessons: items)
        }
        .sorted {
            $0.series.title.localizedCaseInsensitiveCompare($1.series.title) == .orderedAscending
        }
    }

    @discardableResult
    static func addLessonsToLibrary(userId: String, lessonIds: [String]) async throws -> Int {
        let uniqueLessonIds = Array(Set(lessonIds))
        guard !uniqueLessonIds.isEmpty else { return 0 }

        let existing: [UserListeningLesson] = try await supabase
            .from("user_listening_lessons")
            .select("user_id,lesson_id,is_in_learning,downloaded_at,learning_started_at,completed_at")
            .eq("user_id", value: userId)
            .execute()
            .value

        let existingLessonIds = Set(existing.map(\.lesson_id))
        let inserts = uniqueLessonIds
            .filter { !existingLessonIds.contains($0) }
            .map { UserListeningLessonInsert(user_id: userId, lesson_id: $0) }

        guard !inserts.isEmpty else { return 0 }

        try await supabase
            .from("user_listening_lessons")
            .insert(inserts)
            .execute()

        return inserts.count
    }

    static func removeLessonFromLibrary(lessonId: String) async throws {
        try await supabase
            .rpc(
                "remove_listening_lesson_from_library",
                params: RemoveListeningLessonFromLibraryParams(p_lesson_id: lessonId)
            )
            .execute()
    }

    static func startListeningPractice(userId: String, lessonId: String) async throws {
        let update = UserListeningLessonLearningUpdate(
            is_in_learning: true,
            learning_started_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("user_listening_lessons")
            .update(update)
            .eq("user_id", value: userId)
            .eq("lesson_id", value: lessonId)
            .execute()
    }

    static func startShadowingPractice(userId: String, lessonId: String) async throws {
        let update = UserListeningLessonShadowingUpdate(
            is_in_shadowing: true,
            shadowing_started_at: ISO8601DateFormatter().string(from: Date())
        )

        try await supabase
            .from("user_listening_lessons")
            .update(update)
            .eq("user_id", value: userId)
            .eq("lesson_id", value: lessonId)
            .execute()
    }

    static func markLessonCompleted(lessonId: String) async throws -> Double {
        let params = ListeningLessonIdParams(p_lesson_id: lessonId)
        let score: Double = try await supabase
            .rpc("complete_listening_lesson", params: params)
            .execute()
            .value
        return score
    }

    static func restartLesson(lessonId: String) async throws {
        try await supabase
            .rpc(
                "restart_listening_lesson",
                params: ListeningLessonIdParams(p_lesson_id: lessonId)
            )
            .execute()
    }

    static func fetchListeningProgress(userId: String) async throws -> [ListeningProgress] {
        try await supabase
            .from("user_listening_progress")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    static func fetchCompletedSegmentIds(userId: String) async throws -> Set<String> {
        let progresses = try await fetchListeningProgress(userId: userId)

        return Set(progresses.filter { $0.status == "completed" }.map(\.segment_id))
    }

    static func fetchShadowingProgress(userId: String) async throws -> [ShadowingProgress] {
        try await supabase
            .from("user_shadowing_progress")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
    }

    static func fetchPassedShadowingSegmentIds(userId: String) async throws -> Set<String> {
        let progresses = try await fetchShadowingProgress(userId: userId)
        return Set(progresses.filter(\.isPassed).map(\.segment_id))
    }

    static func publicAudioURL(for segment: ListeningSegment) throws -> URL {
        guard let audioPath = segment.audio_path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !audioPath.isEmpty else {
            throw ListeningRepositoryError.missingAudioPath
        }

        return try supabase.storage
            .from(audioBucket)
            .getPublicURL(path: audioPath)
    }

    static func recordSegmentCompleted(
        segmentId: String,
        result: ListeningSentenceResult
    ) async throws {
        let params = RecordListeningSegmentCompletionParams(
            p_segment_id: segmentId,
            p_hinted_word_indexes: result.hintedWordIndices.sorted()
        )
        try await supabase
            .rpc("record_listening_segment_completion", params: params)
            .execute()
    }
}
