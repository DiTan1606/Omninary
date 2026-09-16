import Foundation

struct ListeningMaskProgress: Equatable {
    let fullCorrectWordCount: Int
    let partialWord: String?
    let hasMistake: Bool
    let isComplete: Bool
}

enum ListeningWordTileState: Equatable {
    case hidden
    case partial
    case correct
    case wrong
    case hinted
}

struct ListeningWordTile: Identifiable, Equatable {
    let index: Int
    let target: String
    let displayText: String
    let state: ListeningWordTileState

    var id: Int { index }
}

enum ListeningScoreCalculator {
    static let passingScore = 80.0

    static func hasPassed(score: Double) -> Bool {
        score >= passingScore
    }

    static func sentenceScore(wordCount: Int, hintedWordCount: Int) -> Double {
        guard wordCount > 0 else { return 0 }
        let validHintCount = min(max(hintedWordCount, 0), wordCount)
        let earnedFraction = Double(wordCount - validHintCount) / Double(wordCount)
        return roundedScore(earnedFraction * 100)
    }

    static func lessonScore(results: [ListeningSentenceResult], totalSentenceCount: Int) -> Double {
        guard totalSentenceCount > 0 else { return 0 }

        let earnedFractions = results.reduce(0.0) { total, result in
            guard result.wordCount > 0 else { return total }
            let validHintCount = min(max(result.hintedWordCount, 0), result.wordCount)
            return total + Double(result.wordCount - validHintCount) / Double(result.wordCount)
        }

        return roundedScore(earnedFractions / Double(totalSentenceCount) * 100)
    }

    static func display(_ score: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), score)
    }

    private static func roundedScore(_ score: Double) -> Double {
        (score * 10).rounded() / 10
    }
}

enum ListeningTextMasker {
    private static let wordPattern = #"[A-Za-z0-9]+(?:[’'][A-Za-z0-9]+)?|[^A-Za-z0-9\s]"#

    static func normalizedWords(_ text: String) -> [String] {
        tokens(in: text).compactMap(\.normalizedWord)
    }

    static func progress(target: String, input: String) -> ListeningMaskProgress {
        let targetWords = normalizedWords(target)
        let inputWords = normalizedWords(input)

        var fullCorrectWordCount = 0
        while fullCorrectWordCount < min(targetWords.count, inputWords.count),
              targetWords[fullCorrectWordCount] == inputWords[fullCorrectWordCount] {
            fullCorrectWordCount += 1
        }

        var partialWord: String?
        var hasMistake = false

        if fullCorrectWordCount < inputWords.count {
            let candidate = inputWords[fullCorrectWordCount]
            if fullCorrectWordCount < targetWords.count,
               !candidate.isEmpty,
               targetWords[fullCorrectWordCount].hasPrefix(candidate) {
                partialWord = candidate
            } else {
                hasMistake = true
            }
        }

        return ListeningMaskProgress(
            fullCorrectWordCount: fullCorrectWordCount,
            partialWord: partialWord,
            hasMistake: hasMistake,
            isComplete: !targetWords.isEmpty && targetWords == inputWords
        )
    }

    static func maskedText(target: String, input: String) -> String {
        let tokens = tokens(in: target)
        let progress = progress(target: target, input: input)
        var wordIndex = 0

        let pieces = tokens.map { token -> DisplayPiece in
            guard let normalizedWord = token.normalizedWord else {
                return DisplayPiece(text: token.raw, isClosingPunctuation: token.isClosingPunctuation, isOpeningPunctuation: token.isOpeningPunctuation)
            }

            let displayText: String
            if wordIndex < progress.fullCorrectWordCount {
                displayText = token.raw
            } else if wordIndex == progress.fullCorrectWordCount,
                      let partialWord = progress.partialWord {
                displayText = partialMask(rawWord: token.raw, normalizedWord: normalizedWord, partialWord: partialWord)
            } else {
                displayText = String(repeating: "•", count: max(normalizedWord.count, 1))
            }

            wordIndex += 1
            return DisplayPiece(text: displayText, isClosingPunctuation: false, isOpeningPunctuation: false)
        }

        return joinDisplayPieces(pieces)
    }

    static func answerThroughNextWord(target: String, input: String) -> String {
        let targetWords = normalizedWords(target)
        let currentProgress = progress(target: target, input: input)
        guard !targetWords.isEmpty else { return input }

        let nextWordIndex = min(currentProgress.fullCorrectWordCount, targetWords.count - 1)
        return targetWords.prefix(nextWordIndex + 1).joined(separator: " ")
    }

    static func nextHintWordIndex(target: String, input: String) -> Int? {
        let targetWords = normalizedWords(target)
        guard !targetWords.isEmpty else { return nil }

        let currentProgress = progress(target: target, input: input)
        guard !currentProgress.isComplete else { return nil }
        return min(currentProgress.fullCorrectWordCount, targetWords.count - 1)
    }

    static func wordTiles(
        target: String,
        input: String,
        hintedWordIndices: Set<Int>
    ) -> [ListeningWordTile] {
        let targetTokens = tokens(in: target).filter { $0.normalizedWord != nil }
        let inputTokens = tokens(in: input).filter { $0.normalizedWord != nil }
        var hasMismatch = false

        return targetTokens.enumerated().map { index, targetToken in
            let normalizedTarget = targetToken.normalizedWord ?? ""

            if hintedWordIndices.contains(index) {
                return ListeningWordTile(
                    index: index,
                    target: targetToken.raw,
                    displayText: targetToken.raw,
                    state: .hinted
                )
            }

            guard !hasMismatch, inputTokens.indices.contains(index) else {
                return ListeningWordTile(
                    index: index,
                    target: targetToken.raw,
                    displayText: String(repeating: "•", count: max(normalizedTarget.count, 1)),
                    state: .hidden
                )
            }

            let inputToken = inputTokens[index]
            let normalizedInput = inputToken.normalizedWord ?? ""

            if normalizedInput == normalizedTarget {
                return ListeningWordTile(
                    index: index,
                    target: targetToken.raw,
                    displayText: targetToken.raw,
                    state: .correct
                )
            }

            if !normalizedInput.isEmpty, normalizedTarget.hasPrefix(normalizedInput) {
                return ListeningWordTile(
                    index: index,
                    target: targetToken.raw,
                    displayText: partialMask(
                        rawWord: targetToken.raw,
                        normalizedWord: normalizedTarget,
                        partialWord: normalizedInput
                    ),
                    state: .partial
                )
            }

            hasMismatch = true
            return ListeningWordTile(
                index: index,
                target: targetToken.raw,
                displayText: inputToken.raw,
                state: .wrong
            )
        }
    }

    private static func tokens(in text: String) -> [ListeningToken] {
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let raw = String(text[swiftRange])
            return ListeningToken(raw: raw)
        }
    }

    private static func normalizedWord(_ text: String) -> String {
        let lowercased = text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")

        let allowedScalars = lowercased.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }

        return String(String.UnicodeScalarView(allowedScalars))
    }

    private static func partialMask(rawWord: String, normalizedWord: String, partialWord: String) -> String {
        let visibleCount = min(partialWord.count, rawWord.count)
        let visiblePrefix = String(rawWord.prefix(visibleCount))
        let hiddenCount = max(normalizedWord.count - partialWord.count, 0)
        return visiblePrefix + String(repeating: "•", count: hiddenCount)
    }

    private static func joinDisplayPieces(_ pieces: [DisplayPiece]) -> String {
        var output = ""
        var previousWasOpeningPunctuation = false

        for piece in pieces {
            if output.isEmpty {
                output = piece.text
            } else if piece.isClosingPunctuation {
                output += piece.text
            } else if previousWasOpeningPunctuation {
                output += piece.text
            } else {
                output += " " + piece.text
            }

            previousWasOpeningPunctuation = piece.isOpeningPunctuation
        }

        return output
    }
}

private struct ListeningToken {
    let raw: String

    var normalizedWord: String? {
        let normalized = ListeningTextMasker.normalizedWordsForToken(raw)
        return normalized.isEmpty ? nil : normalized
    }

    var isClosingPunctuation: Bool {
        [".", ",", "!", "?", ";", ":", ")", "]", "}", "\"", "”", "'"].contains(raw)
    }

    var isOpeningPunctuation: Bool {
        ["(", "[", "{", "\"", "“", "'"].contains(raw)
    }
}

private struct DisplayPiece {
    let text: String
    let isClosingPunctuation: Bool
    let isOpeningPunctuation: Bool
}

extension ListeningTextMasker {
    fileprivate static func normalizedWordsForToken(_ token: String) -> String {
        normalizedWord(token)
    }
}
