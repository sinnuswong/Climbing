import Foundation

struct LevelGeneratorConfig: Hashable {
    var width: Int
    var depth: Int
    var maxHeight: Int
    var holeChance: Double
    var pathLengthFactor: Double
    var avoidEdgeBias: Double
    var turnBias: Double
    var seed: UInt64
    var maxAttempts: Int

    static let `default` = LevelGeneratorConfig(
        width: 9,
        depth: 9,
        maxHeight: 8,
        holeChance: 0.25,
        pathLengthFactor: 0.65,
        avoidEdgeBias: 0.65,
        turnBias: 0.6,
        seed: 2025,
        maxAttempts: 300
    )
}

enum LevelGenerator {
    static func generateLevels(count: Int, config: LevelGeneratorConfig) -> [Level] {
        guard count > 0 else { return [] }
        var levels: [Level] = []
        levels.reserveCapacity(count)
        for index in 0..<count {
            let seed = config.seed &+ UInt64(index) &* 7919
            let level = generateLevel(id: index + 1, config: config, seed: seed)
            levels.append(level)
        }
        return levels
    }

    static func generateLevel(id: Int, config: LevelGeneratorConfig, seed: UInt64? = nil) -> Level {
        var rng = SeededGenerator(seed: seed ?? config.seed)
        let width = max(3, config.width)
        let depth = max(3, config.depth)
        let maxHeight = max(2, config.maxHeight)
        let start = GridPoint(x: 0, y: depth - 1)
        let minPathLength = max(Int(Double(width * depth) * clamp(config.pathLengthFactor, min: 0.2, max: 0.9)), maxHeight + 1)

        for _ in 0..<max(10, config.maxAttempts) {
            guard let path = generatePath(
                width: width,
                depth: depth,
                start: start,
                minLength: minPathLength,
                config: config,
                rng: &rng
            ) else {
                continue
            }

            guard let pathHeights = buildPathHeights(
                stepCount: path.count,
                maxHeight: maxHeight,
                rng: &rng
            ) else {
                continue
            }

            var grid = Array(repeating: Array(repeating: 0, count: width), count: depth)
            let pathSet = Set(path)
            for (index, point) in path.enumerated() {
                grid[point.y][point.x] = pathHeights[index]
            }

            let holeChance = clamp(config.holeChance, min: 0.0, max: 0.6)
            for y in 0..<depth {
                for x in 0..<width {
                    if pathSet.contains(GridPoint(x: x, y: y)) { continue }
                    if rng.nextDouble() < holeChance {
                        grid[y][x] = 0
                    } else {
                        let height = rng.nextInt(maxHeight - 1) + 1
                        grid[y][x] = min(height, maxHeight - 1)
                    }
                }
            }

            let level = Level(id: id, width: width, depth: depth, start: start, heights: grid)
            if isReachable(level: level, targetHeight: maxHeight) {
                return level
            }
        }

        return Level.sample()
    }

    static func encodeLevels(_ levels: [Level]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(levels),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func generatePath(width: Int,
                                     depth: Int,
                                     start: GridPoint,
                                     minLength: Int,
                                     config: LevelGeneratorConfig,
                                     rng: inout SeededGenerator) -> [GridPoint]? {
        let maxSteps = width * depth * 4
        let avoidEdgeBias = clamp(config.avoidEdgeBias, min: 0.0, max: 0.9)
        let turnBias = clamp(config.turnBias, min: 0.0, max: 0.9)

        for _ in 0..<max(80, config.maxAttempts / 2) {
            var path: [GridPoint] = [start]
            var visited: Set<GridPoint> = [start]
            var lastDirection: GridPoint?

            for _ in 0..<maxSteps {
                guard let current = path.last else { break }
                if path.count >= minLength, isInterior(current, width: width, depth: depth) {
                    return path
                }

                var neighbors = neighborPoints(of: current, width: width, depth: depth)
                    .filter { !visited.contains($0) }

                if neighbors.isEmpty { break }

                if path.count > 2 {
                    let interior = neighbors.filter { !isEdge($0, width: width, depth: depth) }
                    if !interior.isEmpty {
                        neighbors = interior
                    }
                }

                var weighted: [(GridPoint, Double)] = []
                weighted.reserveCapacity(neighbors.count)
                for neighbor in neighbors {
                    var weight = 1.0
                    if isEdge(neighbor, width: width, depth: depth) {
                        weight *= (1.0 - avoidEdgeBias)
                    } else if isNearEdge(neighbor, width: width, depth: depth) {
                        weight *= (1.0 - avoidEdgeBias * 0.5)
                    }

                    if let lastDirection {
                        let delta = GridPoint(x: neighbor.x - current.x, y: neighbor.y - current.y)
                        if delta.x == lastDirection.x && delta.y == lastDirection.y {
                            weight *= (1.0 - turnBias)
                        } else {
                            weight *= (1.0 + turnBias * 0.4)
                        }
                    }

                    weight = max(weight, 0.05)
                    weighted.append((neighbor, weight))
                }

                let next = chooseWeighted(weighted, rng: &rng)
                lastDirection = GridPoint(x: next.x - current.x, y: next.y - current.y)
                path.append(next)
                visited.insert(next)
            }
        }
        return nil
    }

    private static func buildPathHeights(stepCount: Int,
                                         maxHeight: Int,
                                         rng: inout SeededGenerator) -> [Int]? {
        guard stepCount > 0 else { return nil }
        let incrementsNeeded = maxHeight - 1
        let stepSlots = stepCount - 1
        guard stepSlots >= incrementsNeeded else { return nil }

        var steps = Array(repeating: 0, count: stepSlots)
        var indices = Array(0..<stepSlots)
        shuffle(&indices, rng: &rng)
        for index in 0..<incrementsNeeded {
            steps[indices[index]] = 1
        }

        var heights = Array(repeating: 0, count: stepCount)
        heights[0] = 1
        for index in 1..<stepCount {
            heights[index] = heights[index - 1] + steps[index - 1]
        }
        return heights
    }

    private static func isReachable(level: Level, targetHeight: Int) -> Bool {
        var queue: [GridPoint] = [level.start]
        var visited: Set<GridPoint> = [level.start]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            if level.height(at: current) == targetHeight {
                return true
            }

            for neighbor in neighborPoints(of: current, width: level.width, depth: level.depth) {
                if visited.contains(neighbor) { continue }
                if isLegalMove(level: level, from: current, to: neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
        }

        return false
    }

    private static func isLegalMove(level: Level, from: GridPoint, to: GridPoint) -> Bool {
        let fromHeight = level.height(at: from)
        let toHeight = level.height(at: to)
        guard toHeight > 0 else { return false }
        return (toHeight - fromHeight) <= 1
    }

    private static func neighborPoints(of point: GridPoint, width: Int, depth: Int) -> [GridPoint] {
        let candidates = [
            GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x - 1, y: point.y),
            GridPoint(x: point.x, y: point.y + 1),
            GridPoint(x: point.x, y: point.y - 1),
        ]
        return candidates.filter { $0.x >= 0 && $0.x < width && $0.y >= 0 && $0.y < depth }
    }

    private static func isEdge(_ point: GridPoint, width: Int, depth: Int) -> Bool {
        point.x == 0 || point.x == width - 1 || point.y == 0 || point.y == depth - 1
    }

    private static func isNearEdge(_ point: GridPoint, width: Int, depth: Int) -> Bool {
        point.x == 1 || point.x == width - 2 || point.y == 1 || point.y == depth - 2
    }

    private static func isInterior(_ point: GridPoint, width: Int, depth: Int) -> Bool {
        !isEdge(point, width: width, depth: depth)
    }

    private static func chooseWeighted<T>(_ items: [(T, Double)], rng: inout SeededGenerator) -> T {
        let total = items.reduce(0.0) { $0 + max(0.0, $1.1) }
        let pick = rng.nextDouble() * total
        var running = 0.0
        for (value, weight) in items {
            running += max(0.0, weight)
            if pick <= running { return value }
        }
        return items.last!.0
    }

    private static func shuffle<T>(_ array: inout [T], rng: inout SeededGenerator) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) {
            let swapIndex = rng.nextInt(index + 1)
            if swapIndex != index {
                array.swapAt(index, swapIndex)
            }
        }
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xCAFE_BABE : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    mutating func nextDouble() -> Double {
        Double(next()) / Double(UInt64.max)
    }
}
