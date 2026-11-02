import Testing
@testable import Omninary

struct VocabularyExampleHighlightTests {
    @Test func highlightsWholeWordsAndRepeatedInflections() {
        let sentence = "A bank banks on help from the riverbank and another BANK."
        let matches = VocabularyExampleHighlight.ranges(in: sentence, target: "bank").map { String(sentence[$0]) }
        #expect(matches == ["bank", "banks", "BANK"])
    }

    @Test func highlightsPhrasalVerbInPastTense() {
        let sentence = "People were laid off; employers lay off workers."
        let matches = VocabularyExampleHighlight.ranges(in: sentence, target: "lay off").map { String(sentence[$0]) }
        #expect(matches == ["laid off", "lay off"])
        #expect(VocabularyExampleHighlight.ranges(in: sentence, target: "  ").isEmpty)
    }
}
