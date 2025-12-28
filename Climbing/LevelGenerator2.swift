import Foundation

struct LevelGenerator2Config: Hashable, Codable {
    var width: Int
    var depth: Int
    var height: Int
    var steps: Int
    var mainRouteCount: Int
    var deadEndCount: Int
    var deadEndMinLength: Int
    var deadEndMaxLength: Int
    var fillChance: Double
    var heightFalloff: Double
    var pairChance: Double
    var seed: UInt64
    var maxAttempts: Int

    static let `default` = LevelGenerator2Config(
        width: 9,
        depth: 9,
        height: 8,
        steps: 10,
        mainRouteCount: 2,
        deadEndCount: 4,
        deadEndMinLength: 2,
        deadEndMaxLength: 5,
        fillChance: 0.14,
        heightFalloff: 0.5,
        pairChance: 0.6,
        seed: 2048,
        maxAttempts: 2500
    )
}

struct LevelGenerator2Result {
    let level: Level
    let sequence: [Int]
}

struct LevelGenerator2DebugResult {
    let level: Level
    let sequence: [Int]
    let deadEndPaths: [[VoxelPoint]]
}

enum LevelGenerator2 {
    private struct DeadEndBranch {
        let points: [VoxelPoint]
        let blocker: VoxelPoint?
        let kind: DeadEndKind
    }

    private enum DeadEndKind {
        case blockedMain
        case branch
    }

    static func generateLevels(count: Int, config: LevelGenerator2Config) -> [Level] {
        guard count > 0 else { return [] }
        var levels: [Level] = []
        levels.reserveCapacity(count)
        for index in 0..<count {
            let seed = config.seed &+ UInt64(index) &* 9973
            let level = generateLevel(id: index + 1, config: config, seed: seed)
            levels.append(level)
        }
        return levels
    }

    static func generateLevel(id: Int, config: LevelGenerator2Config, seed: UInt64? = nil) -> Level {
        generateLevelWithSequence(id: id, config: config, seed: seed).level
    }

    static func generateLevelWithSequence(id: Int,
                                          config: LevelGenerator2Config,
                                          seed: UInt64? = nil) -> LevelGenerator2Result {
        let result = generateLevelWithDebug(id: id, config: config, seed: seed)
        return LevelGenerator2Result(level: result.level, sequence: result.sequence)
    }

    static func generateLevelWithDebug(id: Int,
                                       config: LevelGenerator2Config,
                                       seed: UInt64? = nil) -> LevelGenerator2DebugResult {
        var rng = SeededGenerator(seed: seed ?? config.seed)
        let width = max(3, config.width)
        let depth = max(3, config.depth)
        let height = max(2, config.height)
        let maxSteps = max(1, min(config.steps, width * depth - 1))

        for _ in 0..<max(10, config.maxAttempts) {
            let start = randomStart(width: width, depth: depth, rng: &rng)
            guard let pathData = generatePathSequence(steps: maxSteps,
                                                      start: start,
                                                      width: width,
                                                      depth: depth,
                                                      height: height,
                                                      rng: &rng) else {
                continue
            }

            let build = buildLevelWithDeadEnds(id: id,
                                               width: width,
                                               depth: depth,
                                               height: height,
                                               start: start,
                                               path: pathData.path,
                                               config: config,
                                               rng: &rng)
            let level = build.level
            let goal = level.goal(from: start)
            if let shortest = shortestPathLength(level: level, start: start, goal: goal),
               shortest >= maxSteps {
                let sequence = pathData.sequence.map { $0.code }
                let deadEndPaths = build.deadEnds
                    .filter { $0.kind == .blockedMain }
                    .map { $0.points }
                return LevelGenerator2DebugResult(level: level,
                                                  sequence: sequence,
                                                  deadEndPaths: deadEndPaths)
            }
        }

        return LevelGenerator2DebugResult(level: Level.sample(),
                                          sequence: [],
                                          deadEndPaths: [])
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

    static func generateLevelFromSequence(id: Int,
                                          config: LevelGenerator2Config,
                                          sequence: [Int],
                                          seed: UInt64? = nil,
                                          enforceUniquePredecessor: Bool = true,
                                          autoExpand: Bool = false) -> Level? {
        generateLevelFromSequenceDebug(id: id,
                                       config: config,
                                       sequence: sequence,
                                       seed: seed,
                                       enforceUniquePredecessor: enforceUniquePredecessor,
                                       autoExpand: autoExpand)?.level
    }

    static func generateLevelFromSequenceDebug(id: Int,
                                               config: LevelGenerator2Config,
                                               sequence: [Int],
                                               seed: UInt64? = nil,
                                               enforceUniquePredecessor: Bool = true,
                                               autoExpand: Bool = false) -> LevelGenerator2DebugResult? {
        var width = max(3, config.width)
        var depth = max(3, config.depth)
        var height = max(2, config.height)
        guard let relativePath = relativePathFromSequence(sequence: sequence,
                                                          enforceUniquePredecessor: enforceUniquePredecessor) else {
            print(" 1111")
            return nil
        }
        if autoExpand, let bounds = pathBounds(relativePath) {
            let requiredWidth = bounds.maxX - bounds.minX + 1
            let requiredDepth = bounds.maxY - bounds.minY + 1
            let requiredHeight = bounds.maxZ - bounds.minZ + 1
            width = max(width, requiredWidth)
            depth = max(depth, requiredDepth)
            height = max(height, requiredHeight)
        }
        var startRng = SeededGenerator(seed: seed ?? config.seed)
        guard let start = startForSequence(path: relativePath,
                                           width: width,
                                           depth: depth,
                                           height: height,
                                           rng: &startRng) else {
            print(" 11112")

            return nil
        }
        let path = offsetPath(relativePath, by: start)

        let attemptCount = max(1, config.maxAttempts)
        for attempt in 0..<attemptCount {
            print("try \(attempt)")
            var rng = SeededGenerator(seed: (seed ?? config.seed) &+ UInt64(attempt) &* 9973)
            let build = buildLevelWithDeadEnds(id: id,
                                               width: width,
                                               depth: depth,
                                               height: height,
                                               start: start,
                                               path: path,
                                               config: config,
                                               rng: &rng)
            let level = build.level
            let goal = build.level.goal(from: start)
            if let shortest = shortestPathLength(level: level, start: start, goal: goal),
               shortest >= sequence.count-5 {
                let deadEndPaths = build.deadEnds
                    .filter { $0.kind == .blockedMain }
                    .map { $0.points }
                return LevelGenerator2DebugResult(level: level,
                                                  sequence: sequence,
                                                  deadEndPaths: deadEndPaths)
            }

        }
        print(" 11113")

        return nil
    }

    static func vectorTuples(for sequence: [Int]) -> [(Int, Int, Int)] {
        sequence.compactMap { code in
            guard let vector = stepVector(for: code) else { return nil }
            return (vector.dx, vector.dy, vector.dz)
        }
    }

    static func requiredSize(forSequence sequence: [Int],
                             enforceUniquePredecessor: Bool = true) -> (width: Int, depth: Int, height: Int)? {
        guard let path = relativePathFromSequence(sequence: sequence,
                                                  enforceUniquePredecessor: enforceUniquePredecessor),
              let bounds = pathBounds(path) else {
            return nil
        }
        let width = bounds.maxX - bounds.minX + 1
        let depth = bounds.maxY - bounds.minY + 1
        let height = bounds.maxZ - bounds.minZ + 1
        return (width, depth, height)
    }

    static func sequence(fromVectors vectors: [(Int, Int, Int)]) -> [Int]? {
        var codes: [Int] = []
        codes.reserveCapacity(vectors.count)
        for vector in vectors {
            let key = VectorKey(dx: vector.0, dy: vector.1, dz: vector.2)
            guard let code = vectorCodeByKey[key] else { return nil }
            codes.append(code)
        }
        return codes
    }

    private struct StepVector: Hashable {
        let dx: Int
        let dy: Int
        let dz: Int
        let code: Int
    }

    private struct VectorKey: Hashable {
        let dx: Int
        let dy: Int
        let dz: Int
    }

    private static let vectorTable: [StepVector] = {
        let dzOptions = [0, 1, -1, -2]
        var vectors: [StepVector] = []
        vectors.reserveCapacity(16)
        var code = 0
        for axis in 0..<2 {
            for sign in [-1, 1] {
                for dz in dzOptions {
                    let dx = axis == 0 ? sign : 0
                    let dy = axis == 1 ? sign : 0
                    vectors.append(StepVector(dx: dx, dy: dy, dz: dz, code: code))
                    code += 1
                }
            }
        }
        return vectors
    }()

    private static let vectorCodeByKey: [VectorKey: Int] = {
        var table: [VectorKey: Int] = [:]
        for vector in vectorTable {
            table[VectorKey(dx: vector.dx, dy: vector.dy, dz: vector.dz)] = vector.code
        }
        return table
    }()

    private static let allowedDz: Set<Int> = {
        Set(vectorTable.map { $0.dz })
    }()

    private static func stepVector(for code: Int) -> StepVector? {
        guard code >= 0 && code < vectorTable.count else { return nil }
        return vectorTable[code]
    }

    private static func gridDelta(for vector: StepVector) -> (dx: Int, dy: Int, dz: Int) {
        (dx: vector.dx, dy: -vector.dy, dz: vector.dz)
    }

    private static func generatePathSequence(steps: Int,
                                             start: VoxelPoint,
                                             width: Int,
                                             depth: Int,
                                             height: Int,
                                             rng: inout SeededGenerator) -> (sequence: [StepVector], path: [VoxelPoint])? {
        let vectors = vectorTable

        var sequence: [StepVector] = []
        sequence.reserveCapacity(steps)
        var path: [VoxelPoint] = [start]
        var usedColumns: [GridPoint: Int] = [GridPoint(x: start.x, y: start.y): start.z]
        var current = start
        let targetHeight = min(height - 1, max(2, min(steps, height - 1)))

        for stepIndex in 0..<steps {
            var candidates: [(StepVector, VoxelPoint, GridPoint)] = []
            candidates.reserveCapacity(16)
            for vector in vectors {
                let delta = gridDelta(for: vector)
                let nx = current.x + delta.dx
                let ny = current.y + delta.dy
                let nz = current.z + delta.dz
                if nx < 0 || nx >= width || ny < 0 || ny >= depth { continue }
                if nz < 0 || nz > targetHeight { continue }
                let column = GridPoint(x: nx, y: ny)
                if usedColumns[column] != nil { continue }
                if hasAlternatePredecessor(column,
                                           used: usedColumns,
                                           current: GridPoint(x: current.x, y: current.y),
                                           candidateZ: nz) {
                    continue
                }
                let remaining = steps - stepIndex - 1
                let minHeight = max(0, targetHeight - remaining)
                let maxHeight = remaining == 0 ? targetHeight : targetHeight - 1
                if nz < minHeight || nz > maxHeight { continue }
                candidates.append((vector, VoxelPoint(x: nx, y: ny, z: nz), column))
            }

            guard let choice = candidates.randomElement(using: &rng) else { return nil }
            sequence.append(choice.0)
            path.append(choice.1)
            usedColumns[choice.2] = choice.1.z
            current = choice.1
        }

        return (sequence, path)
    }

    private static func relativePathFromSequence(sequence: [Int],
                                                 enforceUniquePredecessor: Bool) -> [VoxelPoint]? {
        guard !sequence.isEmpty else { return nil }
        var path: [VoxelPoint] = [VoxelPoint(x: 0, y: 0, z: 0)]
        var usedColumns: [GridPoint: Int] = [GridPoint(x: 0, y: 0): 0]
        var current = path[0]

        for code in sequence {
            guard let vector = stepVector(for: code) else { return nil }
            let delta = gridDelta(for: vector)
            let nx = current.x + delta.dx
            let ny = current.y + delta.dy
            let nz = current.z + delta.dz
            let column = GridPoint(x: nx, y: ny)
            if usedColumns[column] != nil {
                print("fucked 1112")
                return nil }
            if enforceUniquePredecessor {
                if hasAlternatePredecessor(column,
                                           used: usedColumns,
                                           current: GridPoint(x: current.x, y: current.y),
                                           candidateZ: nz) {
                    print("fucked 11123")
                    return nil
                }
            }
            let next = VoxelPoint(x: nx, y: ny, z: nz)
            path.append(next)
            usedColumns[column] = nz
            current = next
        }

        return path
    }

    private static func startForSequence(path: [VoxelPoint],
                                         width: Int,
                                         depth: Int,
                                         height: Int,
                                         rng: inout SeededGenerator) -> VoxelPoint? {
        guard let bounds = pathBounds(path) else { return nil }
        let minX = bounds.minX
        let maxX = bounds.maxX
        let minY = bounds.minY
        let maxY = bounds.maxY
        let minZ = bounds.minZ
        let maxZ = bounds.maxZ

        let startXMin = -minX
        let startXMax = width - 1 - maxX
        let startYMin = -minY
        let startYMax = depth - 1 - maxY
        let startZMin = -minZ
        let startZMax = height - 1 - maxZ
        guard startXMin <= startXMax,
              startYMin <= startYMax,
              startZMin <= startZMax else {
            return nil
        }

        let startX = randomInRange(startXMin...startXMax, rng: &rng)
        let startY = randomInRange(startYMin...startYMax, rng: &rng)
        let startZ = (startZMin...startZMax).contains(0)
            ? 0
            : randomInRange(startZMin...startZMax, rng: &rng)
        return VoxelPoint(x: startX, y: startY, z: startZ)
    }

    private static func offsetPath(_ path: [VoxelPoint], by start: VoxelPoint) -> [VoxelPoint] {
        path.map { point in
            VoxelPoint(x: point.x + start.x, y: point.y + start.y, z: point.z + start.z)
        }
    }

    private static func pathBounds(_ path: [VoxelPoint]) -> (minX: Int, maxX: Int, minY: Int, maxY: Int, minZ: Int, maxZ: Int)? {
        guard let first = path.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        var minZ = first.z
        var maxZ = first.z

        for point in path.dropFirst() {
            minX = Swift.min(minX, point.x)
            maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y)
            maxY = Swift.max(maxY, point.y)
            minZ = Swift.min(minZ, point.z)
            maxZ = Swift.max(maxZ, point.z)
        }

        return (minX, maxX, minY, maxY, minZ, maxZ)
    }

    private static func randomStart(width: Int, depth: Int, rng: inout SeededGenerator) -> VoxelPoint {
        VoxelPoint(x: rng.nextInt(width), y: rng.nextInt(depth), z: 0)
    }

    private static func randomInRange(_ range: ClosedRange<Int>, rng: inout SeededGenerator) -> Int {
        let count = range.upperBound - range.lowerBound + 1
        return range.lowerBound + rng.nextInt(count)
    }

    private static func buildLevelWithDeadEnds(id: Int,
                                               width: Int,
                                               depth: Int,
                                               height: Int,
                                               start: VoxelPoint,
                                               path: [VoxelPoint],
                                               config: LevelGenerator2Config,
                                               rng: inout SeededGenerator) -> (level: Level, deadEnds: [DeadEndBranch]) {
        let pathColumns = Set(path.map { GridPoint(x: $0.x, y: $0.y) })
        var layers = Array(
            repeating: Array(repeating: Array(repeating: 0, count: width), count: depth),
            count: height
        )
        var protectedAbove = Set<VoxelPoint>()

        for point in path {
            for supportZ in 0...point.z {
                layers[supportZ][point.y][point.x] = 1
            }
            if point.z + 1 < height {
                protectedAbove.insert(VoxelPoint(x: point.x, y: point.y, z: point.z + 1))
            }
        }

        let deadEnds = generateDeadEnds(path: path,
                                        width: width,
                                        depth: depth,
                                        height: height,
                                        config: config,
                                        rng: &rng)
        let blockedColumns = buildBlockedColumns(pathColumns: pathColumns,
                                                 deadEnds: deadEnds,
                                                 width: width,
                                                 depth: depth)
        for deadEnd in deadEnds {
            for point in deadEnd.points {
                for supportZ in 0...point.z {
                    layers[supportZ][point.y][point.x] = 1
                }
                if point.z + 1 < height {
                    protectedAbove.insert(VoxelPoint(x: point.x, y: point.y, z: point.z + 1))
                }
            }
            if let blocker = deadEnd.blocker {
                for supportZ in 0...blocker.z {
                    layers[supportZ][blocker.y][blocker.x] = 1
                }
                if blocker.z + 1 < height {
                    protectedAbove.insert(VoxelPoint(x: blocker.x, y: blocker.y, z: blocker.z + 1))
                }
            }
        }

        let fillChance = clamp(config.fillChance, min: 0.0, max: 0.45)
        let heightFalloff = clamp(config.heightFalloff, min: 0.0, max: 0.85)
        let pairChance = clamp(config.pairChance, min: 0.0, max: 0.9)
        for z in 0..<height {
            let heightFactor = 1.0 - (Double(z) / Double(max(height - 1, 1))) * heightFalloff
            let target = Int(Double(width * depth) * fillChance * max(0.1, heightFactor))
            var placed = countLayer(layers: layers, z: z)
            let attemptLimit = max(width * depth * 6, target * 10)
            for _ in 0..<attemptLimit {
                if placed >= target { break }
                if rng.nextDouble() < pairChance && target - placed > 1 {
                    if placePair(layers: &layers,
                                 width: width,
                                 depth: depth,
                                 z: z,
                                 protectedAbove: protectedAbove,
                                 blockedColumns: blockedColumns,
                                 rng: &rng) {
                        placed += 2
                        continue
                    }
                }
                if placeSingle(layers: &layers,
                               width: width,
                               depth: depth,
                               z: z,
                               protectedAbove: protectedAbove,
                               blockedColumns: blockedColumns,
                               rng: &rng) {
                    placed += 1
                }
            }
        }

        let level = Level(id: id, width: width, depth: depth, height: height, start: start, layers: layers)
        return (level, deadEnds)
    }

    private static func buildLevel(id: Int,
                                   width: Int,
                                   depth: Int,
                                   height: Int,
                                   start: VoxelPoint,
                                   path: [VoxelPoint],
                                   config: LevelGenerator2Config,
                                   rng: inout SeededGenerator) -> Level {
        buildLevelWithDeadEnds(id: id,
                               width: width,
                               depth: depth,
                               height: height,
                               start: start,
                               path: path,
                               config: config,
                               rng: &rng).level
    }

    private static func generateDeadEnds(path: [VoxelPoint],
                                         width: Int,
                                         depth: Int,
                                         height: Int,
                                         config: LevelGenerator2Config,
                                         rng: inout SeededGenerator) -> [DeadEndBranch] {
        let blockedMainCount = max(0, config.mainRouteCount - 1)
        let branchCount = max(0, config.deadEndCount)
        let count = blockedMainCount + branchCount
        guard count > 0, path.count > 2 else { return [] }
        let minLength = max(1, config.deadEndMinLength)
        let maxLength = max(minLength, config.deadEndMaxLength)
        let pathColumns = Set(path.map { GridPoint(x: $0.x, y: $0.y) })
        var reserved = pathColumns
        var deadEnds: [DeadEndBranch] = []
        let goal = path.last ?? path[0]
        var kinds: [DeadEndKind] = []
        if blockedMainCount > 0 {
            kinds.append(contentsOf: Array(repeating: .blockedMain, count: blockedMainCount))
        }
        if branchCount > 0 {
            kinds.append(contentsOf: Array(repeating: .branch, count: branchCount))
        }
        kinds.shuffle(using: &rng)

        for kind in kinds {
            var created = false
            for _ in 0..<80 {
                let startUpperBound: Int
                if kind == .blockedMain {
                    startUpperBound = max(1, (path.count - 2) / 3)
                } else {
                    startUpperBound = max(1, path.count - 2)
                }
                let startIndex: Int
                if kind == .blockedMain {
                    startIndex = rng.nextInt(startUpperBound + 1)
                } else {
                    startIndex = 1 + rng.nextInt(startUpperBound)
                }
                let start = path[startIndex]
                let length: Int
                if kind == .blockedMain {
                    length = maxLength
                } else {
                    length = minLength + rng.nextInt(maxLength - minLength + 1)
                }
                let target = kind == .blockedMain ? goal : nil

                guard let branch = generateBranch(from: start,
                                                  length: length,
                                                  pathColumns: pathColumns,
                                                  reserved: reserved,
                                                  width: width,
                                                  depth: depth,
                                                  height: height,
                                                  rng: &rng,
                                                  target: target) else {
                    continue
                }

                let branchData: (points: [VoxelPoint], blocker: VoxelPoint?)?
                if kind == .blockedMain {
                    branchData = splitBranchForBlocker(branch,
                                                       height: height,
                                                       rng: &rng)
                } else {
                    branchData = (branch, nil)
                }
                guard let branchData else { continue }
                let blocker = branchData.blocker
                if kind == .blockedMain && blocker == nil { continue }
                deadEnds.append(DeadEndBranch(points: branchData.points,
                                              blocker: blocker,
                                              kind: kind))
                for point in branchData.points {
                    reserved.insert(GridPoint(x: point.x, y: point.y))
                }
                if let blocker = blocker {
                    reserved.insert(GridPoint(x: blocker.x, y: blocker.y))
                }
                created = true
                break
            }
            if !created { continue }
        }

        return deadEnds
    }

    private static func generateBranch(from start: VoxelPoint,
                                       length: Int,
                                       pathColumns: Set<GridPoint>,
                                       reserved: Set<GridPoint>,
                                       width: Int,
                                       depth: Int,
                                       height: Int,
                                       rng: inout SeededGenerator,
                                       target: VoxelPoint?) -> [VoxelPoint]? {
        guard length > 0 else { return nil }
        let startColumn = GridPoint(x: start.x, y: start.y)
        var branch: [VoxelPoint] = []
        var usedColumns = reserved
        var current = start

        for stepIndex in 0..<length {
            var candidates: [VoxelPoint] = []
            candidates.reserveCapacity(16)
            for vector in vectorTable {
                let delta = gridDelta(for: vector)
                let nx = current.x + delta.dx
                let ny = current.y + delta.dy
                let nz = current.z + delta.dz
                if nx < 0 || nx >= width || ny < 0 || ny >= depth { continue }
                if nz < 0 || nz >= height { continue }
                let column = GridPoint(x: nx, y: ny)
                if usedColumns.contains(column) { continue }
                let excludes = stepIndex == 0 ? startColumn : nil
                if hasAdjacentPathColumn(column,
                                         pathColumns: pathColumns,
                                         width: width,
                                         depth: depth,
                                         excluding: excludes) {
                    continue
                }
                candidates.append(VoxelPoint(x: nx, y: ny, z: nz))
            }

            guard !candidates.isEmpty else { return nil }
            let next: VoxelPoint
            if let target = target {
                let bestDistance = candidates
                    .map { manhattanDistance($0, target) }
                    .min() ?? 0
                let best = candidates.filter { manhattanDistance($0, target) == bestDistance }
                next = best.randomElement(using: &rng) ?? candidates[0]
            } else {
                next = candidates.randomElement(using: &rng) ?? candidates[0]
            }

            branch.append(next)
            usedColumns.insert(GridPoint(x: next.x, y: next.y))
            current = next
        }

        return branch
    }

    private static func splitBranchForBlocker(_ branch: [VoxelPoint],
                                              height: Int,
                                              rng: inout SeededGenerator) -> (points: [VoxelPoint], blocker: VoxelPoint?)? {
        guard branch.count >= 2 else { return nil }
        let cutMax = branch.count - 2
        let cutIndex: Int
        if cutMax >= 1 {
            cutIndex = 1 + rng.nextInt(cutMax)
        } else {
            cutIndex = 0
        }
        let end = branch[cutIndex]
        let blockedColumn = branch[cutIndex + 1]
        let blockerZ = end.z + 2
        if blockerZ >= height { return nil }
        let blocker = VoxelPoint(x: blockedColumn.x, y: blockedColumn.y, z: blockerZ)
        let points = Array(branch.prefix(cutIndex + 1))
        return (points, blocker)
    }

    

    private static func buildBlockedColumns(pathColumns: Set<GridPoint>,
                                            deadEnds: [DeadEndBranch],
                                            width: Int,
                                            depth: Int) -> Set<GridPoint> {
        var blocked = Set<GridPoint>()
        let pathBuffer = expandColumns(pathColumns, width: width, depth: depth, distance: 1)
        blocked.formUnion(pathBuffer)
        for deadEnd in deadEnds {
            var columns = Set(deadEnd.points.map { GridPoint(x: $0.x, y: $0.y) })
            if let blocker = deadEnd.blocker {
                columns.insert(GridPoint(x: blocker.x, y: blocker.y))
            }
            let buffer = expandColumns(columns, width: width, depth: depth, distance: 1)
            blocked.formUnion(buffer)
        }
        return blocked
    }

    private static func expandColumns(_ columns: Set<GridPoint>,
                                      width: Int,
                                      depth: Int,
                                      distance: Int) -> Set<GridPoint> {
        guard distance > 0 else { return columns }
        var expanded = Set<GridPoint>()
        for point in columns {
            for dx in -distance...distance {
                for dy in -distance...distance {
                    if abs(dx) + abs(dy) > distance { continue }
                    let nx = point.x + dx
                    let ny = point.y + dy
                    if nx < 0 || nx >= width || ny < 0 || ny >= depth { continue }
                    expanded.insert(GridPoint(x: nx, y: ny))
                }
            }
        }
        return expanded
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
                                    blockedColumns: Set<GridPoint>,
                                    rng: inout SeededGenerator) -> Bool {
        let x = rng.nextInt(width)
        let y = rng.nextInt(depth)
        if blockedColumns.contains(GridPoint(x: x, y: y)) { return false }
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
                                  blockedColumns: Set<GridPoint>,
                                  rng: inout SeededGenerator) -> Bool {
        let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let dir = directions[rng.nextInt(directions.count)]
        let x = rng.nextInt(width)
        let y = rng.nextInt(depth)
        let nx = x + dir.0
        let ny = y + dir.1
        if nx < 0 || nx >= width || ny < 0 || ny >= depth { return false }
        if blockedColumns.contains(GridPoint(x: x, y: y)) { return false }
        if blockedColumns.contains(GridPoint(x: nx, y: ny)) { return false }
        if layers[z][y][x] != 0 || layers[z][ny][nx] != 0 { return false }
        if protectedAbove.contains(VoxelPoint(x: x, y: y, z: z)) { return false }
        if protectedAbove.contains(VoxelPoint(x: nx, y: ny, z: z)) { return false }
        let supportA = isSupported(layers: layers, x: x, y: y, z: z)
        let supportB = isSupported(layers: layers, x: nx, y: ny, z: z)
        if supportA == supportB { return false }
        layers[z][y][x] = 1
        layers[z][ny][nx] = 1
        return true
    }

    private static func isSupported(layers: [[[Int]]], x: Int, y: Int, z: Int) -> Bool {
        if z == 0 { return true }
        return layers[z - 1][y][x] != 0
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

    private static func hasAdjacentPathColumn(_ column: GridPoint,
                                              pathColumns: Set<GridPoint>,
                                              width: Int,
                                              depth: Int,
                                              excluding: GridPoint?) -> Bool {
        let neighbors = neighborPoints(of: column, width: width, depth: depth)
        for neighbor in neighbors {
            if let excluding, neighbor == excluding { continue }
            if pathColumns.contains(neighbor) { return true }
        }
        return false
    }

    private static func manhattanDistance(_ a: VoxelPoint, _ b: VoxelPoint) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)
    }

    private static func hasAlternatePredecessor(_ column: GridPoint,
                                                used: [GridPoint: Int],
                                                current: GridPoint,
                                                candidateZ: Int) -> Bool {
//        let neighbors = [
//            GridPoint(x: column.x + 1, y: column.y),
//            GridPoint(x: column.x - 1, y: column.y),
//            GridPoint(x: column.x, y: column.y + 1),
//            GridPoint(x: column.x, y: column.y - 1),
//        ]
//        for neighbor in neighbors {
//            if neighbor == current { continue }
//            if let neighborHeight = used[neighbor] {
//                let dz = candidateZ - neighborHeight
//                if allowedDz.contains(dz) { return true }
//            }
//        }
        return false
    }

    private static func shortestPathLength(level: Level,
                                           start: VoxelPoint,
                                           goal: VoxelPoint) -> Int? {
        var queue: [VoxelPoint] = [start]
        var distances: [VoxelPoint: Int] = [start: 0]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            if current == goal {
                return distances[current]
            }

            let columns = [
                GridPoint(x: current.x + 1, y: current.y),
                GridPoint(x: current.x - 1, y: current.y),
                GridPoint(x: current.x, y: current.y + 1),
                GridPoint(x: current.x, y: current.y - 1),
            ]
            for column in columns {
                guard column.x >= 0, column.x < level.width,
                      column.y >= 0, column.y < level.depth else {
                    continue
                }
                guard let landingHeight = level.landingHeight(from: current, to: column) else { continue }
                let next = VoxelPoint(x: column.x, y: column.y, z: landingHeight)
                if distances[next] != nil { continue }
                distances[next] = (distances[current] ?? 0) + 1
                queue.append(next)
            }
        }

        return nil
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
