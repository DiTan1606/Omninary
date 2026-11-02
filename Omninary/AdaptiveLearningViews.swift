import SwiftUI

/// One word's server-confirmed outcome at the end of a session.
struct WordMasteryResultRow: View {
    let result: WordMasteryResult
    let word: String
    let reason: String?
    let isExtra: Bool

    private var theme: AppTheme { AppTheme(isExtra: isExtra) }

    private var decisionColor: Color {
        switch result.decisionKind {
        case .jump: AppSemanticColor.success
        case .advance: isExtra ? ExtraAuroraPalette.ice : .blue
        case .hold: AppSemanticColor.attention
        }
    }

    private var levelText: String {
        guard let level = result.stored_level else { return "" }
        let title = LearningLevelDisplay.title(for: level)
        return result.decisionKind == .hold ? "\(title) · lần \(result.level_attempt)" : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(word)
                    .font(.headline)
                    .foregroundStyle(isExtra ? Color.white : Color.primary)
                Spacer()
                if let mastery = result.mastery {
                    Text("M \(mastery)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(decisionColor)
                }
            }

            HStack(spacing: 6) {
                if result.mode == "extraordinary" {
                    Text(result.decisionKind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(decisionColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(decisionColor.opacity(0.14)))
                }
                Text(levelText)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text("Ôn lại: \(ReviewTimeFormatter.text(for: result.next_review))")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            SkillBars(scores: result.skill_scores, isExtra: isExtra)

            if let failures = result.first_attempt_failures, failures > 0 {
                Text("Sai ở lần làm đầu: \(failures) dạng bài"
                     + (result.decisionKind == .hold && failures >= ExtraScheduler.holdFirstAttemptFailures
                        ? " → giữ cấp để ôn bù" : ""))
                    .font(.caption2)
                    .foregroundStyle(AppSemanticColor.attention)
            }
            if let previous = result.previous_mastery, let mastery = result.mastery {
                Text("Lần trước \(previous) → lần này \(mastery)")
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
            }
            if let reason {
                Label(reason, systemImage: "bolt.heart.fill")
                    .font(.caption2)
                    .foregroundStyle(AppSemanticColor.attention)
            }
        }
        .padding(AppSpacing.row)
        .appSurface(.row, isExtra: isExtra)
    }
}

/// Compact bars for the five skills (only skills with evidence).
struct SkillBars: View {
    let scores: [String: Double]
    let isExtra: Bool

    var body: some View {
        VStack(spacing: 4) {
            ForEach(LearningSkill.allCases.filter { scores[$0.rawValue] != nil }, id: \.self) { skill in
                let value = scores[skill.rawValue] ?? 0
                HStack(spacing: 8) {
                    Text(skill.title)
                        .font(.caption2)
                        .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                        .frame(width: 96, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(color(for: value))
                                .frame(width: proxy.size.width * min(max(value, 0), 100) / 100)
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(value.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme(isExtra: isExtra).secondaryText)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private func color(for value: Double) -> Color {
        if value >= 80 { return AppSemanticColor.success }
        if value >= 60 { return isExtra ? ExtraAuroraPalette.ice : .blue }
        return AppSemanticColor.attention
    }
}

/// "Ôn tập ngay": every due word, sorted by priority. Ditan picks exactly 5
/// (or all when fewer are due); Extra picks any number.
struct ReviewPickerView: View {
    let candidates: [ReviewCandidate]
    let isExtra: Bool
    let usesExtraAlgorithm: Bool
    let canStudy: Bool
    let onStart: ([ReviewCandidate]) -> Void

    @State private var selected: Set<String> = []

    static let ditanSessionSize = 5

    private var requiredCount: Int { min(Self.ditanSessionSize, candidates.count) }
    private var theme: AppTheme { AppTheme(isExtra: isExtra) }

    private var canStart: Bool {
        guard canStudy else { return false }
        return usesExtraAlgorithm ? !selected.isEmpty : selected.count == requiredCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.item) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cần ôn tập ngay")
                        .font(AppTypography.cardTitle)
                        .foregroundStyle(isExtra ? Color.white : Color.primary)
                }
                Spacer()
                Text(usesExtraAlgorithm ? "\(selected.count) đã chọn" : "\(selected.count)/\(requiredCount)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(canStart ? theme.accent : theme.secondaryText)
            }

            ScrollView {
                LazyVStack(spacing: AppSpacing.inline) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        row(candidate, rank: index + 1)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .scrollBounceBehavior(.basedOnSize)

            Button {
                onStart(candidates.filter { selected.contains($0.id) })
            } label: {
                LearningActionButtonLabel(
                    title: "Ôn tập ngay",
                    systemImage: "play.circle.fill"
                )
            }
            .buttonStyle(AppActionButtonStyle(isExtra: isExtra))
            .disabled(!canStart)
            .accessibilityIdentifier("review-start")
        }
        .padding(AppSpacing.card)
        .appSurface(.card, isExtra: isExtra)
        .onAppear {
            if selected.isEmpty { selected = Set(candidates.prefix(requiredCount).map(\.id)) }
        }
    }

    private func row(_ candidate: ReviewCandidate, rank: Int) -> some View {
        let isOn = selected.contains(candidate.id)
        return Button {
            if isOn {
                selected.remove(candidate.id)
            } else if usesExtraAlgorithm || selected.count < requiredCount {
                selected.insert(candidate.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? (isExtra ? ExtraAuroraPalette.ice : Color.blue) : theme.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(candidate.vocabulary.vocab ?? "")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isExtra ? Color.white : Color.primary)
                        Text(candidate.vocabulary.V_meaning ?? "")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        statusChip(candidate)
                        Text(LearningLevelDisplay.title(for: candidate.vocabulary.learning_level))
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryText)
                        if let mastery = candidate.lastMastery {
                            Text("M gần nhất \(mastery)")
                                .font(.caption2)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }
                Spacer()
                Text("#\(rank)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, AppSpacing.item)
            .appSurface(.row, isExtra: isExtra)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review-word-\(candidate.vocabulary.vocab ?? candidate.id)")
    }

    private func statusChip(_ candidate: ReviewCandidate) -> some View {
        let color: Color = candidate.overdueDays > 0 ? AppSemanticColor.destructive
            : candidate.isNew ? (isExtra ? ExtraAuroraPalette.ice : .blue) : AppSemanticColor.attention
        let text = candidate.isHolding ? "\(candidate.statusText) · đang giữ cấp" : candidate.statusText
        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}
