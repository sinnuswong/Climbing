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
        let gridItems = Array(repeating: GridItem(.fixed(18), spacing: 2), count: config.width)
        return LazyVGrid(columns: gridItems, spacing: 2) {
            ForEach(0..<(config.depth * config.width), id: \.self) { index in
                let x = index % config.width
                let y = index / config.width
                let value = level.heights[safe: y]?[safe: x] ?? 0
                ZStack {
                    Rectangle()
                        .fill(colorForHeight(value))
                    Rectangle()
                        .stroke(.black.opacity(0.25), lineWidth: 1)
                    if value > 0 {
                        Text("\(value)")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }
                .frame(width: 18, height: 18)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Width: \(config.width)", value: $config.width, in: 5...13)
            Stepper("Depth: \(config.depth)", value: $config.depth, in: 5...13)
            Stepper("Max Height: \(config.maxHeight)", value: $config.maxHeight, in: 4...12)
            Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...30)

            sliderRow(title: "Holes", value: $config.holeChance, range: 0.0...0.6)
            sliderRow(title: "Edge Holes", value: $config.edgeHoleBoost, range: 0.0...0.6)
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

    private func colorForHeight(_ height: Int) -> Color {
        if height == 0 { return Color.clear }
        let t = min(1.0, Double(height) / Double(max(config.maxHeight, 1)))
        return Color(red: 0.35 + 0.3 * t, green: 0.7 + 0.2 * t, blue: 0.35)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
#endif
