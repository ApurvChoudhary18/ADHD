import SwiftUI

struct ScanModernView: View {
    @StateObject private var viewModel = ScanModernViewModel()
    @StateObject private var cameraManager = CameraManager.shared
    
    var body: some View {
        ZStack {
            cameraBackground
            
            VStack {
                topBar
                Spacer()
                
                if !viewModel.isSimulatorMode && cameraManager.isAuthorized {
                    matchOverlay
                } else if !viewModel.isSimulatorMode && !cameraManager.isAuthorized {
                    permissionOverlay
                }
                
                Spacer()
                bottomControls
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.setupCamera()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
    
    @ViewBuilder
    private var cameraBackground: some View {
        if viewModel.isSimulatorMode {
            ZStack {
                Color.black.opacity(0.8)
                
                VStack(spacing: 20) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 80))
                        .foregroundStyle(.gray)
                    
                    Text("SIMULATOR MODE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.yellow)
                    
                    Text("Camera not available on simulator")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        } else if cameraManager.isAuthorized {
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
        } else {
            Color.black.opacity(0.3)
        }
    }
    
    private var topBar: some View {
        HStack {
            Text("Scan Room")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    @ViewBuilder
    private var matchOverlay: some View {
        VStack(spacing: 20) {
            ScanStateView(state: viewModel.currentState, confidence: viewModel.confidenceScore)
            
            if viewModel.confidenceScore > 0 {
                ConfidenceBar(progress: viewModel.progressValue, state: viewModel.currentState)
                    .frame(height: 8)
                    .padding(.horizontal, 40)
            }
            
            if let name = viewModel.matchedMemoryName {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
    }
    
    @ViewBuilder
    private var permissionOverlay: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white)
            
            Text("Camera Access Required")
                .font(.headline)
                .foregroundStyle(.white)
            
            Text(cameraManager.permissionError ?? "Please enable camera access in Settings")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .clipShape(Capsule())
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
    }
    
    private var bottomControls: some View {
        HStack {
            Button {
                viewModel.stopScanning()
            } label: {
                Text("Stop")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.bottom, 50)
    }
}

struct ScanStateView: View {
    let state: MatchState
    let confidence: Float
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: stateIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(stateColor)
            }
            
            Text(state.rawValue)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
            
            if confidence > 0 {
                Text("\(Int(confidence * 100))%")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(stateColor)
            }
        }
    }
    
    private var stateIcon: String {
        switch state {
        case .scanning: return "viewfinder"
        case .gettingCloser: return "arrow.up.circle"
        case .possibleMatch: return "questionmark.circle"
        case .likelyMatch: return "checkmark.circle.fill"
        }
    }
    
    private var stateColor: Color {
        switch state {
        case .scanning: return .blue
        case .gettingCloser: return .yellow
        case .possibleMatch: return .orange
        case .likelyMatch: return .green
        }
    }
}

struct ConfidenceBar: View {
    let progress: Double
    let state: MatchState
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                
                Capsule()
                    .fill(barGradient)
                    .frame(width: geometry.size.width * progress)
            }
        }
    }
    
    private var barGradient: LinearGradient {
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
class ScanModernViewModel: ObservableObject {
    @Published var currentState: MatchState = .scanning
    @Published var confidenceScore: Float = 0.0
    @Published var progressValue: Double = 0.0
    @Published var matchedMemoryName: String?
    @Published var isSimulatorMode = false
    
    private let scanController = ScanRoomController()
    private let memoryManager = MemoryManager.shared
    private var updateTimer: Timer?
    
    init() {
        #if targetEnvironment(simulator)
        isSimulatorMode = true
        #endif
    }
    
    func setupCamera() {
        Task {
            await CameraManager.shared.checkAuthorization()
            if CameraManager.shared.isAuthorized {
                CameraManager.shared.configure()
                CameraManager.shared.startSession()
            }
            
            if !memoryManager.memories.isEmpty {
                startScanning()
            }
        }
    }
    
    func startScanning() {
        let memories = memoryManager.memories
        guard !memories.isEmpty else {
            print("[ScanModernViewModel] No memories to scan against")
            return
        }
        
        scanController.startScanning(memories: memories)
        startUpdates()
    }
    
    func stopScanning() {
        scanController.stopScanning()
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func startUpdates() {
        updateTimer?.invalidate()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                if !self.scanController.isScanning {
                    timer.invalidate()
                    return
                }
                
                self.currentState = self.scanController.currentMatchState
                self.confidenceScore = self.scanController.smoothedScore
                self.progressValue = Double(self.confidenceScore)
                
                if let result = self.scanController.currentMatchResult,
                   let memory = self.memoryManager.getMemoryById(result.memoryId) {
                    self.matchedMemoryName = memory.itemName
                }
            }
        }
    }
}

#Preview {
    ScanModernView()
}
