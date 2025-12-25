import Foundation

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var levelIndex: Int = 0
    @Published private(set) var level: Level
    @Published private(set) var playerPosition: GridPoint
    @Published private(set) var steps: Int = 0
    @Published private(set) var currentHeight: Int = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var isAutoRunning: Bool = false
    @Published var showWinAlert: Bool = false

    private let levels: [Level]
    private var hintTask: Task<Void, Never>?
    private var customLevel: Level?
    private var isCustomLevel: Bool = false

    var onMovePlayer: ((GridPoint, Bool) -> Void)?
    var onShowPath: (([GridPoint]) -> Void)?
    var onClearPath: (() -> Void)?
    var onResetCamera: (() -> Void)?
    var onLoadLevel: ((Level, GridPoint) -> Void)?

    init() {
        let loadedLevels = LevelLoader.loadLevels()
        let initialLevel = loadedLevels.first ?? Level.sample()
        levels = loadedLevels
        level = initialLevel
        playerPosition = initialLevel.start
        currentHeight = initialLevel.height(at: initialLevel.start)
    }

    func connectScene(load: @escaping (Level, GridPoint) -> Void,
                      move: @escaping (GridPoint, Bool) -> Void,
                      showPath: @escaping ([GridPoint]) -> Void,
                      clearPath: @escaping () -> Void,
                      resetCamera: @escaping () -> Void) {
        onLoadLevel = load
        onMovePlayer = move
        onShowPath = showPath
        onClearPath = clearPath
        onResetCamera = resetCamera

        load(level, playerPosition)
    }

    func handleTap(at point: GridPoint) {
        guard !isAutoRunning else { return }
        movePlayerIfPossible(to: point, animated: true)
    }

    func showHint() {
        statusMessage = nil
        guard let path = findPath(from: playerPosition) else {
            statusMessage = "No path"
            return
        }
        onShowPath?(path)
    }

    func startAuto() {
        guard !isAutoRunning else { return }
        statusMessage = nil
        guard let path = findPath(from: playerPosition) else {
            statusMessage = "No path"
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

    private func movePlayerIfPossible(to target: GridPoint, animated: Bool) {
        guard isLegalMove(from: playerPosition, to: target) else { return }
        onClearPath?()
        playerPosition = target
        steps += 1
        currentHeight = level.height(at: playerPosition)
        onMovePlayer?(playerPosition, animated)
        checkWin()
    }

    private func isLegalMove(from: GridPoint, to: GridPoint) -> Bool {
        let dx = abs(from.x - to.x)
        let dy = abs(from.y - to.y)
        guard dx + dy == 1 else { return false }

        let fromHeight = level.height(at: from)
        let toHeight = level.height(at: to)
        guard toHeight > 0 else { return false }
        return (toHeight - fromHeight) <= 1
    }

    private func checkWin() {
        if currentHeight == level.maxHeight, !showWinAlert {
            statusMessage = "Reached the top!"
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
        currentHeight = newLevel.height(at: playerPosition)
        onLoadLevel?(newLevel, playerPosition)
    }

    private func findPath(from start: GridPoint) -> [GridPoint]? {
        let targetHeight = level.maxHeight
        var queue: [GridPoint] = [start]
        var visited = Set([start])
        var parent: [GridPoint: GridPoint] = [:]
        var index = 0

        while index < queue.count {
            let current = queue[index]
            index += 1

            if level.height(at: current) == targetHeight {
                return buildPath(from: current, parent: parent, start: start)
            }

            for neighbor in neighbors(of: current) {
                if visited.contains(neighbor) { continue }
                if isLegalMove(from: current, to: neighbor) {
                    visited.insert(neighbor)
                    parent[neighbor] = current
                    queue.append(neighbor)
                }
            }
        }

        return nil
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        [
            GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x - 1, y: point.y),
            GridPoint(x: point.x, y: point.y + 1),
            GridPoint(x: point.x, y: point.y - 1),
        ]
    }

    private func buildPath(from end: GridPoint, parent: [GridPoint: GridPoint], start: GridPoint) -> [GridPoint] {
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
