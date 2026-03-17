import Foundation
import SwiftUI
import Combine

@main
struct MemoryCamApp: App {
    @StateObject private var memoryManager = MemoryManager.shared
    @StateObject private var appState = AppState()
    
    init() {
        setupDependencies()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(memoryManager)
                .environmentObject(appState)
                .onAppear {
                    Task {
                        await initializeApp()
                    }
                }
        }
    }
    
    private func setupDependencies() {
    }
    
    private func initializeApp() async {
        await memoryManager.loadMemories()
        
        await preloadFeatureDescriptors()
        
        await MainActor.run {
            appState.isInitialized = true
        }
        
        print("[MemoryCam] App initialized with \(memoryManager.memories.count) memories")
    }
    
    private func preloadFeatureDescriptors() async {
        guard !memoryManager.memories.isEmpty else { return }
        
        await SceneMatcher.shared.loadReferenceDescriptors(for: memoryManager.memories)
        
        print("[MemoryCam] Preloaded descriptors for \(memoryManager.memories.count) memories")
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isInitialized = false
    @Published var isScanning = false
    @Published var currentScanMemoryId: UUID?
    
    func startScanning(for memoryId: UUID) {
        currentScanMemoryId = memoryId
        isScanning = true
    }
    
    func stopScanning() {
        isScanning = false
        currentScanMemoryId = nil
    }
}

struct ContentViewPlaceholder: View {
    var body: some View {
        VStack {
            Text("MemoryCam")
                .font(.largeTitle)
            Text("Core modules loaded")
                .foregroundColor(.secondary)
        }
    }
}
