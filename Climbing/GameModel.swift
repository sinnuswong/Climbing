import Foundation

struct GridPoint: Hashable, Codable {
    let x: Int
    let y: Int
}

struct VoxelPoint: Hashable, Codable {
    let x: Int
    let y: Int
    let z: Int
}

struct Level: Codable, Identifiable {
    let id: Int
    let width: Int
    let depth: Int
    let height: Int
    let start: VoxelPoint
    let layers: [[[Int]]]
}

extension Level {
    var heightCount: Int {
        max(height, layers.count)
    }

    func isSolid(x: Int, y: Int, z: Int) -> Bool {
        guard x >= 0, x < width,
              y >= 0, y < depth,
              z >= 0, z < heightCount else {
            return false
        }
        guard z < layers.count,
              y < layers[z].count,
              x < layers[z][y].count else {
            return false
        }
        return layers[z][y][x] != 0
    }

    func isSolid(at point: VoxelPoint) -> Bool {
        isSolid(x: point.x, y: point.y, z: point.z)
    }

    func isStandable(x: Int, y: Int, z: Int) -> Bool {
        isSolid(x: x, y: y, z: z) && !isSolid(x: x, y: y, z: z + 1)
    }

    func standHeights(at column: GridPoint) -> [Int] {
        guard column.x >= 0, column.x < width,
              column.y >= 0, column.y < depth else {
            return []
        }
        var heights: [Int] = []
        heights.reserveCapacity(heightCount)
        for z in 0..<heightCount {
            if isStandable(x: column.x, y: column.y, z: z) {
                heights.append(z)
            }
        }
        return heights
    }

    func landingHeight(from current: VoxelPoint, to column: GridPoint) -> Int? {
        let heights = standHeights(at: column)
        guard !heights.isEmpty else { return nil }
        let climbCandidates = heights.filter { $0 - current.z <= 1 }
        if let highest = climbCandidates.max() {
            return highest
        }
        let dropCandidates = heights.filter { $0 < current.z }
        return dropCandidates.max()
    }

    func goal(from start: VoxelPoint) -> VoxelPoint {
        var queue: [VoxelPoint] = [start]
        var visited: Set<VoxelPoint> = [start]
        var index = 0
        var best = start
        var bestHeight = start.z
        var bestDistance = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            let distance = abs(current.x - start.x) + abs(current.y - start.y)
            if current.z > bestHeight
                || (current.z == bestHeight && distance > bestDistance)
                || (current.z == bestHeight && distance == bestDistance && (current.y < best.y || (current.y == best.y && current.x < best.x))) {
                best = current
                bestHeight = current.z
                bestDistance = distance
            }

            let columns = [
                GridPoint(x: current.x + 1, y: current.y),
                GridPoint(x: current.x - 1, y: current.y),
                GridPoint(x: current.x, y: current.y + 1),
                GridPoint(x: current.x, y: current.y - 1),
            ]
            for column in columns {
                guard column.x >= 0, column.x < width,
                      column.y >= 0, column.y < depth else {
                    continue
                }
                guard let landingHeight = landingHeight(from: current, to: column) else { continue }
                let next = VoxelPoint(x: column.x, y: column.y, z: landingHeight)
                if visited.contains(next) { continue }
                visited.insert(next)
                queue.append(next)
            }
        }

        return best
    }

    var maxStandHeight: Int {
        var maxHeight = 0
        for z in 0..<heightCount {
            for y in 0..<depth {
                for x in 0..<width {
                    if isStandable(x: x, y: y, z: z) {
                        maxHeight = max(maxHeight, z)
                    }
                }
            }
        }
        return maxHeight
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
        let layers = [
            [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [1, 1, 0, 0, 0],
            ],
            [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 1, 1, 0],
            ],
            [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 1, 0, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 0],
            ],
            [
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 0],
                [0, 0, 0, 0, 0],
            ],
        ]
        return Level(
            id: 1,
            width: 5,
            depth: 5,
            height: 4,
            start: VoxelPoint(x: 0, y: 4, z: 0),
            layers: layers
        )
    }
}
//好球 - 羽毛球运动AI教练｜附近球搭子｜约球
