import SwiftUI

struct MyVocabularyView: View {
    @StateObject private var workspace = VocabularyWorkspaceStore()
    var body: some View {
        VocabularyWorkspaceBrowser(store: workspace, topic: nil)
            .task { await workspace.load() }
    }
}

struct PrivateTopicCreateView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var onComplete: () -> Void

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }

                Form {
                    Section("Bộ từ riêng") {
                        TextField("Tên bộ từ", text: $name)
                            .foregroundStyle(isExtra ? .white : .primary)
                        TextField("Mô tả ngắn", text: $description)
                            .foregroundStyle(isExtra ? .white : .primary)
                    }
                    .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))

                    Section {
                        Text("Bộ từ riêng chỉ có bạn thấy. Bạn có thể thêm từ và học ngay, khi thấy đủ hay thì gửi quản trị viên duyệt để chia sẻ lên hệ thống.")
                            .font(.caption)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(isExtra ? .hidden : .automatic)
            }
            .navigationTitle("Tạo bộ từ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                        .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tạo") {
                        Task { await createTopic() }
                    }
                    .foregroundColor(isExtra ? ExtraAuroraPalette.ice : .blue)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Đang tạo...")
                        .padding()
                        .background(Color(.systemBackground).opacity(0.85))
                        .cornerRadius(10)
                }
            }
            .alert("Thông báo", isPresented: $showingAlert) {
                Button("OK") {
                    if alertMessage.contains("Đã tạo") {
                        onComplete()
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }.vocabularySheetStyle(isExtra: isExtra)
    }

    private func createTopic() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await VocabularyRepository.createPrivateTopic(name: name, description: description)
            alertMessage = "Đã tạo bộ từ riêng."
            showingAlert = true
        } catch {
            alertMessage = "Tạo bộ từ thất bại: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}
