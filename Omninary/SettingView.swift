import SwiftUI

struct SettingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @State private var isEditingName = false
    @State private var newDisplayName = ""
    @State private var isSavingName = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newDisplayName = auth.displayName
                        isEditingName = true
                    } label: {
                        HStack {
                            Text("Đổi tên hiển thị")
                            Spacer()
                            Text(auth.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Chế độ phát triển") {
                    Picker("Giao diện", selection: $interfaceModeRaw) {
                        ForEach(AppInterfaceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await signOut() }
                    } label: {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Setting")
            .navigationBarTitleDisplayMode(.large)
            .alert("Đổi tên hiển thị", isPresented: $isEditingName) {
                TextField("Tên hiển thị mới", text: $newDisplayName)
                Button("Hủy", role: .cancel) { }
                Button(isSavingName ? "Đang lưu..." : "Lưu") {
                    Task { await updateDisplayName() }
                }
                .disabled(isSavingName || newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Nhập tên bạn muốn hiển thị trong ứng dụng.")
            }
        }
    }

    private func updateDisplayName() async {
        let name = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isSavingName = true
        defer { isSavingName = false }

        do {
            try await auth.updateDisplayName(name)
        } catch {
            errorMessage = "Không thể đổi tên: \(error.localizedDescription)"
        }
    }

    private func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            errorMessage = "Không thể đăng xuất: \(error.localizedDescription)"
        }
    }
}
