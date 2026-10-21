import Foundation
import Testing
@testable import Omninary

struct LearningGridLayoutTests {
    @Test
    func fourSmallWidgetsShareOneRow() {
        var items: [LearningWidgetPlacement] = []
        for id in ["a", "b", "c", "d"] {
            items = LearningGridLayout.add(id, size: .oneByOne, to: items)
        }
        #expect(items.map(\.column) == [0, 1, 2, 3])
        #expect(items.allSatisfy { $0.row == 0 })
    }

    @Test
    func movingIntoAnotherWidgetPushesItForward() {
        let first = LearningWidgetPlacement(widgetID: "a", size: .twoByTwo, column: 0, row: 0)
        let second = LearningWidgetPlacement(widgetID: "b", size: .twoByTwo, column: 2, row: 0)
        let moved = LearningGridLayout.place(first.id, column: 2, row: 0, in: [first, second])
        #expect(moved[0].column == 2 && moved[0].row == 0)
        #expect(moved[1].column == 0 && moved[1].row == 0)
    }

    @Test
    func resizingToFullWidthPushesFollowingWidgetsDown() {
        let first = LearningWidgetPlacement(widgetID: "a", size: .twoByTwo, column: 0, row: 0)
        let second = LearningWidgetPlacement(widgetID: "b", size: .twoByTwo, column: 2, row: 0)
        let resized = LearningGridLayout.place(first.id, size: .fourByTwo, in: [first, second])
        #expect(resized[0].column == 0 && resized[0].row == 0)
        #expect(resized[1].row >= 2)
    }

    @Test
    func normalizingSavedOverlapMovesSecondWidget() {
        let first = LearningWidgetPlacement(widgetID: "a", size: .fourByFour, column: 0, row: 0)
        let second = LearningWidgetPlacement(widgetID: "b", size: .oneByOne, column: 1, row: 1)
        let normalized = LearningGridLayout.normalize([first, second])
        #expect(normalized[1].row >= 4)
    }

    @Test
    func sameProgramCannotBeAddedTwice() {
        let first = LearningGridLayout.add("vocabulary", size: .oneByOne, to: [])
        let both = LearningGridLayout.add("vocabulary", size: .oneByOne, to: first)
        #expect(both == first)
    }

    @Test
    func previouslySavedDuplicateKeepsFirstCard() throws {
        let first = LearningWidgetPlacement(widgetID: "vocabulary", size: .twoByTwo, column: 0, row: 0)
        let duplicate = LearningWidgetPlacement(widgetID: "vocabulary", size: .fourByTwo, column: 0, row: 2)
        let restored = try JSONDecoder().decode([LearningWidgetPlacement].self, from: JSONEncoder().encode([first, duplicate]))
        let normalized = LearningGridLayout.normalize(restored)
        #expect(normalized == [first])
    }

    @Test
    func olderSavedLayoutWithoutInstanceIDsIsKept() throws {
        let oldLayout = Data("[{\"widgetID\":\"vocabulary\",\"size\":\"oneByOne\",\"column\":0,\"row\":0},{\"widgetID\":\"vocabulary\",\"size\":\"oneByOne\",\"column\":1,\"row\":0}]".utf8)
        let restored = try JSONDecoder().decode([LearningWidgetPlacement].self, from: oldLayout)
        #expect(restored.count == 2)
        #expect(LearningGridLayout.normalize(restored).count == 1)
    }
}
