import Foundation
import CryptoKit
import Supabase

struct GrammarPublishedCourse: Codable, Identifiable {
    let topic_id: String
    let title: String
    let title_vi: String
    let part_ids: [String]
    let published_version: UUID
    let renderer_version: Int
    var id: String { topic_id }
}

struct GrammarAudioAsset: Codable {
    let key: String
    let path: String
    let sha256: String
    let byteCount: Int
    let mimeType: String
}

struct GrammarLessonManifest: Codable {
    let schemaVersion: Int
    let rendererVersion: Int
    let versionID: UUID
    let topicID: String
    let course: AnyJSON
    let audioAssets: [GrammarAudioAsset]

    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    func courseObject() throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as? [String: Any] else {
            throw GrammarContentError.invalidContent
        }
        return result
    }
    func validate(topicID expected: String) throws {
        let data = try courseObject()
        guard schemaVersion == 1, rendererVersion == 1, topicID == expected,
              let parts = data["parts"] as? [[String: Any]], (1...180).contains(parts.count),
              let demos = data["contractionDemos"] as? [[String: Any]], demos.count <= 100,
              let banks = data["exercises"] as? [String: [[String: Any]]],
              ["easy", "medium", "hard"].allSatisfy({ (1...500).contains(banks[$0]?.count ?? 0) }),
              let rules = data["teachingRules"] as? [String: Any],
              let pronouns = rules["pronouns"] as? [[String: Any]],
              let contractions = rules["contractions"] as? [[String: Any]],
              contractions.count + ((rules["wordChanges"] as? [[String: Any]])?.count ?? 0) == demos.count,
              rules["roleHelp"] is [String: String], rules["examples"] is [String: [String: String]],
              let stage = data["stage"] as? String, data["stageTitle"] is String,
              let number = data["topicNumber"] as? Int, let count = data["topicCount"] as? Int,
              (1...99).contains(number), number <= count, count <= 180, topicID == "\(stage).\(number)",
              let title = data["title"] as? String, !title.isEmpty,
              data["titleVi"] is String,
              audioAssets.count == parts.count + demos.count,
              Set(audioAssets.map(\.key)).count == audioAssets.count,
              audioAssets.reduce(0, { $0 + $1.byteCount }) <= 52_428_800 else { throw GrammarContentError.invalidContent }
        let wordChanges = rules["wordChanges"] as? [[String: Any]] ?? []
        let matchingIDs = rules["matchingPartIDs"] as? [String] ?? []
        let needsPronouns = parts.contains { ["object-pair", "affirmative", "pronoun"].contains($0["kind"] as? String ?? "") || matchingIDs.contains($0["id"] as? String ?? "") }
        guard !needsPronouns || !pronouns.isEmpty else { throw GrammarContentError.invalidContent }
        for word in wordChanges {
            guard let singular = word["singular"] as? String, !singular.isEmpty,
                  let plural = word["plural"] as? String, !plural.isEmpty,
                  word["meaning"] is String, word["rule"] is String else { throw GrammarContentError.invalidContent }
        }
        for part in parts {
            if let indices = part["wordChangeIDs"] as? [Int] {
                guard !indices.isEmpty, indices.allSatisfy({ wordChanges.indices.contains($0) }) else { throw GrammarContentError.invalidContent }
            }
        }
        for bank in banks.values {
            for question in bank {
                guard question["prompt"] is String, question["explanation"] is String,
                      let type = question["type"] as? String else { throw GrammarContentError.invalidContent }
                if type == "choice" {
                    guard let options = question["options"] as? [String], let answer = question["answer"] as? Int,
                          (2...6).contains(options.count), options.indices.contains(answer) else { throw GrammarContentError.invalidContent }
                } else if type == "fill" {
                    guard question["answer"] is String else { throw GrammarContentError.invalidContent }
                } else { throw GrammarContentError.invalidContent }
            }
        }
        for part in parts {
            for example in part["examples"] as? [[String: Any]] ?? [] {
                if let tokens = example["tokens"] as? [[String: String]] {
                    guard tokens.map({ $0["text"] ?? "" }).joined() == example["en"] as? String else { throw GrammarContentError.invalidContent }
                }
            }
        }
        let partIDs = parts.compactMap { $0["id"] as? String }
        guard partIDs.count == parts.count, Set(partIDs).count == partIDs.count else { throw GrammarContentError.invalidContent }
        let assets = Dictionary(uniqueKeysWithValues: audioAssets.map { ($0.key, $0) })
        for asset in audioAssets {
            guard asset.key.range(of: "^[a-zA-Z0-9_-]+\\.mp3$", options: .regularExpression) != nil,
                  asset.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                  asset.path.lowercased() == "\(topicID)/\(versionID.uuidString.lowercased())/\(asset.key)".lowercased(),
                  asset.mimeType == "audio/mpeg", (1...10_485_760).contains(asset.byteCount) else { throw GrammarContentError.invalidContent }
        }
        var used = Set<String>()
        for track in parts + demos {
            guard let info = track["audioInfo"] as? [String: Any], let key = info["audioFile"] as? String,
                  assets[key] != nil, used.insert(key).inserted,
                  let duration = info["duration"] as? Double, duration.isFinite, duration > 0,
                  let scenes = track["scenes"] as? [[String: Any]], !scenes.isEmpty,
                  let cues = info["cues"] as? [[String: Any]], !cues.isEmpty,
                  let segments = info["segments"] as? [[String: Any]],
                  let levels = info["levels"] as? [Int], levels.allSatisfy({ (0...255).contains($0) }),
                  let envelopeHz = info["envelopeHz"] as? Double, envelopeHz > 0 else { throw GrammarContentError.invalidContent }
            let supported = Set(["example", "pair", "subject", "formula", "overview", "info", "negative", "question", "analysis", "repair", "contract-guide", "contraction", "word-change", "checklist"])
            for scene in scenes {
                guard let kind = scene["kind"] as? String, supported.contains(kind) else { throw GrammarContentError.invalidContent }
                if kind == "example" {
                    let examples = track["examples"] as? [[String: Any]] ?? []
                    let index = scene["example"] as? Int ?? 0
                    guard examples.indices.contains(index), examples[index]["en"] is String, examples[index]["vi"] is String else { throw GrammarContentError.invalidContent }
                }
                if kind == "contraction" {
                    guard let index = scene["pair"] as? Int, contractions.indices.contains(index) else { throw GrammarContentError.invalidContent }
                }
                if kind == "word-change" {
                    guard let index = scene["pair"] as? Int, wordChanges.indices.contains(index) else { throw GrammarContentError.invalidContent }
                }
            }
            var previous = -Double.infinity
            for (index, cue) in cues.enumerated() {
                guard let at = cue["at"] as? Double, at.isFinite, at >= 0, at >= previous, at <= duration,
                      let scene = cue["scene"] as? Int, scenes.indices.contains(scene), index != 0 || at == 0 else { throw GrammarContentError.invalidContent }
                previous = at
            }
            for segment in segments {
                guard let start = segment["start"] as? Double, let end = segment["end"] as? Double,
                      start.isFinite, end.isFinite, start >= 0, end >= start, end <= duration + 0.1 else { throw GrammarContentError.invalidContent }
            }
        }
    }
    func payload() throws -> [String: Any] {
        var data = try courseObject()
        data["atlas"] = "atlas.png"
        data["releaseID"] = versionID.uuidString.lowercased()
        return data
    }
    func summary() throws -> GrammarPublishedCourse {
        let data = try courseObject()
        guard let title = data["title"] as? String, let titleVi = data["titleVi"] as? String,
              let parts = data["parts"] as? [[String: Any]] else { throw GrammarContentError.invalidContent }
        return GrammarPublishedCourse(topic_id: topicID, title: title, title_vi: titleVi,
                                      part_ids: parts.compactMap { $0["id"] as? String },
                                      published_version: versionID, renderer_version: rendererVersion)
    }
}

enum GrammarContentError: LocalizedError {
    case unavailable, invalidContent, invalidAudio, closed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Chưa tải được bài học. Bạn kiểm tra kết nối rồi thử lại nhé."
        case .invalidContent: "Bộ học liệu chưa đầy đủ hoặc chưa tương thích. Bạn thử mở lại bài nhé."
        case .invalidAudio: "Tệp lời giảng chưa khớp phiên bản bài học. Bạn thử tải lại nhé."
        case .closed: "Bài học đã đóng."
        }
    }
}

/// A lesson pins one immutable manifest for its entire lifetime. Audio stays in memory only.
@MainActor
final class GrammarLessonSession {
    let manifest: GrammarLessonManifest
    private let loader: (GrammarAudioAsset) async throws -> Data
    private var cache: [String: Data] = [:]
    private var loading: [String: Task<Data, Error>] = [:]
    private var closed = false
    init(manifest: GrammarLessonManifest, loader: @escaping (GrammarAudioAsset) async throws -> Data) {
        self.manifest = manifest; self.loader = loader
    }
    func audio(_ key: String) async throws -> [String: Any] {
        guard !closed else { throw GrammarContentError.closed }
        guard let asset = manifest.audioAssets.first(where: { $0.key == key }) else { throw GrammarContentError.invalidAudio }
        if let data = cache[key] { return payload(data, key: key) }
        let task: Task<Data, Error>
        if let existing = loading[key] { task = existing }
        else {
            task = Task { [loader] in
                let data = try await loader(asset)
                try Task.checkCancellation()
                guard data.count == asset.byteCount, GrammarLessonManifest.digest(data) == asset.sha256 else { throw GrammarContentError.invalidAudio }
                return data
            }
            loading[key] = task
        }
        do {
            let data = try await task.value
            loading.removeValue(forKey: key)
            guard !closed else { throw GrammarContentError.closed }
            cache[key] = data
            return payload(data, key: key)
        } catch { loading.removeValue(forKey: key); throw error }
    }
    private func payload(_ data: Data, key: String) -> [String: Any] {
        ["key": key, "version": manifest.versionID.uuidString.lowercased(), "mimeType": "audio/mpeg", "base64": data.base64EncodedString()]
    }
    func close() {
        closed = true
        loading.values.forEach { $0.cancel() }; loading.removeAll(); cache.removeAll()
    }
}

/// Do not forward the learner's access token across a redirect to another host.
private final class GrammarContentRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url?.scheme == "https" && request.url?.host == host
        completionHandler(allowed ? request : nil)
    }
}

@MainActor
final class GrammarContentTransport {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 35
        return URLSession(configuration: config, delegate: GrammarContentRedirects(host: AppSupabaseConfiguration.url.host ?? ""), delegateQueue: nil)
    }()
    func courses(userID: String) async throws -> [GrammarPublishedCourse] {
        let data = try await request(path: "rest/v1/grammar_courses", userID: userID,
                                     query: [URLQueryItem(name: "select", value: "topic_id,title,title_vi,part_ids,published_version,renderer_version"), URLQueryItem(name: "renderer_version", value: "eq.1")])
        return try JSONDecoder().decode([GrammarPublishedCourse].self, from: data)
    }
    func lesson(topicID: String, userID: String) async throws -> GrammarLessonManifest {
        struct Response: Decodable { let version_id: UUID; let manifest_text: String; let manifest_sha256: String }
        let bytes = try await request(path: "rest/v1/rpc/get_grammar_lesson", userID: userID, body: ["p_topic_id": topicID])
        let response = try JSONDecoder().decode(Response.self, from: bytes)
        let original = Data(response.manifest_text.utf8)
        guard original.count <= 2_097_152, GrammarLessonManifest.digest(original) == response.manifest_sha256 else { throw GrammarContentError.invalidContent }
        let manifest = try JSONDecoder().decode(GrammarLessonManifest.self, from: original)
        guard manifest.versionID == response.version_id else { throw GrammarContentError.invalidContent }
        try manifest.validate(topicID: topicID)
        return manifest
    }
    func audio(_ asset: GrammarAudioAsset, userID: String) async throws -> Data {
        try await request(path: "storage/v1/object/authenticated/grammar-audio/" + asset.path, userID: userID, maximumSize: 10_485_760)
    }
    private func request(path: String, userID: String, body: [String: String]? = nil, query: [URLQueryItem] = [], maximumSize: Int = 2_097_152) async throws -> Data {
        let auth = try await supabase.auth.session
        guard auth.user.id.uuidString.lowercased() == userID.lowercased() else { throw GrammarContentError.unavailable }
        var components = URLComponents(url: AppSupabaseConfiguration.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw GrammarContentError.unavailable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer " + auth.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(AppSupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body { request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= maximumSize else { throw GrammarContentError.unavailable }
        return data
    }
    deinit { session.invalidateAndCancel() }
}
