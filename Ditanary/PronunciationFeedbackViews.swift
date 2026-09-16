import SwiftUI

extension PronunciationFeedbackLevel {
    var foregroundColor: Color {
        switch self {
        case .good:
            return .green
        case .needsImprovement:
            return .orange
        case .retry:
            return .red
        }
    }

    var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }

    var symbolName: String {
        switch self {
        case .good:
            return "checkmark.circle.fill"
        case .needsImprovement:
            return "exclamationmark.circle.fill"
        case .retry:
            return "xmark.circle.fill"
        }
    }
}

struct PronunciationFeedbackLegend: View {
    let level: PronunciationFeedbackLevel

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(level.foregroundColor)
                .frame(width: 7, height: 7)
            Text(level.title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct PronunciationWordFeedbackSheet: View {
    let feedback: AzurePronunciationAssessment.WordFeedback
    @ObservedObject var pronunciationManager: PronunciationManager

    @Environment(\.dismiss) private var dismiss

    private var level: PronunciationFeedbackLevel {
        PronunciationPassingRule.feedbackLevel(for: feedback)
    }

    private var phonemeText: String {
        feedback.phonemes.map(\.phoneme).joined(separator: " ")
    }

    private var ipaNotation: String? {
        phonemeText.isEmpty ? nil : "/\(phonemeText)/"
    }

    private var recordedWordTiming: (offsetMilliseconds: Int, durationMilliseconds: Int)? {
        guard let offsetMilliseconds = feedback.offsetMilliseconds,
              let durationMilliseconds = feedback.durationMilliseconds,
              durationMilliseconds > 0 else {
            return nil
        }
        return (offsetMilliseconds, durationMilliseconds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(feedback.word)
                            .font(.title2.bold())
                            .foregroundColor(level.foregroundColor)

                        if !phonemeText.isEmpty {
                            Text("/\(phonemeText)/")
                                .font(.title3.monospaced())
                                .foregroundColor(.secondary)
                        }

                        Label(
                            "\(Int(feedback.accuracy.rounded())) điểm - \(level.title)",
                            systemImage: level.symbolName
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(level.foregroundColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(level.backgroundColor)
                    )

                    HStack(spacing: 12) {
                        Button {
                            SpeechManager.shared.speak(word: feedback.word, ipa: ipaNotation)
                        } label: {
                            Label("Omninary đọc", systemImage: "speaker.wave.2.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        if let recordedWordTiming {
                            Button {
                                if pronunciationManager.isPlaying {
                                    pronunciationManager.stopPlayback()
                                } else {
                                    pronunciationManager.playRecordedAudio(
                                        offsetMilliseconds: recordedWordTiming.offsetMilliseconds,
                                        durationMilliseconds: recordedWordTiming.durationMilliseconds
                                    )
                                }
                            } label: {
                                Label(
                                    pronunciationManager.isPlaying ? "Dừng nghe" : "Bạn đọc",
                                    systemImage: pronunciationManager.isPlaying ? "stop.fill" : "person.wave.2.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(pronunciationManager.isPlaying ? .red : .orange)
                        }
                    }

                    if let message = PronunciationPassingRule.feedbackMessage(for: feedback) {
                        Label(message, systemImage: level.symbolName)
                            .font(.subheadline)
                            .foregroundColor(level.foregroundColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Phân tích âm vị")
                            .font(.headline)
                            .padding(.bottom, 10)

                        if feedback.phonemes.isEmpty {
                            Text("Azure chưa trả dữ liệu âm vị cho từ này.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(feedback.phonemes.enumerated()), id: \.offset) { index, phoneme in
                                let phonemeLevel = PronunciationPassingRule.feedbackLevel(for: phoneme)

                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("/\(phoneme.phoneme)/")
                                            .font(.body.monospaced())
                                            .foregroundColor(.primary)

                                        if let heardAs = PronunciationPassingRule.heardAs(for: phoneme) {
                                            Text("Azure nghe gần /\(heardAs)/")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }

                                    Spacer(minLength: 8)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(Int(phoneme.accuracy.rounded())) điểm")
                                            .font(.subheadline.weight(.semibold))

                                        Text(phonemeLevel.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(phonemeLevel.foregroundColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 13)

                                if index < feedback.phonemes.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                }
                .padding()
            }
            .navigationTitle("Chi tiết phát âm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") {
                        dismiss()
                    }
                }
            }
        }
    }
}
