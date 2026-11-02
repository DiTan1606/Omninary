import Foundation
import Supabase

/// Keeps the question as it was answered, even if the lesson is edited later.
struct GrammarAttempt: Codable, Identifiable {
    struct Answer: Codable {
        let questionID: String
        let prompt: String
        let stem: String
        let answer: String
        let correctAnswer: String
        let correct: Bool
        let timedOut: Bool
    }
    let id: UUID
    let topic_id: String
    let level: String
    let completed_at: String
    let duration_seconds: Int
    let score: Int
    let answers: [Answer]
    var lesson_version_id: UUID? = nil

    func payload() throws -> [String: Any] {
        guard let date = ISODate.parse(completed_at) else {
            throw GrammarHistoryError.invalidResponse
        }
        var value: [String: Any] = ["id": id.uuidString.lowercased(), "level": level, "at": date.timeIntervalSince1970 * 1000,
                "duration": duration_seconds, "score": score,
                "results": try JSONSerialization.jsonObject(with: JSONEncoder().encode(answers))]
        if let lesson_version_id { value["lessonVersion"] = lesson_version_id.uuidString.lowercased() }
        return value
    }
}

struct GrammarAttemptCompletion: Decodable {
    let attempt: GrammarAttempt
    let snapshot: AnyJSON
}

enum GrammarHistoryError: LocalizedError {
    case invalidResponse, invalidAttempt, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Chưa đọc được lịch sử làm bài. Bạn thử lại nhé."
        case .invalidAttempt: "Kết quả chưa đầy đủ để lưu."
        case .unavailable: "Chưa lưu được kết quả. Bạn kiểm tra kết nối rồi thử lại nhé."
        }
    }
}
