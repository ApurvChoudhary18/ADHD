import Foundation
import AVFoundation
import UIKit
import Combine

protocol ScanRoomControllerDelegate: AnyObject {
    func scanRoomController(_ controller: ScanRoomController, didUpdateMatchState state: MatchState, for memoryId: UUID?)
    func scanRoomController(_ controller: ScanRoomController, didFindMatch result: MatchResult)
    func scanRoomController(_ controller: ScanRoomController, didFailWithError error: Error)
    func scanRoomController(_ controller: ScanRoomController, didProcessFrame result: MatchResult?)
}

final class ScanRoomController: ObservableObject {
    @Published var currentMatchState: MatchState = .scanning
    @Published var currentMatchResult: MatchResult?
    @Published var isScanning = false
    @Published var frameProcessingRate: Double = 0.0
    @Published var lastProcessedFrame: UIImage?
    @Published var smoothedScore: Float = 0.0
    @Published var currentMotionLevel: MotionLevel = .stable
    @Published var isSimulatorMode = false
    
    weak var delegate: ScanRoomControllerDelegate?
    
    private let cameraManager = CameraManager.shared
    private let sceneMatcher = SceneMatcher.shared
    private var memoriesToMatch: [MemoryItem] = []
    private var simulatorTimer: Timer?
    
    private var scanTimer: Timer?
    private var baseScanInterval: TimeInterval = 0.5
    private var currentScanInterval: TimeInterval = 0.5
    private var lastProcessedTime: Date = Date()
    
    private let processingQueue = DispatchQueue(label: "com.memorycam.scanroom.processing", qos: .userInitiated)
    
    private var isProcessingFrame = false
    private var pendingFrame: UIImage?
    
    private var recentStates: [MatchState] = []
    private let stateStabilityWindow = 3
    private let stateHysteresis: [MatchState: MatchState] = [
        .likelyMatch: .possibleMatch,
        .possibleMatch: .gettingCloser,
        .gettingCloser: .gettingCloser,
        .scanning: .scanning
    ]
    
    private var stableStateCounter = 0
    private var lastStableState: MatchState = .scanning
    private let stabilityThreshold = 2
    
    private var previousFrame: UIImage?
    private var motionHistory: [Double] = []
    private let motionHistorySize = 5
    
    private let minScanInterval: TimeInterval = 0.2
    private let maxScanInterval: TimeInterval = 1.0
    private let highMotionInterval: TimeInterval = 0.8
    private let mediumMotionInterval: TimeInterval = 0.5
    private let lowMotionInterval: TimeInterval = 0.3
    private let stableInterval: TimeInterval = 0.2
    
    private var recentScores: [Float] = []
    private let scoreWindowSize = 15
    private let throttleInterval: TimeInterval = 0.15
    private var lastThrottleTime: Date = Date.distantPast
    
    enum MotionLevel {
        case stable
        case low
        case medium
        case high
        
        var description: String {
            switch self {
            case .stable: return "Stable"
            case .low: return "Low Motion"
            case .medium: return "Medium Motion"
            case .high: return "High Motion"
            }
        }
    }
    
    var currentFrame: UIImage? {
        return cameraManager.currentFrame
    }
    
    init() {
        #if targetEnvironment(simulator)
        isSimulatorMode = true
        #endif
    }
    
    private func setupCamera() {
    }
    
    func checkCameraAuthorization() async {
        await cameraManager.checkAuthorization()
    }
    
    func configureCamera() {
        cameraManager.configure()
    }
    
    func startScanning(memories: [MemoryItem]) {
        guard !memories.isEmpty else {
            print("[ScanRoomController] Cannot start scanning with empty memories array")
            return
        }
        
        clearStabilityState()
        resetMotionTracking()
        
        memoriesToMatch = memories
        isScanning = true
        currentMatchState = .scanning
        currentMatchResult = nil
        smoothedScore = 0.0
        
        Task.detached(priority: .high) { [weak self] in
            await self?.sceneMatcher.loadReferenceDescriptors(for: memories)
            await self?.sceneMatcher.buildContextClusters(from: memories)
            if let firstMemory = memories.first {
                await MainActor.run {
                    self?.sceneMatcher.setCurrentContext(firstMemory.locationDescription)
                }
            }
            print("[ScanRoomController] Loaded descriptors for \(memories.count) memories")
        }
        
        if isSimulatorMode || !cameraManager.isAuthorized {
            startSimulatorMode()
        } else {
            cameraManager.startSession()
            
            cameraManager.setFrameCallback { [weak self] frame in
                self?.handleFrame(frame)
            }
            
            currentScanInterval = baseScanInterval
            scanTimer = Timer.scheduledTimer(withTimeInterval: currentScanInterval, repeats: true) { [weak self] _ in
                self?.processCurrentFrame()
            }
        }
        
        print("[ScanRoomController] Started scanning with \(memories.count) memories (Simulator: \(isSimulatorMode))")
    }
    
    private func startSimulatorMode() {
        print("[ScanRoomController] Running in simulator mode")
        
        simulatorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.simulateMatchResult()
        }
    }
    
    private func simulateMatchResult() {
        guard isScanning, !memoriesToMatch.isEmpty else { return }
        
        let randomMemory = memoriesToMatch.randomElement()!
        
        let states: [MatchState] = [.scanning, .gettingCloser, .possibleMatch, .likelyMatch]
        let weights: [Float] = [0.3, 0.3, 0.25, 0.15]
        
        let random = Float.random(in: 0...1)
        var cumulative: Float = 0
        var selectedState: MatchState = .scanning
        
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if random <= cumulative {
                selectedState = states[index]
                break
            }
        }
        
        let similarityScore: Float
        switch selectedState {
        case .scanning: similarityScore = Float.random(in: 0.1...0.4)
        case .gettingCloser: similarityScore = Float.random(in: 0.4...0.55)
        case .possibleMatch: similarityScore = Float.random(in: 0.55...0.75)
        case .likelyMatch: similarityScore = Float.random(in: 0.75...0.95)
        }
        
        let result = MatchResult(
            memoryId: randomMemory.id,
            similarityScore: similarityScore,
            aggregatedScore: similarityScore,
            isRejected: false
        )
        
        currentMatchResult = result
        smoothedScore = similarityScore
        currentMatchState = selectedState
        
        delegate?.scanRoomController(self, didUpdateMatchState: selectedState, for: randomMemory.id)
        delegate?.scanRoomController(self, didProcessFrame: result)
        
        print("[Simulator] Match: \(randomMemory.itemName) - \(selectedState.rawValue) (\(String(format: "%.2f", similarityScore)))")
    }
    
    private func resetMotionTracking() {
        previousFrame = nil
        motionHistory.removeAll()
        currentMotionLevel = .stable
    }
    
    func startScanning(memoryId: UUID, from memoryManager: MemoryManager) {
        guard let memory = memoryManager.getMemoryById(memoryId) else {
            print("[ScanRoomController] Memory not found: \(memoryId)")
            return
        }
        
        startScanning(memories: [memory])
    }
    
    func stopScanning() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        cameraManager.stopContinuousFrameCapture()
        cameraManager.stopSession()
        
        clearStabilityState()
        
        currentMatchState = .scanning
        currentMatchResult = nil
        lastProcessedFrame = nil
        smoothedScore = 0.0
        
        print("[ScanRoomController] Stopped scanning")
    }
    
    private func clearStabilityState() {
        recentStates.removeAll()
        stableStateCounter = 0
        lastStableState = .scanning
    }
    
    private func handleFrame(_ frame: UIImage) {
        if let previous = previousFrame {
            let motion = detectMotion(currentFrame: frame, previousFrame: previous)
            updateMotionLevel(motion)
        }
        
        previousFrame = frame
        pendingFrame = frame
        
        processCurrentFrameThrottled()
    }
    
    private func processCurrentFrameThrottled() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastThrottleTime)
        
        guard elapsed >= throttleInterval else { return }
        
        lastThrottleTime = now
        processCurrentFrame()
    }
    
    private func processCurrentFrame() {
        guard isScanning else { return }
        
        guard let frame = pendingFrame ?? cameraManager.getCurrentFrame() else {
            return
        }
        
        guard !isProcessingFrame else {
            return
        }
        
        isProcessingFrame = true
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastProcessedTime)
        if elapsed > 0 {
            frameProcessingRate = 1.0 / elapsed
        }
        lastProcessedTime = now
        
        let capturedFrame = frame
        let memories = memoriesToMatch
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            defer {
                Task { @MainActor in
                    self.isProcessingFrame = false
                }
            }
            
            do {
                let memories = self.memoriesToMatch
                
                guard let bestMatch = try await self.sceneMatcher.findBestMatchWithPriority(
                    capturedFrame,
                    againstMemories: memories,
                    useContextPriority: true,
                    maxMemoriesToScan: nil
                ) else {
                    await MainActor.run {
                        self.applyStableState(.scanning, memoryId: nil)
                        self.currentMatchResult = nil
                        self.delegate?.scanRoomController(self, didUpdateMatchState: self.currentMatchState, for: nil)
                        self.delegate?.scanRoomController(self, didProcessFrame: nil)
                    }
                    return
                }
                
                let rawScore = bestMatch.aggregatedScore
                
                self.recentScores.append(rawScore)
                if self.recentScores.count > self.scoreWindowSize {
                    self.recentScores.removeFirst()
                }
                
                let smoothedScore = self.calculateRollingAverage()
                
                await MainActor.run {
                    self.lastProcessedFrame = capturedFrame
                    self.currentMatchResult = bestMatch
                    self.smoothedScore = smoothedScore
                    
                    let stableState = self.determineStableState(bestMatch.matchState)
                    self.applyStableState(stableState, memoryId: bestMatch.memoryId)
                    
                    self.delegate?.scanRoomController(self, didUpdateMatchState: self.currentMatchState, for: bestMatch.memoryId)
                    self.delegate?.scanRoomController(self, didProcessFrame: bestMatch)
                    
                    if self.currentMatchState == .likelyMatch {
                        self.delegate?.scanRoomController(self, didFindMatch: bestMatch)
                        print("[ScanRoomController] Likely match found! Score: \(bestMatch.similarityScore), Smoothed: \(smoothedScore)")
                    }
                }
            } catch {
                print("[ScanRoomController] Error processing frame: \(error)")
                await MainActor.run {
                    self.delegate?.scanRoomController(self, didFailWithError: error)
                }
            }
        }
        
        pendingFrame = nil
    }
    
    private func determineStableState(_ newState: MatchState) -> MatchState {
        recentStates.append(newState)
        
        if recentStates.count > stateStabilityWindow {
            recentStates.removeFirst()
        }
        
        guard recentStates.count >= stateStabilityWindow else {
            return lastStableState
        }
        
        var stateCounts: [MatchState: Int] = [:]
        for state in recentStates {
            stateCounts[state, default: 0] += 1
        }
        
        let sortedStates = stateCounts.sorted { $0.value > $1.value }
        
        guard let dominantState = sortedStates.first else {
            return lastStableState
        }
        
        let requiredCount = (stateStabilityWindow + 1) / 2
        
        if dominantState.value >= requiredCount {
            if dominantState.key == lastStableState {
                stableStateCounter += 1
            } else {
                if let expectedPreviousState = stateHysteresis[lastStableState],
                   recentStates.contains(expectedPreviousState) || lastStableState == .scanning {
                    stableStateCounter += 1
                } else {
                    stableStateCounter = 0
                }
            }
            
            if stableStateCounter >= stabilityThreshold {
                lastStableState = dominantState.key
                stableStateCounter = stabilityThreshold
            }
        }
        
        return lastStableState
    }
    
    private func applyStableState(_ state: MatchState, memoryId: UUID?) {
        currentMatchState = state
        
        if let memoryId = memoryId, var result = currentMatchResult {
            result = MatchResult(
                memoryId: result.memoryId,
                similarityScore: result.similarityScore,
                boundingBox: result.boundingBox,
                aggregatedScore: smoothedScore
            )
            currentMatchResult = result
        }
    }
    
    func updateMemories(_ memories: [MemoryItem]) {
        clearStabilityState()
        memoriesToMatch = memories
        
        Task.detached(priority: .high) { [weak self] in
            await self?.sceneMatcher.loadReferenceDescriptors(for: memories)
        }
    }
    
    func addMemory(_ memory: MemoryItem) {
        memoriesToMatch.append(memory)
        
        Task.detached(priority: .medium) { [weak self] in
            await self?.sceneMatcher.addMemoryToCache(memory)
        }
    }
    
    func removeMemory(_ memoryId: UUID) {
        memoriesToMatch.removeAll { $0.id == memoryId }
        sceneMatcher.removeMemoryFromCache(memoryId)
        clearStabilityState()
    }
    
    func processSingleFrame(_ frame: UIImage) async -> MatchResult? {
        return try? await sceneMatcher.findBestMatch(frame, againstMemories: memoriesToMatch)
    }
    
    func setMatchThreshold(_ threshold: Float) {
    }
    
    func setContext(_ locationDescription: String?) {
        sceneMatcher.setCurrentContext(locationDescription)
    }
    
    private func calculateRollingAverage() -> Float {
        guard !recentScores.isEmpty else { return 0 }
        
        let weights = recentScores.enumerated().map { Float($0.offset + 1) }
        let totalWeight = weights.reduce(0, +)
        
        var weightedSum: Float = 0
        for (index, score) in recentScores.enumerated() {
            weightedSum += score * weights[index]
        }
        
        return weightedSum / totalWeight
    }
    
    private func detectMotion(currentFrame: UIImage, previousFrame: UIImage?) -> Double {
        guard let previous = previousFrame else { return 0.0 }
        
        guard let currentCG = currentFrame.cgImage,
              let previousCG = previous.cgImage else {
            return 0.0
        }
        
        let currentSize = currentCG.width * currentCG.height
        let previousSize = previousCG.width * previousCG.height
        
        guard currentSize > 0 && currentSize == previousSize else { return 0.0 }
        
        let sampleSize = 50
        let scale = max(1, min(currentCG.width, currentCG.height) / sampleSize)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        var currentData = [UInt8](repeating: 0, count: 4)
        var previousData = [UInt8](repeating: 0, count: 4)
        
        var totalDiff: Double = 0
        var sampleCount = 0
        
        let step = scale
        
        for y in stride(from: 0, to: currentCG.height, by: step) {
            for x in stride(from: 0, to: currentCG.width, by: step) {
                currentCG.getPixel(&currentData, atX: x, y: y)
                previousCG.getPixel(&previousData, atX: x, y: y)
                
                let diff = abs(Int(currentData[0]) - Int(previousData[0])) +
                           abs(Int(currentData[1]) - Int(previousData[1])) +
                           abs(Int(currentData[2]) - Int(previousData[2]))
                
                totalDiff += Double(diff)
                sampleCount += 1
            }
        }
        
        guard sampleCount > 0 else { return 0.0 }
        
        let avgDiff = totalDiff / Double(sampleCount)
        let normalizedMotion = min(avgDiff / 128.0, 1.0)
        
        return normalizedMotion
    }
    
    private func updateMotionLevel(_ motion: Double) {
        motionHistory.append(motion)
        
        if motionHistory.count > motionHistorySize {
            motionHistory.removeFirst()
        }
        
        let avgMotion = motionHistory.reduce(0, +) / Double(motionHistory.count)
        
        let newLevel: MotionLevel
        if avgMotion < 0.05 {
            newLevel = .stable
        } else if avgMotion < 0.2 {
            newLevel = .low
        } else if avgMotion < 0.5 {
            newLevel = .medium
        } else {
            newLevel = .high
        }
        
        if newLevel != currentMotionLevel {
            currentMotionLevel = newLevel
            adjustScanInterval(for: newLevel)
        }
    }
    
    private func adjustScanInterval(for level: MotionLevel) {
        let newInterval: TimeInterval
        
        switch level {
        case .stable, .low:
            newInterval = stableInterval
        case .medium:
            newInterval = mediumMotionInterval
        case .high:
            newInterval = highMotionInterval
        }
        
        guard newInterval != currentScanInterval else { return }
        
        currentScanInterval = newInterval
        
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: currentScanInterval, repeats: true) { [weak self] _ in
            self?.processCurrentFrame()
        }
        
        print("[ScanRoomController] Motion level: \(level.description), scan interval: \(String(format: "%.2f", currentScanInterval))s")
    }
}

extension ScanRoomController: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didCaptureFrame image: UIImage) {
    }
    
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
    }
    
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.scanRoomController(self, didFailWithError: error)
        }
    }
}
