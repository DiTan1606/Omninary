import Foundation

enum LearningWidgetSize: String, Codable, CaseIterable, Identifiable {
    case oneByOne, twoByTwo, fourByTwo, fourByFour

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .oneByOne: 1
        case .twoByTwo: 2
        case .fourByTwo, .fourByFour: 4
        }
    }

    var rows: Int {
        switch self {
        case .oneByOne: 1
        case .twoByTwo, .fourByTwo: 2
        case .fourByFour: 4
        }
    }

    var title: String {
        switch self {
        case .oneByOne: "1×1"
        case .twoByTwo: "2×2"
        case .fourByTwo: "4×2"
        case .fourByFour: "4×4"
        }
    }

    var icon: String {
        switch self {
        case .oneByOne: "square"
        case .twoByTwo: "square.grid.2x2"
        case .fourByTwo: "rectangle.grid.1x2"
        case .fourByFour: "square.grid.2x2.fill"
        }
    }
}

struct LearningWidgetPlacement: Codable, Identifiable, Equatable {
    let id: UUID
    let widgetID: String
    var size: LearningWidgetSize
    var column: Int
    var row: Int

    init(id: UUID = UUID(), widgetID: String, size: LearningWidgetSize, column: Int, row: Int) {
        self.id = id
        self.widgetID = widgetID
        self.size = size
        self.column = column
        self.row = row
    }

    private enum CodingKeys: String, CodingKey {
        case id, widgetID, size, column, row
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        widgetID = try values.decode(String.self, forKey: .widgetID)
        size = try values.decode(LearningWidgetSize.self, forKey: .size)
        column = try values.decode(Int.self, forKey: .column)
        row = try values.decode(Int.self, forKey: .row)
    }
}

enum LearningGridLayout {
    static let columns = 4

    static func add(_ widgetID: String, size: LearningWidgetSize, to items: [LearningWidgetPlacement]) -> [LearningWidgetPlacement] {
        guard !items.contains(where: { $0.widgetID == widgetID }) else { return items }
        let occupied = occupiedCells(items)
        let position = firstFree(size: size, from: 0, occupied: occupied)
        return items + [LearningWidgetPlacement(widgetID: widgetID, size: size, column: position.column, row: position.row)]
    }

    static func place(_ id: UUID, size: LearningWidgetSize? = nil, column: Int? = nil, row: Int? = nil, in items: [LearningWidgetPlacement]) -> [LearningWidgetPlacement] {
        guard let current = items.first(where: { $0.id == id }) else { return items }
        let newSize = size ?? current.size
        let target = LearningWidgetPlacement(
            id: id,
            widgetID: current.widgetID,
            size: newSize,
            column: min(max(column ?? current.column, 0), columns - newSize.columns),
            row: max(row ?? current.row, 0)
        )

        var occupied = occupiedCells([target])
        var results: [UUID: LearningWidgetPlacement] = [id: target]
        let remaining = items.enumerated()
            .filter { $0.element.id != id }
            .sorted {
                let lhs = ($0.element.row, $0.element.column, $0.offset)
                let rhs = ($1.element.row, $1.element.column, $1.offset)
                return lhs < rhs
            }

        for (_, item) in remaining {
            let position = fits(item.size, atColumn: item.column, row: item.row, occupied: occupied)
                ? (column: item.column, row: item.row)
                : firstFree(size: item.size, from: 0, occupied: occupied)
            var placed = item
            placed.column = position.column
            placed.row = position.row
            results[item.id] = placed
            occupied.formUnion(cells(for: placed))
        }
        return items.compactMap { results[$0.id] }
    }

    static func normalize(_ items: [LearningWidgetPlacement]) -> [LearningWidgetPlacement] {
        var result: [LearningWidgetPlacement] = []
        for item in items where !result.contains(where: { $0.widgetID == item.widgetID }) {
            let safeColumn = min(max(item.column, 0), columns - item.size.columns)
            let safeRow = max(item.row, 0)
            let occupied = occupiedCells(result)
            let position = fits(item.size, atColumn: safeColumn, row: safeRow, occupied: occupied)
                ? (column: safeColumn, row: safeRow)
                : firstFree(size: item.size, from: safeRow * columns + safeColumn, occupied: occupied)
            result.append(LearningWidgetPlacement(id: item.id, widgetID: item.widgetID, size: item.size, column: position.column, row: position.row))
        }
        return result
    }

    private static func firstFree(size: LearningWidgetSize, from index: Int, occupied: Set<Int>) -> (column: Int, row: Int) {
        var index = max(0, index)
        while true {
            let column = index % columns
            let row = index / columns
            if fits(size, atColumn: column, row: row, occupied: occupied) {
                return (column, row)
            }
            index += 1
        }
    }

    private static func fits(_ size: LearningWidgetSize, atColumn column: Int, row: Int, occupied: Set<Int>) -> Bool {
        guard column >= 0, row >= 0, column + size.columns <= columns else { return false }
        for y in row..<(row + size.rows) {
            for x in column..<(column + size.columns) where occupied.contains(y * columns + x) {
                return false
            }
        }
        return true
    }

    private static func occupiedCells(_ items: [LearningWidgetPlacement]) -> Set<Int> {
        Set(items.flatMap(cells(for:)))
    }

    private static func cells(for item: LearningWidgetPlacement) -> [Int] {
        (item.row..<(item.row + item.size.rows)).flatMap { row in
            (item.column..<(item.column + item.size.columns)).map { row * columns + $0 }
        }
    }
}
