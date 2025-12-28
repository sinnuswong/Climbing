//
//  ContentView.swift
//  Climbing
//
//  Created by Sinnus Wong on 12/24/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = GameViewModel()
#if DEBUG
    @State private var showGenerator = false
    @State private var showGenerator2 = false
#endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityKitContainer(viewModel: viewModel)
                .ignoresSafeArea()

            hudOverlay
        }
        .alert("Level Complete", isPresented: $viewModel.showWinAlert) {
            Button("Next Level") { viewModel.advanceLevel() }
            Button("Keep Looking", role: .cancel) { viewModel.dismissWinAlert() }
        } message: {
            Text("You reached the flag.")
        }
#if DEBUG
        .sheet(isPresented: $showGenerator) {
            LevelGeneratorPreviewView { level in
                viewModel.loadCustomLevel(level)
            }
        }
        .sheet(isPresented: $showGenerator2) {
            LevelGenerator2PreviewView { level in
                viewModel.loadCustomLevel(level)
            }
        }
#endif
    }

    private var hudOverlay: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Level \(viewModel.levelIndex + 1)")
                    .font(.headline)
                Text("Z \(viewModel.currentHeight)")
                Text("Steps \(viewModel.steps)")
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.leading, 16)
            .padding(.top, 16)

            VStack(spacing: 10) {
                Button("Auto") { viewModel.startAuto() }
                    .disabled(viewModel.isAutoRunning)
                Button("Hint") { viewModel.showHint() }
                    .disabled(viewModel.isAutoRunning)
                Button("Reset View") { viewModel.resetCamera() }
#if DEBUG
                Button("Generator") { showGenerator = true }
                Button("Generator2") { showGenerator2 = true }
#endif
            }
            .font(.headline)
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }
}

#Preview {
    ContentView()
}
