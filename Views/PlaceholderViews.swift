import SwiftUI

struct SaveMemoryView: View {
    @StateObject private var viewModel = SaveMemoryViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Memory")
                .font(.title)
                .fontWeight(.bold)
            
            if viewModel.isCapturing {
                CameraPreviewView()
                    .frame(height: 300)
                    .cornerRadius(12)
                
                Text("Capturing frames: \(viewModel.capturedFrameCount)/10")
                    .foregroundColor(.secondary)
            } else {
                PlaceholderCameraView()
                    .frame(height: 300)
                    .cornerRadius(12)
                    .background(Color.gray.opacity(0.1))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                TextField("Item Name", text: $viewModel.itemName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Location Description", text: $viewModel.locationDescription)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Notes (optional)", text: $viewModel.notes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            
            if viewModel.isListening {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                    Text(viewModel.transcribedText)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    viewModel.startVoiceInput()
                }) {
                    Label("Voice Input", systemImage: "mic")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    viewModel.startCapture()
                }) {
                    Label("Capture", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    viewModel.saveMemory()
                }) {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canSave)
            }
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding()
    }
}

@MainActor
class SaveMemoryViewModel: ObservableObject {
    @Published var itemName = ""
    @Published var locationDescription = ""
    @Published var notes = ""
    @Published var capturedFrames: [UIImage] = []
    @Published var isCapturing = false
    @Published var capturedFrameCount = 0
    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var isSaving = false
    @Published var isSaved = false
    
    private let memoryManager = MemoryManager.shared
    private let voiceInputManager = VoiceInputManager()
    private let cameraManager = CameraManager.shared
    
    var canSave: Bool {
        !itemName.isEmpty && !locationDescription.isEmpty
    }
    
    func checkCameraPermission() async {
        await cameraManager.checkAuthorization()
        if cameraManager.isAuthorized {
            cameraManager.configure()
            cameraManager.startSession()
        }
    }
    
    func startCapture() {
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
    
    func stopCapture() {
        cameraManager.stopFrameCapture()
        isCapturing = false
    }
    
    func startVoiceInput() {
        Task {
            await voiceInputManager.requestAuthorization()
            do {
                try voiceInputManager.startListening()
                isListening = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func saveMemory() {
        stopCapture()
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await memoryManager.saveMemory(
                    itemName: itemName,
                    locationDescription: locationDescription,
                    capturedFrames: capturedFrames,
                    notes: notes.isEmpty ? nil : notes
                )
                await MainActor.run {
                    self.isSaving = false
                    self.isSaved = true
                    self.resetForm()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.isSaved = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isSaving = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func resetForm() {
        itemName = ""
        locationDescription = ""
        notes = ""
        capturedFrames = []
        isCapturing = false
    }
}

struct PlaceholderCameraView: View {
    var body: some View {
        VStack {
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("Camera Preview")
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SaveMemoryView_Previews: PreviewProvider {
    static var previews: some View {
        SaveMemoryView()
    }
}

struct ScanRoomView: View {
    @StateObject private var viewModel = ScanRoomViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            CameraPreviewView()
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("Cancel") {
                        viewModel.stopScanning()
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    if let memoryName = viewModel.targetMemoryName {
                        Text("Finding: \(memoryName)")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding(.top)
                
                Spacer()
                
                VStack(spacing: 15) {
                    MatchStateView(state: viewModel.currentState)
                    
                    if viewModel.currentState == .likelyMatch {
                        Button("Found It!") {
                            viewModel.stopScanning()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(16)
                .padding()
            }
        }
        .onAppear {
            viewModel.startScanning()
        }
    }
}

@MainActor
class ScanRoomViewModel: ObservableObject {
    @Published var currentState: MatchState = .scanning
    @Published var targetMemoryName: String?
    @Published var matchResult: MatchResult?
    
    private let scanRoomController = ScanRoomController()
    private let memoryManager = MemoryManager.shared
    
    func startScanning() {
        Task {
            let memories = memoryManager.memories
            if let first = memories.first {
                targetMemoryName = first.itemName
                scanRoomController.startScanning(memories: memories)
            }
        }
    }
    
    func stopScanning() {
        scanRoomController.stopScanning()
    }
}

struct MatchStateView: View {
    let state: MatchState
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
            
            Text(state.rawValue)
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    private var iconName: String {
        switch state {
        case .scanning:
            return "scan"
        case .gettingCloser:
            return "arrow.up.circle"
        case .possibleMatch:
            return "questionmark.circle"
        case .likelyMatch:
            return "checkmark.circle.fill"
        }
    }
    
    private var iconColor: Color {
        switch state {
        case .scanning:
            return .blue
        case .gettingCloser:
            return .yellow
        case .possibleMatch:
            return .orange
        case .likelyMatch:
            return .green
        }
    }
}

struct FindView: View {
    @StateObject private var viewModel = FindViewModel()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Find Your Item")
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack {
                    TextField("Search items...", text: $viewModel.searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: viewModel.searchQuery) { _, newValue in
                            viewModel.search(query: newValue)
                        }
                    
                    Button(action: {
                        viewModel.startVoiceSearch()
                    }) {
                        Image(systemName: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                if viewModel.isListening {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.red)
                        Text("Listening...")
                            .foregroundColor(.secondary)
                    }
                }
                
                if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                    Text("No items found")
                        .foregroundColor(.secondary)
                } else if !viewModel.searchResults.isEmpty {
                    List(viewModel.searchResults, id: \.id) { memory in
                        NavigationLink(destination: MemoryDetailView(memory: memory)) {
                            VStack(alignment: .leading) {
                                Text(memory.itemName)
                                    .font(.headline)
                                Text(memory.locationDescription)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(memory.createdAt, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.top)
        }
    }
}

@MainActor
class FindViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [MemoryItem] = []
    @Published var isListening = false
    @Published var transcribedText = ""
    
    private let memoryManager = MemoryManager.shared
    private let voiceInputManager = VoiceInputManager()
    private let searchEngine = SearchEngine.shared
    
    func search(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        
        searchResults = searchEngine.search(query: query, in: memoryManager.memories)
    }
    
    func startVoiceSearch() {
        Task {
            await voiceInputManager.requestAuthorization()
            do {
                voiceInputManager.onResult = { [weak self] text in
                    Task { @MainActor in
                        self?.transcribedText = text
                        self?.searchQuery = text
                        self?.search(text)
                        self?.isListening = false
                    }
                }
                try voiceInputManager.startListening()
                isListening = true
            } catch {
                print("Voice search error: \(error)")
                isListening = false
            }
        }
    }
    
    func stopVoiceSearch() {
        voiceInputManager.stopListening()
        isListening = false
    }
}

struct MemoryDetailView: View {
    let memory: MemoryItem
    @State private var isScanning = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(memory.itemName)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack {
                    Image(systemName: "location.fill")
                    Text(memory.locationDescription)
                }
                .foregroundColor(.secondary)
                
                if let notes = memory.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !memory.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tags")
                            .font(.headline)
                        TagListView(tags: memory.tags)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Created")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(memory.createdAt, style: .date)
                            .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Last Updated")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(memory.updatedAt, style: .date)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 10)
                
                Text("Reference Images")
                    .font(.headline)
                
                if memory.referenceFrames.isEmpty {
                    Text("No reference images")
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(memory.referenceImages, id: \.self) { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                
                Button(action: {
                    isScanning = true
                }) {
                    Text("Start Scanning")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Memory Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FindView_Previews: PreviewProvider {
    static var previews: some View {
        FindView()
    }
}
