import SwiftUI
import UIKit

#if DEBUG
struct LevelGeneratorPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = LevelGeneratorConfig.default
    @State private var level = Level.sample()
    @State private var levelCount: Int = 10
    @State private var showJson = false
    @State private var didCopy = false
    @State private var layerIndex: Int = 0
    private let onPlayLevel: (Level) -> Void

    init(onPlayLevel: @escaping (Level) -> Void = { _ in }) {
        self.onPlayLevel = onPlayLevel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelGrid
                    controls
                    if showJson {
                        jsonPreview
                    }
                }
                .padding(16)
            }
            .navigationTitle("Level Generator")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { regenerate() }
    }

    private var levelGrid: some View {
        let gridItems = Array(repeating: GridItem(.fixed(18), spacing: 2), count: level.width)
        let maxLayer = max(level.height - 1, 0)
        let currentLayer = min(layerIndex, maxLayer)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Layer Z \(currentLayer)")
                .font(.headline)
            LazyVGrid(columns: gridItems, spacing: 2) {
                ForEach(0..<(level.depth * level.width), id: \.self) { index in
                    let x = index % level.width
                    let y = index / level.width
                    let value = level.layers[safe: currentLayer]?[safe: y]?[safe: x] ?? 0
                    let isStandable = level.isStandable(x: x, y: y, z: currentLayer)
                    ZStack {
                        Rectangle()
                            .fill(colorForVoxel(value, layer: currentLayer))
                        Rectangle()
                            .stroke(.black.opacity(0.25), lineWidth: 1)
                        if isStandable {
                            Circle()
                                .fill(.yellow.opacity(0.85))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 18, height: 18)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Width: \(config.width)", value: $config.width, in: 5...20)
            Stepper("Depth: \(config.depth)", value: $config.depth, in: 5...20)
            Stepper("Height: \(config.height)", value: $config.height, in: 4...20)
            Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...30)
            Stepper("Layer: \(layerIndex)", value: $layerIndex, in: 0...max(level.height - 1, 0))

            sliderRow(title: "Fill Chance", value: $config.fillChance, range: 0.0...0.4)
            sliderRow(title: "Height Falloff", value: $config.heightFalloff, range: 0.0...0.8)
            sliderRow(title: "Pair Chance", value: $config.pairChance, range: 0.0...0.8)
            sliderRow(title: "Path Length", value: $config.pathLengthFactor, range: 0.3...0.85)
            sliderRow(title: "Avoid Edge", value: $config.avoidEdgeBias, range: 0.0...0.85)
            sliderRow(title: "Turn Bias", value: $config.turnBias, range: 0.0...0.85)

            HStack {
                Button("Generate") { regenerate() }
                Spacer()
                Button("New Seed") {
                    config.seed = UInt64.random(in: 1...999_999)
                }
            }
            .buttonStyle(.bordered)

            Button(didCopy ? "Copied" : "Copy JSON") {
                copyJSON()
            }
            .buttonStyle(.bordered)

            Button("Play This Level") {
                onPlayLevel(level)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var jsonPreview: some View {
        let json = jsonString
        return VStack(alignment: .leading, spacing: 8) {
            Text("JSON")
                .font(.headline)
            TextEditor(text: .constant(json))
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
        }
    }

    private func regenerate() {
        level = LevelGenerator.generateLevel(id: 1, config: config)
        didCopy = false
        layerIndex = min(layerIndex, max(level.height - 1, 0))
    }

    private var jsonString: String {
        let levels = LevelGenerator.generateLevels(count: levelCount, config: config)
        return LevelGenerator.encodeLevels(levels)
    }

    private func copyJSON() {
        UIPasteboard.general.string = jsonString
        didCopy = true
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue))")
            Slider(value: value, in: range, step: 0.01)
        }
    }

    private func colorForVoxel(_ value: Int, layer: Int) -> Color {
        if value == 0 { return Color.clear }
        let t = min(1.0, Double(layer) / Double(max(level.height - 1, 1)))
        return Color(red: 0.25 + 0.35 * t, green: 0.6 + 0.25 * t, blue: 0.35 + 0.25 * t)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
#endif
