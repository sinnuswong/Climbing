import Foundation
import SwiftUI
import UIKit

#if DEBUG
struct LevelGenerator2PreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = LevelGenerator2Config.default
    @State private var level = Level.sample()
    @State private var levelCount: Int = 10
    @State private var showJson = false
    @State private var didCopy = false
    @State private var didCopySequence = false
    @State private var didCopyVectors = false
    @State private var layerIndex: Int = 0
    @State private var sequenceCodes: [Int] = []
    @State private var sequenceInput = ""
    @State private var sequenceError: String?
    @State private var showDeadEnds = false
    @State private var deadEndMap: [VoxelPoint: Int] = [:]
    private let onPlayLevel: (Level, Set<VoxelPoint>) -> Void
    private static var storedConfig = LevelGenerator2Config.default
    private static var storedLevelCount: Int = 10
    private static var storedLayerIndex: Int = 0
    private static var storedShowJson = false
    private static var storedShowDeadEnds = false

    init(onPlayLevel: @escaping (Level, Set<VoxelPoint>) -> Void = { _, _ in }) {
        self.onPlayLevel = onPlayLevel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelGrid
                    controls
                    sequenceControls
                    if showJson {
                        jsonPreview
                    }
                }
                .padding(16)
            }
            .navigationTitle("Level Generator 2")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            loadState()
            regenerate()
        }
        .onChange(of: config) { _ in
            saveState()
        }
        .onChange(of: levelCount) { _ in
            saveState()
        }
        .onChange(of: layerIndex) { _ in
            saveState()
        }
        .onChange(of: showJson) { _ in
            saveState()
        }
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
                    let baseColor = colorForVoxel(value, layer: currentLayer)
                    let highlight = value == 0 ? nil : deadEndColor(for: VoxelPoint(x: x, y: y, z: currentLayer))
                    ZStack {
                        Rectangle()
                            .fill(baseColor)
                        if let highlight {
                            Rectangle()
                                .fill(highlight)
                        }
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
            Stepper("Steps: \(config.steps)", value: $config.steps, in: 5...40)
            mainRouteSlider
            Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...30)
            Stepper("Layer: \(layerIndex)", value: $layerIndex, in: 0...max(level.height - 1, 0))
            Stepper("Dead Ends: \(config.deadEndCount)", value: $config.deadEndCount, in: 0...20)
            Stepper("Dead End Min: \(config.deadEndMinLength)", value: $config.deadEndMinLength, in: 1...10)
            Stepper("Dead End Max: \(config.deadEndMaxLength)", value: $config.deadEndMaxLength, in: config.deadEndMinLength...12)

            sliderRow(title: "Fill Chance", value: $config.fillChance, range: 0.0...0.4)
            sliderRow(title: "Height Falloff", value: $config.heightFalloff, range: 0.0...0.8)
            sliderRow(title: "Pair Chance", value: $config.pairChance, range: 0.0...0.8)

            HStack {
                Button("Generate") { regenerate() }
                Spacer()
                Button("New Seed") {
                    config.seed = UInt64.random(in: 1...999_999)
                }
            }
            .buttonStyle(.bordered)

            Button(showDeadEnds ? "Hide Dead Ends" : "Show Dead Ends") {
                showDeadEnds.toggle()
            }
            .buttonStyle(.bordered)

            Button(didCopy ? "Copied" : "Copy JSON") {
                copyJSON()
            }
            .buttonStyle(.bordered)

            Button("Play This Level") {
                onPlayLevel(level, Set(deadEndMap.keys))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sequenceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Path Sequence")
                .font(.headline)
            TextEditor(text: .constant(sequenceText))
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))

            Text("Vectors (dx, dy, dz)")
                .font(.subheadline)
            TextEditor(text: .constant(vectorText))
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))

            HStack {
                Button(didCopySequence ? "Copied Codes" : "Copy Codes") {
                    copySequence()
                }
                Button(didCopyVectors ? "Copied Vectors" : "Copy Vectors") {
                    copyVectors()
                }
            }
            .buttonStyle(.bordered)

            Text("Import Sequence (codes or vectors)")
                .font(.subheadline)
            TextEditor(text: $sequenceInput)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))

            if let error = sequenceError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Button("Load Sequence") {
                loadSequence()
            }
            .buttonStyle(.bordered)
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
        let result = LevelGenerator2.generateLevelWithDebug(id: 1, config: config)
        level = result.level
        sequenceCodes = result.sequence
        deadEndMap = buildDeadEndMap(paths: result.deadEndPaths)
        didCopy = false
        didCopySequence = false
        didCopyVectors = false
        sequenceError = nil
        layerIndex = min(layerIndex, max(level.height - 1, 0))
    }

    private var jsonString: String {
        let levels = LevelGenerator2.generateLevels(count: levelCount, config: config)
        return LevelGenerator2.encodeLevels(levels)
    }

    private func copyJSON() {
        UIPasteboard.general.string = jsonString
        didCopy = true
    }

    private var sequenceText: String {
        guard !sequenceCodes.isEmpty else { return "[]" }
        let body = sequenceCodes.map(String.init).joined(separator: ", ")
        return "[\(body)]"
    }

    private var vectorText: String {
        let vectors = LevelGenerator2.vectorTuples(for: sequenceCodes)
        guard !vectors.isEmpty else { return "" }
        return vectors.map { "\($0.0), \($0.1), \($0.2)" }.joined(separator: "\n")
    }

    private func copySequence() {
        UIPasteboard.general.string = sequenceText
        didCopySequence = true
    }

    private func copyVectors() {
        UIPasteboard.general.string = vectorText
        didCopyVectors = true
    }

    private func loadSequence() {
        didCopySequence = false
        didCopyVectors = false
        switch parseSequenceInput(sequenceInput) {
        case .success(let codes):
            config.steps = codes.count
            print("codes.count \(codes.count)")
            if let required = LevelGenerator2.requiredSize(forSequence: codes, enforceUniquePredecessor: false) {
                config.width = max(config.width, required.width)
                config.depth = max(config.depth, required.depth)
                config.height = max(config.height, required.height)
            }
            if let generated = LevelGenerator2.generateLevelFromSequenceDebug(id: 1,
                                                                              config: config,
                                                                              sequence: codes,
                                                                              enforceUniquePredecessor: false,
                                                                              autoExpand: true) {
                level = generated.level
                sequenceCodes = codes
                deadEndMap = buildDeadEndMap(paths: generated.deadEndPaths)
                sequenceError = nil
                layerIndex = min(layerIndex, max(level.height - 1, 0))
            } else {
                deadEndMap = [:]
                sequenceError = "Sequence is invalid for the current size or rules."
            }
        case .failure(let error):
            deadEndMap = [:]
            sequenceError = error.localizedDescription
        }
    }

    private func parseSequenceInput(_ input: String) -> Result<[Int], SequenceParseError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.message("Enter codes or vectors.")) }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let codes = json as? [Int] {
                return validateCodes(codes)
            }
            if let vectors = json as? [[Int]] {
                let tuples = vectors.compactMap { triple -> (Int, Int, Int)? in
                    guard triple.count == 3 else { return nil }
                    return (triple[0], triple[1], triple[2])
                }
                if tuples.count != vectors.count {
                    return .failure(.message("Vector JSON must be [[dx, dy, dz], ...]."))
                }
                guard let codes = LevelGenerator2.sequence(fromVectors: tuples) else {
                    return .failure(.message("Vectors must match the 16 allowed steps."))
                }
                return validateCodes(codes)
            }
        }

        let lines = trimmed.split(whereSeparator: \.isNewline)
        let parsedLines = lines.compactMap { line -> [Int]? in
            let numbers = extractInts(from: String(line))
            return numbers.isEmpty ? nil : numbers
        }
        guard !parsedLines.isEmpty else { return .failure(.message("No numbers found.")) }
        let allTriples = parsedLines.allSatisfy { $0.count == 3 }
        if allTriples {
            let tuples = parsedLines.map { ($0[0], $0[1], $0[2]) }
            guard let codes = LevelGenerator2.sequence(fromVectors: tuples) else {
                return .failure(.message("Vectors must match the 16 allowed steps."))
            }
            return validateCodes(codes)
        }

        let codes = parsedLines.flatMap { $0 }
        return validateCodes(codes)
    }

    private func validateCodes(_ codes: [Int]) -> Result<[Int], SequenceParseError> {
        guard !codes.isEmpty else { return .failure(.message("Sequence is empty.")) }
        if let invalid = codes.first(where: { $0 < 0 || $0 > 15 }) {
            return .failure(.message("Code out of range: \(invalid)."))
        }
        return .success(codes)
    }

    private func extractInts(from text: String) -> [Int] {
        let tokens = text.split { char in
            !(char.isNumber || char == "-")
        }
        return tokens.compactMap { Int($0) }
    }

    private func deadEndColor(for point: VoxelPoint) -> Color? {
        guard showDeadEnds, let index = deadEndMap[point] else { return nil }
        let palette = deadEndPalette
        return palette[index % palette.count]
    }

    private var deadEndPalette: [Color] {
        [
            Color(red: 0.98, green: 0.1, blue: 0.1),
            Color(red: 0.1, green: 0.85, blue: 0.2),
            Color(red: 0.1, green: 0.6, blue: 0.98),
            Color(red: 0.98, green: 0.85, blue: 0.1),
            Color(red: 0.98, green: 0.1, blue: 0.75),
            Color(red: 0.2, green: 0.95, blue: 0.9),
        ]
    }

    private func buildDeadEndMap(paths: [[VoxelPoint]]) -> [VoxelPoint: Int] {
        var map: [VoxelPoint: Int] = [:]
        for (index, path) in paths.enumerated() {
            for point in path {
                map[point] = index
            }
        }
        return map
    }

    private func saveState() {
        Self.storedConfig = config
        Self.storedLevelCount = levelCount
        Self.storedLayerIndex = layerIndex
        Self.storedShowJson = showJson
        Self.storedShowDeadEnds = showDeadEnds
    }

    private func loadState() {
        config = Self.storedConfig
        levelCount = Self.storedLevelCount
        layerIndex = Self.storedLayerIndex
        showJson = Self.storedShowJson
        showDeadEnds = Self.storedShowDeadEnds
    }

    private enum SequenceParseError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let message):
                return message
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue))")
            Slider(value: value, in: range, step: 0.01)
        }
    }

    private var mainRouteSlider: some View {
        let binding = Binding<Double>(
            get: { Double(config.mainRouteCount) },
            set: { config.mainRouteCount = Int($0.rounded()) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text("Main Routes (k): \(config.mainRouteCount)")
            Slider(value: binding, in: 1...8, step: 1)
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
