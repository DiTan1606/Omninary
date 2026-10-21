import SwiftUI

/// Hàng thông tin thứ hai của đầu thẻ; nội dung dài vẫn nằm trên cùng một hàng.
struct VocabularyCardMetadata: View {
    let item: Vocabulary
    let onSpeak: () -> Void
    var onHeader = true
    var isExtra = false
    @ScaledMetric(relativeTo: .caption) private var rowHeight = 44

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let ipa = text(item.IPA) {
                    Text(ipa).font(.subheadline)
                        .accessibilityLabel("Phiên âm: \(ipa)")
                        .accessibilityIdentifier("vocabulary-ipa")
                }
                if let form = text(item.word_form) {
                    metadataTag(form).accessibilityLabel("Từ loại: \(form)")
                        .accessibilityIdentifier("vocabulary-word-form")
                }
                if let level = text(item.CEFR) {
                    metadataTag(level).accessibilityLabel("Cấp độ: \(level)")
                        .accessibilityIdentifier("vocabulary-cefr")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(tint)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSpeak)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Nghe phát âm từ \(item.vocab ?? "")"), onSpeak)
    }

    private var tint: Color { onHeader ? .white : AppTheme(isExtra: isExtra).accent }

    private func metadataTag(_ value: String) -> some View {
        Text(value).font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(tint.opacity(onHeader ? 0.16 : 0.1), in: Capsule())
    }

    private func text(_ value: String?) -> String? { Vocabulary.normalizedExample(value) }
}

struct VocabularyCardContent: View {
    let item: Vocabulary
    let isExtra: Bool

    private var theme: AppTheme { AppTheme(isExtra: isExtra) }
    private var formulaInk: Color {
        isExtra ? Color(red: 0.96, green: 0.73, blue: 0.51) : Color(red: 0.58, green: 0.25, blue: 0.10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                if let meaning = text(item.V_meaning) {
                    Text(meaning)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("vocabulary-short-meaning")
                }
                if let definition = text(item.E_meaning) {
                    Button {
                        SpeechManager.shared.speak(word: definition, ipa: nil)
                    } label: {
                        Text(definition)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .foregroundStyle(isExtra ? Color.white.opacity(0.85) : Color.primary.opacity(0.82))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Nghe nghĩa tiếng Anh")
                    .accessibilityIdentifier("vocabulary-english-definition")
                }
                if let translation = text(item.EV_meaning) {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(isExtra ? Color.white.opacity(0.58) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("vocabulary-definition-translation")
                }
            }

            if item.englishExample != nil || item.vietnameseExample != nil { example }

            let formulas = Vocabulary.supplementaryValues(item.formula)
            if !formulas.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("Công thức", color: formulaInk)
                    ForEach(Array(formulas.enumerated()), id: \.offset) { _, formula in
                        Text(formula).font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(formulaInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(isExtra ? Color(red: 0.48, green: 0.26, blue: 0.13).opacity(0.28)
                            : Color(red: 1, green: 0.95, blue: 0.90), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("vocabulary-formulas")
            }

            verticalSection("Cụm thường gặp", value: item.collocation, identifier: "vocabulary-collocations")
            verticalSection("Ghi chú", value: item.note, identifier: "vocabulary-notes")
            verticalSection("Thông tin thêm", value: item.bonus, identifier: "vocabulary-bonus")
            verticalSection("Họ từ", value: item.word_family, identifier: "vocabulary-word-family")
            relatedWords("Từ đồng nghĩa", value: item.synonymous, isAntonym: false)
            relatedWords("Từ trái nghĩa", value: item.antonym, isAntonym: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var example: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let english = item.englishExample {
                Button {
                    SpeechManager.shared.speak(example: english, targetWord: item.vocab ?? "", ipa: item.IPA)
                } label: {
                    Text(highlightedExample(english))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Nghe cả câu ví dụ tiếng Anh")
                .accessibilityIdentifier("vocabulary-english-example")
            }
            if let vietnamese = item.vietnameseExample {
                Text(vietnamese)
                    .font(.subheadline)
                    .foregroundStyle(isExtra ? Color.white.opacity(0.62) : Color(red: 0.37, green: 0.44, blue: 0.52))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("vocabulary-vietnamese-example")
            }
        }
        .foregroundStyle(isExtra ? Color.white.opacity(0.92) : Color(red: 0.12, green: 0.17, blue: 0.25))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(isExtra ? theme.accent.opacity(0.1) : Color(red: 0.92, green: 0.96, blue: 1),
                    in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            if isExtra {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func highlightedExample(_ sentence: String) -> AttributedString {
        var result = AttributedString(sentence)
        for range in VocabularyExampleHighlight.ranges(in: sentence, target: item.vocab ?? "") {
            if let attributedRange = Range(range, in: result) {
                result[attributedRange].foregroundColor = isExtra
                    ? theme.accent
                    : Color(red: 0.04, green: 0.28, blue: 0.65)
                result[attributedRange].font = .body.bold()
            }
        }
        return result
    }

    @ViewBuilder
    private func verticalSection(_ title: String, value: String?, identifier: String) -> some View {
        let values = Vocabulary.supplementaryValues(value)
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(title)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value).font(.subheadline)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(isExtra ? Color.white.opacity(0.06) : Color(UIColor.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .accessibilityIdentifier(identifier)
        }
    }

    @ViewBuilder
    private func relatedWords(_ title: String, value: String?, isAntonym: Bool) -> some View {
        let values = Vocabulary.supplementaryValues(value)
        let tint = isAntonym ? AppSemanticColor.destructive : AppSemanticColor.success
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(title)
                VocabularyChipLayout(spacing: 8) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(value).font(.subheadline.weight(.medium))
                            .foregroundStyle(tint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(tint.opacity(isExtra ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .accessibilityIdentifier(isAntonym ? "vocabulary-antonyms" : "vocabulary-synonyms")
        }
    }

    private func sectionTitle(_ title: String, color: Color? = nil) -> some View {
        Text(title).font(.caption.weight(.bold))
            .foregroundStyle(color ?? theme.secondaryText)
    }

    private func text(_ value: String?) -> String? { Vocabulary.normalizedExample(value) }
}

/// Xếp thẻ liên hệ từ theo hàng ngang, xuống hàng khi hết chỗ; cụm dài không tràn thẻ.
private struct VocabularyChipLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let limit = max(1, width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + spacing })
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
            if x > 0 && x + size.width > limit {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: limit, height: y + rowHeight), frames)
    }
}

enum VocabularyExampleHighlight {
    static func ranges(in sentence: String, target: String) -> [Range<String.Index>] {
        let words = target.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return [] }
        // Bao gồm các đuôi phổ biến; một số biến thể bất quy tắc của cụm động từ.
        let irregular = ["lay": ["laid", "laying"], "make": ["made"], "take": ["took", "taken"],
                         "get": ["got", "gotten"], "give": ["gave", "given"], "go": ["went", "gone"],
                         "run": ["ran", "running"], "put": ["putting"], "set": ["setting"],
                         "cut": ["cutting"], "come": ["came"], "keep": ["kept"], "bring": ["brought"]]
        let base = first.lowercased()
        var forms = [base, base + "s", base + "es", base + "ed", base + "ing"]
        if base.hasSuffix("e") { forms += [base + "d", String(base.dropLast()) + "ing"] }
        if base.hasSuffix("y") { forms += [String(base.dropLast()) + "ies", String(base.dropLast()) + "ied"] }
        forms += irregular[base] ?? []
        let firstPattern = forms.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let tail = words.dropFirst().map { "\\s+" + NSRegularExpression.escapedPattern(for: $0) }.joined()
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(firstPattern))\(tail)(?![\\p{L}\\p{N}])"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return expression.matches(in: sentence, range: NSRange(sentence.startIndex..., in: sentence))
            .compactMap { Range($0.range, in: sentence) }
    }
}
