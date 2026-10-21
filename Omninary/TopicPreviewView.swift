import SwiftUI

struct TopicPreviewView: View {
    let topicName: String
    let vocabs: [Vocabulary]
    let missingVocabs: [Vocabulary]
    let isFullyDownloaded: Bool
    let needsUpdate: Bool
    let onDownload: () -> Void
    @Binding var isDownloading: Bool
    
    private var vocabularyItems: [Vocabulary] { Vocabulary.sortedItems(vocabs) }

    @AppStorage("development_interface_mode") private var interfaceModeRaw = AppInterfaceMode.ditandnary.rawValue
    private var isExtra: Bool {
        interfaceModeRaw == AppInterfaceMode.extraordinary.rawValue
    }

    var missingWordKeys: Set<String> {
        Set(missingVocabs.map(\.vocabularyIdentity))
    }
    
    var body: some View {
        List {
            Section {
                ForEach(Array(vocabularyItems.enumerated()), id: \.element.vocabularyIdentity) { index, vocabulary in
                    let word = vocabulary.vocab ?? ""
                    let meanings = [vocabulary]
                    let isNewWord = missingWordKeys.contains(vocabulary.vocabularyIdentity)
                    let isBottom = (index == vocabularyItems.count - 1)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(word)
                                .font(AppTypography.cardTitle)
                                .foregroundStyle(isExtra ? Color.white : Color.primary)
                            if isNewWord {
                                Text("Mới")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppSemanticColor.attention)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(AppSemanticColor.attention.opacity(0.12)))
                            }
                            Spacer()
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { pronunciationAndForm(vocabulary) }
                            VStack(alignment: .leading, spacing: 6) { pronunciationAndForm(vocabulary) }
                        }

                        let vMeanings = Array(Set(meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty })).joined(separator: "; ")
                        if !vMeanings.isEmpty {
                            Text(vMeanings)
                                .font(AppTypography.body)
                                .foregroundStyle(isExtra ? Color.white.opacity(0.85) : .primary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(AppSurfaceBackground(kind: .row, isExtra: isExtra, grouped: true))
                    .listRowSeparator(isBottom ? .hidden : .visible, edges: .bottom)
                    .listRowSeparator(.hidden, edges: .top)
                    .listRowSeparatorTint(isExtra ? Color.white.opacity(0.12) : Color(UIColor.separator))
                }
            } header: {
                Text("Danh sách từ vựng (\(vocabularyItems.count) từ)")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(isExtra ? Color.white.opacity(0.8) : .secondary)
            }
            .listSectionSeparator(.hidden, edges: .all)
        }
        .scrollContentBackground(isExtra ? .hidden : .automatic)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            downloadActionBar
        }
        .background {
            if isExtra {
                AuroraBackdrop()
            } else {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            }
        }
        .navigationTitle(topicName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func pronunciationAndForm(_ vocabulary: Vocabulary) -> some View {
        if let ipa = vocabulary.IPA, !ipa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(ipa)
                .font(.subheadline)
                .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : .blue)
        }
        if let form = vocabulary.word_form?.trimmingCharacters(in: .whitespacesAndNewlines), !form.isEmpty {
            Text(form)
                .font(.caption.weight(.medium))
                .foregroundStyle(isExtra ? ExtraAuroraPalette.ice : .blue)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background((isExtra ? ExtraAuroraPalette.ice : Color.blue).opacity(0.12), in: Capsule())
                .accessibilityLabel("Từ loại: \(form)")
        }
    }

    private var downloadActionBar: some View {
        let count = Vocabulary.sortedItems(missingVocabs).count
        return AppFloatingDownloadBar(
            title: isFullyDownloaded ? "Bộ từ này đã có trong máy của bạn" : (isDownloading ? "Đang tải..." : (needsUpdate ? "Cập nhật \(count) từ mới" : "Tải bộ từ này về máy")),
            isWorking: isDownloading, isComplete: isFullyDownloaded, isExtra: isExtra,
            action: onDownload
        )
    }
}
