import Foundation
import Supabase
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var isCheckingAuth = true
    @Published var currentUser: User?
    @Published var currentUserRole: String = "user"
    
    private var authStateTask: Task<Void, Never>?
    
    init() {
        Task {
            await checkSession()
            listenToAuthChanges()
        }
    }
    
    func checkSession() async {
        do {
            let user = try await AuthService.currentUser()
            self.currentUser = user
            self.isAuthenticated = true
            await fetchUserRole(userId: user.id.uuidString)
        } catch {
            self.isAuthenticated = false
            self.currentUser = nil
            self.currentUserRole = "user"
        }
        self.isCheckingAuth = false
    }
    
    func fetchUserRole(userId: String) async {
        do {
            if let role = try await ProfileRepository.fetchRole(userId: userId) {
                self.currentUserRole = role
            }
        } catch {
            print("Lỗi lấy role: \(error)")
        }
    }
    
    func listenToAuthChanges() {
        authStateTask?.cancel()
        authStateTask = AuthService.listenToAuthChanges { [weak self] user in
            guard let self else { return }
            self.currentUser = user
            self.isAuthenticated = (user != nil)

            if let userId = user?.id.uuidString {
                await self.fetchUserRole(userId: userId)
            } else {
                self.currentUserRole = "user"
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await AuthService.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        try await AuthService.signUp(email: email, password: password, displayName: displayName)
    }
    
    func signOut() async throws {
        try await AuthService.signOut()
        self.isAuthenticated = false
        self.currentUser = nil
        self.currentUserRole = "user"
    }
    
    // Lấy tên hiển thị từ metadata (hoặc trả về mặc định nếu không có)
    var avatarURL: String? {
        guard let metadata = currentUser?.userMetadata else { return nil }
        if case let .string(url) = metadata["avatar_url"] {
            return url
        }
        return nil
    }
    
    func updateDisplayName(_ name: String) async throws {
        guard let userId = currentUser?.id else { return }
        
        try await AuthService.updateUserMetadata(["display_name": .string(name)])
        
        try await ProfileRepository.updateDisplayName(userId: userId.uuidString, name: name)
        
        await checkSession()
    }
    
    func updateAvatar(data: Data) async throws {
        guard let userId = currentUser?.id else { return }

        let urlString = try await AuthService.uploadAvatar(userId: userId, data: data)
        try await AuthService.updateUserMetadata(["avatar_url": .string(urlString)])
        try await ProfileRepository.updateAvatarURL(userId: userId.uuidString, urlString: urlString)
        
        await checkSession()
    }
    
    var displayName: String {
        guard let metadata = currentUser?.userMetadata else { return "Người dùng" }
        
        // Thử lấy từ metadata (cách an toàn với AnyJSON)
        if case let .string(name) = metadata["display_name"] {
            return name
        }
        if case let .string(name) = metadata["full_name"] {
            return name
        }
        
        // Fallback dùng JSONSerialization
        do {
            let data = try JSONEncoder().encode(metadata)
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let name = dict["display_name"] as? String { return name }
                if let name = dict["full_name"] as? String { return name }
            }
        } catch {
            print("Lỗi parse metadata: \(error)")
        }
        
        return "Người dùng"
    }
    
    var isAdmin: Bool {
        let adminUUID = AppConfig.adminUserId.lowercased()
        let adminEmail = AppConfig.adminEmail.lowercased()
        
        // 1. Kiểm tra bằng ID cho chắc chắn nhất
        if let id = currentUser?.id.uuidString.lowercased(), id == adminUUID {
            return true
        }
        
        // 2. Hoặc kiểm tra bằng email
        if let email = currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), email == adminEmail {
            return true
        }
        
        // 3. Kiểm tra bằng currentUserRole (từ bảng profiles)
        if currentUserRole == "admin" {
            return true
        }
        
        // 4. Hoặc kiểm tra qua userMetadata
        if let metadata = currentUser?.userMetadata {
            if case let .string(role) = metadata["role"], role == "admin" {
                return true
            }
        }
        
        return false
    }
}
