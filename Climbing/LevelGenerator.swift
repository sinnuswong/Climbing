import Foundation

struct LevelGeneratorConfig: Hashable {
    var width: Int
    var depth: Int
    var height: Int
    var fillChance: Double
    var heightFalloff: Double
    var pairChance: Double
    var pathLengthFactor: Double
    var avoidEdgeBias: Double
    var turnBias: Double
    var seed: UInt64
    var maxAttempts: Int

    static let `default` = LevelGeneratorConfig(
        width: 9,
        depth: 9,
        height: 8,
        fillChance: 0.16,
        heightFalloff: 0.45,
        pairChance: 0.6,
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
        let height = max(2, config.height)
        let startColumn = GridPoint(x: 0, y: depth - 1)
        let start = VoxelPoint(x: startColumn.x, y: startColumn.y, z: 0)
        let targetHeight = height - 1
        let minPathLength = max(
            Int(Double(width * depth) * clamp(config.pathLengthFactor, min: 0.2, max: 0.9)),
            targetHeight + 1
        )

        for _ in 0..<max(10, config.maxAttempts) {
            guard let path = generatePath(
                width: width,
                depth: depth,
                start: startColumn,
                minLength: minPathLength,
                config: config,
                rng: &rng
            ) else {
                continue
            }

            guard let pathHeights = buildPathHeights(
                stepCount: path.count,
                maxHeight: targetHeight,
                rng: &rng
            ) else {
                continue
            }

            var layers = Array(
                repeating: Array(repeating: Array(repeating: 0, count: width), count: depth),
                count: height
            )
            var protectedAbove = Set<VoxelPoint>()
            for (index, point) in path.enumerated() {
                let z = pathHeights[index]
                for supportZ in 0...z {
                    layers[supportZ][point.y][point.x] = 1
                }
                if z + 1 < height {
                    protectedAbove.insert(VoxelPoint(x: point.x, y: point.y, z: z + 1))
                }
            }

            let fillChance = clamp(config.fillChance, min: 0.0, max: 0.45)
            let heightFalloff = clamp(config.heightFalloff, min: 0.0, max: 0.85)
            let pairChance = clamp(config.pairChance, min: 0.0, max: 0.9)
            for z in 0..<height {
                let heightFactor = 1.0 - (Double(z) / Double(max(height - 1, 1))) * heightFalloff
                let additionalTarget = Int(Double(width * depth) * fillChance * max(0.1, heightFactor))
                let existing = countLayer(layers: layers, z: z)
                var remaining = min(additionalTarget, width * depth - existing)
                let attemptLimit = max(width * depth * 6, remaining * 10)
                for _ in 0..<attemptLimit {
                    if remaining <= 0 { break }
                    if rng.nextDouble() < pairChance && remaining > 1 {
                        if placePair(layers: &layers,
                                     width: width,
                                     depth: depth,
                                     z: z,
                                     protectedAbove: protectedAbove,
                                     rng: &rng) {
                            remaining -= 2
                            continue
                        }
                    }
                    if placeSingle(layers: &layers,
                                   width: width,
                                   depth: depth,
                                   z: z,
                                   protectedAbove: protectedAbove,
                                   rng: &rng) {
                        remaining -= 1
                    }
                }
            }

            enforceFloatingAdjacency(layers: &layers, width: width, depth: depth, height: height, maxDistance: 2)

            let level = Level(id: id, width: width, depth: depth, height: height, start: start, layers: layers)
            if isReachable(level: level, targetHeight: targetHeight) {
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
        let incrementsNeeded = maxHeight
        let stepSlots = stepCount - 1
        guard stepSlots >= incrementsNeeded else { return nil }

        var steps = Array(repeating: 0, count: stepSlots)
        var indices = Array(0..<stepSlots)
        shuffle(&indices, rng: &rng)
        for index in 0..<incrementsNeeded {
            steps[indices[index]] = 1
        }

        var heights = Array(repeating: 0, count: stepCount)
        heights[0] = 0
        for index in 1..<stepCount {
            heights[index] = heights[index - 1] + steps[index - 1]
        }
        return heights
    }

    private static func isReachable(level: Level, targetHeight: Int) -> Bool {
        var queue: [VoxelPoint] = [level.start]
        var visited: Set<VoxelPoint> = [level.start]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            if current.z == targetHeight {
                return true
            }

            for neighbor in neighbors(of: current, level: level) {
                if visited.contains(neighbor) { continue }
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }

        return false
    }

    private static func neighbors(of point: VoxelPoint, level: Level) -> [VoxelPoint] {
        let columns = [
            GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x - 1, y: point.y),
            GridPoint(x: point.x, y: point.y + 1),
            GridPoint(x: point.x, y: point.y - 1),
        ]
        var results: [VoxelPoint] = []
        results.reserveCapacity(columns.count)
        for column in columns {
            guard column.x >= 0, column.x < level.width,
                  column.y >= 0, column.y < level.depth else { continue }
            guard let landingHeight = level.landingHeight(from: point, to: column) else { continue }
            results.append(VoxelPoint(x: column.x, y: column.y, z: landingHeight))
        }
        return results
    }

    private static func countLayer(layers: [[[Int]]], z: Int) -> Int {
        guard z >= 0, z < layers.count else { return 0 }
        var count = 0
        for row in layers[z] {
            for value in row where value != 0 {
                count += 1
            }
        }
        return count
    }

    private static func placeSingle(layers: inout [[[Int]]],
                                    width: Int,
                                    depth: Int,
                                    z: Int,
                                    protectedAbove: Set<VoxelPoint>,
                                    rng: inout SeededGenerator) -> Bool {
        let x = rng.nextInt(width)
        let y = rng.nextInt(depth)
        if layers[z][y][x] != 0 { return false }
        if protectedAbove.contains(VoxelPoint(x: x, y: y, z: z)) { return false }
        if !isSupported(layers: layers, x: x, y: y, z: z) { return false }
        layers[z][y][x] = 1
        return true
    }

    private static func placePair(layers: inout [[[Int]]],
                                  width: Int,
                                  depth: Int,
                                  z: Int,
                                  protectedAbove: Set<VoxelPoint>,
                                  rng: inout SeededGenerator) -> Bool {
        let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let dir = directions[rng.nextInt(directions.count)]
        let x = rng.nextInt(width)
        let y = rng.nextInt(depth)
        let nx = x + dir.0
        let ny = y + dir.1
        if nx < 0 || nx >= width || ny < 0 || ny >= depth { return false }
        if layers[z][y][x] != 0 || layers[z][ny][nx] != 0 { return false }
        if protectedAbove.contains(VoxelPoint(x: x, y: y, z: z)) { return false }
        if protectedAbove.contains(VoxelPoint(x: nx, y: ny, z: z)) { return false }
        let supportA = isSupported(layers: layers, x: x, y: y, z: z)
        let supportB = isSupported(layers: layers, x: nx, y: ny, z: z)
        if !supportA && !supportB { return false }
        layers[z][y][x] = 1
        layers[z][ny][nx] = 1
        return true
    }

    private static func isSupported(layers: [[[Int]]], x: Int, y: Int, z: Int) -> Bool {
        if z == 0 { return true }
        return layers[z - 1][y][x] != 0
    }

    private static func enforceFloatingAdjacency(layers: inout [[[Int]]],
                                                 width: Int,
                                                 depth: Int,
                                                 height: Int,
                                                 maxDistance: Int) {
        guard height > 1 else { return }
        for z in 1..<height {
            var anchored = Array(repeating: Array(repeating: false, count: width), count: depth)
            for y in 0..<depth {
                for x in 0..<width {
                    if layers[z][y][x] != 0 && layers[z - 1][y][x] != 0 {
                        anchored[y][x] = true
                    }
                }
            }

            for y in 0..<depth {
                for x in 0..<width {
                    if layers[z][y][x] == 0 { continue }
                    if layers[z - 1][y][x] != 0 { continue }
                    if hasAnchoredNeighbor(x: x, y: y, anchored: anchored, maxDistance: maxDistance) {
                        continue
                    }
                    for supportZ in 0..<z {
                        layers[supportZ][y][x] = 1
                    }
                    anchored[y][x] = true
                }
            }
        }
    }

    private static func hasAnchoredNeighbor(x: Int,
                                            y: Int,
                                            anchored: [[Bool]],
                                            maxDistance: Int) -> Bool {
        let depth = anchored.count
        guard depth > 0 else { return false }
        let width = anchored[0].count
        for dx in -maxDistance...maxDistance {
            for dy in -maxDistance...maxDistance {
                if abs(dx) + abs(dy) > maxDistance { continue }
                let nx = x + dx
                let ny = y + dy
                if nx < 0 || nx >= width || ny < 0 || ny >= depth { continue }
                if anchored[ny][nx] { return true }
            }
        }
        return false
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
