import SwiftUI
import Charts

struct LearningView: View {
    let openVocabularyRequest: UUID?

    @State private var showVocabularyLearning = false
    @State private var lastHandledVocabularyRequest: UUID?

    init(openVocabularyRequest: UUID? = nil) {
        self.openVocabularyRequest = openVocabularyRequest
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NavigationLink {
                        VocabularyLearningView()
                    } label: {
                        LearningCategoryCard(
                            title: "Học từ vựng",
                            subtitle: "Ôn tập ngắt quãng, ghi nhớ nghĩa và luyện phát âm câu ví dụ.",
                            icon: "books.vertical.fill",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ListeningPracticeDashboardView()
                    } label: {
                        LearningCategoryCard(
                            title: "Luyện nghe chép chính tả",
                            subtitle: "Chọn bài đã đưa vào luyện nghe và chép lại từng câu bạn nghe được.",
                            icon: "headphones",
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ShadowingPracticeDashboardView()
                    } label: {
                        LearningCategoryCard(
                            title: "Luyện Shadowing",
                            subtitle: "Nghe câu mẫu, nhại lại và nhận phản hồi phát âm chi tiết từ Azure.",
                            icon: "waveform.and.mic",
                            tint: .purple
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Học tiếng Anh")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showVocabularyLearning) {
                VocabularyLearningView()
            }
        }
        .onAppear {
            openVocabularyIfNeeded()
        }
        .onChange(of: openVocabularyRequest) { _, _ in
            openVocabularyIfNeeded()
        }
    }

    private func openVocabularyIfNeeded() {
        guard let openVocabularyRequest,
              openVocabularyRequest != lastHandledVocabularyRequest else {
            return
        }

        lastHandledVocabularyRequest = openVocabularyRequest
        showVocabularyLearning = true
    }
}

private struct LearningCategoryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(tint.opacity(0.14))
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundColor(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 5)
        )
    }
}

struct VocabularyLearningView: View {
    @State private var isLoading = true
    
    @State private var learningVocabGroups: [[Vocabulary]] = []
    @State private var tasks: [LearningTask] = []
    
    @State private var totalLearningWords = 0
    @State private var totalSavedWords = 0
    @State private var dueVocabsCount = 0
    @State private var wordsWithoutExampleExercises: [String] = []
    
    @State private var showLearningSession = false
    @State private var statsByLevel: [Int: Int] = [1:0, 2:0, 3:0, 4:0, 5:0, 6:0]
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Đang tải dữ liệu...")
                } else {
                    dashboardView()
                }
            }
            .navigationTitle("Học từ vựng")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                Task { await prepareSession() }
            }
            .fullScreenCover(isPresented: $showLearningSession, onDismiss: {
                Task { await prepareSession() }
            }) {
                LearningSessionView(
                    tasks: tasks,
                    learningVocabGroups: learningVocabGroups,
                    onClose: {
                        showLearningSession = false
                    }
                )
            }
            .alert("Thông báo", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    @ViewBuilder
    func dashboardView() -> some View {
        ScrollView {
            VStack(spacing: 25) {
                // Progress Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tiến độ học tập")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(totalLearningWords)")
                                    .font(.system(size: 34, weight: .bold))
                                Text("/ \(totalSavedWords)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("từ")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        
                        Chart {
                            ForEach(1...6, id: \.self) { level in
                                SectorMark(
                                    angle: .value("Số từ", statsByLevel[level] ?? 0),
                                    innerRadius: .ratio(0.6),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(colorForLevel(level))
                                .cornerRadius(4)
                            }
                        }
                        .frame(width: 80, height: 80)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Phân bổ cấp độ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Chart {
                            ForEach(1...6, id: \.self) { level in
                                BarMark(
                                    x: .value("Cấp độ", LearningLevelDisplay.title(for: level)),
                                    y: .value("Số từ", statsByLevel[level] ?? 0)
                                )
                                .foregroundStyle(colorForLevel(level))
                                .cornerRadius(6)
                                .annotation(position: .top) {
                                    let count = statsByLevel[level] ?? 0
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(height: 150)
                        .chartLegend(.hidden)
                        .chartYAxis(.hidden)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
                )
                .padding(.horizontal)
                
                // Review Section
                VStack(spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Cần ôn tập hôm nay")
                                .font(.headline)
                            
                            Text(dueVocabsCount > 0 ? "Bạn có \(dueVocabsCount) từ vựng đến hạn ôn tập." : "Tuyệt vời! Bạn đã hoàn thành hết các từ cần ôn.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 30))
                            .foregroundColor(dueVocabsCount > 0 ? .orange : .green)
                    }
                    
                    if dueVocabsCount > 0 && !tasks.isEmpty {
                        Button(action: {
                            showLearningSession = true
                        }) {
                            HStack {
                                Text("Ôn tập ngay")
                                    .bold()
                                Image(systemName: "arrow.right")
                            }
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(18)
                            .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        if !wordsWithoutExampleExercises.isEmpty {
                            Label(
                                "\(wordsWithoutExampleExercises.count) từ trong set sẽ bỏ qua phần ghép câu và phát âm vì chưa có ví dụ.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if dueVocabsCount > 0 {
                        Label(
                            "Không thể tạo bài ôn tập từ dữ liệu hiện có.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(18)
                    } else {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Hoàn thành mục tiêu!")
                                .bold()
                        }
                        .foregroundColor(.green)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(18)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 5)
                )
                .padding(.horizontal)

            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
    
    func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 1: return .red.opacity(0.7)
        case 2: return .orange.opacity(0.7)
        case 3: return .yellow.opacity(0.7)
        case 4: return .green.opacity(0.7)
        case 5: return .blue.opacity(0.7)
        case 6: return .purple.opacity(0.7)
        default: return .gray
        }
    }
    
    @MainActor
    private func prepareSession() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
                learningVocabGroups = []
                tasks = []
                totalLearningWords = 0
                totalSavedWords = 0
                dueVocabsCount = 0
                wordsWithoutExampleExercises = []
                statsByLevel = [1:0, 2:0, 3:0, 4:0, 5:0, 6:0]
                return
            }

            let allResponse = try await VocabularyRepository.fetchUserVocabs(userId: userId)
            let plan = LearningSessionBuilder.build(from: allResponse)

            statsByLevel = plan.statsByLevel
            totalLearningWords = plan.totalLearningWords
            totalSavedWords = plan.totalSavedWords
            dueVocabsCount = plan.dueVocabsCount
            wordsWithoutExampleExercises = plan.wordsWithoutExampleExercises
            learningVocabGroups = plan.selectedGroups
            tasks = plan.tasks
        } catch {
            errorMessage = "Không tải được dữ liệu học từ vựng: \(error.localizedDescription)"
        }
    }
}
