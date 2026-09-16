import Foundation
import Supabase

enum AuthService {
    static func currentUser() async throws -> User {
        try await supabase.auth.session.user
    }

    static func listenToAuthChanges(_ handler: @MainActor @escaping (User?) async -> Void) -> Task<Void, Never> {
        Task {
            for await (_, session) in supabase.auth.authStateChanges {
                await handler(session?.user)
            }
        }
    }

    static func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    static func signUp(email: String, password: String, displayName: String) async throws {
        let metadata: [String: AnyJSON] = [
            "full_name": .string(displayName),
            "display_name": .string(displayName),
            "name": .string(displayName)
        ]

        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: metadata
        )
    }

    static func signOut() async throws {
        try await supabase.auth.signOut()
    }

    static func updateUserMetadata(_ metadata: [String: AnyJSON]) async throws {
        _ = try await supabase.auth.update(user: UserAttributes(data: metadata))
    }

    static func uploadAvatar(userId: UUID, data: Data, date: Date = Date()) async throws -> String {
        let fileName = "\(userId.uuidString)_\(date.timeIntervalSince1970).jpg"
        let filePath = "avatars/\(fileName)"

        try await supabase.storage
            .from("avatars")
            .upload(
                filePath,
                data: data,
                options: FileOptions(cacheControl: "3600", upsert: true)
            )

        return try supabase.storage
            .from("avatars")
            .getPublicURL(path: filePath)
            .absoluteString
    }
}
