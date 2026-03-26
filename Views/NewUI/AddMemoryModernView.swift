import SwiftUI

struct AddMemoryModernView: View {
    @StateObject private var viewModel = AddMemoryModernViewModel()
    @StateObject private var cameraManager = CameraManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    cameraSection
                    
                    formSection
                    
                    saveButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Memory")
            .overlay { saveOverlay }
        }
        .onAppear {
            viewModel.checkCameraPermission()
        }
    }
    
    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .frame(height: 250)
            
            if viewModel.isCapturing {
                captureProgressView
            } else if viewModel.isSimulatorMode {
                simulatorPlaceholder
            } else if !cameraManager.isAuthorized {
                cameraPermissionView
            } else {
                cameraPreviewView
            }
        }
    }
    
    private var captureProgressView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Capturing \(viewModel.capturedFrameCount)/10")
                .font(.headline)
                .foregroundStyle(.white)
            
            CaptureProgressBar(progress: viewModel.captureProgress)
                .frame(height: 6)
                .padding(.horizontal, 40)
        }
    }
    
    private var simulatorPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            
            Text("Simulator Mode")
                .font(.subheadline)
                .foregroundStyle(.gray)
            
            PrimaryButton(title: "Simulate Capture", icon: "camera.fill") {
                viewModel.simulateCapture()
            }
            .frame(width: 160)
        }
    }
    
    private var cameraPermissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.gray)
            
            Text("Camera Access Required")
                .font(.subheadline)
                .foregroundStyle(.gray)
            
            if let error = cameraManager.permissionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
    }
    
    @ViewBuilder
    private var cameraPreviewView: some View {
        CameraPreviewView(cameraManager: cameraManager)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    viewModel.startCapture()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                        Text("Capture")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
                .padding(12)
            }
    }
    
    private var formSection: some View {
        VStack(spacing: 16) {
            ModernTextField(
                icon: "tag.fill",
                placeholder: "Item Name",
                text: $viewModel.itemName
            )
            .overlay(alignment: .trailing) {
                voiceButton(for: .itemName)
            }
            
            ModernTextField(
                icon: "location.fill",
                placeholder: "Location Description",
                text: $viewModel.locationDescription
            )
            .overlay(alignment: .trailing) {
                voiceButton(for: .location)
            }
            
            ModernTextField(
                icon: "note.text",
                placeholder: "Notes (optional)",
                text: $viewModel.notes
            )
            
            if let voiceError = viewModel.voiceError {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    @ViewBuilder
    private func voiceButton(for field: VoiceField) -> some View {
        Button {
            viewModel.toggleVoiceInput(for: field)
        } label: {
            Image(systemName: viewModel.isListening && viewModel.activeVoiceField == field ? "mic.fill" : "mic")
                .foregroundStyle(viewModel.isListening && viewModel.activeVoiceField == field ? .red : .blue)
                .padding(12)
        }
    }
    
    private var saveButton: some View {
        PrimaryButton(title: "Save Memory", icon: "checkmark.circle.fill") {
            viewModel.saveMemory()
        }
        .disabled(!viewModel.canSave)
        .opacity(viewModel.canSave ? 1 : 0.5)
    }
    
    @ViewBuilder
    private var saveOverlay: some View {
        if viewModel.isSaved {
            SuccessOverlay(message: "Memory Saved!")
                .transition(.scale.combined(with: .opacity))
        }
    }
}

enum VoiceField {
    case itemName
    case location
    case notes
}

@MainActor
class AddMemoryModernViewModel: ObservableObject {
    @Published var itemName = ""
    @Published var locationDescription = ""
    @Published var notes = ""
    @Published var capturedFrames: [UIImage] = []
    @Published var isCapturing = false
    @Published var capturedFrameCount = 0
    @Published var isSaving = false
    @Published var isSaved = false
    @Published var saveProgress: Double = 0.0
    @Published var isSimulatorMode = false
    @Published var isListening = false
    @Published var voiceError: String?
    @Published var activeVoiceField: VoiceField?
    
    private let memoryManager = MemoryManager.shared
    private let cameraManager = CameraManager.shared
    private let voiceManager = VoiceInputManager.shared
    
    var canSave: Bool {
        !itemName.isEmpty && !locationDescription.isEmpty
    }
    
    var captureProgress: Double {
        Double(capturedFrameCount) / 10.0
    }
    
    init() {
        #if targetEnvironment(simulator)
        isSimulatorMode = true
        #endif
        setupVoiceCallback()
    }
    
    private func setupVoiceCallback() {
        voiceManager.onResult = { [weak self] transcript in
            Task { @MainActor in
                guard let self = self, let field = self.activeVoiceField else { return }
                
                let parsed = self.voiceManager.parseTranscript(transcript)
                
                switch field {
                case .itemName:
                    if !parsed.itemName.isEmpty {
                        self.itemName = parsed.itemName
                    } else {
                        self.itemName = transcript
                    }
                case .location:
                    if !parsed.locationDescription.isEmpty {
                        self.locationDescription = parsed.locationDescription
                    } else {
                        self.locationDescription = transcript
                    }
                case .notes:
                    self.notes = transcript
                }
                
                self.isListening = false
                self.activeVoiceField = nil
            }
        }
    }
    
    func checkCameraPermission() {
        Task {
            await cameraManager.checkAuthorization()
            if cameraManager.isAuthorized {
                cameraManager.configure()
                cameraManager.startSession()
            }
        }
    }
    
    func toggleVoiceInput(for field: VoiceField) {
        if isListening {
            stopVoiceInput()
        } else {
            startVoiceInput(for: field)
        }
    }
    
    private func startVoiceInput(for field: VoiceField) {
        voiceError = nil
        
        Task {
            let authorized = await voiceManager.requestAuthorization()
            
            if authorized {
                do {
                    try voiceManager.startListening()
                    isListening = true
                    activeVoiceField = field
                } catch {
                    voiceError = error.localizedDescription
                    isListening = false
                    activeVoiceField = nil
                }
            } else {
                voiceError = voiceManager.authorizationError ?? "Voice input not authorized"
                isListening = false
                activeVoiceField = nil
            }
        }
    }
    
    private func stopVoiceInput() {
        voiceManager.stopListening()
        isListening = false
        activeVoiceField = nil
    }
    
    func startCapture() {
        guard !isSimulatorMode else {
            simulateCapture()
            return
        }
        
        guard cameraManager.isAuthorized else {
            print("[AddMemoryModernViewModel] Camera not authorized")
            return
        }
        
        capturedFrames = []
        capturedFrameCount = 0
        isCapturing = true
        
        cameraManager.startFrameCapture(count: 10) { [weak self] frame in
            Task { @MainActor in
                guard let self = self else { return }
                self.capturedFrames.append(frame)
                self.capturedFrameCount = self.capturedFrames.count
                
                if self.capturedFrameCount >= 10 {
                    self.stopCapture()
                }
            }
        }
    }
    
    func simulateCapture() {
        capturedFrames = []
        capturedFrameCount = 10
        isCapturing = false
        
        for i in 0..<10 {
            if let placeholderImage = createPlaceholderImage(index: i) {
                capturedFrames.append(placeholderImage)
            }
        }
    }
    
    private func createPlaceholderImage(index: Int) -> UIImage? {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            UIColor.systemGray.withAlphaComponent(0.3).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            let text = "Frame \(index + 1)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.gray
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    func stopCapture() {
        cameraManager.stopFrameCapture()
        isCapturing = false
    }
    
    func saveMemory() {
        stopCapture()
        stopVoiceInput()
        isSaving = true
        saveProgress = 0.3
        
        Task {
            do {
                saveProgress = 0.6
                _ = try await memoryManager.saveMemory(
                    itemName: itemName,
                    locationDescription: locationDescription,
                    capturedFrames: capturedFrames,
                    notes: notes.isEmpty ? nil : notes
                )
                saveProgress = 1.0
                isSaving = false
                withAnimation(.spring(response: 0.3)) {
                    isSaved = true
                }
                resetForm()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        isSaved = false
                        saveProgress = 0.0
                    }
                }
            } catch {
                isSaving = false
                print("[AddMemoryModernViewModel] Failed to save memory: \(error)")
            }
        }
    }
    
    private func resetForm() {
        itemName = ""
        locationDescription = ""
        notes = ""
        capturedFrames = []
        capturedFrameCount = 0
    }
}

struct ModernTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CaptureProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green)
                    .frame(width: geometry.size.width * progress)
            }
        }
    }
}

struct SuccessOverlay: View {
    let message: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                
                Text(message)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

#Preview {
    AddMemoryModernView()
}
