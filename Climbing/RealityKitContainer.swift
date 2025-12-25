import RealityKit
import SwiftUI

struct RealityKitContainer: UIViewRepresentable {
    @ObservedObject var viewModel: GameViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let scene = GameScene(arView: arView)
        context.coordinator.scene = scene

        viewModel.connectScene(
            load: { [weak scene] level, start, goal in
                scene?.build(level: level, playerStart: start, goal: goal)
            },
            move: { [weak scene] point, animated in
                scene?.movePlayer(to: point, animated: animated)
            },
            showPath: { [weak scene] path in
                scene?.showPath(path)
            },
            clearPath: { [weak scene] in
                scene?.clearHighlights()
            },
            resetCamera: { [weak scene] in
                scene?.resetCamera()
            }
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))

        arView.addGestureRecognizer(tap)
        arView.addGestureRecognizer(pan)
        arView.addGestureRecognizer(pinch)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject {
        let viewModel: GameViewModel
        var scene: GameScene?

        init(viewModel: GameViewModel) {
            self.viewModel = viewModel
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = scene?.arView else { return }
            let location = gesture.location(in: arView)
            guard let entity = arView.entity(at: location) else { return }
            if let point = parseVoxelPoint(from: entity) {
                Task { @MainActor in
                    viewModel.handleTap(at: point)
                }
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            scene?.cameraController.handlePan(gesture)
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            scene?.cameraController.handlePinch(gesture)
        }

        private func parseVoxelPoint(from entity: Entity) -> VoxelPoint? {
            if let point = parseName(entity.name) {
                return point
            }
            if let parent = entity.parent, let point = parseName(parent.name) {
                return point
            }
            return nil
        }

        private func parseName(_ name: String) -> VoxelPoint? {
            guard name.hasPrefix("tile_") else { return nil }
            let parts = name.split(separator: "_")
            guard parts.count == 4,
                  let x = Int(parts[1]),
                  let y = Int(parts[2]),
                  let z = Int(parts[3]) else {
                return nil
            }
            return VoxelPoint(x: x, y: y, z: z)
        }
    }
}
