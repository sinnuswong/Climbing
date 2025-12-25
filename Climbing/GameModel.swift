import Foundation

struct GridPoint: Hashable, Codable {
    let x: Int
    let y: Int
}

struct Level: Codable, Identifiable {
    let id: Int
    let width: Int
    let depth: Int
    let start: GridPoint
    let heights: [[Int]]
}

extension Level {
    func height(at point: GridPoint) -> Int {
        guard point.y >= 0, point.y < heights.count else { return 0 }
        let row = heights[point.y]
        guard point.x >= 0, point.x < row.count else { return 0 }
        return row[point.x]
    }

    var maxHeight: Int {
        heights.flatMap { $0 }.max() ?? 0
    }
}

enum LevelLoader {
    static func loadLevels() -> [Level] {
        guard let url = Bundle.main.url(forResource: "levels", withExtension: "json") else {
            return [Level.sample()]
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Level].self, from: data)
        } catch {
            return [Level.sample()]
        }
    }
}

extension Level {
    static func sample() -> Level {
        let heights = [
            [1, 1, 2, 2, 2],
            [1, 2, 2, 3, 2],
            [1, 2, 3, 3, 2],
            [1, 2, 3, 4, 2],
            [1, 1, 2, 2, 2],
        ]
        return Level(
            id: 1,
            width: 5,
            depth: 5,
            start: GridPoint(x: 0, y: 4),
            heights: heights
        )
    }
}
//好球 - 羽毛球运动AI教练｜附近球搭子｜约球