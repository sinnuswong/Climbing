import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var levelIndex: Int = 0
    @Published private(set) var level: Level
    @Published private(set) var playerPosition: VoxelPoint
    @Published private(set) var goalPosition: VoxelPoint
    @Published private(set) var steps: Int = 0
    @Published private(set) var currentHeight: Int = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var isAutoRunning: Bool = false
    @Published var showWinAlert: Bool = false

    private let levels: [Level]
    private var hintTask: Task<Void, Never>?
    private var customLevel: Level?
    private var isCustomLevel: Bool = false

    var onMovePlayer: ((VoxelPoint, Bool) -> Void)?
    var onShowPath: (([VoxelPoint]) -> Void)?
    var onClearPath: (() -> Void)?
    var onResetCamera: (() -> Void)?
    var onLoadLevel: ((Level, VoxelPoint, VoxelPoint) -> Void)?

    init() {
        let loadedLevels = LevelLoader.loadLevels()
        let initialLevel = loadedLevels.first ?? Level.sample()
        levels = loadedLevels
        level = initialLevel
        playerPosition = initialLevel.start
        goalPosition = initialLevel.goal(from: initialLevel.start)
        currentHeight = initialLevel.start.z
    }

    func connectScene(load: @escaping (Level, VoxelPoint, VoxelPoint) -> Void,
                      move: @escaping (VoxelPoint, Bool) -> Void,
                      showPath: @escaping ([VoxelPoint]) -> Void,
                      clearPath: @escaping () -> Void,
                      resetCamera: @escaping () -> Void) {
        onLoadLevel = load
        onMovePlayer = move
        onShowPath = showPath
        onClearPath = clearPath
        onResetCamera = resetCamera

        load(level, playerPosition, goalPosition)
    }

    func handleTap(at point: VoxelPoint) {
        guard !isAutoRunning else { return }
        movePlayerIfPossible(to: point, animated: true)
    }

    func showHint() {
        statusMessage = nil
        guard let path = findPath(from: playerPosition) else {
            statusMessage = "No path to the flag"
            return
        }
        onShowPath?(path)
    }

    func startAuto() {
        guard !isAutoRunning else { return }
        statusMessage = nil
        guard let path = findPath(from: playerPosition) else {
            statusMessage = "No path to the flag"
            return
        }

        isAutoRunning = true
        onShowPath?(path)
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            for step in path.dropFirst() {
                movePlayerIfPossible(to: step, animated: true)
                try? await Task.sleep(for: .milliseconds(350))
            }
            isAutoRunning = false
        }
    }

    func resetCamera() {
        onResetCamera?()
    }

    func advanceLevel() {
        if isCustomLevel, let customLevel {
            applyLevel(customLevel, index: 0, custom: true)
            return
        }
        guard !levels.isEmpty else { return }
        let nextIndex = (levelIndex + 1) % levels.count
        loadLevel(at: nextIndex)
    }

    func dismissWinAlert() {
        showWinAlert = false
    }

    func loadCustomLevel(_ level: Level) {
        customLevel = level
        applyLevel(level, index: 0, custom: true)
    }

    private func movePlayerIfPossible(to target: VoxelPoint, animated: Bool) {
        guard isLegalMove(from: playerPosition, to: target) else { return }
        onClearPath?()
        playerPosition = target
        steps += 1
        currentHeight = playerPosition.z
        onMovePlayer?(playerPosition, animated)
        checkWin()
    }

    private func isLegalMove(from: VoxelPoint, to: VoxelPoint) -> Bool {
        let dx = abs(from.x - to.x)
        let dy = abs(from.y - to.y)
        guard dx + dy == 1 else { return false }
        let column = GridPoint(x: to.x, y: to.y)
        guard let landingHeight = level.landingHeight(from: from, to: column) else {
            return false
        }
        return landingHeight == to.z
    }

    private func checkWin() {
        if playerPosition == goalPosition, !showWinAlert {
            statusMessage = "Reached the flag!"
            showWinAlert = true
            isAutoRunning = false
            hintTask?.cancel()
        }
    }

    private func loadLevel(at index: Int) {
        guard index >= 0, index < levels.count else { return }
        applyLevel(levels[index], index: index, custom: false)
    }

    private func applyLevel(_ newLevel: Level, index: Int, custom: Bool) {
        hintTask?.cancel()
        showWinAlert = false
        isAutoRunning = false
        steps = 0
        statusMessage = nil
        isCustomLevel = custom
        levelIndex = index
        level = newLevel
        playerPosition = newLevel.start
        goalPosition = newLevel.goal(from: newLevel.start)
        currentHeight = newLevel.start.z
        onLoadLevel?(newLevel, playerPosition, goalPosition)
    }

    private func findPath(from start: VoxelPoint) -> [VoxelPoint]? {
        let target = goalPosition
        var queue: [VoxelPoint] = [start]
        var visited = Set([start])
        var parent: [VoxelPoint: VoxelPoint] = [:]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            if current == target {
                return buildPath(from: current, parent: parent, start: start)
            }

            for neighbor in neighbors(of: current) {
                if visited.contains(neighbor) { continue }
                visited.insert(neighbor)
                parent[neighbor] = current
                queue.append(neighbor)
            }
        }

        return nil
    }

    private func neighbors(of point: VoxelPoint) -> [VoxelPoint] {
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

    private func buildPath(from end: VoxelPoint, parent: [VoxelPoint: VoxelPoint], start: VoxelPoint) -> [VoxelPoint] {
        var path = [end]
        var current = end
        while current != start {
            guard let next = parent[current] else { break }
            current = next
            path.append(current)
        }
        return path.reversed()
    }
}
