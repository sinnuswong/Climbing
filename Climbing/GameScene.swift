import Foundation
import RealityKit
import simd
import UIKit

final class GameScene {
    let arView: ARView

    private let rootAnchor = AnchorEntity()
    private let blockSize: Float = 1.0
    private let capThickness: Float = 0.12
    private let playerHeight: Float = 0.6
    private let topLift: Float = 0.01

    private var level: Level?
    private var tileEntities: [VoxelPoint: ModelEntity] = [:]
    private var highlighted: [VoxelPoint] = []
    private var playerEntity: ModelEntity?
    private var goalEntity: Entity?
    private var mapOffset = SIMD3<Float>(0, 0, 0)
    private var deadEndPoints: Set<VoxelPoint> = []

    private var blockMaterial: UnlitMaterial
    private var topMaterial: UnlitMaterial
    private var highlightMaterial: UnlitMaterial
    private var playerMaterial: UnlitMaterial
    private var deadEndMaterial: UnlitMaterial

    let cameraController: CameraController

    init(arView: ARView) {
        self.arView = arView
        let lineColor = UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.95)
        blockMaterial = GameScene.makeGridMaterial(
            fill: UIColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1.0),
            line: lineColor
        )
        topMaterial = GameScene.makeGridMaterial(
            fill: UIColor(red: 0.42, green: 0.7, blue: 0.34, alpha: 1.0),
            line: lineColor
        )
        highlightMaterial = GameScene.makeGridMaterial(
            fill: UIColor(red: 0.98, green: 0.84, blue: 0.25, alpha: 1.0),
            line: lineColor
        )
        playerMaterial = UnlitMaterial(color: UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0))
        deadEndMaterial = GameScene.makeGridMaterial(
            fill: UIColor(red: 0.62, green: 0.2, blue: 0.85, alpha: 1.0),
            line: lineColor
        )
        arView.cameraMode = .nonAR
        arView.environment.background = .color(.init(red: 0.95, green: 0.93, blue: 0.85, alpha: 1.0))
        arView.scene.anchors.append(rootAnchor)
        cameraController = CameraController(arView: arView)
    }

    func build(level: Level, playerStart: VoxelPoint, goal: VoxelPoint, deadEnds: Set<VoxelPoint>) {
        self.level = level
        tileEntities.removeAll()
        highlighted.removeAll()
        rootAnchor.children.removeAll()
        goalEntity = nil
        deadEndPoints = deadEnds

        mapOffset = SIMD3<Float>(blockSize / 2.0, 0, blockSize / 2.0)

        let cubeMesh = MeshResource.generateBox(size: blockSize)
        let topMesh = MeshResource.generatePlane(width: blockSize, depth: blockSize)

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var maxY: Float = 0
        var hasBlocks = false

        for z in 0..<level.heightCount {
            for y in 0..<level.depth {
                for x in 0..<level.width {
                    guard level.isSolid(x: x, y: y, z: z) else { continue }
                    hasBlocks = true
                    let centerX = Float(x) * blockSize + mapOffset.x
                    let centerZ = Float(y) * blockSize + mapOffset.z
                    let half = blockSize / 2.0
                    minX = Swift.min(minX, centerX - half)
                    maxX = Swift.max(maxX, centerX + half)
                    minZ = Swift.min(minZ, centerZ - half)
                    maxZ = Swift.max(maxZ, centerZ + half)
                    maxY = Swift.max(maxY, (Float(z) + 1.0) * blockSize)

                    let yPosition = (Float(z) + 0.5) * blockSize
                    let position = SIMD3<Float>(centerX, yPosition, centerZ)
                    let block = ModelEntity(mesh: cubeMesh, materials: [blockMaterial])
                    block.position = position
                    rootAnchor.addChild(block)

                    guard level.isStandable(x: x, y: y, z: z) else { continue }
                    let topY = (Float(z) + 1.0) * blockSize + topLift
                    let topPosition = SIMD3<Float>(centerX, topY, centerZ)
                    let capMaterial = deadEndPoints.contains(VoxelPoint(x: x, y: y, z: z)) ? deadEndMaterial : topMaterial
                    let top = ModelEntity(mesh: topMesh, materials: [capMaterial])
                    top.position = topPosition
                    top.name = "tile_\(x)_\(y)_\(z)"
                    top.collision = CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(blockSize, capThickness, blockSize))])
                    top.physicsBody = PhysicsBodyComponent(mode: .static)
                    tileEntities[VoxelPoint(x: x, y: y, z: z)] = top
                    rootAnchor.addChild(top)
                }
            }
        }

        let playerMesh = MeshResource.generateSphere(radius: playerHeight * 0.35)
        let player = ModelEntity(mesh: playerMesh, materials: [playerMaterial])
        playerEntity = player
        rootAnchor.addChild(player)
        movePlayer(to: playerStart, animated: false)
        addGoalFlag(at: goal)

        let targetX = hasBlocks ? (minX + maxX) * 0.5 : 0
        let targetZ = hasBlocks ? (minZ + maxZ) * 0.5 : 0
        let targetHeight = maxY * 0.55 + 0.4
        let target = SIMD3<Float>(targetX, targetHeight, targetZ)
        let span = hasBlocks ? max(maxX - minX, maxZ - minZ) : max(Float(level.width), Float(level.depth))
        let distance = max(12.0, span * 2.0 + maxY)
        addTopLight(targetX: targetX, targetZ: targetZ, maxY: maxY, span: span)
        cameraController.reset(target: target, distance: distance, pitch: 0.85)
    }

    private func addGoalFlag(at goal: VoxelPoint) {
        let poleHeight = blockSize * 1.4
        let poleSize = SIMD3<Float>(0.08, poleHeight, 0.08)
        let poleMesh = MeshResource.generateBox(size: poleSize)
        let poleMaterial = UnlitMaterial(color: UIColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1.0))
        let pole = ModelEntity(mesh: poleMesh, materials: [poleMaterial])

        let flagSize = SIMD3<Float>(0.5, 0.28, 0.04)
        let flagMesh = MeshResource.generateBox(size: flagSize)
        let flagMaterial = UnlitMaterial(color: UIColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0))
        let flag = ModelEntity(mesh: flagMesh, materials: [flagMaterial])

        let baseY = (Float(goal.z) + 1.0) * blockSize
        let centerX = Float(goal.x) * blockSize + mapOffset.x
        let centerZ = Float(goal.y) * blockSize + mapOffset.z

        pole.position = SIMD3<Float>(centerX, baseY + poleHeight / 2.0, centerZ)
        flag.position = SIMD3<Float>(centerX + 0.28, baseY + poleHeight * 0.75, centerZ)

        let flagRoot = Entity()
        flagRoot.name = "tile_\(goal.x)_\(goal.y)_\(goal.z)"
        flagRoot.addChild(pole)
        flagRoot.addChild(flag)
        rootAnchor.addChild(flagRoot)
        goalEntity = flagRoot
    }

    func movePlayer(to point: VoxelPoint, animated: Bool) {
        guard let playerEntity else { return }

        let height = Float(point.z + 1)
        let position = SIMD3<Float>(
            Float(point.x) * blockSize + mapOffset.x,
            height * blockSize + playerHeight / 2.0,
            Float(point.y) * blockSize + mapOffset.z
        )
        var transform = playerEntity.transform
        transform.translation = position
        if animated {
            playerEntity.move(to: transform, relativeTo: rootAnchor, duration: 0.25, timingFunction: .easeInOut)
        } else {
            playerEntity.transform = transform
        }
    }

    func showPath(_ path: [VoxelPoint]) {
        clearHighlights()
        highlighted = path
        for point in path {
            guard let tile = tileEntities[point] else { continue }
            updateMaterial(of: tile, material: highlightMaterial)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.clearHighlights()
        }
    }

    func clearHighlights() {
        for point in highlighted {
            guard let tile = tileEntities[point] else { continue }
            let baseMaterial = deadEndPoints.contains(point) ? deadEndMaterial : topMaterial
            updateMaterial(of: tile, material: baseMaterial)
        }
        highlighted.removeAll()
    }

    func resetCamera() {
        cameraController.reset()
    }

    private func updateMaterial(of entity: ModelEntity, material: UnlitMaterial) {
        if var model = entity.model {
            model.materials = [material]
            entity.model = model
        }
    }

    private func addTopLight(targetX: Float, targetZ: Float, maxY: Float, span: Float) {
        let light = DirectionalLight()
        light.light.intensity = 35000
        light.light.color = .white
        let height = maxY + span * 1.2 + 6.0
        let position = SIMD3<Float>(targetX, height, targetZ)
        light.position = position
        light.look(at: SIMD3<Float>(targetX, 0, targetZ), from: position, relativeTo: nil)
        rootAnchor.addChild(light)
    }

    private static func makeGridMaterial(fill: UIColor,
                                         line: UIColor,
                                         size: Int = 96,
                                         lineWidth: Int = 2) -> UnlitMaterial {
        var material = UnlitMaterial(color: .white)
        guard let cgImage = makeGridImage(fill: fill, line: line, size: size, lineWidth: lineWidth),
              let texture = try? TextureResource.generate(from: cgImage, withName: nil, options: .init(semantic: .color)) else {
            material.baseColor = .color(fill)
            return material
        }
        material.baseColor = .texture(texture)
        return material
    }

    private static func makeGridImage(fill: UIColor,
                                      line: UIColor,
                                      size: Int,
                                      lineWidth: Int) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            fill.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let strokeWidth = CGFloat(max(1, lineWidth))
            let inset = strokeWidth / 2.0
            context.cgContext.setStrokeColor(line.cgColor)
            context.cgContext.setLineWidth(strokeWidth)
            context.cgContext.stroke(CGRect(x: inset, y: inset, width: CGFloat(size) - strokeWidth, height: CGFloat(size) - strokeWidth))
        }
        return image.cgImage
    }
}

final class CameraController {
    private weak var arView: ARView?

    private(set) var target = SIMD3<Float>(0, 0, 0)
    private var yaw: Float = .pi / 4.0
    private var pitch: Float = 0.65
    private var distance: Float = 12.0
    private var homeYaw: Float = .pi / 4.0
    private var homePitch: Float = 0.65
    private var homeDistance: Float = 12.0
    private var homeTarget = SIMD3<Float>(0, 0, 0)

    private let minPitch: Float = 0.25
    private let maxPitch: Float = 1.25
    private let minDistance: Float = 6.0
    private let maxDistance: Float = 24.0

    init(arView: ARView) {
        self.arView = arView
    }

    func reset(target: SIMD3<Float>? = nil, distance: Float? = nil, pitch: Float? = nil, yaw: Float? = nil) {
        if let target {
            homeTarget = target
        }
        if let distance {
            homeDistance = clamp(distance, min: minDistance, max: maxDistance * 1.4)
        }
        if let pitch {
            homePitch = clamp(pitch, min: minPitch, max: maxPitch)
        }
        if let yaw {
            homeYaw = yaw
        }
        self.target = homeTarget
        self.distance = homeDistance
        self.yaw = homeYaw
        self.pitch = homePitch
        apply()
    }

    func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let translation = gesture.translation(in: view)
        yaw -= Float(translation.x) * 0.005
        pitch -= Float(translation.y) * 0.005
        pitch = clamp(pitch, min: minPitch, max: maxPitch)
        gesture.setTranslation(.zero, in: view)
        apply()
    }

    func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        let scale = Float(gesture.scale)
        distance = clamp(distance / scale, min: minDistance, max: maxDistance)
        gesture.scale = 1.0
        apply()
    }

    private func apply() {
        guard let arView else { return }
        let x = target.x + distance * cos(pitch) * sin(yaw)
        let y = target.y + distance * sin(pitch)
        let z = target.z + distance * cos(pitch) * cos(yaw)
        let position = SIMD3<Float>(x, y, z)
        let camera = arView.scene.__defaultCamera
        camera?.look(at: target, from: position, relativeTo: nil)
    }

    private func clamp(_ value: Float, min: Float, max: Float) -> Float {
        Swift.max(min, Swift.min(max, value))
    }
}
