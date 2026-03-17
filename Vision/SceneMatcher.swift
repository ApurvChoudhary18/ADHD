import Foundation
import Vision
import UIKit

enum MatchState: String {
    case scanning = "Scanning"
    case gettingCloser = "Getting Closer"
    case possibleMatch = "Possible Match"
    case likelyMatch = "Likely Match!"
}

struct MatchResult {
    let memoryId: UUID
    let similarityScore: Float
    let aggregatedScore: Float
    let matchState: MatchState
    let boundingBox: CGRect?
    let timestamp: Date
    let confidence: Float
    let isRejected: Bool
    let rejectionReason: String?
    
    init(
        memoryId: UUID,
        similarityScore: Float,
        boundingBox: CGRect? = nil,
        aggregatedScore: Float? = nil,
        isRejected: Bool = false,
        rejectionReason: String? = nil
    ) {
        self.memoryId = memoryId
        self.similarityScore = similarityScore
        self.aggregatedScore = aggregatedScore ?? similarityScore
        self.boundingBox = boundingBox
        self.timestamp = Date()
        self.confidence = aggregatedScore ?? similarityScore
        self.isRejected = isRejected
        self.rejectionReason = rejectionReason
        
        if isRejected {
            self.matchState = .scanning
        } else if similarityScore > 0.85 {
            self.matchState = .likelyMatch
        } else if similarityScore > 0.70 {
            self.matchState = .possibleMatch
        } else if similarityScore > 0.50 {
            self.matchState = .gettingCloser
        } else {
            self.matchState = .scanning
        }
    }
}

struct MemoryContextCluster: Identifiable {
    let id: String
    var memoryIds: [UUID]
    var locationKeywords: Set<String>
    var lastMatched: Date
    var matchCount: Int
    
    init(locationDescription: String) {
        let keywords = locationDescription.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 2 }
        
        self.id = keywords.sorted().joined(separator: "_")
        self.memoryIds = []
        self.locationKeywords = Set(keywords)
        self.lastMatched = Date.distantPast
        self.matchCount = 0
    }
    
    mutating func addMemory(_ id: UUID) {
        if !memoryIds.contains(id) {
            memoryIds.append(id)
        }
    }
    
    mutating func recordMatch() {
        matchCount += 1
        lastMatched = Date()
    }
}

struct MultiCandidateResult {
    let candidates: [MatchResult]
    let topMatch: MatchResult?
    let candidateCount: Int
    
    var hasConfidentMatch: Bool {
        return topMatch != nil && topMatch!.matchState == .likelyMatch
    }
}

final class SceneMatcher: @unchecked Sendable {
    static let shared = SceneMatcher()
    
    private let featureExtractor = FeatureExtractor.shared
    private var cachedDescriptors: [UUID: [VNFeaturePrintObservation]] = [:]
    private let maxCachedDescriptors = 10
    
    private let cacheLock = NSLock()
    
    private var likelyMatchThreshold: Float = 0.85
    private var possibleMatchThreshold: Float = 0.70
    private var gettingCloserThreshold: Float = 0.50
    
    private var recentScores: [UUID: [Float]] = [:]
    private let scoreWindowSize = 5
    
    private var contextClusters: [String: MemoryContextCluster] = [:]
    private var currentContext: String?
    private var candidateStability: [UUID: [UUID]] = [:]
    private let stabilityWindowSize = 3
    
    private var lazyLoadedMemories: Set<UUID> = []
    private var pendingLoads: Set<UUID> = []
    private let loadLock = NSLock()
    
    static var debugMode: Bool = false
    
    private init() {}
    
    func setCurrentContext(_ locationDescription: String?) {
        if let loc = locationDescription {
            let keywords = loc.lowercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 2 }
                .sorted()
                .joined(separator: "_")
            currentContext = keywords
        } else {
            currentContext = nil
        }
        
        if Self.debugMode {
            print("[SceneMatcher] Current context set to: \(currentContext ?? "none")")
        }
    }
    
    func buildContextClusters(from memories: [MemoryItem]) {
        cacheLock.lock()
        contextClusters.removeAll()
        cacheLock.unlock()
        
        for memory in memories {
            let clusterId = createClusterId(from: memory.locationDescription)
            
            cacheLock.lock()
            if contextClusters[clusterId] == nil {
                contextClusters[clusterId] = MemoryContextCluster(locationDescription: memory.locationDescription)
            }
            contextClusters[clusterId]?.addMemory(memory.id)
            cacheLock.unlock()
        }
        
        if Self.debugMode {
            print("[SceneMatcher] Built \(contextClusters.count) context clusters")
        }
    }
    
    private func createClusterId(from locationDescription: String) -> String {
        let keywords = locationDescription.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { $0.count > 2 }
            .sorted()
        return keywords.joined(separator: "_")
    }
    
    func getPrioritizedMemories(from memories: [MemoryItem]) -> [MemoryItem] {
        var prioritized: [MemoryItem] = []
        var remaining: [UUID] = []
        
        cacheLock.lock()
        
        if let contextId = currentContext, let cluster = contextClusters[contextId] {
            let clusterIds = Set(cluster.memoryIds)
            prioritized = memories.filter { clusterIds.contains($0.id) }
            remaining = memories.filter { !clusterIds.contains($0.id) }.map { $0.id }
        } else {
            let sortedClusters = contextClusters.sorted { $0.value.matchCount > $1.value.matchCount }
            var usedIds: Set<UUID> = []
            
            for (_, cluster) in sortedClusters {
                for id in cluster.memoryIds {
                    if !usedIds.contains(id) {
                        if let memory = memories.first(where: { $0.id == id }) {
                            prioritized.append(memory)
                            usedIds.insert(id)
                        }
                    }
                }
            }
            remaining = memories.filter { !usedIds.contains($0.id) }.map { $0.id }
        }
        
        cacheLock.unlock()
        
        for id in remaining {
            if let memory = memories.first(where: { $0.id == id }) {
                prioritized.append(memory)
            }
        }
        
        return prioritized
    }
    
    func setThresholds(likely: Float, possible: Float, closer: Float) {
        likelyMatchThreshold = likely
        possibleMatchThreshold = possible
        gettingCloserThreshold = closer
    }
    
    func resetThresholds() {
        likelyMatchThreshold = 0.85
        possibleMatchThreshold = 0.70
        gettingCloserThreshold = 0.50
    }
    
    func loadReferenceDescriptors(for memories: [MemoryItem]) async {
        cacheLock.lock()
        cachedDescriptors.removeAll()
        candidateStability.removeAll()
        cacheLock.unlock()
        
        buildContextClusters(from: memories)
        
        for memory in memories {
            let descriptors: [VNFeaturePrintObservation]
            
            if memory.hasDescriptors {
                descriptors = memory.deserializeFeaturePrints()
            } else {
                descriptors = await extractFeaturePrintsFromFrames(memory.referenceFrames)
            }
            
            cacheLock.lock()
            cachedDescriptors[memory.id] = descriptors
            cacheLock.unlock()
            
            recentScores[memory.id] = []
            candidateStability[memory.id] = []
            
            if Self.debugMode {
                print("[SceneMatcher] Loaded \(descriptors.count) feature prints for \(memory.itemName)")
            }
        }
        
        print("[SceneMatcher] Loaded descriptors for \(cachedDescriptors.count) memories")
    }
    
    func preloadDescriptors(for memoryIds: [UUID], from memories: [MemoryItem]) async {
        for memoryId in memoryIds {
            await loadDescriptorsIfNeeded(for: memoryId, from: memories)
        }
    }
    
    private func loadDescriptorsIfNeeded(for memoryId: UUID, from memories: [MemoryItem]) async {
        loadLock.lock()
        if lazyLoadedMemories.contains(memoryId) || pendingLoads.contains(memoryId) {
            loadLock.unlock()
            return
        }
        pendingLoads.insert(memoryId)
        loadLock.unlock()
        
        defer {
            loadLock.lock()
            pendingLoads.remove(memoryId)
            loadLock.unlock()
        }
        
        guard let memory = memories.first(where: { $0.id == memoryId }) else { return }
        
        let descriptors: [VNFeaturePrintObservation]
        
        if memory.hasDescriptors {
            descriptors = memory.deserializeFeaturePrints()
        } else {
            descriptors = await extractFeaturePrintsFromFrames(memory.referenceFrames)
        }
        
        cacheLock.lock()
        cachedDescriptors[memoryId] = descriptors
        lazyLoadedMemories.insert(memoryId)
        
        recentScores[memoryId] = []
        candidateStability[memoryId] = []
        cacheLock.unlock()
        
        if Self.debugMode {
            print("[SceneMatcher] Lazy loaded \(descriptors.count) feature prints for \(memory.itemName)")
        }
    }
    
    private func updateCandidateStability(for matchedMemoryId: UUID, in memories: [MemoryItem]) {
        cacheLock.lock()
        
        for (memoryId, history) in candidateStability {
            if memoryId == matchedMemoryId {
                var updatedHistory = history
                updatedHistory.append(matchedMemoryId)
                if updatedHistory.count > stabilityWindowSize {
                    updatedHistory.removeFirst()
                }
                candidateStability[memoryId] = updatedHistory
            } else {
                candidateStability[memoryId] = []
            }
        }
        
        if let clusterId = createClusterId(from: memories.first(where: { $0.id == matchedMemoryId })?.locationDescription ?? "") {
            contextClusters[clusterId]?.recordMatch()
        }
        
        cacheLock.unlock()
    }
    
    func getStabilityScore(for memoryId: UUID) -> Float {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        guard let history = candidateStability[memoryId], !history.isEmpty else {
            return 0.0
        }
        
        let count = history.filter { $0 == memoryId }.count
        return Float(count) / Float(stabilityWindowSize)
    }
    
    func findBestMatchWithPriority(
        _ frame: UIImage,
        againstMemories memories: [MemoryItem],
        useContextPriority: Bool = true,
        maxMemoriesToScan: Int? = nil,
        useLazyLoading: Bool = true
    ) async throws -> MatchResult? {
        var memoriesToScan: [MemoryItem]
        
        if useContextPriority {
            memoriesToScan = getPrioritizedMemories(from: memories)
        } else {
            memoriesToScan = memories
        }
        
        let candidateIds = memoriesToScan.map { $0.id }
        
        if useLazyLoading {
            await preloadDescriptors(for: candidateIds, from: memories)
        }
        
        let limitedMemories: [MemoryItem]
        if let maxScan = maxMemoriesToScan, memoriesToScan.count > maxScan {
            limitedMemories = Array(memoriesToScan.prefix(maxScan))
        } else {
            limitedMemories = memoriesToScan
        }
        
        return try await findBestMatch(frame, againstMemories: limitedMemories)
    }
    
    func findMultiCandidateWithPriority(
        _ frame: UIImage,
        againstMemories memories: [MemoryItem],
        maxCandidates: Int = 3,
        useContextPriority: Bool = true,
        maxMemoriesToScan: Int? = nil,
        useLazyLoading: Bool = true
    ) async throws -> MultiCandidateResult {
        var memoriesToScan: [MemoryItem]
        
        if useContextPriority {
            memoriesToScan = getPrioritizedMemories(from: memories)
        } else {
            memoriesToScan = memories
        }
        
        let candidateIds = memoriesToScan.map { $0.id }
        
        if useLazyLoading {
            await preloadDescriptors(for: candidateIds, from: memories)
        }
        
        let limitedMemories: [MemoryItem]
        if let maxScan = maxMemoriesToScan, memoriesToScan.count > maxScan {
            limitedMemories = Array(memoriesToScan.prefix(maxScan))
        } else {
            limitedMemories = memoriesToScan
        }
        
        return try await findMultiCandidateMatches(frame, againstMemories: limitedMemories, maxCandidates: maxCandidates)
    }
    
    private func extractFeaturePrintsFromFrames(_ frameData: [Data]) async -> [VNFeaturePrintObservation] {
        var featurePrints: [VNFeaturePrintObservation] = []
        
        for data in frameData {
            if let image = UIImage(data: data) {
                if let extracted = try? await featureExtractor.extractFeaturePrints(from: image) {
                    featurePrints.append(contentsOf: extracted)
                }
            }
        }
        
        return featurePrints
    }
    
    func matchFrame(_ frame: UIImage, againstMemory memory: MemoryItem) async throws -> MatchResult {
        let liveFeaturePrints = try await featureExtractor.extractFeaturePrints(from: frame)
        
        cacheLock.lock()
        let referenceDescriptors = cachedDescriptors[memory.id] ?? []
        cacheLock.unlock()
        
        guard !referenceDescriptors.isEmpty else {
            return MatchResult(memoryId: memory.id, similarityScore: 0.0)
        }
        
        let (bestScore, aggregatedScore) = computeAggregatedScore(
            liveFeaturePrints: liveFeaturePrints,
            referenceFeaturePrints: referenceDescriptors
        )
        
        let boundingBox = await detectBoundingRegion(in: frame)
        
        let result = MatchResult(
            memoryId: memory.id,
            similarityScore: bestScore,
            boundingBox: boundingBox,
            aggregatedScore: aggregatedScore
        )
        
        updateRecentScores(for: memory.id, score: aggregatedScore)
        
        return result
    }
    
    func matchFrame(_ frame: UIImage, againstMemories memories: [MemoryItem]) async throws -> [MatchResult] {
        let liveFeaturePrints = try await featureExtractor.extractFeaturePrints(from: frame)
        
        var results: [MatchResult] = []
        
        for memory in memories {
            cacheLock.lock()
            let referenceDescriptors = cachedDescriptors[memory.id] ?? []
            cacheLock.unlock()
            
            guard !referenceDescriptors.isEmpty else {
                results.append(MatchResult(memoryId: memory.id, similarityScore: 0.0))
                continue
            }
            
            let (bestScore, aggregatedScore) = computeAggregatedScore(
                liveFeaturePrints: liveFeaturePrints,
                referenceFeaturePrints: referenceDescriptors
            )
            
            let result = MatchResult(
                memoryId: memory.id,
                similarityScore: bestScore,
                boundingBox: nil,
                aggregatedScore: aggregatedScore
            )
            
            results.append(result)
            
            updateRecentScores(for: memory.id, score: aggregatedScore)
        }
        
        return results.sorted { $0.aggregatedScore > $1.aggregatedScore }
    }
    
    private func computeAggregatedScore(liveFeaturePrints: [VNFeaturePrintObservation], referenceFeaturePrints: [VNFeaturePrintObservation]) -> (Float, Float) {
        guard !liveFeaturePrints.isEmpty && !referenceFeaturePrints.isEmpty else {
            return (0.0, 0.0)
        }
        
        var allScores: [Float] = []
        
        for liveFP in liveFeaturePrints {
            var bestForLive: Float = 0.0
            for refFP in referenceFeaturePrints {
                do {
                    let similarity = try featureExtractor.computeSimilarity(between: liveFP, and: refFP)
                    bestForLive = max(bestForLive, similarity)
                    allScores.append(similarity)
                    
                    if similarity > likelyMatchThreshold {
                        return (similarity, similarity)
                    }
                } catch {
                    continue
                }
            }
        }
        
        guard !allScores.isEmpty else { return (0.0, 0.0) }
        
        let bestScore = allScores.max() ?? 0.0
        
        let sortedScores = allScores.sorted(by: >)
        let topCount = max(1, sortedScores.count / 3)
        let topScores = Array(sortedScores.prefix(topCount))
        let aggregatedScore = topScores.reduce(0, +) / Float(topScores.count)
        
        return (bestScore, aggregatedScore)
    }
    
    func findBestMatch(_ frame: UIImage, againstMemories memories: [MemoryItem]) async throws -> MatchResult? {
        guard !memories.isEmpty else { return nil }
        
        let liveFeaturePrints = try await featureExtractor.extractFeaturePrints(from: frame)
        
        guard !liveFeaturePrints.isEmpty else { return nil }
        
        var bestResult: MatchResult?
        var bestScore: Float = 0.0
        
        for memory in memories {
            cacheLock.lock()
            let referenceDescriptors = cachedDescriptors[memory.id] ?? []
            cacheLock.unlock()
            
            guard !referenceDescriptors.isEmpty else { continue }
            
            let (similarity, aggregatedScore) = computeAggregatedScore(
                liveFeaturePrints: liveFeaturePrints,
                referenceFeaturePrints: referenceDescriptors
            )
            
            if aggregatedScore > bestScore {
                bestScore = aggregatedScore
                
                let boundingBox = await detectBoundingRegion(in: frame)
                
                bestResult = MatchResult(
                    memoryId: memory.id,
                    similarityScore: similarity,
                    boundingBox: boundingBox,
                    aggregatedScore: aggregatedScore
                )
            }
            
            if similarity > likelyMatchThreshold {
                updateRecentScores(for: memory.id, score: aggregatedScore)
                break
            }
        }
        
        if let result = bestResult {
            updateRecentScores(for: result.memoryId, score: result.aggregatedScore)
        }
        
        return bestResult
    }
    
    func findBestMatchWithThreshold(
        _ frame: UIImage,
        againstMemories memories: [MemoryItem],
        threshold: Float
    ) async throws -> MatchResult? {
        guard !memories.isEmpty else { return nil }
        
        let liveFeaturePrints = try await featureExtractor.extractFeaturePrints(from: frame)
        
        guard !liveFeaturePrints.isEmpty else { return nil }
        
        for memory in memories {
            cacheLock.lock()
            let referenceDescriptors = cachedDescriptors[memory.id] ?? []
            cacheLock.unlock()
            
            guard !referenceDescriptors.isEmpty else { continue }
            
            let (similarity, aggregatedScore) = computeAggregatedScore(
                liveFeaturePrints: liveFeaturePrints,
                referenceFeaturePrints: referenceDescriptors
            )
            
            if aggregatedScore >= threshold {
                let boundingBox = await detectBoundingRegion(in: frame)
                
                let result = MatchResult(
                    memoryId: memory.id,
                    similarityScore: similarity,
                    boundingBox: boundingBox,
                    aggregatedScore: aggregatedScore
                )
                
                updateRecentScores(for: memory.id, score: aggregatedScore)
                
                return result
            }
        }
        
        return nil
    }
    
    func findMultiCandidateMatches(
        _ frame: UIImage,
        againstMemories memories: [MemoryItem],
        maxCandidates: Int = 3
    ) async throws -> MultiCandidateResult {
        guard !memories.isEmpty else {
            return MultiCandidateResult(candidates: [], topMatch: nil, candidateCount: 0)
        }
        
        let liveFeaturePrints = try await featureExtractor.extractFeaturePrints(from: frame)
        
        guard !liveFeaturePrints.isEmpty else {
            return MultiCandidateResult(candidates: [], topMatch: nil, candidateCount: 0)
        }
        
        var results: [MatchResult] = []
        
        for memory in memories {
            cacheLock.lock()
            let referenceDescriptors = cachedDescriptors[memory.id] ?? []
            cacheLock.unlock()
            
            guard !referenceDescriptors.isEmpty else { continue }
            
            let (similarity, aggregatedScore) = computeAggregatedScore(
                liveFeaturePrints: liveFeaturePrints,
                referenceFeaturePrints: referenceDescriptors
            )
            
            let result = MatchResult(
                memoryId: memory.id,
                similarityScore: similarity,
                boundingBox: nil,
                aggregatedScore: aggregatedScore,
                isRejected: false,
                rejectionReason: nil
            )
            
            results.append(result)
            
            updateRecentScores(for: memory.id, score: aggregatedScore)
        }
        
        let sortedResults = results.sorted { $0.aggregatedScore > $1.aggregatedScore }
        
        let topCandidates = Array(sortedResults.prefix(maxCandidates))
        let topMatch = topCandidates.first
        
        if Self.debugMode {
            print("[SceneMatcher] Multi-candidate results:")
            for (index, candidate) in topCandidates.enumerated() {
                let memory = memories.first { $0.id == candidate.memoryId }
                print("[SceneMatcher]   \(index + 1). \(memory?.itemName ?? "unknown"): score=\(String(format: "%.3f", candidate.similarityScore)), aggregated=\(String(format: "%.3f", candidate.aggregatedScore))")
            }
        }
        
        return MultiCandidateResult(
            candidates: topCandidates,
            topMatch: topMatch,
            candidateCount: topCandidates.count
        )
    }
    
    func computeConfidence(for result: MatchResult, againstMemory memory: MemoryItem) -> Float {
        guard !result.isRejected else { return 0.0 }
        
        let smoothedScore = getSmoothedScore(for: memory.id) ?? result.aggregatedScore
        
        cacheLock.lock()
        let descriptorCount = cachedDescriptors[memory.id]?.count ?? 0
        cacheLock.unlock()
        
        var confidence = result.aggregatedScore
        
        if descriptorCount >= 5 {
            confidence += 0.05
        }
        
        let scoreStability = computeScoreStability(for: memory.id)
        confidence += scoreStability * 0.1
        
        return min(confidence, 1.0)
    }
    
    private func computeScoreStability(for memoryId: UUID) -> Float {
        guard let scores = recentScores[memoryId], scores.count >= 3 else {
            return 0.0
        }
        
        let mean = scores.reduce(0, +) / Float(scores.count)
        
        let variance = scores.reduce(0) { sum, score in
            let diff = score - mean
            return sum + diff * diff
        } / Float(scores.count)
        
        let stdDev = sqrt(variance)
        
        return 1.0 - min(stdDev * 2, 0.5)
    }
    
    func getSmoothedScore(for memoryId: UUID) -> Float? {
        guard let scores = recentScores[memoryId], !scores.isEmpty else {
            return nil
        }
        
        let sortedScores = scores.sorted(by: >)
        
        let weightFactor: Float = 0.4
        var weightedSum: Float = 0
        var weightTotal: Float = 0
        
        for (index, score) in sortedScores.enumerated() {
            let weight = pow(1.0 - weightFactor, Float(index))
            weightedSum += score * weight
            weightTotal += weight
        }
        
        return weightTotal > 0 ? weightedSum / weightTotal : 0
    }
    
    private func updateRecentScores(for memoryId: UUID, score: Float) {
        if recentScores[memoryId] == nil {
            recentScores[memoryId] = []
        }
        
        recentScores[memoryId]?.append(score)
        
        if let scores = recentScores[memoryId], scores.count > scoreWindowSize {
            recentScores[memoryId] = Array(scores.suffix(scoreWindowSize))
        }
    }
    
    private func detectBoundingRegion(in frame: UIImage) async -> CGRect? {
        guard let cgImage = frame.cgImage else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRectangleObservation],
                      let firstObservation = observations.first else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let boundingBox = firstObservation.boundingBox
                continuation.resume(returning: boundingBox)
            }
            
            request.minimumAspectRatio = 0.3
            request.maximumAspectRatio = 1.0
            request.minimumSize = 0.1
            request.maximumObservations = 1
            request.minimumConfidence = 0.5
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    func updateCachedDescriptors(for memory: MemoryItem) async {
        let descriptors: [VNFeaturePrintObservation]
        
        if memory.hasDescriptors {
            descriptors = memory.deserializeFeaturePrints()
        } else {
            descriptors = await extractFeaturePrintsFromFrames(memory.referenceFrames)
        }
        
        cacheLock.lock()
        cachedDescriptors[memory.id] = descriptors
        cacheLock.unlock()
        
        recentScores[memory.id] = []
    }
    
    func addMemoryToCache(_ memory: MemoryItem) async {
        await updateCachedDescriptors(for: memory)
    }
    
    func removeMemoryFromCache(_ memoryId: UUID) {
        cacheLock.lock()
        cachedDescriptors.removeValue(forKey: memoryId)
        cacheLock.unlock()
        
        recentScores.removeValue(forKey: memoryId)
    }
    
    func clearCache() {
        cacheLock.lock()
        cachedDescriptors.removeAll()
        cacheLock.unlock()
        
        recentScores.removeAll()
    }
    
    func getCachedDescriptorCount(for memoryId: UUID) -> Int {
        cacheLock.lock()
        let count = cachedDescriptors[memoryId]?.count ?? 0
        cacheLock.unlock()
        return count
    }
    
    func hasCachedDescriptors(for memoryId: UUID) -> Bool {
        cacheLock.lock()
        let hasDescriptors = (cachedDescriptors[memoryId]?.isEmpty ?? true) == false
        cacheLock.unlock()
        return hasDescriptors
    }
    
    func getRecentScoreCount(for memoryId: UUID) -> Int {
        return recentScores[memoryId]?.count ?? 0
    }
    
    func clearRecentScores(for memoryId: UUID) {
        recentScores[memoryId] = []
    }
}
