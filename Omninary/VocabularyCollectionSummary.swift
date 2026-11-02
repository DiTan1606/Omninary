import Foundation
import SwiftUI
import Charts

struct VocabularyCollectionSummary {
    static let cefrLevels = ["A1", "A2", "B1", "B2", "C1", "C2"]
    static let learningBuckets = Array(0...7)

    let total: Int
    let cefrCounts: [String: Int]
    let learningLevelCounts: [Int: Int]
    let unclassifiedLevelCount: Int
    let unlearnedCount: Int

    var learningTotal: Int { total - unlearnedCount }

    static func learningTitle(for bucket: Int) -> String {
        LearningLevelDisplay.title(for: bucket == 7 ? 10 : bucket)
    }

    init(vocabularies: [Vocabulary]) {
        let items = Vocabulary.sortedItems(vocabularies)
        total = items.count
        var levels: [String: Int] = [:]
        var learningLevels: [Int: Int] = [:]
        var missingLevels = 0
        var unlearned = 0
        for item in items {
            let level = (item.CEFR ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if Self.cefrLevels.contains(level) { levels[level, default: 0] += 1 }
            else { missingLevels += 1 }

            if let learningLevel = item.learning_level, learningLevel >= 0 {
                learningLevels[LearningLevelDisplay.bucket(for: learningLevel), default: 0] += 1
            } else {
                unlearned += 1
            }
        }
        cefrCounts = levels
        learningLevelCounts = learningLevels
        unclassifiedLevelCount = missingLevels
        unlearnedCount = unlearned
    }
}

struct VocabularyCollectionSummaryCard: View {
    private enum Statistic: Hashable { case cefr, learning }

    let vocabularies: [Vocabulary]
    let isExtra: Bool
    @State private var statistic: Statistic = .cefr
    @ScaledMetric(relativeTo: .caption) private var chartHeight = 170
    @ScaledMetric(relativeTo: .caption) private var learningBarHeight = 10
    private var accent: Color { isExtra ? ExtraAuroraPalette.ice : .blue }
    private var secondaryText: Color { AppTheme(isExtra: isExtra).secondaryText }

    var body: some View {
        let summary = VocabularyCollectionSummary(vocabularies: vocabularies)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tổng quan bộ từ").font(AppTypography.cardTitle)
                    Text("\(summary.total) từ").font(.subheadline).foregroundStyle(secondaryText)
                        .accessibilityIdentifier("vocabularyCollectionTotal")
                }
                Spacer(minLength: 0)
            }

            Picker("Loại biểu đồ", selection: $statistic) {
                Text("CEFR").tag(Statistic.cefr)
                    .accessibilityLabel("CEFR, Common European Framework of Reference for Languages, Khung tham chiếu ngôn ngữ chung châu Âu")
                Text("Cấp độ học").tag(Statistic.learning)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("vocabularyCollectionChartPicker")

            if statistic == .cefr {
                VStack(alignment: .leading, spacing: 12) {
                    Chart {
                        ForEach(VocabularyCollectionSummary.cefrLevels, id: \.self) { level in
                            let count = summary.cefrCounts[level, default: 0]
                            BarMark(x: .value("CEFR", level), y: .value("Số từ", count), width: .ratio(0.55))
                                .foregroundStyle(accent.gradient)
                                .cornerRadius(4)
                                .annotation(position: .top, spacing: 4) {
                                    chartCount(count)
                                }
                                .accessibilityLabel(Text(level))
                                .accessibilityValue(Text("\(count) từ"))
                        }
                    }
                    .chartXScale(domain: VocabularyCollectionSummary.cefrLevels)
                    .chartYScale(domain: 0...chartMaximum(summary.cefrCounts.values.max() ?? 0))
                    .chartXAxis {
                        AxisMarks(values: VocabularyCollectionSummary.cefrLevels) {
                            AxisValueLabel().font(.caption).foregroundStyle(secondaryText)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: cefrTicks(maximum: summary.cefrCounts.values.max() ?? 0)) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(secondaryText.opacity(0.15))
                            AxisValueLabel().font(.caption2).foregroundStyle(secondaryText)
                        }
                    }
                    .frame(height: chartHeight)
                    .accessibilityIdentifier("vocabularyCollectionCEFRChart")
                    if summary.unclassifiedLevelCount > 0 {
                        Text("\(summary.unclassifiedLevelCount) từ chưa xác định CEFR")
                            .font(.caption).foregroundStyle(secondaryText)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        ForEach(VocabularyCollectionSummary.learningBuckets, id: \.self) { bucket in
                            let title = VocabularyCollectionSummary.learningTitle(for: bucket)
                            let count = summary.learningLevelCounts[bucket, default: 0]
                            GridRow {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(secondaryText)
                                    .fixedSize()
                                GeometryReader { geometry in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill((bucket == 7 ? AppSemanticColor.success : accent).gradient)
                                        .frame(width: geometry.size.width * Double(count)
                                            / chartMaximum(summary.learningLevelCounts.values.max() ?? 0))
                                }
                                .frame(height: learningBarHeight)
                                chartCount(count)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(title))
                            .accessibilityValue(Text("\(count) từ"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: chartHeight)
                    .accessibilityIdentifier("vocabularyCollectionLearningChart")
                    if summary.unlearnedCount > 0 {
                        Text("\(summary.unlearnedCount) từ chưa học")
                            .font(.caption).foregroundStyle(secondaryText)
                    }
                }
            }
        }
        .foregroundStyle(isExtra ? .white : .primary)
        .padding(AppSpacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.card, isExtra: isExtra)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vocabularyCollectionSummary")
    }

    private func chartCount(_ count: Int) -> some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(secondaryText)
            .fixedSize()
            .accessibilityHidden(true)
    }

    private func chartMaximum(_ count: Int) -> Double {
        max(1, Double(count) * 1.25)
    }

    private func cefrTicks(maximum: Int) -> [Int] {
        Array(stride(from: 0, through: max(1, maximum), by: max(1, Int(ceil(Double(maximum) / 2)))))
    }
}
