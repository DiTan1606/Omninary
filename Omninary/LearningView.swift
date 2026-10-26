import SwiftUI
import Charts

struct LearningView: View {
    let openVocabularyRequest: UUID?

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @AppStorage("learning_dashboard_widget_ids") private var dashboardWidgetIDsRaw = ""
    @AppStorage("learning_dashboard_widget_sizes") private var dashboardWidgetSizesRaw = ""
    @AppStorage("learning_dashboard_layout_v2") private var dashboardLayoutRaw = ""
    @State private var placements: [LearningWidgetPlacement] = []
    @State private var isEditingDashboard = false
    @State private var showVocabularyLearning = false
    @State private var selectedDashboardWidget: LearningDashboardWidget?
    @State private var lastHandledVocabularyRequest: UUID?
    @State private var showingWidgetPicker = false
    @Environment(\.omniV2) private var v2
    @State private var showIsland = false

    init(openVocabularyRequest: UUID? = nil) {
        self.openVocabularyRequest = openVocabularyRequest
    }

    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    var body: some View {
        if v2 { v2Body } else { legacyBody }
    }

    /// New Learning page: three fixed cards with pixel scenes; no widget grid.
    private var v2Body: some View {
        NavigationStack {
            // Học từ vựng opens Đảo nhà; the list review page lives in Nhà nghiên cứu.
            LearningV2Page { widget in if widget == .vocabulary { showIsland = true } else { selectedDashboardWidget = widget } }
                .omniTabRoot(.learning)
                .toolbar(.hidden, for: .navigationBar)
                .fullScreenCover(isPresented: $showIsland) { IslandScreen() }
                .navigationDestination(item: $selectedDashboardWidget) { widget in
                    dashboardDestination(for: widget)
                }
        }
        .onAppear { openIslandIfNeeded() }
        .onChange(of: openVocabularyRequest) { _, _ in
            openIslandIfNeeded()
        }
    }

    private func openIslandIfNeeded() {
        guard let openVocabularyRequest, openVocabularyRequest != lastHandledVocabularyRequest else { return }
        lastHandledVocabularyRequest = openVocabularyRequest
        showIsland = true
    }

    private var legacyBody: some View {
        NavigationStack {
            dashboardContent
            .navigationTitle("Learning")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditingDashboard {
                        Button("Xong", action: finishEditingDashboard)
                            .font(.headline)
                    } else {
                        addWidgetButton
                    }
                }
            }
            .navigationDestination(isPresented: $showVocabularyLearning) {
                VocabularyLearningView()
            }
            .navigationDestination(item: $selectedDashboardWidget) { widget in
                dashboardDestination(for: widget)
            }
            .sheet(isPresented: $showingWidgetPicker) {
                widgetPicker
            }
        }
        .onAppear {
            if !isEditingDashboard { loadDashboard() }
            openVocabularyIfNeeded()
        }
        .onChange(of: openVocabularyRequest) { _, _ in
            openVocabularyIfNeeded()
        }
    }

    private var dashboardContent: some View {
        ZStack {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }

            LearningDashboardGrid(
                placements: placements,
                isExtra: isExtra,
                isEditing: isEditingDashboard,
                onOpen: { selectedDashboardWidget = $0 },
                onBeginEditing: beginEditingDashboard,
                onMove: moveWidget,
                onResize: setWidgetSize,
                onRemove: removeWidget
            )
        }
    }

    private var widgetPicker: some View {
        LearningWidgetPicker(
            widgetCounts: Dictionary(grouping: placements, by: \.widgetID).mapValues(\.count),
            isExtra: isExtra,
            onSelect: addWidget
        )
        .presentationDetents([.fraction(0.5)])
        .presentationDragIndicator(.visible)
    }

    private func openVocabularyIfNeeded() {
        guard let openVocabularyRequest,
              openVocabularyRequest != lastHandledVocabularyRequest else {
            return
        }

        lastHandledVocabularyRequest = openVocabularyRequest
        showVocabularyLearning = true
    }

    @ViewBuilder
    private func dashboardDestination(for widget: LearningDashboardWidget) -> some View {
        switch widget {
        case .vocabulary:
            VocabularyLearningView()
        case .listening:
            ListeningPracticeDashboardView()
        case .shadowing:
            ShadowingPracticeDashboardView()
        }
    }

    private func addWidget(_ widget: LearningDashboardWidget, size: LearningWidgetSize) {
        guard !placements.contains(where: { $0.widgetID == widget.rawValue }) else { return }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            placements = LearningGridLayout.add(widget.rawValue, size: size, to: placements)
        }
        saveDashboard()
        showingWidgetPicker = false
    }

    private func beginEditingDashboard() {
        guard !isEditingDashboard else { return }
        isEditingDashboard = true
    }

    private func finishEditingDashboard() {
        saveDashboard()
        isEditingDashboard = false
    }

    private func setWidgetSize(_ size: LearningWidgetSize, for id: UUID) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            placements = LearningGridLayout.place(id, size: size, in: placements)
        }
    }

    private func removeWidget(_ id: UUID) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            placements.removeAll { $0.id == id }
        }
    }

    private func moveWidget(_ id: UUID, column: Int, row: Int) {
        let moved = LearningGridLayout.place(id, column: column, row: row, in: placements)
        guard moved != placements else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            placements = moved
        }
    }

    private func loadDashboard() {
        if let data = dashboardLayoutRaw.data(using: .utf8),
           let saved = try? JSONDecoder().decode([LearningWidgetPlacement].self, from: data) {
            placements = LearningGridLayout.normalize(saved.filter { LearningDashboardWidget(rawValue: $0.widgetID) != nil })
            saveDashboard()
            return
        }

        var migrated: [LearningWidgetPlacement] = []
        let oldSizes = dashboardWidgetSizesRaw.split(separator: ",").compactMap { entry -> (String, LearningWidgetSize)? in
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let size: LearningWidgetSize
            switch parts[1] {
            case "wide": size = .fourByTwo
            case "large": size = .fourByFour
            default: size = .twoByTwo
            }
            return (parts[0], size)
        }.reduce(into: [String: LearningWidgetSize]()) { result, entry in
            result[entry.0] = entry.1
        }
        for id in dashboardWidgetIDsRaw.split(separator: ",").map(String.init) where LearningDashboardWidget(rawValue: id) != nil {
            migrated = LearningGridLayout.add(id, size: oldSizes[id] ?? .twoByTwo, to: migrated)
        }
        placements = migrated
        saveDashboard()
    }

    private func saveDashboard() {
        guard let data = try? JSONEncoder().encode(placements),
              let raw = String(data: data, encoding: .utf8) else { return }
        dashboardLayoutRaw = raw
    }

    @ViewBuilder
    private var addWidgetButton: some View {
        Button { showingWidgetPicker = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isExtra ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thêm thẻ học")
        .modifier(LearningAddButtonGlassEffect())
    }
}

enum LearningDashboardWidget: String, CaseIterable, Identifiable {
    case vocabulary
    case listening
    case shadowing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: "Học từ vựng"
        case .listening: "Luyện nghe chép chính tả"
        case .shadowing: "Luyện Shadowing"
        }
    }

    var subtitle: String {
        switch self {
        case .vocabulary: "Ghi nhớ và ôn tập từ"
        case .listening: "Nghe và chép lại"
        case .shadowing: "Nghe, nhại lại và luyện nói"
        }
    }

    var icon: String {
        switch self {
        case .vocabulary: "books.vertical.fill"
        case .listening: "headphones"
        case .shadowing: "waveform.and.mic"
        }
    }

    var tint: Color {
        switch self {
        case .vocabulary: .blue
        case .listening: .yellow
        case .shadowing: .purple
        }
    }

    func iconTint(isExtra: Bool) -> Color {
        switch self {
        case .vocabulary:
            return isExtra ? ExtraAuroraPalette.ice : .blue
        case .listening:
            return .yellow
        case .shadowing:
            return .purple
        }
    }
}

private struct LearningDashboardGrid: View {
    let placements: [LearningWidgetPlacement]
    let isExtra: Bool
    let isEditing: Bool
    let onOpen: (LearningDashboardWidget) -> Void
    let onBeginEditing: () -> Void
    let onMove: (UUID, Int, Int) -> Void
    let onResize: (LearningWidgetSize, UUID) -> Void
    let onRemove: (UUID) -> Void
    @State private var dragSession: LearningDashboardDragSession?

    private let spacing = AppSpacing.learningGridGap

    var body: some View {
        GeometryReader { geometry in
            let gridWidth = max(0, geometry.size.width - 2 * AppSpacing.page)
            let cell = max(0, (gridWidth - 3 * spacing) / 4)
            let stride = cell + spacing
            let lastRow = placements.map { $0.row + $0.size.rows }.max() ?? 0
            let gridHeight = CGFloat(lastRow) * stride - (lastRow > 0 ? spacing : 0)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    if isEditing {
                        editGrid(cell: cell, stride: stride, rows: max(lastRow + 2, 6))
                    }
                    ForEach(placements) { placement in
                        if let widget = LearningDashboardWidget(rawValue: placement.widgetID) {
                            dashboardTile(widget: widget, placement: placement, cell: cell, stride: stride)
                                .offset(tileOffset(for: placement, stride: stride))
                                .transaction { transaction in
                                    if dragSession?.id == placement.id { transaction.animation = nil }
                                }
                                .zIndex(dragSession?.id == placement.id ? 10 : 1)
                                .shadow(color: .black.opacity(dragSession?.id == placement.id ? 0.22 : 0), radius: 16, y: 8)
                        }
                    }
                }
                .frame(width: gridWidth, height: max(gridHeight, isEditing ? CGFloat(max(lastRow + 2, 6)) * stride : 0), alignment: .topLeading)
                .coordinateSpace(name: "learningDashboardGrid")
                .padding(.horizontal, AppSpacing.page)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { dragSession = nil }
        }
    }

    private func dashboardTile(widget: LearningDashboardWidget, placement: LearningWidgetPlacement, cell: CGFloat, stride: CGFloat) -> some View {
        let width = CGFloat(placement.size.columns) * cell + CGFloat(placement.size.columns - 1) * spacing
        let height = CGFloat(placement.size.rows) * cell + CGFloat(placement.size.rows - 1) * spacing
        return LearningDashboardTile(
            widget: widget,
            placement: placement,
            isExtra: isExtra,
            isEditing: isEditing,
            onOpen: { onOpen(widget) },
            onBeginEditing: onBeginEditing,
            onDragChanged: { translation in
                updateDrag(for: placement, translation: translation, stride: stride)
            },
            onDragEnded: finishDrag,
            onResize: { onResize($0, placement.id) },
            onRemove: { onRemove(placement.id) }
        )
        .frame(width: width, height: height)
    }

    private func tileOffset(for placement: LearningWidgetPlacement, stride: CGFloat) -> CGSize {
        if let dragSession, dragSession.id == placement.id {
            return CGSize(
                width: CGFloat(dragSession.startColumn) * stride + dragSession.translation.width,
                height: CGFloat(dragSession.startRow) * stride + dragSession.translation.height
            )
        }
        return CGSize(width: CGFloat(placement.column) * stride, height: CGFloat(placement.row) * stride)
    }

    private func updateDrag(for placement: LearningWidgetPlacement, translation: CGSize, stride: CGFloat) {
        if dragSession == nil {
            dragSession = LearningDashboardDragSession(
                id: placement.id,
                startColumn: placement.column,
                startRow: placement.row,
                targetColumn: placement.column,
                targetRow: placement.row,
                translation: .zero
            )
        }
        guard var session = dragSession, session.id == placement.id else { return }
        session.translation = translation
        let column = min(max(session.startColumn + Int((translation.width / stride).rounded()), 0), 4 - placement.size.columns)
        let row = max(session.startRow + Int((translation.height / stride).rounded()), 0)
        let changedCell = column != session.targetColumn || row != session.targetRow
        session.targetColumn = column
        session.targetRow = row
        dragSession = session
        if changedCell { onMove(placement.id, column, row) }
    }

    private func finishDrag() {
        guard dragSession != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            dragSession = nil
        }
    }

    private func editGrid(cell: CGFloat, stride: CGFloat, rows: Int) -> some View {
        ForEach(0..<(rows * 4), id: \.self) { index in
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(isExtra ? Color.white.opacity(0.12) : Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: cell, height: cell)
                .offset(x: CGFloat(index % 4) * stride, y: CGFloat(index / 4) * stride)
        }
    }
}

private struct LearningDashboardDragSession {
    let id: UUID
    let startColumn: Int
    let startRow: Int
    var targetColumn: Int
    var targetRow: Int
    var translation: CGSize
}

private struct LearningDashboardTile: View {
    let widget: LearningDashboardWidget
    let placement: LearningWidgetPlacement
    let isExtra: Bool
    let isEditing: Bool
    let onOpen: () -> Void
    let onBeginEditing: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onResize: (LearningWidgetSize) -> Void
    let onRemove: () -> Void

    var body: some View {
        LearningWidgetCard(widget: widget, size: placement.size, isExtra: isExtra)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(widget.title)
            .accessibilityIdentifier("learning-card-\(widget.rawValue)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !isEditing { onOpen() }
            }
            .overlay {
                LearningCardTouchSurface(
                    isEditing: isEditing,
                    onOpen: onOpen,
                    onBeginEditing: onBeginEditing,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
            .overlay(alignment: .topTrailing) {
                if isEditing { editButtons }
            }
    }

    private var editButtons: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(LearningWidgetSize.allCases) { option in
                    Button {
                        onResize(option)
                    } label: {
                        Label(option.title, systemImage: option == placement.size ? "checkmark" : option.icon)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 27, height: 27)
            }
            .accessibilityLabel("Đổi kích thước thẻ")
            .accessibilityIdentifier("learning-card-resize-\(widget.rawValue)")
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 27, height: 27)
            }
            .accessibilityLabel("Xóa thẻ")
            .accessibilityIdentifier("learning-card-remove-\(widget.rawValue)")
        }
        .foregroundStyle(isExtra ? Color.white : Color.primary)
        .background(.regularMaterial, in: Capsule())
        .padding(5)
        .accessibilityElement(children: .contain)
    }

}

private struct LearningWidgetCard: View {
    let widget: LearningDashboardWidget
    let size: LearningWidgetSize
    let isExtra: Bool
    var body: some View {
        let iconColor = widget.iconTint(isExtra: isExtra)
        return VStack(alignment: .leading, spacing: size == .oneByOne ? 3 : 10) {
            Image(systemName: widget.icon)
                .font(.system(size: size == .oneByOne ? 22 : 26, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: size == .oneByOne ? 32 : 48, height: size == .oneByOne ? 32 : 48)
                .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            Spacer(minLength: 0)

            Text(widget.title)
                .font(size == .oneByOne ? .system(size: 10, weight: .bold) : AppTypography.cardTitle)
                .foregroundStyle(isExtra ? .white : .primary)
                .lineLimit(size == .oneByOne ? 2 : 3)

            if size == .fourByTwo || size == .fourByFour {
                Text(widget.subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(size == .oneByOne ? AppSpacing.inline : AppSpacing.card)
        .appSurface(size == .oneByOne ? .row : .card, isExtra: isExtra)
    }

}

private struct LearningWidgetPicker: View {
    let widgetCounts: [String: Int]
    let isExtra: Bool
    let onSelect: (LearningDashboardWidget, LearningWidgetSize) -> Void
    @State private var pendingWidget: LearningDashboardWidget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if pendingWidget != nil {
                        Button { withAnimation { pendingWidget = nil } } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Quay lại danh sách chương trình")
                    }
                    Text(pendingWidget == nil ? "Thêm thẻ học" : "Chọn kích thước")
                        .font(.title3.weight(.bold))
                }

                if let widget = pendingWidget {
                    Text(widget.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.cardGap), GridItem(.flexible(), spacing: AppSpacing.cardGap)], spacing: AppSpacing.cardGap) {
                        ForEach(LearningWidgetSize.allCases) { size in
                            Button {
                                onSelect(widget, size)
                            } label: {
                                Label(size.title, systemImage: size.icon)
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .background(widget.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Chọn chương trình, sau đó chọn kích thước thẻ.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(spacing: AppSpacing.cardGap) {
                        ForEach(LearningDashboardWidget.allCases) { widget in
                            LearningWidgetPickerOption(
                                widget: widget,
                                count: widgetCounts[widget.rawValue] ?? 0,
                                isExtra: isExtra,
                                action: { withAnimation { pendingWidget = widget } }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct LearningWidgetPickerOption: View {
    let widget: LearningDashboardWidget
    let count: Int
    let isExtra: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: widget.icon)
                    .font(.title3.weight(.bold))
                    .foregroundColor(widget.iconTint(isExtra: isExtra))
                Text(widget.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text("Đã thêm")
                        .font(.caption)
                        .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                } else {
                    Image(systemName: "chevron.right").font(.caption)
                }
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .appSurface(.row, isExtra: isExtra)
        }
        .buttonStyle(.plain)
        .disabled(count > 0)
    }

    private var foregroundColor: Color {
        isExtra ? .white : widget.tint
    }

}

private struct LearningAddButtonGlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content
            } else {
                content
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.8) }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 5)
            }
        }
    }
}

struct VocabularyLearningView: View {
    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    @ObservedObject private var heartManager = OmniLearningHeartManager.shared
    @State private var isLoading = true
    
    private var isExtra: Bool {
        (AppInterfaceMode(rawValue: interfaceModeRaw) ?? .ditandnary).usesDarkTheme
    }

    
    @State private var totalLearningWords = 0
    @State private var totalSavedWords = 0
    @State private var dueVocabsCount = 0
    @State private var wordsWithoutExampleExercises: [String] = []
    
    @State private var activeSession: ActiveLearningSession?
    @State private var statsByLevel: [Int: Int] = Dictionary(uniqueKeysWithValues: (0...7).map { ($0, 0) })
    @State private var errorMessage: String?
    @State private var reviewCandidates: [ReviewCandidate] = []
    @State private var allVocabs: [Vocabulary] = []
    @State private var skillProfiles: [String: WordSkillProfile] = [:]

    /// Algorithm mode follows the server entitlement, not the preview theme.
    private var usesExtraAlgorithm: Bool { heartManager.isExtra }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isExtra {
                    AuroraBackdrop()
                } else {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                }

                VStack {
                    if isLoading {
                        ProgressView("Đang tải dữ liệu...")
                            .foregroundStyle(isExtra ? .white : .primary)
                    } else {
                        dashboardView()
                    }
                }
            }
            .navigationTitle("Học từ vựng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                Task { await prepareSession() }
            }
            // item-based presentation hands the exact session that was just
            // built to the cover; isPresented would capture stale state.
            .fullScreenCover(item: $activeSession, onDismiss: {
                Task { await prepareSession() }
            }) { session in
                LearningSessionView(
                    sessionID: session.id,
                    tasks: session.tasks,
                    learningVocabGroups: session.groups,
                    reasons: session.reasons,
                    onClose: {
                        activeSession = nil
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
    
    private func dashboardView() -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: AppSpacing.cardGap) {
                    progressCard
                    reviewCard
                        .frame(height: reviewCandidates.isEmpty ? nil : max(280, geometry.size.height - 32))
                }
                .padding(.vertical)
            }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tiến độ học tập")
                        .font(.headline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(totalLearningWords)")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(isExtra ? .white : .primary)
                        Text("/ \(totalSavedWords)")
                            .font(.headline)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                        Text("từ")
                            .font(.subheadline)
                            .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                    }
                }
                Spacer()

                Chart {
                    ForEach(0...7, id: \.self) { level in
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
                .background(isExtra ? Color.white.opacity(0.12) : Color.black.opacity(0.08))

            VStack(alignment: .leading, spacing: 15) {
                Text("Phân bổ cấp độ")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isExtra ? .white : .primary)

                Chart {
                    ForEach(0...7, id: \.self) { level in
                        BarMark(
                            x: .value("Cấp độ", LearningLevelDisplay.title(for: level == 7 ? 10 : level)),
                            y: .value("Số từ", statsByLevel[level] ?? 0)
                        )
                        .foregroundStyle(colorForLevel(level))
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            let count = statsByLevel[level] ?? 0
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                            }
                        }
                    }
                }
                .frame(height: 150)
                .chartLegend(.hidden)
                .chartYAxis(.hidden)
            }
        }
        .padding(AppSpacing.card)
        .appSurface(.card, isExtra: isExtra)
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vocabulary-learning-progress")
    }

    private var reviewCard: some View {
        Group {
            if !reviewCandidates.isEmpty {
                VStack(spacing: AppSpacing.item) {
                    ReviewPickerView(
                        candidates: reviewCandidates,
                        isExtra: isExtra,
                        usesExtraAlgorithm: usesExtraAlgorithm,
                        canStudy: heartManager.canStudy,
                        onStart: startReview
                    )
                    if !heartManager.isExtra && heartManager.remainingHearts == 0 {
                        Label(
                            heartManager.resetCountdownString.isEmpty
                                ? "Đang kiểm tra thời gian hồi lượt học..."
                                : "10 lượt học sẽ hồi lại sau \(heartManager.resetCountdownString)",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundColor(AppSemanticColor.attention)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                reviewCardContent
            }
        }
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vocabulary-learning-review")
    }

    private var reviewCardContent: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cần ôn tập hôm nay")
                        .font(.headline)
                        .foregroundColor(isExtra ? .white : .primary)

                    Text(dueVocabsCount > 0 ? "Bạn có \(dueVocabsCount) từ vựng đến hạn ôn tập." : "Tuyệt vời! Bạn đã hoàn thành hết các từ vựng cần ôn.")
                        .font(.subheadline)
                        .foregroundColor(AppTheme(isExtra: isExtra).secondaryText)
                }
                Spacer()

                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 30))
                    .foregroundColor(dueVocabsCount > 0 ? AppSemanticColor.attention : AppSemanticColor.success)
            }

            if dueVocabsCount > 0 && !reviewCandidates.isEmpty {
                HStack {
                    Text("Ôn tập ngay").bold()
                    Image(systemName: "arrow.right")
                }
                .font(AppTypography.action)
                .foregroundStyle(heartManager.canStudy ? Color.white : AppTheme(isExtra: isExtra).secondaryText)
                .padding(.horizontal, AppSpacing.row)
                .padding(.vertical, AppSpacing.item)
                .frame(maxWidth: .infinity, minHeight: 52)
                .modifier(AppActionFill(isExtra: isExtra, enabled: heartManager.canStudy))
                .opacity(heartManager.canStudy ? 1 : 0.55)
                if !heartManager.isExtra && heartManager.remainingHearts == 0 {
                    Label(
                        heartManager.resetCountdownString.isEmpty
                            ? "Đang kiểm tra thời gian hồi lượt học..."
                            : "10 lượt học sẽ hồi lại sau \(heartManager.resetCountdownString)",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundColor(AppSemanticColor.attention)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !wordsWithoutExampleExercises.isEmpty {
                    Label(
                        "\(wordsWithoutExampleExercises.count) nghĩa trong phiên sẽ bỏ qua phần ghép câu và phát âm vì chưa có ví dụ.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(AppSemanticColor.attention)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if dueVocabsCount > 0 {
                Label(
                    "Không thể tạo bài ôn tập từ dữ liệu hiện có.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundColor(AppSemanticColor.attention)
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
                .foregroundColor(AppSemanticColor.success)
                .padding()
                .frame(maxWidth: .infinity)
                .background(AppSemanticColor.success.opacity(0.1))
                .cornerRadius(18)
            }
        }
        .padding(AppSpacing.card)
        .appSurface(.card, isExtra: isExtra)
    }

    private func startReview(_ picked: [ReviewCandidate]) {
        guard !picked.isEmpty else { return }
        let plan = AdaptiveSessionBuilder.build(
            selected: picked.map(\.vocabulary),
            distractorPool: allVocabs,
            profiles: skillProfiles,
            isExtra: usesExtraAlgorithm
        )
        guard !plan.tasks.isEmpty else {
            errorMessage = "Không thể tạo bài ôn tập từ dữ liệu hiện có."
            return
        }
        var sessionTasks = plan.tasks
        #if DEBUG
        // Simulator clones have no audio input; recording would abort the test run.
        if ProcessInfo.processInfo.arguments.contains("-RealSessionUITestNoSpeech") {
            sessionTasks.removeAll { $0.type == .pronunciationExample }
        }
        #endif
        openReview(ActiveLearningSession(id: UUID(), tasks: sessionTasks,
                                         groups: plan.selectedGroups, reasons: plan.reasons))
    }

    private func openReview(_ session: ActiveLearningSession) {
        if !heartManager.canStudy {
            let countdown = heartManager.resetCountdownString.isEmpty
                ? ""
                : " Lượt học sẽ hồi lại sau \(heartManager.resetCountdownString)."
            errorMessage = "Bạn đã hết lượt học hôm nay (00 lượt).\(countdown) Bạn có thể vào My Omni đổi Trái tim bên lề hoặc nâng cấp Extraordinary để học không giới hạn."
        } else {
            activeSession = session
        }
    }

    func colorForLevel(_ level: Int) -> Color {
        switch level {
        case 0: return .red.opacity(0.7)
        case 1: return .orange.opacity(0.7)
        case 2: return .yellow.opacity(0.7)
        case 3: return .green.opacity(0.7)
        case 4: return .blue.opacity(0.7)
        case 5: return .cyan.opacity(0.7)
        case 6: return .purple.opacity(0.7)
        case 7: return .mint.opacity(0.7)
        default: return .gray
        }
    }
    
    @MainActor
    private func prepareSession() async {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LearningLayoutUITest") {
            allVocabs = LearningLayoutPreview.words
            reviewCandidates = ReviewPriority.candidates(from: allVocabs, profiles: [:], now: Date())
            totalLearningWords = 114
            totalSavedWords = 321
            dueVocabsCount = allVocabs.count
            statsByLevel = [0: 25, 1: 30, 2: 22, 3: 15, 4: 12, 5: 5, 6: 3, 7: 2]
            return
        }
        #endif

        do {
            await heartManager.refreshHearts()

            guard let userId = AuthManager.shared.currentUser?.id.uuidString else {
                totalLearningWords = 0
                totalSavedWords = 0
                dueVocabsCount = 0
                wordsWithoutExampleExercises = []
                statsByLevel = Dictionary(uniqueKeysWithValues: (0...7).map { ($0, 0) })
                return
            }

            await OmniStreakFreezeManager.shared.syncFromRemote(userId: userId)

            let allResponse = try await VocabularyRepository.fetchUserVocabs(userId: userId)
            let plan = LearningSessionBuilder.build(from: allResponse)
            // Profiles are optional evidence: a missing table or network hiccup
            // must not block learning, it only removes personalisation.
            skillProfiles = (try? await LearningProfileRepository.fetchProfiles(userId: userId)) ?? [:]
            allVocabs = allResponse
            reviewCandidates = ReviewPriority.candidates(from: allResponse, profiles: skillProfiles, now: Date())

            statsByLevel = plan.statsByLevel
            totalLearningWords = plan.totalLearningWords
            totalSavedWords = plan.totalSavedWords
            dueVocabsCount = plan.dueVocabsCount
            wordsWithoutExampleExercises = plan.wordsWithoutExampleExercises
            // Session tasks are built only by startReview from the learner's
            // picks; a late refresh must never replace them with a random plan.
        } catch {
            errorMessage = "Không tải được dữ liệu học từ vựng: \(error.localizedDescription)"
        }
    }
}

/// Everything a vocabulary session needs, built once when the learner starts it.
struct ActiveLearningSession: Identifiable {
    let id: UUID
    let tasks: [LearningTask]
    let groups: [[Vocabulary]]
    let reasons: [String: String]
}
