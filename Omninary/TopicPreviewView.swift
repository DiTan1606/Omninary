import SwiftUI

struct TopicPreviewView: View {
    let topicName: String
    let vocabs: [Vocabulary]
    let missingVocabs: [Vocabulary]
    let isFullyDownloaded: Bool
    let needsUpdate: Bool
    let onDownload: () -> Void
    @Binding var isDownloading: Bool
    
    var groupedByWord: [String: [Vocabulary]] {
        Dictionary(grouping: vocabs, by: { $0.vocab?.trimmingCharacters(in: .whitespaces) ?? "Unknown" })
    }
    
    var uniqueWords: [String] {
        groupedByWord.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var missingWordKeys: Set<String> {
        Set(missingVocabs.compactMap { $0.normalizedWord })
    }
    
    var body: some View {
        VStack {
            List {
                Section(header: Text("Danh sách từ vựng (\(uniqueWords.count) từ)")) {
                    ForEach(uniqueWords, id: \.self) { word in
                        let meanings = groupedByWord[word] ?? []
                        let firstMeaning = meanings.first
                        let isNewWord = firstMeaning?.normalizedWord.map { missingWordKeys.contains($0) } ?? false
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(word)
                                    .font(.headline)
                                if isNewWord {
                                    Text("Mới")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                }
                                Spacer()
                            }
                            
                            if let ipa = firstMeaning?.IPA, !ipa.isEmpty {
                                Text(ipa)
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            
                            let vMeanings = Array(Set(meanings.compactMap { $0.V_meaning }.filter { !$0.isEmpty })).joined(separator: "; ")
                            if !vMeanings.isEmpty {
                                Text(vMeanings)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(isNewWord ? Color.orange.opacity(0.08) : Color.clear)
                    }
                }
            }
            
            if !isFullyDownloaded {
                Button(action: {
                    onDownload()
                }) {
                    HStack {
                        if isDownloading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Đang tải...")
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                            let uniqueMissing = Set(missingVocabs.compactMap { $0.vocab?.trimmingCharacters(in: .whitespaces).lowercased() }).count
                            Text(needsUpdate ? "Cập nhật \(uniqueMissing) từ mới" : "Tải bộ từ này về máy")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isDownloading ? Color.gray : (needsUpdate ? Color.orange : Color.blue))
                    .cornerRadius(12)
                    .padding()
                }
                .disabled(isDownloading)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Bộ từ này đã có trong máy của bạn")
                }
                .font(.headline)
                .foregroundColor(.green)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .padding()
            }
        }
        .navigationTitle(topicName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
