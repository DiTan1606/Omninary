import Foundation
import AVFoundation

enum SpeechPlaybackSpeed: Double, CaseIterable, Identifiable {
    case slow = 0.5
    case normal = 1.0
    case fast = 1.5

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .slow:
            return "0.5x"
        case .normal:
            return "1x"
        case .fast:
            return "1.5x"
        }
    }
}

class SpeechManager: ObservableObject {
    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()

    private let defaultSpeechRate: Float = 0.45

    private var preferredSpeed: Double {
        let stored = UserDefaults.standard.double(forKey: "vocabulary_speech_speed")
        return SpeechPlaybackSpeed(rawValue: stored)?.rawValue ?? SpeechPlaybackSpeed.normal.rawValue
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speak(
        word: String,
        ipa: String?,
        rateMultiplier: Double? = nil,
        stopPrevious: Bool = true
    ) {
        // Dừng giọng đọc cũ nếu đang đọc dở
        if stopPrevious {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance: AVSpeechUtterance
        
        if let ipa = ipa, !ipa.isEmpty {
            // Xóa dấu '/' thường có trong IPA (ví dụ: "/prəˈdʒekt/") để engine dễ đọc hơn
            let cleanIPA = ipa.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
            
            let attrString = NSMutableAttributedString(string: word)
            // Cung cấp phiên âm IPA để Apple Voice đọc đúng chuẩn theo từng từ loại (Giải quyết bài toán từ đồng âm dị nghĩa)
            attrString.addAttribute(.accessibilitySpeechIPANotation, value: cleanIPA, range: NSRange(location: 0, length: word.utf16.count))
            
            utterance = AVSpeechUtterance(attributedString: attrString)
        } else {
            // Nếu không có IPA thì đọc mặc định
            utterance = AVSpeechUtterance(string: word)
        }
        
        // Cài đặt giọng Mỹ (hoặc bạn có thể cho user tự chọn Anh-Anh, Anh-Mỹ sau này)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate(for: rateMultiplier ?? preferredSpeed)

        synthesizer.speak(utterance)
    }

    func speak(
        example sentence: String,
        targetWord: String,
        ipa: String?,
        rateMultiplier: Double? = nil,
        stopPrevious: Bool = true
    ) {
        if stopPrevious {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let attributedSentence = NSMutableAttributedString(string: sentence)
        if let ipa = ipa, !ipa.isEmpty,
           let targetRange = firstWholeWordRange(of: targetWord, in: sentence) {
            let cleanIPA = ipa.replacingOccurrences(of: "/", with: "").trimmingCharacters(in: .whitespaces)
            attributedSentence.addAttribute(
                .accessibilitySpeechIPANotation,
                value: cleanIPA,
                range: NSRange(targetRange, in: sentence)
            )
        }

        let utterance = AVSpeechUtterance(attributedString: attributedSentence)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = speechRate(for: rateMultiplier ?? preferredSpeed)
        synthesizer.speak(utterance)
    }

    private func speechRate(for multiplier: Double) -> Float {
        let rate = defaultSpeechRate * Float(multiplier)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func firstWholeWordRange(of target: String, in sentence: String) -> Range<String.Index>? {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else { return nil }

        var searchStart = sentence.startIndex
        while searchStart < sentence.endIndex,
              let range = sentence.range(
                of: trimmedTarget,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<sentence.endIndex
              ) {
            let beforeIsLetter = range.lowerBound > sentence.startIndex
                && sentence[sentence.index(before: range.lowerBound)].isLetter
            let afterIsLetter = range.upperBound < sentence.endIndex
                && sentence[range.upperBound].isLetter

            if !beforeIsLetter && !afterIsLetter {
                return range
            }

            searchStart = range.upperBound
        }

        return nil
    }
}
