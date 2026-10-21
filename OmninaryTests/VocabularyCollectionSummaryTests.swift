import Testing
@testable import Omninary

struct VocabularyCollectionSummaryTests {
    @Test func countsLearningItemsIndependentlyAndNormalizesMetadata() {
        let first = Vocabulary(catalog_id: "bank-finance", vocab: "bank", CEFR: " a1 ", learning_level: 1)
        let second = Vocabulary(catalog_id: "bank-river", vocab: "bank", CEFR: "A2", learning_level: 6)
        let third = Vocabulary(catalog_id: "bank-verb", vocab: "bank", CEFR: "c2", learning_level: 10)
        let summary = VocabularyCollectionSummary(vocabularies: [first, second, third, first])
        #expect(summary.total == 3)
        #expect(summary.cefrCounts == ["A1": 1, "A2": 1, "C2": 1])
        #expect(summary.learningLevelCounts == [1: 1, 6: 1, 7: 1])
        #expect(summary.unclassifiedLevelCount == 0)
        #expect(summary.unlearnedCount == 0)
    }

    @Test func unknownAndMissingMetadataRemainAccountedFor() {
        let items = [
            Vocabulary(catalog_id: "one", CEFR: "B1", learning_level: 0),
            Vocabulary(catalog_id: "two", CEFR: "unknown", learning_level: -1),
            Vocabulary(catalog_id: "three")
        ]
        let summary = VocabularyCollectionSummary(vocabularies: items)
        #expect(summary.unclassifiedLevelCount == 2)
        #expect(summary.unlearnedCount == 2)
        #expect(summary.cefrCounts.values.reduce(0, +) + summary.unclassifiedLevelCount == summary.total)
        #expect(summary.learningLevelCounts.values.reduce(0, +) + summary.unlearnedCount == summary.total)
        #expect(summary.learningTotal == 1)
        let empty = VocabularyCollectionSummary(vocabularies: [])
        #expect(empty.total == 0)
        #expect(empty.cefrCounts.isEmpty)
        #expect(empty.learningLevelCounts.isEmpty)
        #expect(empty.learningTotal == 0)
    }

    @Test func learningDistributionMatchesTheEightDashboardBuckets() {
        let items = (0...10).map { level in
            Vocabulary(catalog_id: "level-\(level)", learning_level: level)
        } + [Vocabulary(catalog_id: "new"), Vocabulary(catalog_id: "negative", learning_level: -1)]
        let summary = VocabularyCollectionSummary(vocabularies: items)
        let dashboard = LearningSessionBuilder.build(from: items)

        #expect(summary.learningLevelCounts == dashboard.statsByLevel)
        #expect(summary.learningTotal == dashboard.totalLearningWords)
        #expect(summary.learningLevelCounts[6] == 4)
        #expect(summary.learningLevelCounts[7] == 1)
        #expect(summary.unlearnedCount == 2)
        #expect(VocabularyCollectionSummary.learningBuckets.map(VocabularyCollectionSummary.learningTitle)
            == ["Cấp 0", "Cấp 1", "Cấp 2", "Cấp 3", "Cấp 4", "Cấp 5", "Master", "Super"])
    }
}
