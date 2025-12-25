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
    private let topLift: Float = 0.0
    private let edgeThickness: Float = 0.04
    private let edgeHeight: Float = 0.02
    private let edgeYOffset: Float = 0.004
    private let edgeOutset: Float = 0.004

    private var level: Level?
    private var tileEntities: [GridPoint: ModelEntity] = [:]
    private var highlighted: [GridPoint] = []
    private var playerEntity: ModelEntity?
    private var mapOffset = SIMD3<Float>(0, 0, 0)

    private let blockMaterial = UnlitMaterial(color: UIColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1.0))
    private let topMaterial = UnlitMaterial(color: UIColor(red: 0.42, green: 0.7, blue: 0.34, alpha: 1.0))
    private let highlightMaterial = UnlitMaterial(color: UIColor(red: 0.98, green: 0.84, blue: 0.25, alpha: 1.0))
    private let playerMaterial = UnlitMaterial(color: UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0))
    private let edgeMaterial = UnlitMaterial(color: UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.95))

    let cameraController: CameraController

    init(arView: ARView) {
        self.arView = arView
        arView.cameraMode = .nonAR
        arView.environment.background = .color(.init(red: 0.95, green: 0.93, blue: 0.85, alpha: 1.0))
        arView.scene.anchors.append(rootAnchor)
        cameraController = CameraController(arView: arView)
    }

    func build(level: Level, playerStart: GridPoint) {
        self.level = level
        tileEntities.removeAll()
        highlighted.removeAll()
        rootAnchor.children.removeAll()

        let mapWidth = Float(level.width - 1) * blockSize
        let mapDepth = Float(level.depth - 1) * blockSize
        mapOffset = SIMD3<Float>(-mapWidth / 2.0, 0, -mapDepth / 2.0)

        let cubeMesh = MeshResource.generateBox(size: blockSize)
        let topMesh = MeshResource.generateBox(size: SIMD3<Float>(blockSize, capThickness, blockSize))
        let edgeMeshX = MeshResource.generateBox(size: SIMD3<Float>(blockSize, edgeHeight, edgeThickness))
        let edgeMeshZ = MeshResource.generateBox(size: SIMD3<Float>(edgeThickness, edgeHeight, blockSize))
        let edgeMeshY = MeshResource.generateBox(size: SIMD3<Float>(edgeThickness, blockSize, edgeThickness))

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        var maxY: Float = 0
        var hasBlocks = false

        for y in 0..<level.depth {
            for x in 0..<level.width {
                let height = level.height(at: GridPoint(x: x, y: y))
                if height <= 0 { continue }
                hasBlocks = true
                let centerX = Float(x) * blockSize + mapOffset.x
                let centerZ = Float(y) * blockSize + mapOffset.z
                let half = blockSize / 2.0
                minX = Swift.min(minX, centerX - half)
                maxX = Swift.max(maxX, centerX + half)
                minZ = Swift.min(minZ, centerZ - half)
                maxZ = Swift.max(maxZ, centerZ + half)
                maxY = Swift.max(maxY, Float(height) * blockSize)

                for layer in 0..<height {
                    let yPosition = (Float(layer) + 0.5) * blockSize
                    let position = SIMD3<Float>(centerX, yPosition, centerZ)
                    let block = ModelEntity(mesh: cubeMesh, materials: [blockMaterial])
                    block.position = position
                    rootAnchor.addChild(block)

                    addCubeEdges(
                        centerX: centerX,
                        centerY: yPosition,
                        centerZ: centerZ,
                        edgeMeshX: edgeMeshX,
                        edgeMeshZ: edgeMeshZ,
                        edgeMeshY: edgeMeshY
                    )
                }

                let topY = Float(height) * blockSize - (capThickness / 2.0) + topLift
                let topPosition = SIMD3<Float>(centerX, topY, centerZ)
                let top = ModelEntity(mesh: topMesh, materials: [topMaterial])
                top.position = topPosition
                top.name = "tile_\(x)_\(y)"
                top.collision = CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(blockSize, capThickness, blockSize))])
                top.physicsBody = PhysicsBodyComponent(mode: .static)
                tileEntities[GridPoint(x: x, y: y)] = top
                rootAnchor.addChild(top)

            }
        }

        let playerMesh = MeshResource.generateSphere(radius: playerHeight * 0.35)
        let player = ModelEntity(mesh: playerMesh, materials: [playerMaterial])
        playerEntity = player
        rootAnchor.addChild(player)
        movePlayer(to: playerStart, animated: false)

        let targetX = hasBlocks ? (minX + maxX) * 0.5 : 0
        let targetZ = hasBlocks ? (minZ + maxZ) * 0.5 : 0
        let targetHeight = maxY * 0.55 + 0.4
        let target = SIMD3<Float>(targetX, targetHeight, targetZ)
        let span = hasBlocks ? max(maxX - minX, maxZ - minZ) : max(Float(level.width), Float(level.depth))
        let distance = max(12.0, span * 2.0 + maxY)
        addTopLight(targetX: targetX, targetZ: targetZ, maxY: maxY, span: span)
        cameraController.reset(target: target, distance: distance, pitch: 0.85)
    }

    func movePlayer(to point: GridPoint, animated: Bool) {
        guard let level else { return }
        guard let playerEntity else { return }

        let height = Float(level.height(at: point))
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

    func showPath(_ path: [GridPoint]) {
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
            updateMaterial(of: tile, material: topMaterial)
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

    private func addCubeEdges(centerX: Float,
                              centerY: Float,
                              centerZ: Float,
                              edgeMeshX: MeshResource,
                              edgeMeshZ: MeshResource,
                              edgeMeshY: MeshResource) {
        let half = blockSize / 2.0
        let topY = centerY + half + edgeYOffset
        let bottomY = centerY - half - edgeYOffset
        let xEdge = half + edgeOutset
        let zEdge = half + edgeOutset

        addEdge(mesh: edgeMeshX, position: SIMD3<Float>(centerX, topY, centerZ + zEdge))
        addEdge(mesh: edgeMeshX, position: SIMD3<Float>(centerX, topY, centerZ - zEdge))
        addEdge(mesh: edgeMeshZ, position: SIMD3<Float>(centerX + xEdge, topY, centerZ))
        addEdge(mesh: edgeMeshZ, position: SIMD3<Float>(centerX - xEdge, topY, centerZ))

        addEdge(mesh: edgeMeshX, position: SIMD3<Float>(centerX, bottomY, centerZ + zEdge))
        addEdge(mesh: edgeMeshX, position: SIMD3<Float>(centerX, bottomY, centerZ - zEdge))
        addEdge(mesh: edgeMeshZ, position: SIMD3<Float>(centerX + xEdge, bottomY, centerZ))
        addEdge(mesh: edgeMeshZ, position: SIMD3<Float>(centerX - xEdge, bottomY, centerZ))

        addEdge(mesh: edgeMeshY, position: SIMD3<Float>(centerX + xEdge, centerY, centerZ + zEdge))
        addEdge(mesh: edgeMeshY, position: SIMD3<Float>(centerX + xEdge, centerY, centerZ - zEdge))
        addEdge(mesh: edgeMeshY, position: SIMD3<Float>(centerX - xEdge, centerY, centerZ + zEdge))
        addEdge(mesh: edgeMeshY, position: SIMD3<Float>(centerX - xEdge, centerY, centerZ - zEdge))
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

    private func addEdge(mesh: MeshResource, position: SIMD3<Float>) {
        let edge = ModelEntity(mesh: mesh, materials: [edgeMaterial])
        edge.position = position
        rootAnchor.addChild(edge)
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
