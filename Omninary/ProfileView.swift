import SwiftUI
import PhotosUI

struct ProfileView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var isEditingName = false
    @State private var newDisplayName = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Avatar Section
                ZStack(alignment: .bottomTrailing) {
                    if let urlString = auth.avatarURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 4))
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.gray)
                    }
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Image(systemName: "camera.fill")
                            .padding(8)
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .offset(x: 5, y: 5)
                }
                .padding(.top, 40)
                .onChange(of: selectedItem) { _, newItem in
                    if let newItem = newItem {
                        Task {
                            await uploadAvatar(newItem)
                        }
                    }
                }
                
                VStack(spacing: 8) {
                    Text(auth.displayName)
                        .font(.title)
                        .bold()
                    
                    Text(auth.currentUser?.email ?? "Không có email")
                        .foregroundColor(.secondary)
                }
                
                if isLoading {
                    ProgressView("Đang cập nhật...")
                        .padding()
                }
                
                List {
                    Section {
                        Button(action: {
                            newDisplayName = auth.displayName
                            isEditingName = true
                        }) {
                            HStack {
                                Image(systemName: "person.fill")
                                Text("Đổi tên hiển thị")
                                Spacer()
                                Text(auth.displayName)
                                    .foregroundColor(.gray)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            Task {
                                do {
                                    try await auth.signOut()
                                } catch {
                                    print("Lỗi đăng xuất: \(error)")
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Đăng xuất")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hồ sơ cá nhân")
            .alert("Đổi tên hiển thị", isPresented: $isEditingName) {
                TextField("Tên mới", text: $newDisplayName)
                Button("Hủy", role: .cancel) { }
                Button("Lưu") {
                    Task {
                        await updateName()
                    }
                }
            } message: {
                Text("Nhập tên bạn muốn hiển thị trong ứng dụng.")
            }
        }
    }
    
    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                try await auth.updateAvatar(data: data)
            }
        } catch {
            print("Lỗi tải ảnh: \(error)")
        }
    }
    
    private func updateName() async {
        guard !newDisplayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await auth.updateDisplayName(newDisplayName)
        } catch {
            print("Lỗi cập nhật tên: \(error)")
        }
    }
}
