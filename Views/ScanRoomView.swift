import SwiftUI

struct ScanRoomView: View {
    @StateObject private var viewModel = ScanRoomViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            CameraPreviewView(cameraManager: CameraManager.shared)
                .ignoresSafeArea()
                .opacity(viewModel.isSimulatorMode ? 0.3 : 1.0)
            
            if viewModel.isSimulatorMode {
                Color.black
                    .ignoresSafeArea()
                    .opacity(0.5)
            }
            
            VStack {
                HStack {
                    Button("Cancel") {
                        viewModel.stopScanning()
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    if viewModel.isSimulatorMode {
                        Text("SIMULATOR MODE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                VStack(spacing: 20) {
                    MatchStateView(
                        state: viewModel.currentState,
                        confidence: viewModel.confidenceScore,
                        matchedMemoryName: viewModel.matchedMemoryName
                    )
                    
                    if viewModel.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    MatchProgressBar(state: viewModel.currentState, progress: viewModel.progressValue)
                        .frame(height: 8)
                        .padding(.horizontal, 40)
                    
                    if viewModel.currentState == .likelyMatch {
                        Button("Found It!") {
                            viewModel.stopScanning()
                            dismiss()
                        }
                        .font(.headline)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 15)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                        .shadow(color: .green.opacity(0.5), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                        .shadow(radius: 10)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
}

struct MatchStateView: View {
    let state: MatchState
    let confidence: Float
    let matchedMemoryName: String?
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 50))
                .foregroundColor(iconColor)
                .symbolEffect(.pulse, isActive: state == .likelyMatch)
            
            Text(state.rawValue)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if confidence > 0 {
                Text("\(Int(confidence * 100))%")
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundColor(iconColor)
            }
            
            if let name = matchedMemoryName {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
            }
        }
        .animation(.spring(response: 0.3), value: state)
    }
    
    private var iconName: String {
        switch state {
        case .scanning: return "viewfinder"
        case .gettingCloser: return "arrow.up.circle"
        case .possibleMatch: return "questionmark.circle"
        case .likelyMatch: return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch state {
        case .scanning: return .blue
        case .gettingCloser: return .yellow
        case .possibleMatch: return .orange
        case .likelyMatch: return .green
        }
    }
}

struct MatchProgressBar: View {
    let state: MatchState
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressGradient)
                    .frame(width: geometry.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
    }
    
    private var progressGradient: LinearGradient {
        switch state {
        case .scanning:
            return LinearGradient(colors: [.blue], startPoint: .leading, endPoint: .trailing)
        case .gettingCloser:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        case .possibleMatch:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        case .likelyMatch:
            return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
        }
    }
}

@MainActor
class ScanRoomViewModel: ObservableObject {
    @Published var currentState: MatchState = .scanning
    @Published var targetMemoryName: String?
    @Published var matchedMemoryName: String?
    @Published var matchResult: MatchResult?
    @Published var confidenceScore: Float = 0.0
    @Published var progressValue: Double = 0.0
    @Published var isProcessing: Bool = false
    @Published var isSimulatorMode: Bool = false
    @Published var errorMessage: String?
    
    private let scanRoomController = ScanRoomController()
    private let memoryManager = MemoryManager.shared
    
    private var scoreHistory: [Float] = []
    private let scoreHistoryLimit = 10
    
    init() {
        #if targetEnvironment(simulator)
        isSimulatorMode = true
        #endif
    }
    
    func startScanning() {
        let memories = memoryManager.memories
        
        guard !memories.isEmpty else {
            errorMessage = "No memories to scan"
            return
        }
        
        targetMemoryName = memories.first?.itemName
        matchedMemoryName = nil
        currentState = .scanning
        confidenceScore = 0
        progressValue = 0
        scoreHistory.removeAll()
        
        scanRoomController.startScanning(memories: memories)
        
        startStateUpdates()
    }
    
    func stopScanning() {
        scanRoomController.stopScanning()
    }
    
    private func startStateUpdates() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if !self.scanRoomController.isScanning {
                    timer.invalidate()
                    return
                }
                
                self.isProcessing = self.scanRoomController.isProcessingFrame
                self.updateFromController()
            }
        }
    }
    
    private func updateFromController() {
        let newState = scanRoomController.currentMatchState
        let newScore = scanRoomController.smoothedScore
        
        if newScore > 0 {
            scoreHistory.append(newScore)
            if scoreHistory.count > scoreHistoryLimit {
                scoreHistory.removeFirst()
            }
            
            confidenceScore = calculateSmoothedScore()
            
            if let result = scanRoomController.currentMatchResult,
               let memory = memoryManager.getMemoryById(result.memoryId) {
                matchedMemoryName = memory.itemName
            }
        }
        
        withAnimation(.spring(response: 0.3)) {
            currentState = newState
            progressValue = Double(confidenceScore)
        }
    }
    
    private func calculateSmoothedScore() -> Float {
        guard !scoreHistory.isEmpty else { return 0 }
        
        let weights = scoreHistory.enumerated().map { Float($0.offset + 1) }
        let totalWeight = weights.reduce(0, +)
        
        var weightedSum: Float = 0
        for (index, score) in scoreHistory.enumerated() {
            weightedSum += score * weights[index]
        }
        
        return weightedSum / totalWeight
    }
}

#Preview {
    ScanRoomView()
}
